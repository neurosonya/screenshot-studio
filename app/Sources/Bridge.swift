import Cocoa
import WebKit
import UniformTypeIdentifiers

final class Bridge: NSObject, WKScriptMessageHandler {
    unowned let app: AppDelegate

    init(app: AppDelegate) { self.app = app }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "save": save(body)
        case "copy": copy(body)
        case "capture": app.captureArea()
        default: break
        }
    }

    private func save(_ body: [String: Any]) {
        guard let b64 = body["data"] as? String, let data = Data(base64Encoded: b64) else { return }
        let name = body["filename"] as? String ?? "snap.png"
        let mime = body["mime"] as? String ?? "image/png"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [UTType(mimeType: mime) ?? .png]
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: app.window) { result in
            guard result == .OK, let url = panel.url else {
                self.app.toast("Экспорт отменен")
                return
            }
            do {
                try data.write(to: url)
                self.app.toast("Сохранено: " + url.lastPathComponent)
            } catch {
                self.app.toast("Не удалось сохранить: " + error.localizedDescription)
            }
        }
    }

    private func copy(_ body: [String: Any]) {
        guard let b64 = body["data"] as? String,
              let data = Data(base64Encoded: b64),
              let image = NSImage(data: data) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.png, .tiff], owner: nil)
        pb.setData(data, forType: .png)
        if let tiff = image.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        app.toast("Скопировано в буфер обмена!")
    }
}
