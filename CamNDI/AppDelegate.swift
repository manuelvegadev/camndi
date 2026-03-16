//
//  AppDelegate.swift
//  CamNDI
//
//  NSStatusItem tray icon and menu — app entry point.
//

import AppKit
import os

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var previewLayer: CALayer!
    private var menuIsOpen = false

    private let cameraController = CameraController()
    private let ndiSender = NDISender()

    private var cameraSubmenu: NSMenu!
    private var statsSubmenu: NSMenu!

    // Stats
    private var statsTimer: Timer?
    private var statsResolutionItem: NSMenuItem!
    private var statsFPSItem: NSMenuItem!
    private var statsDataRateItem: NSMenuItem!
    private var statsFramesSentItem: NSMenuItem!
    private var statsDroppedItem: NSMenuItem!
    private var prevFramesSent: Int64 = 0
    private var prevBytesSent: Int64 = 0
    private var prevStatsTime: CFAbsoluteTime = 0
    private var prevCaptureFrameCount: Int64 = 0

    // Frame stats — protected by statsLock (written on capture queue, read on main)
    private let statsLock = OSAllocatedUnfairLock(initialState: (width: 0, height: 0, count: Int64(0)))

    // MARK: - Entry Point

    static func main() {
        signal(SIGPIPE, SIG_IGN)

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        startPipeline()
        startStatsTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statsTimer?.invalidate()
        cameraController.stop()
        ndiSender.stop()
    }

    // MARK: - Status Bar Menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.fill",
                                   accessibilityDescription: "CamNDI")
        }

        let menu = NSMenu()
        menu.delegate = self

        // --- Header bar ---
        let headerItem = NSMenuItem()
        let headerView = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 30))

        let titleLabel = NSTextField(labelWithString: "CamNDI")
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.sizeToFit()
        titleLabel.frame.origin = NSPoint(x: 14, y: (30 - titleLabel.frame.height) / 2)
        headerView.addSubview(titleLabel)

        let ghButton = NSButton(frame: NSRect(x: 336 - 14 - 20, y: (30 - 20) / 2, width: 20, height: 20))
        ghButton.bezelStyle = .inline
        ghButton.isBordered = false
        if let img = NSImage(named: "GitHubMark") {
            img.size = NSSize(width: 16, height: 16)
            ghButton.image = img
        }
        ghButton.target = self
        ghButton.action = #selector(openGitHub(_:))
        headerView.addSubview(ghButton)

        headerItem.view = headerView
        menu.addItem(headerItem)

        // --- Live preview ---
        let previewItem = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 196))
        container.wantsLayer = true

        previewLayer = CALayer()
        previewLayer.frame = CGRect(x: 8, y: 8, width: 320, height: 180)
        previewLayer.backgroundColor = NSColor.black.cgColor
        previewLayer.cornerRadius = 6
        previewLayer.masksToBounds = true
        previewLayer.contentsGravity = .resizeAspect
        previewLayer.actions = ["contents": NSNull()]
        container.layer?.addSublayer(previewLayer)

        previewItem.view = container
        menu.addItem(previewItem)

        menu.addItem(.separator())

        // --- Camera selection submenu ---
        let cameraItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        cameraSubmenu = NSMenu()
        cameraSubmenu.delegate = self
        cameraItem.submenu = cameraSubmenu
        menu.addItem(cameraItem)

        menu.addItem(.separator())

        // --- NDI source label + restart ---
        let ndiLabel = NSMenuItem(title: "NDI: CamNDI", action: nil, keyEquivalent: "")
        ndiLabel.isEnabled = false
        menu.addItem(ndiLabel)

        let restartNDI = NSMenuItem(title: "Restart NDI",
                                    action: #selector(restartNDISender(_:)),
                                    keyEquivalent: "")
        restartNDI.target = self
        menu.addItem(restartNDI)

        menu.addItem(.separator())

        // --- Statistics (collapsible via submenu) ---
        let statsItem = NSMenuItem(title: "Statistics", action: nil, keyEquivalent: "")
        statsSubmenu = NSMenu()

        statsResolutionItem = addDisabledItem(to: statsSubmenu, title: "—")
        statsFPSItem = addDisabledItem(to: statsSubmenu, title: "—")
        statsDataRateItem = addDisabledItem(to: statsSubmenu, title: "—")
        statsFramesSentItem = addDisabledItem(to: statsSubmenu, title: "Sent: 0")
        statsDroppedItem = addDisabledItem(to: statsSubmenu, title: "Dropped: 0")

        statsItem.submenu = statsSubmenu
        menu.addItem(statsItem)

        menu.addItem(.separator())

        // --- Quit ---
        let quitItem = NSMenuItem(title: "Quit CamNDI",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func addDisabledItem(to menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    // MARK: - Pipeline

    private func startPipeline() {
        cameraController.onFrame = { [weak self] pixelBuffer in
            guard let self else { return }

            // Lazy-start NDI on first camera frame so the source only appears
            // on the network once we're actually producing video.
            if !self.ndiSender.isActive {
                if !self.ndiSender.start() {
                    print("[CamNDI] NDI unavailable — camera preview only")
                }
            }

            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            self.statsLock.withLock {
                $0.width = w
                $0.height = h
                $0.count += 1
            }

            self.ndiSender.send(pixelBuffer: pixelBuffer)

            // Only render preview when the menu is visible
            guard self.menuIsOpen else { return }

            guard let cgImage = Self.createCGImage(from: pixelBuffer) else { return }

            DispatchQueue.main.async {
                self.previewLayer?.contents = cgImage
            }
        }

        cameraController.start()
    }

    // MARK: - Preview Helper

    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let ctx = CGContext(data: base,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: stride,
                                  space: sRGBColorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                              CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        return ctx.makeImage()
    }

    // MARK: - Stats Timer

    private func startStatsTimer() {
        prevStatsTime = CFAbsoluteTimeGetCurrent()
        prevFramesSent = 0
        prevCaptureFrameCount = 0

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    private func updateStats() {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - prevStatsTime
        guard elapsed > 0 else { return }

        let frameStats = statsLock.withLock { $0 }
        let captureFPS = Double(frameStats.count - prevCaptureFrameCount) / elapsed
        prevCaptureFrameCount = frameStats.count

        let sent = ndiSender.framesSent
        let ndiSentFPS = Double(sent - prevFramesSent) / elapsed

        let totalBytes = ndiSender.bytesSent
        let bytesInInterval = totalBytes - prevBytesSent

        prevFramesSent = sent
        prevBytesSent = totalBytes
        prevStatsTime = now

        let dataRateMBps = (Double(bytesInInterval) / elapsed) / (1024.0 * 1024.0)

        statsResolutionItem.title = "\(frameStats.width)×\(frameStats.height)"
        statsFPSItem.title = "Capture \(String(format: "%.1f", captureFPS)) fps → NDI \(String(format: "%.1f", ndiSentFPS)) fps"
        statsDataRateItem.title = "\(String(format: "%.1f", dataRateMBps)) MB/s"
        statsFramesSentItem.title = "Sent: \(formatCount(sent))"
        statsDroppedItem.title = "Dropped: \(formatCount(ndiSender.droppedFrames))"
    }

    private func formatCount(_ n: Int64) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - Actions

    @objc private func openGitHub(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://github.com/manuelvegadev/CamNDI")!)
    }

    @objc private func restartNDISender(_ sender: NSMenuItem) {
        _ = ndiSender.restart()
    }

    @objc private func selectCamera(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        cameraController.switchCamera(deviceID: deviceID)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {

    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusItem.menu { menuIsOpen = true }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === statusItem.menu { menuIsOpen = false }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === cameraSubmenu else { return }

        menu.removeAllItems()

        let cameras = CameraController.availableCameras
        let currentID = cameraController.currentDeviceID

        for device in cameras {
            let item = NSMenuItem(title: device.localizedName,
                                  action: #selector(selectCamera(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            item.state = (device.uniqueID == currentID) ? .on : .off
            menu.addItem(item)
        }

        if cameras.isEmpty {
            let none = NSMenuItem(title: "No cameras found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
    }
}
