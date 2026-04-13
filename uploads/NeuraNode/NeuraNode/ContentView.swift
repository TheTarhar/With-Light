import SwiftUI

struct ContentView: View {
    @EnvironmentObject var nodeManager: NodeManager

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.07, green: 0.08, blue: 0.11)],
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
                        Text("Activate Remote Access")
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { nodeManager.remoteAccessEnabled },
                            set: { nodeManager.setRemoteAccess($0) }
                        ))
                        .labelsHidden()
                        .tint(.green)
                        .scaleEffect(1.35)
                    }

                    Divider().overlay(.white.opacity(0.12))

                    VStack(alignment: .leading, spacing: 12) {
                        StatusRow(label: "Status", value: nodeManager.statusText)
                        StatusRow(label: "Model", value: nodeManager.modelStateText)
                        StatusRow(label: "Progress", value: nodeManager.downloadProgressText)
                        StatusRow(label: "Tailscale IP", value: nodeManager.tailscaleAddressText)
                        StatusRow(label: "Port", value: "8080")

                        if let error = nodeManager.lastError {
                            StatusRow(label: "Last Error", value: error, valueColor: .red.opacity(0.95))
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
