# OTP Bridge

Privacy-first local app that syncs SMS OTPs from Android to macOS instantly, with auto-copy to clipboard.

**No cloud. No servers. No subscriptions. Everything stays on your local Wi-Fi network.**

---

## What Problem Does This Solve?

When you receive a verification code via SMS on your Android phone while working on your Mac, you have to:
1. Pick up your phone
2. Read the SMS
3. Manually type the code on your Mac

OTP Bridge eliminates this friction:
- OTPs appear on your Mac **instantly** when the SMS arrives on your phone
- The code is **automatically copied to your clipboard** — just paste it
- A desktop notification shows the OTP for reference
- OTP history is maintained in the menu bar

---

## Architecture

### High-Level Overview

```
┌─────────────────────────┐          ┌─────────────────────────────┐
│      Android App         │          │        macOS App            │
│                          │          │                             │
│  NotificationListener    │          │  MenuBarExtra (menu bar)    │
│        │                 │          │        │                    │
│  OTP Extractor           │    TCP   │  TCP Server (port 8420)     │
│        │                 │◄────────►│        │                    │
│  WebSocket Client ───────│──────────│  Decrypt + Dispatch         │
│        │                 │          │     ┌───┴───┐               │
│  Room Database           │          │  Clipboard  Notification    │
│                          │          │  Manager    Manager         │
└─────────────────────────┘          └─────────────────────────────┘
```

### Communication Protocol

| Layer | Detail |
|-------|--------|
| Transport | Raw TCP over local Wi-Fi (port 8420) |
| Framing | `[4-byte big-endian length][payload]` |
| Handshake | JSON `{"type":"handshake","device_id":"...","public_key":"..."}` |
| Encryption | ChaCha20-Poly1305 with X25519-derived shared secret |
| Key Exchange | X25519 (Curve25519) ECDH during pairing via QR code |

### Pairing Flow

```
Mac                              Android
│                                 │
│  1. Generate X25519 keypair     │
│  2. Display QR code with:       │
│     - device_id                 │
│     - public_key (32 bytes)     │
│     - IP address                │
│     - port                      │
│                                 │
│         ┌──── Scan QR ────┐     │
│         │                 │     │
│         └─────────────────┘     │
│                                 │
│         3. Android generates    │
│            X25519 keypair       │
│                                 │
│  4. Connect TCP to Mac:8420    │
│  5. Send handshake with        │
│     its public_key             │
│                                 │
│  6. Mac derives shared secret  │
│     using ECDH                 │
│                                 │
│  7. Mac sends handshake_ack    │
│     with its public_key        │
│                                 │
│  8. Android derives same       │
│     shared secret              │
│                                 │
│  ═══ Encrypted channel ═══     │
```

### Encryption Details

| Component | Algorithm |
|-----------|-----------|
| Key Exchange | X25519 (Curve25519) ECDH |
| Symmetric Cipher | ChaCha20-Poly1305 |
| Key Derivation | HKDF-SHA256 with salt `"OTPBridge-v1"` |
| Nonce | Random 12 bytes per message |

**Wire format:** `[4-byte length][12-byte nonce][ciphertext][16-byte auth tag]`

---

## Project Structure

