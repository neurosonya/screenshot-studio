import Cocoa
import WebKit
import UniformTypeIdentifiers
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    static var shared: AppDelegate!

    var window: NSWindow!
    var webView: WKWebView!
    var statusItem: NSStatusItem!
    var bridge: Bridge!
    var hotKeyRef: EventHotKeyRef?

    private var pageLoaded = false
    private var pendingJS: [String] = []
    private var pendingURLs: [URL] = []

    // MARK: - Запуск

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildMenu()
        buildWindow()
        buildStatusItem()
        registerHotKey()
        NSApp.activate(ignoringOtherApps: true)
        pendingURLs.forEach { openFile($0) }
        pendingURLs.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // файлы, переданные при запуске («Открыть в...»), приходят раньше, чем создано окно
    func application(_ application: NSApplication, open urls: [URL]) {
        if window == nil { pendingURLs.append(contentsOf: urls) }
        else { urls.forEach { openFile($0) } }
    }

    // MARK: - Окно и WebView

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        bridge = Bridge(app: self)
        config.userContentController.add(bridge, name: "native")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1380, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Скриншот-студия"
        window.minSize = NSSize(width: 960, height: 640)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.makeKeyAndOrderFront(nil)

        guard let url = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            fatalError("editor.html не найден в Resources")
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func showWindow() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        pendingJS.forEach { webView.evaluateJavaScript($0, completionHandler: nil) }
        pendingJS.removeAll()
        runSelfCheckHooks()
    }

    // Автопроверка сборки без участия человека (только при заданных переменных окружения):
    // SNAPSTUDIO_EVAL - тело async-функции JS, результат печатается в stdout;
    // SNAPSTUDIO_SNAPSHOT - путь, куда сохранить снимок содержимого окна;
    // SNAPSTUDIO_QUIT - завершить приложение после проверки.
    private func runSelfCheckHooks() {
        let env = ProcessInfo.processInfo.environment
        guard env["SNAPSTUDIO_EVAL"] != nil || env["SNAPSTUDIO_SNAPSHOT"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let finish = {
                if let path = env["SNAPSTUDIO_SNAPSHOT"] {
                    self.webView.takeSnapshot(with: nil) { image, _ in
                        if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                           let png = rep.representation(using: .png, properties: [:]) {
                            try? png.write(to: URL(fileURLWithPath: path))
                            print("SNAPSHOT:", path)
                        }
                        if env["SNAPSTUDIO_QUIT"] != nil { NSApp.terminate(nil) }
                    }
                } else if env["SNAPSTUDIO_QUIT"] != nil {
                    NSApp.terminate(nil)
                }
            }
            if let code = env["SNAPSTUDIO_EVAL"] {
                self.webView.callAsyncJavaScript(code, arguments: [:], in: nil, in: .page) { result in
                    switch result {
                    case .success(let value): print("EVAL:", value)
                    case .failure(let error): print("EVAL ERROR:", error)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: finish)
                }
            } else {
                finish()
            }
        }
    }

    // системное окно выбора файла для <input type="file"> внутри страницы
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }

    // MARK: - JS-мост

    func js(_ code: String) {
        if pageLoaded { webView.evaluateJavaScript(code, completionHandler: nil) }
        else { pendingJS.append(code) }
    }

    func toast(_ message: String) {
        js("window.__native.toast(\(jsString(message)))")
    }

    func sendImage(_ data: Data, mime: String) {
        let b64 = data.base64EncodedString()
        js("window.__native.receiveImage(\"\(b64)\", \(jsString(mime)))")
        showWindow()
    }

    func openFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        sendImage(data, mime: mime)
    }

    // MARK: - Захват области экрана

    func captureArea() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-\(UUID().uuidString).png")
        window.orderOut(nil)
        // окно должно успеть исчезнуть, прежде чем появится курсор выделения
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-i", "-x", "-t", "png", tmp.path]
            proc.terminationHandler = { _ in
                DispatchQueue.main.async {
                    if let data = try? Data(contentsOf: tmp) {
                        self.sendImage(data, mime: "image/png")
                        try? FileManager.default.removeItem(at: tmp)
                    } else {
                        self.showWindow()
                    }
                }
            }
            do { try proc.run() } catch {
                self.showWindow()
                self.toast("Не удалось запустить захват экрана")
            }
        }
    }

    // MARK: - Меню

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "О программе Скриншот-студия",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Завершить Скриншот-студию",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let file = NSMenu(title: "Файл")
        file.addItem(item("Новый снап", #selector(menuNew), "n"))
        file.addItem(item("Открыть картинку...", #selector(menuOpen), "o"))
        file.addItem(item("Снять область экрана", #selector(menuCapture), "a", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(item("Сохранить проект", #selector(menuSave), "s"))
        file.addItem(item("Экспорт картинки...", #selector(menuExport), "e"))
        file.addItem(item("Копировать результат", #selector(menuCopy), "c", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(withTitle: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(); fileItem.submenu = file
        mainMenu.addItem(fileItem)

        let edit = NSMenu(title: "Правка")
        edit.addItem(item("Отменить", #selector(menuUndo), "z"))
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: NSSelectorFromString("cut:"), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: NSSelectorFromString("paste:"), keyEquivalent: "v")
        edit.addItem(withTitle: "Выделить все", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = edit
        mainMenu.addItem(editItem)

        let view = NSMenu(title: "Вид")
        view.addItem(item("По размеру окна", #selector(menuZoomFit), "0"))
        view.addItem(item("50%", #selector(menuZoom50), ""))
        view.addItem(item("100%", #selector(menuZoom100), "1"))
        view.addItem(item("200%", #selector(menuZoom200), "2"))
        view.addItem(.separator())
        view.addItem(withTitle: "Во весь экран", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        let viewItem = NSMenuItem(); viewItem.submenu = view
        mainMenu.addItem(viewItem)

        let win = NSMenu(title: "Окно")
        win.addItem(withTitle: "Свернуть", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Показать Скриншот-студию", action: #selector(menuShow), keyEquivalent: "")
        let winItem = NSMenuItem(); winItem.submenu = win
        mainMenu.addItem(winItem)
        NSApp.windowsMenu = win

        NSApp.mainMenu = mainMenu
    }

    private func item(_ title: String, _ action: Selector, _ key: String,
                      _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        it.target = self
        return it
    }

    @objc func menuNew() { js("window.__native.newSnap()") }
    @objc func menuSave() { js("saveProject()") }
    @objc func menuExport() { js("exportImage()") }
    @objc func menuCopy() { js("copyImage()") }
    @objc func menuUndo() { js("window.__native.menuUndo()") }
    @objc func menuCapture() { captureArea() }
    @objc func menuShow() { showWindow() }
    @objc func menuZoomFit() { js("window.__native.setZoom('fit')") }
    @objc func menuZoom50() { js("window.__native.setZoom('0.5')") }
    @objc func menuZoom100() { js("window.__native.setZoom('1')") }
    @objc func menuZoom200() { js("window.__native.setZoom('2')") }

    @objc func menuOpen() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window) { result in
            if result == .OK, let url = panel.url { self.openFile(url) }
        }
    }

    // MARK: - Значок в строке меню и глобальный хоткей

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "Скриншот-студия")
        let menu = NSMenu()
        menu.addItem(item("Снять область экрана   ⌃⌥S", #selector(menuCapture), ""))
        menu.addItem(item("Открыть Скриншот-студию", #selector(menuShow), ""))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Завершить", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { AppDelegate.shared.captureArea() }
            return noErr
        }, 1, &eventType, nil, nil)
        let hotKeyID = EventHotKeyID(signature: OSType(0x53534E50), id: 1) // "SSNP"
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

func jsString(_ s: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [s])
    let arr = String(data: data, encoding: .utf8)!
    return String(arr.dropFirst().dropLast())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
