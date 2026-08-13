# OTP Bridge — Current State & Issues

## What's Built

An Android ↔ macOS app that syncs SMS OTPs over local Wi-Fi. Android extracts OTPs from incoming SMS and sends them encrypted to the Mac, which auto-copies to clipboard.

**Tech stack:**
- Android: Kotlin + Jetpack Compose, NotificationListenerService + SMS BroadcastReceiver, Room DB, Raw TCP client, X25519 + AES-256-GCM
- macOS: Swift + SwiftUI + AppKit, MenuBarExtra, Raw TCP server (NWListener), SwiftData, CryptoKit
- Both in monorepo at `/Users/alokkumar/Documents/Bridge`
- Android builds with JDK 17: `export JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home && cd android-app && ./gradlew assembleDebug`
- macOS builds with: `xcodebuild -project mac-app/OTPBridge.xcodeproj -scheme OTPBridge build`

**Status: working end-to-end.** OTPs are extracted on Android, sent encrypted, decrypted on the Mac, and auto-copied to the clipboard. Verified with a live OTP on a physical device.

---

## RESOLVED ISSUES

### ✅ 1. CRITICAL: Decryption failed on Mac (`authenticationFailure`)

**Root cause:** A wire-format mismatch, not a key-derivation problem. Android's `CryptoManager.encrypt()` prepended a redundant 4-byte length header *inside* the encrypted payload, producing `[4-byte len][12-byte nonce][ciphertext+tag]`. `WebSocketClient.sendFrame()` then added the outer TCP frame length on top. The Mac's `AES.GCM.SealedBox(combined:)` expects exactly `[12-byte nonce][ciphertext+tag]` with no inner prefix, so the 4 stray bytes shifted the nonce and every decrypt failed with `authenticationFailure`. (The X25519 shared-secret derivation was actually correct on both sides.)

**Fix:** `encrypt()` now returns `[12-byte nonce][ciphertext+tag]` with no inner length; `decrypt()` updated to match. Files: `android-app/.../crypto/CryptoManager.kt`.

### ✅ 2. Mac TCP server (`NWListener`) silently died → `ECONNREFUSED`

**Root cause:** `WebSocketServer.start()` called `stop()` unconditionally at the top, cancelling a healthy listener. `PairingWindow.startPairing()` calls `start()` again, so opening the pairing window tore down the live socket. The listener also never recovered from a `.failed` state. Android then logged repeated `failed to connect ... ECONNREFUSED (Connection refused)` on port 8420.

**Fix:** `start()` now no-ops if the listener is already `.ready`, and the `stateUpdateHandler` auto-restarts on `.failed`. File: `mac-app/.../WebSocketServer/WebSocketServer.swift`.

### ✅ 3. Stale shared secret on reconnect / re-pair

**Root cause:** On a new TCP connection the Mac kept the previous `sharedSecret`; on Android, `handshakeComplete` stayed `true` after a disconnect, so a reconnected socket skipped the handshake and sent encrypted data the other side couldn't read.

**Fix:**
- Mac: `handleNewConnection()` clears `sharedSecret`/`isConnected` so a fresh handshake is required; `processMessage()` resets and re-handshakes if decryption fails (covers the "cleared one side only" case).
- Android: `handleDisconnect()` resets `handshakeComplete`; `sendOTP()` now guards on `handshakeComplete` before sending.

### ✅ 4. macOS asset catalog was never bundled (no app icon / logo)

**Root cause:** `Assets.xcassets` was not referenced in `OTPBridge.xcodeproj` at all — there was no `PBXResourcesBuildPhase`, so no `Assets.car` was produced. `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` had nothing to compile, so the app icon and any named images (e.g. `Image("Logo")`) resolved to the empty-asset placeholder.

**Fix:** Added the asset catalog as a `PBXFileReference`, put it in the `OTPBridge` group, and created a `PBXResourcesBuildPhase` that compiles it. `Assets.car` now ships with both `AppIcon` and `Logo`. File: `mac-app/OTPBridge.xcodeproj/project.pbxproj`.

### ✅ 5. Branding — logo wired into both apps

