import Foundation
import JinduCore

// 進度表的 MCP 服務（stdio 傳輸）。
// 協定很小：每行一個 JSON-RPC 訊息，從標準輸入讀、往標準輸出寫；日誌只能走標準錯誤。
// 這裡只做轉接，工具的定義和實作都在 JinduCore 的 AgentTools。

let serverVersion = "0.3.1"
let supportedProtocols = ["2025-06-18", "2025-03-26", "2024-11-05"]

func log(_ message: String) {
    FileHandle.standardError.write(Data("[progress-catcher] \(message)\n".utf8))
}

func send(_ object: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

func reply(_ id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func fail(_ id: Any, code: Int, _ message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as [String: Any]])
}

/// 和菜單欄 app 用同一個資料夾；JINDU_DATA_DIR 可以改到別處（測試用）。
func dataDirectory() -> URL {
    if let custom = ProcessInfo.processInfo.environment["JINDU_DATA_DIR"], !custom.isEmpty {
        return URL(fileURLWithPath: custom)
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Jindu")
}

MainActor.assumeIsolated {
    // 打包腳本用：印出工具清單（名字 + 一句話），寫進安裝包的 manifest，免得兩邊對不上。
    if CommandLine.arguments.contains("--list-tools") {
        let brief = AgentTools.definitions.map { ["name": $0["name"] ?? "", "description": $0["title"] ?? ""] }
        send(["version": serverVersion, "tools": brief])
        exit(0)
    }

    let store = Store(directory: dataDirectory())
    log("ready, data at \(store.fileURL?.path ?? "?")")

    while let line = readLine(strippingNewline: true) {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
        guard let raw = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
              let message = raw as? [String: Any] else {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"] as [String: Any]])
            continue
        }
        let method = message["method"] as? String
        let params = message["params"] as? [String: Any] ?? [:]
        // 沒有 id 的是通知，不用回。
        guard let id = message["id"], !(id is NSNull) else { continue }
        guard let method else { continue } // 對方的回應，我們沒發過請求，忽略

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            reply(id, result: [
                "protocolVersion": supportedProtocols.contains(requested) ? requested : supportedProtocols[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "progress-catcher", "title": "Progress Catcher", "version": serverVersion],
                "instructions": AgentTools.serverInstructions,
            ])

        case "ping":
            reply(id, result: [:])

        case "tools/list":
            reply(id, result: ["tools": AgentTools.definitions])

        case "tools/call":
            guard let name = params["name"] as? String else {
                fail(id, code: -32602, "Missing tool name")
                continue
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try AgentTools.call(name, arguments: arguments, store: store)
                reply(id, result: ["content": [["type": "text", "text": text]], "isError": false])
            } catch let error as ToolError {
                // 工具層面的錯（找不到項目、參數不對）照規範放在結果裡，讓模型看得到、能自己修正。
                reply(id, result: ["content": [["type": "text", "text": error.message]], "isError": true])
            } catch {
                reply(id, result: ["content": [["type": "text", "text": "Unexpected error: \(error)"]], "isError": true])
            }

        case "resources/list":
            reply(id, result: ["resources": []])
        case "prompts/list":
            reply(id, result: ["prompts": []])

        default:
            fail(id, code: -32601, "Method not found: \(method)")
        }
    }
}
