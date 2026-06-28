# Graph Report - .  (2026-06-28)

## Corpus Check
- 78 files · ~105,078 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 501 nodes · 652 edges · 44 communities (42 shown, 2 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 23 edges (avg confidence: 0.88)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Android TCP Client|Android TCP Client]]
- [[_COMMUNITY_macOS Menu Bar UI|macOS Menu Bar UI]]
- [[_COMMUNITY_macOS App Lifecycle|macOS App Lifecycle]]
- [[_COMMUNITY_macOS WebSocket Server|macOS WebSocket Server]]
- [[_COMMUNITY_Android Main Activity|Android Main Activity]]
- [[_COMMUNITY_Android UI Screens|Android UI Screens]]
- [[_COMMUNITY_macOS Crypto Manager|macOS Crypto Manager]]
- [[_COMMUNITY_macOS Key Pair Store|macOS Key Pair Store]]
- [[_COMMUNITY_Android Key Pair Store|Android Key Pair Store]]
- [[_COMMUNITY_macOS SwiftData Storage|macOS SwiftData Storage]]
- [[_COMMUNITY_Test Suite|Test Suite]]
- [[_COMMUNITY_BLE Advertiser (Mac)|BLE Advertiser (Mac)]]
- [[_COMMUNITY_Android Foreground Service|Android Foreground Service]]
- [[_COMMUNITY_macOS Pairing Manager|macOS Pairing Manager]]
- [[_COMMUNITY_Android Crypto Manager|Android Crypto Manager]]
- [[_COMMUNITY_Android ViewModel|Android ViewModel]]
- [[_COMMUNITY_macOS Clipboard Manager|macOS Clipboard Manager]]
- [[_COMMUNITY_SMS & Boot Receivers|SMS & Boot Receivers]]
- [[_COMMUNITY_Android Pairing Manager|Android Pairing Manager]]
- [[_COMMUNITY_Android OTP Database|Android OTP Database]]
- [[_COMMUNITY_BLE Scanner (Android)|BLE Scanner (Android)]]
- [[_COMMUNITY_Architecture & Contribution Docs|Architecture & Contribution Docs]]
- [[_COMMUNITY_macOS Component Architecture|macOS Component Architecture]]
- [[_COMMUNITY_Android Room Database|Android Room Database]]
- [[_COMMUNITY_Brand & Visual Identity|Brand & Visual Identity]]
- [[_COMMUNITY_Network Security & Permissions|Network Security & Permissions]]
- [[_COMMUNITY_QR Code Generator|QR Code Generator]]
- [[_COMMUNITY_OTP Record Model|OTP Record Model]]
- [[_COMMUNITY_Android Notification Helper|Android Notification Helper]]
- [[_COMMUNITY_OTP Extractor & Issues|OTP Extractor & Issues]]
- [[_COMMUNITY_Crypto Wire Format & Security|Crypto Wire Format & Security]]
- [[_COMMUNITY_Notification Listener Service|Notification Listener Service]]
- [[_COMMUNITY_Company Resolver|Company Resolver]]
- [[_COMMUNITY_OTP Extractor Logic|OTP Extractor Logic]]
- [[_COMMUNITY_Decryption & Key Issues|Decryption & Key Issues]]
- [[_COMMUNITY_TCP Frame Protocol|TCP Frame Protocol]]
- [[_COMMUNITY_QR Pairing Flow|QR Pairing Flow]]
- [[_COMMUNITY_Protocol Layer Stack|Protocol Layer Stack]]
- [[_COMMUNITY_OTP Entity Model|OTP Entity Model]]

## God Nodes (most connected - your core abstractions)
1. `WebSocketClient` - 23 edges
2. `WebSocketServer` - 20 edges
3. `MainActivity` - 14 edges
4. `MenuBarView` - 14 edges
5. `BLEAdvertiser` - 12 edges
6. `ClipboardManager` - 11 edges
7. `CryptoManager` - 11 edges
8. `BridgeForegroundService` - 10 edges
9. `MainViewModel` - 10 edges
10. `StorageManager` - 10 edges

## Surprising Connections (you probably didn't know these)
- `OTPExtractor (regex 4-8 digits)` --semantically_similar_to--> `OTPExtractor`  [INFERRED] [semantically similar]
  docs/ARCHITECTURE.md → README.md
- `TCP Client (java.net.Socket)` --semantically_similar_to--> `WebSocketClient (TCP Client)`  [INFERRED] [semantically similar]
  docs/ARCHITECTURE.md → README.md
- `Room Database (OTPEntity)` --semantically_similar_to--> `Room Database (Android)`  [INFERRED] [semantically similar]
  docs/ARCHITECTURE.md → README.md
- `NWListener TCP Server` --semantically_similar_to--> `TCP Server / WebSocketServer.swift`  [INFERRED] [semantically similar]
  docs/ARCHITECTURE.md → README.md
