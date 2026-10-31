# Contributing to OTP Bridge

Contributions back to https://github.com/alokkr016/Bridge are welcome. You may not copy this code into another project, republish it, or keep a fork as a separate app. A fork is only for opening a pull request here. The full terms are in [LICENSE](LICENSE).

## Getting Started

### Prerequisites

- **Android development**: Android Studio, JDK 17, physical Android device (API 26+)
- **macOS development**: Xcode 15+, macOS 14+ (Sonoma)
- Both machines on the same Wi-Fi network for testing

### Repository Setup

```bash
git clone <repo-url> Bridge
cd Bridge
```

### Building

**Android:**
```bash
export JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home
cd android-app
./gradlew assembleDebug
```

**macOS:**
```bash
xcodebuild -project mac-app/OTPBridge.xcodeproj -scheme OTPBridge build
```

## Architecture for Agents

This section is designed for AI coding agents working on this codebase.

### Key Facts

| Fact | Detail |
|------|--------|
| Android package | `io.github.alokkr016.otpbridge` |
| macOS bundle ID | `io.github.alokkr016.OTPBridge` |
| Port | 8420 (TCP) |
| Protocol | Custom raw TCP with `[4-byte length][payload]` framing |
| Encryption | X25519 + ChaCha20-Poly1305 |
| Min Android | API 26 (Android 8) |
| Min macOS | 14 (Sonoma) |

### Communication Protocol

Both platforms use a custom binary protocol over TCP. **NOT WebSocket**.

**Frame format:**
```
Byte 0-3:  Payload length (big-endian uint32)
Byte 4-N:  Payload data (JSON or encrypted JSON)
```

**Handshake (first message from Android to Mac):**
```json
{
  "type": "handshake",
  "device_id": "<UUID>",
  "public_key": "<base64-encoded-32-byte-X25519-raw-public-key>"
}
```

**Handshake ack (Mac to Android):**
```json
{
  "type": "handshake_ack",
  "device_id": "<UUID>",
  "public_key": "<base64-encoded-32-byte-X25519-raw-public-key>"
}
```

**OTP message (Android to Mac, encrypted):**
```json
{
  "type": "otp",
  "sender": "HDFC",
  "otp": "843921",
  "timestamp": 1719138212
}
```

### Critical Implementation Details

1. **Public key format**: Both platforms use **raw 32-byte** Curve25519/X25519 keys. Android's `KeyPair.public.encoded` returns 44-byte X509 format — extract last 32 bytes with `.takeLast(32).toByteArray()`.

2. **JSON serialization**: Android uses `kotlinx-serialization` with `encodeDefaults = true` and `@SerialName` annotations to ensure `type` field is always sent. The default serialization omits fields with default values.

3. **Base64 in QR URLs**: Use URL-safe base64 (`-` and `_` instead of `+` and `/`) because Android's `Uri.getQueryParameter()` URL-decodes `+` as space. The device ID is the URI host, not a query parameter: `otpbridge://<device_id>?pk=...`

4. **Network security**: Android blocks cleartext HTTP/WS by default. Add `network_security_config.xml` with `cleartextTrafficPermitted="true"` and reference in `AndroidManifest.xml`.

5. **Crypto wire format**: Encrypted payload = `[12-byte nonce][ChaChaPoly ciphertext]`. The 4-byte length prefix covers the entire encrypted payload including nonce and auth tag.

### File Map for Common Changes

| Change | Android Files | macOS Files |
|--------|--------------|-------------|
| QR pairing flow | `ui/PairingScreen.kt`, `pairing/PairingManager.kt` | `Pairing/PairingWindow.swift`, `Pairing/PairingManager.swift`, `Pairing/QRCodeGenerator.swift` |
| OTP detection | `otp/OTPExtractor.kt`, `notification/OTNotificationListenerService.kt` | (no changes needed) |
| Encryption | `crypto/CryptoManager.kt`, `crypto/KeyPairStore.kt` | `Crypto/CryptoManager.swift`, `Crypto/KeyPairStore.swift` |
| WebSocket/TCP | `websocket/WebSocketClient.kt` | `WebSocketServer/WebSocketServer.swift` |
| Clipboard | (no changes needed) | `Clipboard/ClipboardManager.swift` |
| Menu bar UI | (no changes needed) | `MenuBar/MenuBarView.swift`, `UI/PairingWindow.swift` |
| Android UI | `ui/MainScreen.kt`, `viewmodel/MainViewModel.kt` | (no changes needed) |
| Database | `database/OTPDatabase.kt`, `database/OTPDao.kt`, `database/OTPEntity.kt` | `Storage/OTPRecord.swift`, `Storage/StorageManager.swift` |
| App lifecycle | `MainActivity.kt`, `OTPBridgeApp.kt`, `service/BridgeForegroundService.kt` | `OTPBridgeApp.swift` |

### Testing Checklist

When making changes, verify:

- [ ] Android builds: `./gradlew assembleDebug`
- [ ] macOS builds: `xcodebuild -project mac-app/OTPBridge.xcodeproj -scheme OTPBridge build`
- [ ] Pairing works end-to-end
- [ ] OTP extraction works (send test SMS)
- [ ] Clipboard copy works
- [ ] Notifications appear
- [ ] Encrypted messages decrypt correctly on both sides

### Debugging

**Android logs:**
```bash
adb logcat --pid=$(adb shell pidof io.github.alokkr016.otpbridge) | grep -iE "WebSocket|Pairing|OTP|error"
```

**macOS logs (Console.app):**
```bash
log show --predicate 'process == "OTPBridge"' --last 5m
```

**macOS logs (NSLog):**
All `NSLog("[OTPBridge] ...")` calls appear in Console.app under the OTPBridge process.
