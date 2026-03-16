# CamNDI

A lightweight native macOS menu bar app that captures a USB webcam and broadcasts it as an NDI source on the local network.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![NDI](https://img.shields.io/badge/NDI-SDK%206-green)

## Features

- **Zero-dependency** — pure AppKit, no Electron, no browser tech, no OBS required
- **Menu bar only** — lives in the system tray with a live camera preview
- **NDI output** — appears as "CamNDI" on the local network, visible to any NDI receiver
- **Camera selection** — switch between built-in and external USB cameras
- **macOS Camera Effects** — works with Apple's built-in portrait mode, background replacement, and reactions (via the green camera button)
- **Live statistics** — resolution, capture/NDI FPS, data rate, frame counts
- **Lightweight** — no GPU compositing overhead, direct pixel buffer passthrough to NDI

## Requirements

- macOS 15 or later
- [NDI SDK for Apple](https://ndi.video/for-developers/ndi-sdk/) installed

## Setup

1. **Install the NDI SDK**

   Download from [ndi.video](https://ndi.video/for-developers/ndi-sdk/) and run the installer. The SDK installs to `/Library/NDI SDK for Apple/`.

2. **Clone the repo**

   ```bash
   git clone https://github.com/manuelvegadev/CamNDI.git
   cd CamNDI
   ```

3. **Copy NDI SDK files into the project**

   ```bash
   cp /Library/NDI\ SDK\ for\ Apple/include/*.h NDI/
   cp /Library/NDI\ SDK\ for\ Apple/lib/macOS/libndi.dylib NDI/
   ```

4. **Open and build**

   ```bash
   open CamNDI.xcodeproj
   ```

   Build and run (⌘R). The app appears as a camera icon in the menu bar.

## Architecture

```
CamNDI/
├── AppDelegate.swift        # Menu bar UI, pipeline wiring, stats
├── CameraController.swift   # AVCaptureSession, camera switching
├── NDISender.swift           # NDI C API bridge, async frame sending
├── BridgingHeader.h          # Exposes NDI C headers to Swift
└── Info.plist                # Camera/network permissions, LSUIElement
NDI/
├── *.h                       # NDI SDK headers (not included — see Setup)
└── libndi.dylib              # NDI runtime library (not included)
```

**Frame pipeline:**

```
AVCaptureSession → CVPixelBuffer → NDIlib_send_send_video_v2
                                 → CALayer.contents (preview)
```

Frames pass directly from the camera to NDI with no intermediate processing. macOS system camera effects (portrait, background, studio light) are applied by the OS before frames reach the app.

## Building a DMG

To create a distributable `.dmg` installer:

```bash
./scripts/build-dmg.sh
```

This builds a Release configuration, embeds `libndi.dylib` inside the app bundle, and creates `build/CamNDI.dmg`. Users just drag CamNDI.app to Applications.

> **Note:** For distribution to others, you should sign with a Developer ID certificate and notarize with Apple. See [Apple's documentation on notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## License

MIT
