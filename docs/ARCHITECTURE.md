# OTP Bridge — Architecture

## System Overview

OTP Bridge is a two-device system: an Android phone and a Mac, communicating over local Wi-Fi using a custom encrypted TCP protocol.

```
┌──────────────────────────────────┐         ┌──────────────────────────────────┐
│           Android App            │         │           macOS App              │
│                                  │         │                                  │
│  ┌─────────────────────────┐    │         │    ┌─────────────────────────┐  │
│  │  NotificationListener   │    │         │    │  MenuBarExtra           │  │
│  │  (listens to SMS,       │    │         │    │  (menu bar icon +       │  │
│  │   banking apps)         │    │         │    │   dropdown)             │  │
│  └──────────┬──────────────┘    │         │    └──────────┬──────────────┘  │
│             │                   │         │               │                 │
│  ┌──────────▼──────────────┐    │         │    ┌──────────▼──────────────┐  │
│  │  OTP Extractor          │    │         │    │  TCP Server             │  │
│  │  (regex: 4-8 digit      │    │         │    │  (port 8420)            │  │
│  │   codes near keywords)  │    │         │    │  (NWListener)           │  │
│  └──────────┬──────────────┘    │         │    └──────────┬──────────────┘  │
│             │                   │         │               │                 │
│  ┌──────────▼──────────────┐    │         │    ┌──────────▼──────────────┐  │
│  │  CryptoManager          │    │         │    │  CryptoManager          │  │
│  │  (X25519 + ChaCha20)    │    │         │    │  (Curve25519 + ChaCha)  │  │
│  └──────────┬──────────────┘    │  TCP    │    └──────────┬──────────────┘  │
│             │                   │◄───────►│               │                 │
│  ┌──────────▼──────────────┐    │  :8420  │    ┌──────────▼──────────────┐  │
│  │  TCP Client             │    │         │    │  Decrypt + Dispatch     │  │
│  │  (java.net.Socket)      │    │         │    └──────┬──────────┬───────┘  │
│  └─────────────────────────┘    │         │           │          │          │
│                                  │         │    ┌──────▼──┐ ┌────▼────────┐ │
│  ┌─────────────────────────┐    │         │    │Clipboard│ │Notification │ │
│  │  Room Database          │    │         │    │ Manager │ │  Manager    │ │
│  │  (OTP history)          │    │         │    └─────────┘ └─────────────┘ │
│  └─────────────────────────┘    │         │                                  │
│                                  │         │    ┌─────────────────────────┐  │
│  ┌─────────────────────────┐    │         │    │  SwiftData Storage      │  │
│  │  PairingManager         │    │         │    │  (OTP history)          │  │
│  │  (QR code scanning,     │    │         │    └─────────────────────────┘  │
│  │   key exchange)         │    │         │                                  │
│  └─────────────────────────┘    │         │    ┌─────────────────────────┐  │
│                                  │         │    │  PairingManager         │  │
│                                  │         │    │  (QR generation,        │  │
│                                  │         │    │   key exchange)         │  │
│                                  │         │    └─────────────────────────┘  │
└──────────────────────────────────┘         └──────────────────────────────────┘
```

## Protocol Layers

### Layer 1: TCP Transport
- Android opens TCP connection to Mac's IP on port 8420
- Raw bytes, no HTTP, no WebSocket handshake

### Layer 2: Frame Protocol
```
┌──────────────┬─────────────────────────────┐
│ Length (4B)   │ Payload (variable)           │
│ big-endian   │ JSON or encrypted bytes      │
└──────────────┴─────────────────────────────┘
```

### Layer 3: Message Types

| Message | Direction | Content |
|---------|-----------|---------|
| `handshake` | Android → Mac | `{"type":"handshake","device_id":"...","public_key":"..."}` |
| `handshake_ack` | Mac → Android | `{"type":"handshake_ack","device_id":"...","public_key":"..."}` |
| `otp` | Android → Mac | `{"type":"otp","sender":"HDFC","otp":"843921","timestamp":...}` (encrypted) |

### Layer 4: Encryption (after handshake)

```
┌───────────┬────────────────────┬──────────────┐
│ Nonce 12B │ Ciphertext (var)   │ Auth Tag 16B │
└───────────┴────────────────────┴──────────────┘
```

