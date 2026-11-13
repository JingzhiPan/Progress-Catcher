// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Jindu",
    platforms: [.macOS(.v14)],
    targets: [
        // 純邏輯：資料模型、存檔、日期統計、格子排版。不依賴介面，可單獨測試。
        .target(name: "JinduCore"),
        // 菜單欄 app 本體。
        .executableTarget(name: "Jindu", dependencies: ["JinduCore"]),
        .testTarget(name: "JinduCoreTests", dependencies: ["JinduCore"]),
    ]
)
