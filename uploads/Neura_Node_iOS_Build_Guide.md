# Neura Node

A SwiftUI iOS app that turns an iPhone into a headless local LLM node with an OpenAI-compatible API on port 8080.

Important honesty note: the current upstream `MLCSwift` package exposes a Swift API, but internally still imports `MLCEngineObjC`. So this solution uses the modern Swift-facing MLC package exactly as requested, without you writing Objective-C or touching legacy `LLMEngine.mm`, but the upstream package is not literally zero-ObjC internally.

## What this delivers

- `NeuraNodeApp.swift`, main entry point
- `NodeManager.swift`, state, model boot, HTTP server, background keep-alive, Tailscale IP detection
- `ContentView.swift`, minimal dark UI
- exact Xcode setup steps
- exact `Info.plist` keys
- exact capabilities to enable
- a practical local REST server wrapper because I could not verify a current public iOS `MLCEngine.serve()` Swift API in upstream docs/source

---

## 1. Xcode project setup

### Create the project

1. Open Xcode.
2. File, New, Project.
3. Choose iOS, App.
4. Product Name: `Neura Node`
5. Interface: `SwiftUI`
6. Language: `Swift`
7. Use Core Data: off
8. Include Tests: optional
9. Save project somewhere convenient.

### Minimum deployment target

Set deployment target to **iOS 16.0+**.

Reason: cleaner async/await and `Network.framework` usage.

### Add the MLC Swift package

In Xcode:

1. Select the project.
2. Select the app target.
3. Go to `Package Dependencies`.
4. Add local package dependency pointing to:
   - `.../mlc-llm/ios/MLCSwift`

If you prefer a remote dependency, you can clone `mlc-llm` locally first, then add the local package. The official iOS packaging flow still expects the `mlc_llm package` build step outside Xcode.

### Prepare model/runtime artifacts

MLC requires prebuilt runtime/model libraries plus a `bundle` directory.

Use a separate local checkout of `mlc-llm`, then:

```bash
git clone https://github.com/mlc-ai/mlc-llm.git
cd mlc-llm
git submodule update --init --recursive
cd ios
```

Create `mlc-package-config.json` in your Neura Node project root. Example for a realistic iPhone 12 Pro Max target:

```json
{
  "device": "iphone",
  "model_list": [
    {
      "model": "HF://mlc-ai/Llama-3.2-1B-Instruct-q4f16_1-MLC",
      "model_id": "Llama-3.2-1B-Instruct-q4f16_1-MLC",
      "estimated_vram_bytes": 2200000000,
      "model_lib": "llama_q4f16_1",
      "bundle_weight": true,
      "overrides": {
        "context_window_size": 2048,
        "prefill_chunk_size": 128
      }
    }
  ]
}
```

Then build the package artifacts:

```bash
export MLC_LLM_SOURCE_DIR=/absolute/path/to/mlc-llm
cd /path/to/your/NeuraNodeProject
mlc_llm package
```

That should create:

```text
dist/
  bundle/
    mlc-app-config.json
    Llama-3.2-1B-Instruct-q4f16_1-MLC/
  lib/
    libmlc_llm.a
    libmodel_iphone.a
    libsentencepiece.a
    libtokenizers_cpp.a
    libtokenizers_c.a
    libtvm_runtime.a
```

For a drawer device, I strongly recommend `bundle_weight: true` so it boots without needing to fetch model files at runtime.

### Add the bundled files into the app

In Xcode:

1. Select target, `Build Phases`
2. Add a `Copy Files` phase or `Copy Bundle Resources` entry
3. Copy the entire `dist/bundle` folder into the app bundle

The app code below expects:

```text
Bundle.main/bundle/mlc-app-config.json
Bundle.main/bundle/<model directory>
```

### Linker and library settings

In target `Build Settings`:

#### Library Search Paths
Add:

```text
$(PROJECT_DIR)/dist/lib
```

#### Other Linker Flags
Add:

```text
-Wl,-all_load
-lmodel_iphone
-lmlc_llm
-ltvm_runtime
-ltokenizers_cpp
-lsentencepiece
-ltokenizers_c
```

### Frameworks to add

Under `Frameworks, Libraries, and Embedded Content`, make sure these are present:

- `AVFoundation.framework`
- `Network.framework`
- `UIKit.framework` (normally already available)

---

## 2. Signing & Capabilities

Open target, `Signing & Capabilities`, then add:

### Background Modes
Check:

- `Audio, AirPlay, and Picture in Picture`
- `Background fetch` (optional, not critical)
- `Background processing` (optional, useful but not enough alone)

The important one for your keep-awake strategy is **Audio**.

