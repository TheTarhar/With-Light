import SwiftUI
import Foundation
import AVFoundation
import Network
import MLCSwift
import Darwin

struct ModelConfig: Decodable {
    let tokenizerFiles: [String]

    enum CodingKeys: String, CodingKey {
        case tokenizerFiles = "tokenizer_files"
    }
}

struct ParamsConfig: Decodable {
    struct ParamsRecord: Decodable {
        let dataPath: String

        enum CodingKeys: String, CodingKey {
            case dataPath = "dataPath"
        }
    }

    let records: [ParamsRecord]
}

struct TinyHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let bodyData: Data
}

struct TinyHTTPResponse {
    let statusCode: Int
    let statusText: String
    let headers: [String: String]
    let body: Data

    static func json(_ object: Any, statusCode: Int = 200, statusText: String = "OK") -> TinyHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        return TinyHTTPResponse(
            statusCode: statusCode,
            statusText: statusText,
            headers: [
                "Content-Type": "application/json",
                "Content-Length": "\(data.count)",
                "Connection": "close"
            ],
            body: data
        )
    }

    static func badRequest(_ message: String) -> TinyHTTPResponse {
        .json(["error": ["message": message, "type": "bad_request"]], statusCode: 400, statusText: "Bad Request")
    }

    static func internalServerError(_ message: String) -> TinyHTTPResponse {
        .json(["error": ["message": message, "type": "server_error"]], statusCode: 500, statusText: "Internal Server Error")
    }

    static func notFound() -> TinyHTTPResponse {
        .json(["error": ["message": "Not found", "type": "not_found"]], statusCode: 404, statusText: "Not Found")
    }

    func serialized() -> Data {
        var text = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        for (key, value) in headers {
            text += "\(key): \(value)\r\n"
        }
        text += "\r\n"
        var data = Data(text.utf8)
        data.append(body)
        return data
    }
}

final class TinyHTTPServer {
    typealias Handler = (TinyHTTPRequest) async -> TinyHTTPResponse

    private let port: UInt16
    private let handler: Handler
    private let queue = DispatchQueue(label: "neura.node.http")
    private var listener: NWListener?

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2_000_000) { [weak self] data, _, _, error in
            guard let self, let data, !data.isEmpty, error == nil else {
                connection.cancel()
                return
            }

            Task {
                let response: TinyHTTPResponse
                do {
                    let request = try self.parseRequest(data)
                    response = await self.handler(request)
                } catch {
                    response = .badRequest("Malformed HTTP request")
                }

                connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func parseRequest(_ data: Data) throws -> TinyHTTPRequest {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "TinyHTTPServer", code: 1)
        }

        let pieces = text.components(separatedBy: "\r\n\r\n")
        let headerBlob = pieces.first ?? ""
        let bodyBlob = pieces.dropFirst().joined(separator: "\r\n\r\n")
        let lines = headerBlob.components(separatedBy: "\r\n")

        guard let requestLine = lines.first else {
            throw NSError(domain: "TinyHTTPServer", code: 2)
        }

        let requestParts = requestLine.components(separatedBy: " ")
        guard requestParts.count >= 2 else {
            throw NSError(domain: "TinyHTTPServer", code: 3)
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let comps = line.components(separatedBy: ": ")
            if comps.count >= 2 {
                headers[comps[0].lowercased()] = comps.dropFirst().joined(separator: ": ")
            }
        }

        return TinyHTTPRequest(
            method: requestParts[0],
            path: requestParts[1],
            headers: headers,
            bodyData: Data(bodyBlob.utf8)
        )
    }
}

@MainActor
final class NodeManager: NSObject, ObservableObject {
    @Published var remoteAccessEnabled = false
    @Published var isModelLoaded = false
    @Published var isServerRunning = false
    @Published var statusText = "Ready"
    @Published var modelStateText = "Not downloaded"
    @Published var downloadProgressText = "0 / 0"
    @Published var tailscaleAddressText = "Not detected"
    @Published var lastError: String?

    let port: UInt16 = 8080

    private let engine = MLCEngine()
    private var audioPlayer: AVAudioPlayer?
    private var httpServer: TinyHTTPServer?
    private let fileManager = FileManager.default

    private let modelID = "Llama-3.2-1B-Instruct-q4f16_1-MLC"
    private let modelLib = "llama_q4f16_1"
    private let modelRepoBase = URL(string: "https://huggingface.co/mlc-ai/Llama-3.2-1B-Instruct-q4f16_1-MLC/resolve/main")!

    private var activeDownloads: [URLSessionDownloadTask] = []
    private var totalFiles = 0
    private var completedFiles = 0

