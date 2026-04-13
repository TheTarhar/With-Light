# NeuraNode

Production-oriented SwiftUI iOS project skeleton for a headless local LLM node.

## Requirements
- iOS 16.0+
- iPhone 12 Pro Max target
- Local checkout of `mlc-ai/mlc-llm`
- Add local package dependency: `ios/MLCSwift`
- Link MLC runtime/model static libraries built via `mlc_llm package`

## Included files
- `NeuraNode.xcodeproj`
- `NeuraNode/NeuraNodeApp.swift`
- `NeuraNode/NodeManager.swift`
- `NeuraNode/ContentView.swift`
- `NeuraNode/Info.plist`

## Notes
- Model weights are not bundled. The app downloads `Llama-3.2-1B-Instruct-q4f16_1-MLC` on first activation.
- Tiny HTTP server serves `/health`, `/v1/models`, and `/v1/chat/completions` on port 8080.
- Background persistence uses `AVAudioSession` playback plus a silent loop.
- You still need to add the `MLCSwift` package and MLC linker settings inside Xcode.