### Network related privacy expectations
Local network prompts can appear when binding/listening or advertising services.

If you want Bonjour discovery, add it. If not, you can skip Bonjour and just show the Tailscale IP plus port.

For your case, I would skip Bonjour unless you explicitly want zero-config local discovery.

---

## 3. Info.plist keys

Add these keys manually.

### Required

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>fetch</string>
    <string>processing</string>
</array>

<key>NSLocalNetworkUsageDescription</key>
<string>Neura Node exposes a local API so your other devices can connect to the on-device model.</string>
```

### Optional, only if using Bonjour service advertisement

```xml
<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
</array>
```

### ATS
Not needed for serving local HTTP on port 8080.

If you later make the app call insecure remote HTTP endpoints, then add ATS exceptions. For this build, leave ATS alone.

---

## 4. File layout

Create these Swift files in your app target:

- `NeuraNodeApp.swift`
- `NodeManager.swift`
- `ContentView.swift`

---

## 5. NeuraNodeApp.swift

```swift
import SwiftUI
import UIKit

@main
struct NeuraNodeApp: App {
    @StateObject private var nodeManager = NodeManager()

    init() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(nodeManager)
                .preferredColorScheme(.dark)
        }
    }
}
```

---

## 6. NodeManager.swift

```swift
import SwiftUI
import Foundation
import AVFoundation
import Network
import MLCSwift
import Darwin

@MainActor
final class NodeManager: NSObject, ObservableObject {
    @Published var remoteAccessEnabled: Bool = false
    @Published var isModelLoaded: Bool = false
    @Published var isServerRunning: Bool = false
    @Published var statusText: String = "Offline"
    @Published var tailscaleAddressText: String = "Not detected"
    @Published var lastError: String?

    let port: UInt16 = 8080

    private let engine = MLCEngine()
    private var httpServer: TinyHTTPServer?
    private var audioPlayer: AVAudioPlayer?

    private let modelID = "Llama-3.2-1B-Instruct-q4f16_1-MLC"
    private let modelLib = "llama_q4f16_1"