```
Bridge/
├── README.md                          # This file
├── android-app/                       # Android Kotlin project
│   ├── build.gradle.kts               # Root Gradle config
│   ├── settings.gradle.kts
│   ├── gradle.properties
│   ├── app/
│   │   ├── build.gradle.kts           # App dependencies & config
│   │   ├── src/main/
│   │   │   ├── AndroidManifest.xml
│   │   │   ├── res/xml/network_security_config.xml
│   │   │   └── kotlin/io/github/alokkr016/otpbridge/
│   │   │       ├── OTPBridgeApp.kt              # Application class
│   │   │       ├── MainActivity.kt              # Compose activity
│   │   │       ├── crypto/
│   │   │       │   ├── CryptoManager.kt         # X25519 + ChaCha20
│   │   │       │   └── KeyPairStore.kt          # Key persistence
│   │   │       ├── notification/
│   │   │       │   ├── OTNotificationListenerService.kt
│   │   │       │   └── NotificationHelper.kt
│   │   │       ├── otp/
│   │   │       │   ├── OTPExtractor.kt          # Regex extraction
│   │   │       │   └── OTPMessage.kt            # Data classes
│   │   │       ├── pairing/
│   │   │       │   └── PairingManager.kt
│   │   │       ├── websocket/
│   │   │       │   └── WebSocketClient.kt       # Raw TCP client
│   │   │       ├── database/
│   │   │       │   ├── OTPDatabase.kt
│   │   │       │   ├── OTPDao.kt
│   │   │       │   └── OTPEntity.kt
│   │   │       ├── ui/
│   │   │       │   ├── MainScreen.kt
│   │   │       │   ├── PairingScreen.kt         # QR scanner (ZXing)
│   │   │       │   └── theme/
│   │   │       ├── viewmodel/
│   │   │       │   └── MainViewModel.kt
│   │   │       └── service/
│   │   │           └── BridgeForegroundService.kt
│   │   └── build/outputs/apk/debug/
│   │       └── app-debug.apk
│
└── mac-app/                           # macOS Swift project
    ├── OTPBridge.xcodeproj/
    └── OTPBridge/
        ├── OTPBridgeApp.swift          # App entry + MenuBarExtra
        ├── crypto/
        │   ├── CryptoManager.swift     # Curve25519 + ChaChaPoly
        │   └── KeyPairStore.swift      # Keychain persistence
        ├── pairing/
        │   ├── PairingManager.swift
        │   └── QRCodeGenerator.swift
        ├── WebSocketServer/
        │   └── WebSocketServer.swift   # Raw TCP server
        ├── clipboard/
        │   └── ClipboardManager.swift
        ├── notification/
        │   └── NotificationManager.swift
        ├── storage/
        │   ├── OTPRecord.swift          # SwiftData model
        │   └── StorageManager.swift
        ├── menubar/
        │   └── MenuBarView.swift
        └── ui/
            ├── ContentView.swift
            ├── PairingWindow.swift
            └── StatusView.swift
```

---

## Tech Stack

### Android

| Component | Technology | Version |
|-----------|-----------|---------|
| Language | Kotlin | 2.0.21 |
| UI | Jetpack Compose + Material3 | BOM 2024.01.00 |
| Notification Listener | NotificationListenerService | API 26+ |
| Camera / QR | CameraX + ZXing | 3.5.2 |
| Database | Room | 2.6.1 |
| Networking | Raw TCP (java.net.Socket) | - |
| Crypto | javax.crypto (X25519 + ChaCha20-Poly1305) | API 26+ |
| Serialization | kotlinx-serialization-json | 1.6.2 |
| Build | Gradle | 8.14 |
| Min SDK | 26 (Android 8) | - |
| Target SDK | 35 | - |

### macOS

| Component | Technology | Version |
|-----------|-----------|---------|
| Language | Swift | 5.0 |
| UI | SwiftUI + AppKit | - |
| Menu Bar | MenuBarExtra | macOS 14+ |
| Networking | Network.framework (NWListener + NWConnection) | - |
| Crypto | CryptoKit (Curve25519 + ChaChaPoly) | - |
| QR Code | CoreImage CIFilter.qrCodeGenerator | - |
| Storage | SwiftData | - |
| Notifications | UserNotifications | - |
| Clipboard | NSPasteboard | - |
| Min Target | macOS 14 (Sonoma) | - |

---

## Build & Run

### Prerequisites

- **Android**: Android Studio, JDK 17, Android device (API 26+)
- **macOS**: Xcode 15+, macOS 14+
- Both devices on the same Wi-Fi network

### Android

```bash
export JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home
cd android-app
./gradlew assembleDebug
```

APK output: `android-app/app/build/outputs/apk/debug/app-debug.apk`