All OTP messages are encrypted with ChaCha20-Poly1305 using the shared secret derived from X25519 ECDH.

## Component Details

### Android

#### NotificationListenerService
- Listens for all system notifications
- Extracts title (sender) and text from extras
- Passes to OTPExtractor
- **Requires**: User grants notification access in Settings

#### OTPExtractor
- Regex pattern: `\b\d{4,8}\b` near keywords (`OTP`, `code`, `verification`, `PIN`)
- Context-aware: `OTP is 843921` → extracts `843921`
- Returns null if no OTP pattern found (filters out non-OTP notifications)

#### TCP Client (WebSocketClient.kt)
- Connects via `java.net.Socket`
- Sends/receives 4-byte length-prefixed frames
- Auto-reconnect with exponential backoff (1s → 30s max)
- Reads in background coroutine, dispatches to main thread

#### BLE Scanner
- Runs in the background to scan for BLE advertisements from the paired Mac
- Extracts the Mac's new IP address dynamically, eliminating the need to re-scan the QR code if the IP changes

#### Update Manager (UpdateManager.kt)
- Queries `https://bridge-updater.alokraj016.workers.dev/android` to check for updates
- Downloads the release `.apk` to the cache directory and triggers package installation securely via `FileProvider` and system installation `Intent`

#### Room Database
- Entity: `OTPEntity(id, sender, otp, timestamp, synced)`
- DAO: `getRecentOTPs()` returns `Flow<List<OTPEntity>>`
- Used for OTP history display in Compose UI

### macOS

#### Menu Bar (MenuBarExtra)
- Shows key icon in menu bar
- Dropdown: connection status, last OTP, recent history, update triggers
- "Pair New Device..." opens pairing window
- "Check for Updates..." manually queries the update worker

#### TCP Server (WebSocketServer.swift)
- `NWListener` on port 8420
- Accepts single connection (Phase 1)
- Reads length-prefixed frames in async loop
- Dispatches handshake → decrypt → OTP to handlers

#### BLE Advertiser
- Advertises the Mac's local Wi-Fi IP address over Bluetooth LE upon startup or IP change
- Allows the paired Android device to auto-discover connection details without re-pairing

#### Updater Manager (UpdaterManager.swift)
- Connects to the update worker to check for new versions on startup
- Downloads the `.dmg` asset, mounts it locally via `hdiutil`, overwrites the app bundle in `/Applications`, and automatically restarts the app

#### Pairing Window
- Shows QR code with pairing URL
- QR encodes: `otpbridge://<device_id>?pk=<key>&ip=<ip>&port=8420`
- Updates UI when handshake completes

#### Clipboard Manager
- `NSPasteboard.general.setString(otp, forType: .string)`
- Clears after 2 seconds

#### Notification Manager
- `UNUserNotificationCenter` for system notifications
- Shows: "OTP Received: 843921 from HDFC — Copied to clipboard"

## Auto-Update Architecture

The update system is completely serverless and private-repo friendly, consisting of:
1. **GitHub Releases**: Hosts the release assets (`Bridge-Installer.dmg` and `app-release.apk`) in the private repository.
2. **Cloudflare Worker (bridge-updater)**:
   - Serves as a secure API gateway proxying GitHub's private API using a securely stored `GITHUB_TOKEN`.
   - `GET /android`: Returns the latest version name, calculated version code (e.g. `1.0.2` -> `10002`), release notes, and download proxy URL.
   - `GET /` or `/mac`: Returns Tauri-compatible JSON containing the latest DMG proxy URL.
   - `GET /download/*`: Streams the binary file payloads directly from GitHub release assets to client devices.

## Data Flow: End to End

```
1. SMS arrives on Android
2. NotificationListenerService fires
3. OTPExtractor regex finds "843921" in text
4. OTPMessage("HDFC", "843921", timestamp) created
5. Message serialized to JSON, encrypted with ChaCha20-Poly1305
6. Encrypted bytes framed: [4B length][encrypted payload]
7. Sent over TCP to Mac:8420
8. Mac server reads frame, decrypts with shared secret
9. JSON parsed → OTPMessage extracted
10. NSPasteboard.setString("843921") — copied to clipboard
11. UNUserNotificationCenter posts notification
12. SwiftData saves OTPRecord for history
13. MenuBarView updates with new OTP
```