    override init() {
        super.init()
        refreshNetworkStatus()
        statusText = "Ready"
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
            try configureAudioSession()
            try startSilentKeepAlive()
            refreshNetworkStatus()

            if !isModelLoaded {
                statusText = "Loading model..."
                try await loadBundledModel()
                isModelLoaded = true
            }

            statusText = "Starting API server..."
            try await startHTTPServer()

            remoteAccessEnabled = true
            isServerRunning = true
            statusText = "Online at \(tailscaleAddressText):\(port)"
        } catch {
            lastError = error.localizedDescription
            statusText = "Error: \(error.localizedDescription)"
            remoteAccessEnabled = false
            isServerRunning = false
        }
    }

    func stopNode() {
        httpServer?.stop()
        httpServer = nil

        Task {
            await engine.unload()
        }

        audioPlayer?.stop()
        audioPlayer = nil

        remoteAccessEnabled = false
        isServerRunning = false
        isModelLoaded = false
        statusText = "Offline"
    }

    func refreshNetworkStatus() {
        tailscaleAddressText = Self.detectTailscaleIPv4() ?? Self.detectPrimaryIPv4() ?? "IP unavailable"

        if isServerRunning {
            statusText = "Online at \(tailscaleAddressText):\(port)"
        }
    }

    private func loadBundledModel() async throws {
        let bundleURL = Bundle.main.bundleURL.appending(path: "bundle")
        let modelURL = bundleURL.appending(path: modelID)

        guard FileManager.default.fileExists(atPath: modelURL.path()) else {
            throw NSError(
                domain: "NeuraNode",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Bundled model directory not found at \(modelURL.path())"]
            )
        }

        await engine.reload(modelPath: modelURL.path(), modelLib: modelLib)
    }

    private func startHTTPServer() async throws {
        if httpServer != nil { return }

        let server = TinyHTTPServer(port: port) { [weak self] request in
            guard let self else {
                return TinyHTTPResponse.internalServerError("Node manager deallocated")
            }
            return await self.handle(request: request)
        }

        try server.start()
        httpServer = server
    }

    private func handle(request: TinyHTTPRequest) async -> TinyHTTPResponse {
        if request.method == "GET" && request.path == "/v1/models" {
            let payload: [String: Any] = [
                "object": "list",
                "data": [[
                    "id": modelID,
                    "object": "model",
                    "owned_by": "neura-node"
                ]]
            ]
            return .json(payload)
        }

        if request.method == "GET" && request.path == "/health" {
            return .json([
                "ok": true,
                "model_loaded": isModelLoaded,
                "server_running": isServerRunning,
                "address": tailscaleAddressText,
                "port": port
            ])
        }

        if request.method == "POST" && request.path == "/v1/chat/completions" {
            do {
                let body = try JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any] ?? [:]
                let messagesArray = body["messages"] as? [[String: Any]] ?? []
                let temperature = body["temperature"] as? Double
                let maxTokens = body["max_tokens"] as? Int
                let stream = (body["stream"] as? Bool) ?? false

                if stream {
                    return .badRequest("Streaming HTTP responses are not implemented in this lightweight wrapper yet. Send stream=false.")
                }

                let mlcMessages: [ChatCompletionMessage] = messagesArray.compactMap { item in
                    guard let roleString = item["role"] as? String else { return nil }
                    let content = item["content"] as? String ?? ""

                    let role: ChatCompletionRole
                    switch roleString {
                    case "system": role = .system
                    case "assistant": role = .assistant
                    case "tool": role = .tool
                    default: role = .user
                    }

                    return ChatCompletionMessage(role: role, content: content)
                }

                var fullText = ""
                var usageBlock: CompletionUsage?

                let streamResponses = await engine.chat.completions.create(
                    messages: mlcMessages,
                    model: modelID,
                    max_tokens: maxTokens,
                    stream: true,
                    stream_options: StreamOptions(include_usage: true),
                    temperature: temperature.map(Float.init)
                )

                for await chunk in streamResponses {
                    if let usage = chunk.usage {
                        usageBlock = usage
                    } else if let content = chunk.choices.first?.delta.content?.asText() {
                        fullText += content
                    }
                }

                let payload: [String: Any] = [
                    "id": UUID().uuidString,
                    "object": "chat.completion",
                    "created": Int(Date().timeIntervalSince1970),
                    "model": modelID,
                    "choices": [[
                        "index": 0,
                        "message": [
                            "role": "assistant",
                            "content": fullText
                        ],
                        "finish_reason": "stop"
                    ]],
                    "usage": [
                        "prompt_tokens": usageBlock?.prompt_tokens ?? 0,
                        "completion_tokens": usageBlock?.completion_tokens ?? 0,
                        "total_tokens": usageBlock?.total_tokens ?? 0
                    ]
                ]

                return .json(payload)
            } catch {
                return .internalServerError(error.localizedDescription)
            }
        }

        return .notFound()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func startSilentKeepAlive() throws {
        if audioPlayer != nil {
            if audioPlayer?.isPlaying == true { return }
        }

        guard let silenceURL = Self.ensureSilentAudioFile() else {
            throw NSError(
                domain: "NeuraNode",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Could not prepare silent audio file"]
            )
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
            AVEncoderBitRateKey: 12800,
            AVLinearPCMBitDepthKey: 16
        ]

        do {
            let format = AVAudioFormat(settings: settings)
            guard let format else { return nil }
            let frameCount: AVAudioFrameCount = 44100
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
            buffer.frameLength = frameCount

            let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            try file.write(from: buffer)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func detectTailscaleIPv4() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)

            guard family == UInt8(AF_INET), name == "tailscale0" || name.hasPrefix("utun") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            let candidate = String(cString: host)
            if candidate != "127.0.0.1" {
                address = candidate
                break
            }
        }

        return address
    }

    private static func detectPrimaryIPv4() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)

            guard family == UInt8(AF_INET), name == "en0" || name == "pdp_ip0" || name.hasPrefix("bridge") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            let candidate = String(cString: host)
            if candidate != "127.0.0.1" {
                address = candidate
                break
            }
        }

        return address
    }
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

    static func json(_ object: Any, statusCode: Int = 200) -> TinyHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])) ?? Data("{}".utf8)
        return TinyHTTPResponse(
            statusCode: statusCode,
            statusText: "OK",
            headers: [
                "Content-Type": "application/json",
                "Content-Length": "\(data.count)",
                "Connection": "close"
            ],
            body: data
        )
    }

    static func badRequest(_ message: String) -> TinyHTTPResponse {
        json(["error": ["message": message, "type": "bad_request"]], statusCode: 400)
    }

    static func internalServerError(_ message: String) -> TinyHTTPResponse {
        json(["error": ["message": message, "type": "server_error"]], statusCode: 500)
    }

    static func notFound() -> TinyHTTPResponse {
        json(["error": ["message": "Not found", "type": "not_found"]], statusCode: 404)
    }

    func serialized() -> Data {
        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        for (key, value) in headers {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"

        var data = Data(response.utf8)
        data.append(body)
        return data
    }
}

final class TinyHTTPServer {
    typealias Handler = (TinyHTTPRequest) async -> TinyHTTPResponse