- `SMSReceiver (bypass Samsung SMS hiding)` --semantically_similar_to--> `SMSReceiver (BroadcastReceiver)`  [INFERRED] [semantically similar]
  ISSUES.md → README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **OTP End-to-End Transmission Flow** — readme_notification_listener, readme_otp_extractor, readme_websocket_client, readme_crypto_manager_android, docs_architecture_nwlistener, readme_crypto_manager_macos, readme_clipboard_manager, readme_notification_manager [EXTRACTED 0.95]
- **QR Pairing and X25519 Key Exchange Flow** — readme_qr_pairing, readme_x25519_key_exchange, readme_sha256_kdf, readme_pairing_manager_android, readme_pairing_manager_macos [EXTRACTED 0.95]
- **Encrypted TCP Protocol Stack** — docs_architecture_tcp_transport, docs_architecture_frame_layer, docs_architecture_encryption_layer, readme_aes_gcm_encryption [EXTRACTED 0.95]

## Communities (44 total, 2 thin omitted)

### Community 0 - "Android TCP Client"
Cohesion: 0.11
Nodes (16): Boolean, ByteArray, Context, Int, OTPMessage, String, Unit, DataInputStream (+8 more)

### Community 1 - "macOS Menu Bar UI"
Cohesion: 0.12
Nodes (17): ButtonStyle, Configuration, Identifiable, Bool, Date, String, SwiftUI, UUID (+9 more)

### Community 2 - "macOS App Lifecycle"
Cohesion: 0.08
Nodes (18): App, Foundation, String, Void, Notification, OTPBridgeApp, SwiftUI, NotificationManager (+10 more)

### Community 3 - "macOS WebSocket Server"
Cohesion: 0.16
Nodes (12): Bool, CryptoKit, Data, Foundation, Int, String, TimeInterval, Void (+4 more)

### Community 4 - "Android Main Activity"
Cohesion: 0.11
Nodes (10): Boolean, String, OTPBridgeApp, Boolean, Application, Bundle, ClipboardManager, ComponentActivity (+2 more)

### Community 5 - "Android UI Screens"
Cohesion: 0.13
Nodes (17): Long, String, ByteArray, Int, PairedDevice, String, Bitmap, ImageProxy (+9 more)

### Community 6 - "macOS Crypto Manager"
Cohesion: 0.13
Nodes (11): CryptoError, decryptionFailed, encryptionFailed, noKeyPair, CryptoManager, CryptoKit, Curve25519, Data (+3 more)

### Community 7 - "macOS Key Pair Store"
Cohesion: 0.14
Nodes (11): Bool, KeyPairStore, PairedDevice, CryptoKit, Curve25519, Data, Foundation, Int (+3 more)

### Community 8 - "Android Key Pair Store"
Cohesion: 0.14
Nodes (9): Boolean, ByteArray, KeyPairStore, PairedDevice, Int, KeyPair, PairedDevice, String (+1 more)

### Community 9 - "macOS SwiftData Storage"
Cohesion: 0.15
Nodes (9): Foundation, Int, String, SwiftData, TimeInterval, ModelContainer, ModelContext, OTPRecord (+1 more)

### Community 10 - "Test Suite"
Cohesion: 0.15
Nodes (7): XCTest, String, XCTest, OTPBridge, CryptoManagerTests, OTPExtractorTests, XCTestCase

### Community 11 - "BLE Advertiser (Mac)"
Cohesion: 0.17
Nodes (8): CBMutableCharacteristic, CBPeripheralManager, CBPeripheralManagerDelegate, CBService, CoreBluetooth, Foundation, String, BLEAdvertiser

### Community 12 - "Android Foreground Service"
Cohesion: 0.17
Nodes (8): Int, Intent, Notification, IBinder, PowerManager, Service, BridgeForegroundService, WifiManager

### Community 13 - "macOS Pairing Manager"
Cohesion: 0.18
Nodes (7): Bool, CryptoKit, Data, Foundation, PairedDevice, PairingManager, String

### Community 14 - "Android Crypto Manager"
Cohesion: 0.23
Nodes (5): ByteArray, CryptoManager, KeyPair, String, java

### Community 15 - "Android ViewModel"
Cohesion: 0.15
Nodes (9): Boolean, ByteArray, Int, List, OTPEntity, String, AndroidViewModel, StateFlow (+1 more)

### Community 16 - "macOS Clipboard Manager"
Cohesion: 0.21
Nodes (5): ClipboardManager, Cocoa, Int, String, Timer

### Community 17 - "SMS & Boot Receivers"
Cohesion: 0.18
Nodes (7): Context, Intent, Context, Intent, BroadcastReceiver, SMSReceiver, BootReceiver

### Community 18 - "Android Pairing Manager"
Cohesion: 0.20
Nodes (5): Boolean, ByteArray, Int, PairingManager, String

### Community 19 - "Android OTP Database"
Cohesion: 0.24
Nodes (5): List, Long, OTPEntity, OTPDao, Flow

### Community 20 - "BLE Scanner (Android)"
Cohesion: 0.24
Nodes (5): String, Unit, BluetoothDevice, BluetoothGatt, BLEScanner