    private lazy var modelBaseURL: URL = {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: modelID)
    }()

    override init() {
        super.init()
        refreshNetworkStatus()
        refreshLocalModelState()
    }

    func setRemoteAccess(_ enabled: Bool) {
        if enabled {
            Task {
                await startNode()
            }
        } else {
            stopNode()
        }
    }

    func startNode() async {
        do {
            lastError = nil
            try configureAudioSession()
            try startSilentKeepAlive()
            refreshNetworkStatus()

            if !localModelReady() {
                statusText = "Downloading model..."
                modelStateText = "Downloading"
                try await downloadModelIfNeeded()
            }

            if !isModelLoaded {
                statusText = "Loading model..."
                try await loadModel()
                isModelLoaded = true
                modelStateText = "Loaded"
            }

            statusText = "Starting API server..."
            try await startHTTPServer()
            isServerRunning = true
            remoteAccessEnabled = true
            statusText = "Online at \(tailscaleAddressText):\(port)"
        } catch {
            lastError = error.localizedDescription
            statusText = "Error: \(error.localizedDescription)"
            modelStateText = "Failed"
            isServerRunning = false
            remoteAccessEnabled = false
        }
    }

    func stopNode() {
        httpServer?.stop()
        httpServer = nil
        isServerRunning = false

        Task {
            await engine.unload()
        }

        audioPlayer?.stop()
        audioPlayer = nil
        isModelLoaded = false
        remoteAccessEnabled = false
        refreshLocalModelState()
        statusText = "Offline"
    }

    func refreshNetworkStatus() {
        tailscaleAddressText = Self.detectTailscaleIPv4() ?? Self.detectPrimaryIPv4() ?? "IP unavailable"
        if isServerRunning {
            statusText = "Online at \(tailscaleAddressText):\(port)"
        }
    }

    private func refreshLocalModelState() {
        if localModelReady() {
            modelStateText = "Downloaded"
            let count = localFileCount()
            downloadProgressText = "\(count) / \(count)"
        } else {
            modelStateText = "Not downloaded"
            downloadProgressText = "0 / ?"
        }
    }

    private func loadModel() async throws {
        guard fileManager.fileExists(atPath: modelBaseURL.path()) else {
            throw NSError(domain: "NeuraNode", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Model folder missing"])
        }

        await engine.reload(modelPath: modelBaseURL.path(), modelLib: modelLib)
    }

    private func startHTTPServer() async throws {
        if httpServer != nil { return }

        let server = TinyHTTPServer(port: port) { [weak self] request in
            guard let self else {
                return .internalServerError("Node manager unavailable")
            }
            return await self.handle(request: request)
        }
        try server.start()
        httpServer = server
    }

    private func handle(request: TinyHTTPRequest) async -> TinyHTTPResponse {
        if request.method == "GET" && request.path == "/health" {
            return .json([
                "ok": true,
                "server_running": isServerRunning,
                "model_loaded": isModelLoaded,
                "downloaded": localModelReady(),
                "address": tailscaleAddressText,
                "port": port
            ])
        }

        if request.method == "GET" && request.path == "/v1/models" {
            return .json([
                "object": "list",
                "data": [[
                    "id": modelID,
                    "object": "model",
                    "owned_by": "neura-node"
                ]]
            ])
        }

        if request.method == "POST" && request.path == "/v1/chat/completions" {
            do {
                let json = try JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any] ?? [:]
                let messages = json["messages"] as? [[String: Any]] ?? []
                let maxTokens = json["max_tokens"] as? Int
                let temperature = json["temperature"] as? Double
                let stream = (json["stream"] as? Bool) ?? false

                if stream {
                    return .badRequest("stream=true is not implemented in this lightweight server yet")
                }

                let mlcMessages: [ChatCompletionMessage] = messages.compactMap { item in
                    guard let roleRaw = item["role"] as? String else { return nil }
                    let content = item["content"] as? String ?? ""
                    let role: ChatCompletionRole
                    switch roleRaw {
                    case "system": role = .system
                    case "assistant": role = .assistant
                    case "tool": role = .tool
                    default: role = .user
                    }
                    return ChatCompletionMessage(role: role, content: content)
                }

                var combined = ""
                var usage: CompletionUsage?

                let responseStream = await engine.chat.completions.create(
                    messages: mlcMessages,
                    model: modelID,
                    max_tokens: maxTokens,
                    stream: true,
                    stream_options: StreamOptions(include_usage: true),
                    temperature: temperature.map(Float.init)
                )

                for await chunk in responseStream {
                    if let finalUsage = chunk.usage {
                        usage = finalUsage
                    } else if let token = chunk.choices.first?.delta.content?.asText() {
                        combined += token
                    }
                }

                return .json([
                    "id": UUID().uuidString,
                    "object": "chat.completion",
                    "created": Int(Date().timeIntervalSince1970),
                    "model": modelID,
                    "choices": [[
                        "index": 0,
                        "message": [
                            "role": "assistant",
                            "content": combined
                        ],
                        "finish_reason": "stop"
                    ]],
                    "usage": [
                        "prompt_tokens": usage?.prompt_tokens ?? 0,
                        "completion_tokens": usage?.completion_tokens ?? 0,
                        "total_tokens": usage?.total_tokens ?? 0
                    ]
                ])
            } catch {
                return .internalServerError(error.localizedDescription)
            }
        }

        return .notFound()
    }

    private func downloadModelIfNeeded() async throws {
        try fileManager.createDirectory(at: modelBaseURL, withIntermediateDirectories: true)

        let modelConfigURL = modelBaseURL.appending(path: "mlc-chat-config.json")
        let tensorCacheURL = modelBaseURL.appending(path: "tensor-cache.json")

        if !fileManager.fileExists(atPath: modelConfigURL.path()) {
            try await downloadFile(from: modelRepoBase.appending(path: "mlc-chat-config.json"), to: modelConfigURL)
        }

        if !fileManager.fileExists(atPath: tensorCacheURL.path()) {
            try await downloadFile(from: modelRepoBase.appending(path: "tensor-cache.json"), to: tensorCacheURL)
        }

        let modelConfig = try decode(ModelConfig.self, from: modelConfigURL)
        let paramsConfig = try decode(ParamsConfig.self, from: tensorCacheURL)

        var files: [(URL, URL)] = []
        for tokenizerFile in modelConfig.tokenizerFiles {
            files.append((modelRepoBase.appending(path: tokenizerFile), modelBaseURL.appending(path: tokenizerFile)))
        }
        for record in paramsConfig.records {
            files.append((modelRepoBase.appending(path: record.dataPath), modelBaseURL.appending(path: record.dataPath)))
        }

        totalFiles = files.count + 2
        completedFiles = 0
        if fileManager.fileExists(atPath: modelConfigURL.path()) { completedFiles += 1 }
        if fileManager.fileExists(atPath: tensorCacheURL.path()) { completedFiles += 1 }
        downloadProgressText = "\(completedFiles) / \(totalFiles)"

        for (remote, local) in files {
            if fileManager.fileExists(atPath: local.path()) {
                completedFiles += 1
                downloadProgressText = "\(completedFiles) / \(totalFiles)"
                continue
            }
            statusText = "Downloading \(local.lastPathComponent)..."
            try await downloadFile(from: remote, to: local)
            completedFiles += 1
            downloadProgressText = "\(completedFiles) / \(totalFiles)"
        }

        modelStateText = "Downloaded"
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func downloadFile(from remoteURL: URL, to localURL: URL) async throws {
        try fileManager.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tempURL, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: NSError(domain: "NeuraNode", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Download failed for \(remoteURL.lastPathComponent)"]))
                    return
                }

                do {
                    try? self?.fileManager.removeItem(at: localURL)
                    try self?.fileManager.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: tempURL, to: localURL)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            self.activeDownloads.append(task)
            task.resume()
        }
    }

    private func localModelReady() -> Bool {
        let modelConfigURL = modelBaseURL.appending(path: "mlc-chat-config.json")
        let tensorCacheURL = modelBaseURL.appending(path: "tensor-cache.json")
        guard fileManager.fileExists(atPath: modelConfigURL.path()),
              fileManager.fileExists(atPath: tensorCacheURL.path()) else {
            return false
        }

        guard let modelConfig = try? decode(ModelConfig.self, from: modelConfigURL),
              let paramsConfig = try? decode(ParamsConfig.self, from: tensorCacheURL) else {
            return false
        }

        for tokenizerFile in modelConfig.tokenizerFiles {
            if !fileManager.fileExists(atPath: modelBaseURL.appending(path: tokenizerFile).path()) {
                return false
            }
        }
        for record in paramsConfig.records {
            if !fileManager.fileExists(atPath: modelBaseURL.appending(path: record.dataPath).path()) {
                return false
            }
        }
        return true
    }

    private func localFileCount() -> Int {
        guard let urls = try? fileManager.contentsOfDirectory(at: modelBaseURL, includingPropertiesForKeys: nil) else {
            return 0
        }
        return urls.count
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func startSilentKeepAlive() throws {
        if audioPlayer?.isPlaying == true { return }
        guard let silenceURL = Self.ensureSilentAudioFile() else {
            throw NSError(domain: "NeuraNode", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Unable to create silent audio file"])
        }

        let player = try AVAudioPlayer(contentsOf: silenceURL)
        player.volume = 0.0
        player.numberOfLoops = -1
        player.prepareToPlay()
        player.play()
        audioPlayer = player
    }

    private static func ensureSilentAudioFile() -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let caches else { return nil }
        let fileURL = caches.appendingPathComponent("silence.caf")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleIMA4,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 12800
        ]

        do {
            guard let format = AVAudioFormat(settings: settings),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else {
                return nil
            }
            buffer.frameLength = 44100
            let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            try file.write(from: buffer)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func detectTailscaleIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let addr = interface.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)
            guard family == UInt8(AF_INET), name == "tailscale0" || name.hasPrefix("utun") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let candidate = String(cString: host)
            if candidate != "127.0.0.1" {
                return candidate
            }
        }
        return nil
    }

    private static func detectPrimaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let addr = interface.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)
            guard family == UInt8(AF_INET), name == "en0" || name == "pdp_ip0" || name.hasPrefix("bridge") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let candidate = String(cString: host)
            if candidate != "127.0.0.1" {
                return candidate
            }
        }
        return nil
    }
}