    private let port: UInt16
    private let handler: Handler
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "neura.node.http")

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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, _, error in
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

        let parts = text.components(separatedBy: "\r\n\r\n")
        let head = parts.first ?? ""
        let bodyString = parts.dropFirst().joined(separator: "\r\n\r\n")

        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw NSError(domain: "TinyHTTPServer", code: 2)
        }

        let requestParts = requestLine.components(separatedBy: " ")
        guard requestParts.count >= 2 else {
            throw NSError(domain: "TinyHTTPServer", code: 3)
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pieces = line.components(separatedBy: ": ")
            if pieces.count >= 2 {
                headers[pieces[0]] = pieces.dropFirst().joined(separator: ": ")
            }
        }

        return TinyHTTPRequest(
            method: requestParts[0],
            path: requestParts[1],
            headers: headers,
            bodyData: Data(bodyString.utf8)
        )
    }
}
```

---

## 7. ContentView.swift

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var nodeManager: NodeManager

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Neura Node")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Headless local LLM server")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }

                VStack(spacing: 18) {
                    HStack {
                        Text("Remote API Access")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { nodeManager.remoteAccessEnabled },
                            set: { newValue in
                                nodeManager.setRemoteAccess(newValue)
                            }
                        ))
                        .labelsHidden()
                        .tint(.green)
                        .scaleEffect(1.25)
                    }

                    Divider().overlay(.white.opacity(0.12))

                    VStack(alignment: .leading, spacing: 12) {
                        StatusRow(label: "Status", value: nodeManager.statusText)
                        StatusRow(label: "Tailscale IP", value: nodeManager.tailscaleAddressText)
                        StatusRow(label: "Port", value: "8080")

                        if let error = nodeManager.lastError {
                            StatusRow(label: "Last Error", value: error, valueColor: .red.opacity(0.9))
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )

                Spacer()
            }
            .padding(24)
        }
    }
}

private struct StatusRow: View {
    let label: String
    let value: String
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

            Text(value)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

---

## 8. How to use it

1. Install Tailscale on the iPhone separately and log it in.
2. Launch `Neura Node` once.
3. Tap the single toggle.
4. Wait for `Loading model...` then `Online at x.x.x.x:8080`.
5. From another device on Tailscale, call:

```bash
curl http://TAILSCALE_IP:8080/health
```

Then:

```bash
curl http://TAILSCALE_IP:8080/v1/models
```

Then a chat completion:

```bash
curl http://TAILSCALE_IP:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Llama-3.2-1B-Instruct-q4f16_1-MLC",
    "messages": [
      {"role": "user", "content": "Give me a one sentence hello."}
    ],
    "stream": false,
    "max_tokens": 80
  }'
```

---

## 9. Practical notes for the iPhone 12 Pro Max target

### Recommended model class

For stable always-on behavior on A14 with 6 GB RAM, I would not start with a 7B model.

Use one of these first:

- Llama 3.2 1B Instruct, safest
- Gemma 2B quantized, maybe acceptable
- Phi small models, depending on converted availability

If you push too large a model, the phone will thermal throttle, memory pressure will spike, and the app may get killed.

### Headless reality check

The silent-audio trick plus idle timer disable helps a lot, but iOS does not provide a true never-kill guarantee for arbitrary local servers. This is the best practical loophole-based setup, not a formal daemon entitlement.

### Boot reliability

For a drawer phone, bundle the weights in-app.
Do not rely on first-launch downloads.

### Auto-start on device reboot

iOS does not let third-party apps fully auto-launch after reboot like a daemon. You will likely need one manual launch after a reboot unless you use device management or supervised enterprise flows.

---

## 10. Recommended next improvements

If you want this productionised further, the next things I’d add are:

1. SSE streaming support for `stream: true`
2. API key auth header for the local endpoint
3. automatic model selection from `mlc-app-config.json`
4. Bonjour advertisement toggle
5. watchdog and self-heal logging to file
6. lock-screen friendly single huge start button

---

## 11. Biggest constraint I want to be blunt about

Your requirement mentioned using `MLCEngine` native `.serve()` if available. I could verify the public iOS Swift API for `reload`, `unload`, and `chat.completions.create`, but I could not verify a current public Swift iOS `.serve()` entrypoint in upstream docs/source. So I intentionally used a tiny Swift HTTP wrapper instead of inventing an API that may not exist in the package version you pull.

That makes this answer more honest and more likely to compile.

---

## 12. Files saved

This guide was saved to:

`/home/taha/.openclaw/workspace/uploads/Neura_Node_iOS_Build_Guide.md`

If you want, I can do the next step too and generate a full ready-to-import Xcode project skeleton plus a ZIP in `/uploads/` instead of just the guide.