Install on device:
```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### macOS

```bash
xcodebuild -project mac-app/OTPBridge.xcodeproj -scheme OTPBridge -destination 'platform=macOS' build
```

Or open `mac-app/OTPBridge.xcodeproj` in Xcode and press ⌘R.

### First Time Setup

1. **macOS**: Launch app → click key icon in menu bar → "Pair New Device..."
2. **Android**: Open OTP Bridge → tap "Pair with Mac" → scan QR code
3. Connection establishes automatically
4. Send an SMS with an OTP to your phone → it auto-copies to Mac clipboard

---

## How to Contribute

### Development Setup

1. Clone the repo
2. Open `android-app/` in Android Studio
3. Open `mac-app/OTPBridge.xcodeproj` in Xcode
4. Make changes, build, and test on real devices (emulators can't receive SMS)

### Code Conventions

**Android (Kotlin):**
- Package: `io.github.alokkr016.otpbridge`
- Use `@SerialName` annotations on `@Serializable` data classes (kotlinx-serialization defaults to camelCase)
- Room entities use `@Entity` and DAOs use `@Dao`
- UI follows Jetpack Compose patterns with Material3

**macOS (Swift):**
- Bundle ID: `io.github.alokkr016.OTPBridge`
- Use `NSLog("[OTPBridge] ...")` for debug logging (appears in Console.app)
- Crypto uses CryptoKit (`Curve25519`, `ChaChaPoly`, `Insecure.SHA1`)
- UI uses SwiftUI with `MenuBarExtra` for menu bar

### Key Patterns

**Message Framing (both platforms):**
```
[4 bytes: payload length][payload bytes]
```

**Encryption (both platforms):**
```
[12 bytes: nonce][ciphertext][16 bytes: auth tag]
```

**Handshake JSON:**
```json
{
  "type": "handshake",
  "device_id": "<UUID>",
  "public_key": "<base64-encoded-32-byte-X25519-key>"
}
```

### Known Issues & Areas for Improvement

1. **Single device pairing** — only one Android device at a time (Phase 2: multi-device)
2. **No auto-reconnect on Mac side** — server must be listening
3. **QR re-pairing** — clearing app data required to re-pair
4. **No BLE discovery** — planned for Phase 3

### Testing

**Manual testing flow:**
1. Build both apps
2. Launch Mac app → click "Pair New Device"
3. Launch Android app → "Pair with Mac" → scan QR
4. Verify: Mac shows "Device Connected", Android shows "Connected"
5. Send SMS with OTP (e.g., "Your OTP is 123456")
6. Verify: OTP appears in Mac menu bar and clipboard

**Check logs:**
```bash
# Android
adb logcat --pid=$(adb shell pidof io.github.alokkr016.otpbridge) | grep -iE "WebSocket|Pairing|OTP"

# macOS
log show --predicate 'process == "OTPBridge"' --last 5m
```

---

## Roadmap

### Phase 1 (Current) ✅
- [x] Device pairing via QR code
- [x] X25519 key exchange
- [x] ChaCha20-Poly1305 encryption
- [x] OTP extraction from notifications
- [x] Auto-copy to clipboard
- [x] Desktop notifications
- [x] Menu bar app
- [x] OTP history

### Phase 2
- [ ] Auto-reconnect handling
- [ ] Auto-launch at login
- [ ] Multiple device support
- [ ] Improved OTP detection patterns

### Phase 3
- [ ] BLE for device discovery
- [ ] Clipboard sync (bidirectional)
- [ ] Notification mirroring
- [ ] Nearby lock (auto-lock Mac when phone moves away)

### Future
- [ ] File transfer (small files/text snippets)

---

## Security Model

| Property | Implementation |
|----------|---------------|
| **Encryption** | ChaCha20-Poly1305 (AEAD) |
| **Key Exchange** | X25519 ECDH |
| **Key Storage** | Android: encrypted SharedPreferences / macOS: Keychain |
| **Transport** | Local TCP only (no internet) |
| **Pairing** | Requires physical proximity (QR scan) |
| **No cloud** | Zero network calls outside local Wi-Fi |
| **No analytics** | Zero telemetry or tracking |

### Threat Model

- **Network eavesdropper**: Cannot decrypt (ChaCha20-Poly1305)
- **Remote attacker**: Cannot reach (no internet exposure)
- **Compromised app**: Keys in Keychain/encrypted storage
- **Physical access**: QR scan required for pairing

---

## License

Private — All rights reserved.
