// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Jindu",
    platforms: [.macOS(.v14)],
    targets: [
        // 純邏輯：資料模型、存檔、日期統計、格子排版、給 agent 用的工具。不依賴介面，可單獨測試。
        .target(name: "JinduCore"),
        // 菜單欄 app 本體。
        .executableTarget(name: "Jindu", dependencies: ["JinduCore"]),
        // MCP 服務：讓 agent（Claude 等）透過標準輸入輸出讀寫同一份資料。
        .executableTarget(name: "JinduMCP", dependencies: ["JinduCore"]),
        .testTarget(name: "JinduCoreTests", dependencies: ["JinduCore"]),
    ]
)