- App icons regenerated at all sizes from `logo.png` (macOS `AppIcon.appiconset` 16–1024px; Android `mipmap-*` launcher icons at every density, with an adaptive icon that renders the full logo edge-to-edge).
- In-app headers use the logo: macOS pairing window (with a connected-state checkmark badge) and the menu dropdown header; Android top app bar.
- Menu bar **tray** icon is the SF Symbol `link` (interlocking links, echoing the logo's bridge/infinity mark) — kept as a template glyph so it adapts to light/dark menu bars.

### ✅ 6. Show which company an OTP came from

**Added:** `CompanyResolver` on Android maps the SMS source to a friendly brand name — first from keywords in the message body (e.g. "Flipkart", "Amazon", "Google"), falling back to the TRAI sender-header token (e.g. `VA-FLPKRT-S` → "Flipkart"). The resolved name travels in a new optional `company` field in the OTP payload; the Mac stores it (SwiftData) and shows it in the hero card, recent list, and notification, falling back to the raw sender when unknown. Files: `android-app/.../otp/CompanyResolver.kt`, `OTPMessage.kt`, `OTPExtractor.kt`; `mac-app/.../WebSocketServer.swift`, `Storage/OTPRecord.swift`, `StorageManager.swift`, `MenuBar/MenuBarView.swift`.

### ✅ 7. macOS menu bar UI redesign

Rebuilt the dropdown: compact header with a connection pill, a hero OTP card (company name + digit-grouped code like `853 114` + click-to-copy with animated checkmark), a clean RECENT list with hover highlight and relative timestamps, and icon-styled footer rows. Fixed a layout bug where the `.ultraThinMaterial` background plus empty header elements created large blank gaps in the panel. File: `mac-app/.../MenuBar/MenuBarView.swift`.

### ✅ (Earlier) Samsung hides SMS content in notifications

Solved by `SMSReceiver.kt` (`SMS_RECEIVED` BroadcastReceiver) which reads the full SMS body directly. `RECEIVE_SMS` permission is granted.

### ✅ (Earlier) Mac server only started when paired

Server now starts unconditionally in `applicationDidFinishLaunching`.

---

## File Locations

| File | Purpose |
|------|---------|
| `android-app/.../crypto/CryptoManager.kt` | X25519 keygen, deriveSharedSecret (SHA256 of ECDH output), AES-GCM encrypt/decrypt |
| `android-app/.../websocket/WebSocketClient.kt` | TCP client, handshake, sends encrypted OTPs |
| `android-app/.../otp/CompanyResolver.kt` | Resolves brand/company name from sender header + message body |
| `android-app/.../otp/OTPExtractor.kt` | Extracts the OTP code and attaches the resolved company |
| `android-app/.../notification/SMSReceiver.kt` | BroadcastReceiver for SMS (bypasses Samsung hiding) |
| `android-app/.../ui/MainScreen.kt` | Main UI, pairing flow, logo in top bar |
| `mac-app/OTPBridge/WebSocketServer/WebSocketServer.swift` | NWListener TCP server, handshake, decrypt, dispatch, auto-restart |
| `mac-app/OTPBridge/Crypto/CryptoManager.swift` | Curve25519 keygen, deriveSharedSecret (SHA256 of ECDH), AES-GCM encrypt/decrypt |
| `mac-app/OTPBridge/MenuBar/MenuBarView.swift` | Redesigned menu bar dropdown with OTP history |
| `mac-app/OTPBridge/UI/PairingWindow.swift` | QR code display for pairing (logo header) |
| `mac-app/OTPBridge/OTPBridgeApp.swift` | App entry, `link` tray glyph, starts server on launch |
| `mac-app/OTPBridge/Assets.xcassets` | App icon + Logo (now compiled into the app) |
| `mac-app/OTPBridge.xcodeproj/project.pbxproj` | Project; now includes the asset-catalog resources build phase |

---

## Key Protocol

- **Transport:** Raw TCP on port 8420 (NOT WebSocket)
- **Framing:** `[4-byte big-endian length][payload]`
- **Handshake:** JSON `{"type":"handshake","device_id":"...","public_key":"<base64 32-byte raw X25519 key>"}`
- **Encryption:** AES-256-GCM with 12-byte random nonce, key = SHA-256(X25519 ECDH shared secret)
- **Wire format (encrypted):** `[4-byte frame length][12-byte nonce][AES-GCM ciphertext+tag]` — no inner length prefix
- **OTP payload (decrypted JSON):** `{"type":"otp","sender":"...","otp":"...","company":"<optional brand>","timestamp":<ms>}`

---

## Clean Re-pair Procedure (if keys ever get out of sync)

1. Kill Mac app: `pkill -f OTPBridge`
2. Clear both sides:
   - Mac: `defaults delete io.github.alokkr016.bridge`
   - Android: `adb shell pm clear io.github.alokkr016.otpbridge`
3. Rebuild: Android with JDK 17, Mac with xcodebuild
4. Reinstall Android APK, launch both
5. Mac: menu bar → "Pair New Device…" → QR shows
6. Android: open app → "Pair with Mac" → scan QR
7. Trigger an OTP SMS; it should decrypt and auto-copy on the Mac.