### Community 21 - "Architecture & Contribution Docs"
Cohesion: 0.20
Nodes (10): File Map for Common Changes, End-to-End Data Flow, OTP Bridge System Architecture, Issue: macOS asset catalog not bundled, macOS Menu Bar UI Redesign, macOS App, MenuBarExtra (macOS), MenuBarView (+2 more)

### Community 22 - "macOS Component Architecture"
Cohesion: 0.20
Nodes (10): Clipboard Manager (NSPasteboard), Notification Manager (UNUserNotificationCenter), NWListener TCP Server, Room Database (OTPEntity), Issue: NWListener silently dies (ECONNREFUSED), ClipboardManager (macOS), TCP Server / WebSocketServer.swift, NotificationManager (macOS) (+2 more)

### Community 23 - "Android Room Database"
Cohesion: 0.25
Nodes (7): Context, getDatabase(), migrate(), OTPDatabase, OTPDao, RoomDatabase, SupportSQLiteDatabase

### Community 24 - "Brand & Visual Identity"
Cohesion: 0.58
Nodes (9): OTP Bridge Brand Identity, Brand Color Palette: Cyan Border + Orange Glyph + Dark Background, OTP Bridge Android App Logo, OTP Bridge macOS App Icon Set, OTP Bridge macOS Logo Image Set, OTP Bridge Android Launcher Icon, OTP Bridge Android Launcher Foreground Icon, OTP Bridge Master Logo (High Resolution) (+1 more)

### Community 25 - "Network Security & Permissions"
Cohesion: 0.25
Nodes (8): Android Network Security Config, SMSReceiver (bypass Samsung SMS hiding), Android App, BridgeForegroundService, MainViewModel, NotificationListenerService, PairingScreen (Android UI), SMSReceiver (BroadcastReceiver)

### Community 26 - "QR Code Generator"
Cohesion: 0.25
Nodes (6): CoreImage.CIFilterBuiltins, Foundation, NSImage, String, SwiftUI, QRCodeGenerator

### Community 27 - "OTP Record Model"
Cohesion: 0.36
Nodes (6): Date, Foundation, String, SwiftData, UUID, OTPRecord

### Community 28 - "Android Notification Helper"
Cohesion: 0.38
Nodes (3): Boolean, Context, NotificationHelper

### Community 29 - "OTP Extractor & Issues"
Cohesion: 0.33
Nodes (7): OTPExtractor (regex 4-8 digits), TCP Client (java.net.Socket), CompanyResolver (OTP brand detection), Issue: Stale shared secret on reconnect, OTPExtractor, OTP Message (Encrypted Payload), WebSocketClient (TCP Client)

### Community 30 - "Crypto Wire Format & Security"
Cohesion: 0.40
Nodes (6): Crypto Wire Format (nonce+ciphertext), X25519 Raw 32-byte Key Format, AES-256-GCM Encryption, Security Model, SHA-256 Key Derivation, X25519 ECDH Key Exchange

### Community 31 - "Notification Listener Service"
Cohesion: 0.40
Nodes (3): OTNotificationListenerService, NotificationListenerService, StatusBarNotification

### Community 33 - "OTP Extractor Logic"
Cohesion: 0.40
Nodes (3): OTPMessage, String, OTPExtractor

### Community 34 - "Decryption & Key Issues"
Cohesion: 0.50
Nodes (5): Issue: Decryption authenticationFailure (Wire Format Mismatch), CryptoManager (Android), CryptoManager (macOS), KeyPairStore (Android), KeyPairStore (macOS)

### Community 35 - "TCP Frame Protocol"
Cohesion: 0.67
Nodes (4): Communication Protocol Specification, 4-byte Length-Prefixed Frame Protocol, Handshake Message, Custom TCP Protocol (port 8420)

### Community 36 - "QR Pairing Flow"
Cohesion: 0.67
Nodes (4): Pairing Window (QR + otpbridge:// URL), PairingManager (Android), PairingManager (macOS), QR Code Pairing Flow

### Community 37 - "Protocol Layer Stack"
Cohesion: 0.67
Nodes (3): ChaCha20-Poly1305 Encryption Layer, Frame Protocol Layer, TCP Transport Layer

## Knowledge Gaps
- **136 isolated node(s):** `ClipboardManager`, `String`, `Bundle`, `Boolean`, `String` (+131 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `BLEAdvertiser` connect `BLE Advertiser (Mac)` to `macOS App Lifecycle`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **Why does `PairingWindow` connect `macOS Menu Bar UI` to `macOS App Lifecycle`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **What connects `ClipboardManager`, `String`, `Bundle` to the rest of the system?**
  _137 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Android TCP Client` be split into smaller, more focused modules?**
  _Cohesion score 0.11397849462365592 - nodes in this community are weakly interconnected._
- **Should `macOS Menu Bar UI` be split into smaller, more focused modules?**
  _Cohesion score 0.12183908045977011 - nodes in this community are weakly interconnected._
- **Should `macOS App Lifecycle` be split into smaller, more focused modules?**
  _Cohesion score 0.07936507936507936 - nodes in this community are weakly interconnected._
- **Should `Android Main Activity` be split into smaller, more focused modules?**
  _Cohesion score 0.10507246376811594 - nodes in this community are weakly interconnected._