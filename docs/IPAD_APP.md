# iPad app — implementation plan

Hand this file to the agent that builds the iPad app. Do **not** change the Mac menu-bar tray icon (`Image(systemName: "infinity")` in `mac-app/OTPBridge/OTPBridgeApp.swift`).

## Goal

Ship an iPadOS app that receives SMS OTPs from the existing Android Bridge phone and **copies them to the iPad clipboard**, then shows them on screen.

User requirements (explicit):

> The OTP should be there when the iPad is unlocked.
> If the user **closes** the app (goes Home / switches away), Bridge must **keep running or relaunch in the background** so the next OTP still copies.

Success looks like:

1. Phone already paired with a Mac can **also** pair with an iPad (multi-device).
2. User opens Bridge once, pairs, then presses Home or opens Safari. App is no longer on screen.
3. An SMS OTP arrives on the phone.
4. User unlocks the iPad → code is on the **clipboard** and in a notification (app may have been woken in the background).

## What is already done

### Android multi-device pairing (this repo, do not redo)

The phone is no longer one-Mac-only.

| File | Change |
|------|--------|
| `android-app/.../crypto/KeyPairStore.kt` | JSON list of peers; migrates the old single pairing |
| `android-app/.../pairing/PairingManager.kt` | `getPairedDevices()`, `removeDevice()`, `completePairing` **upserts** |
| `android-app/.../websocket/WebSocketClient.kt` | One TCP session per peer; `sendOTP` / clipboard / call **fan out** to every connected peer |
| `android-app/.../pairing/BLEScanner.kt` | IP refresh only auto-updates when there is a **single** peer (avoid rewriting the iPad IP with the Mac IP) |
| `android-app/.../viewmodel/MainViewModel.kt` | `pairedDevices`, `removeDevice` |
| `android-app/.../ui/SettingsScreen.kt` | Lists devices, **Add Mac or iPad**, remove one, unpair all |
| `android-app/.../ui/MainScreen.kt` | Settings → Add device reopens the existing QR scanner |

Pairing a second device: **Settings → Add Mac or iPad** → scan that device’s QR. Same `otpbridge://` URL as the Mac.

### Mac app

Leave it alone except you may **copy** these files into the iPad target (adapt `NSImage` → `UIImage`, `NSPasteboard` → `UIPasteboard`):

- `mac-app/OTPBridge/Crypto/CryptoManager.swift`
- `mac-app/OTPBridge/Crypto/KeyPairStore.swift`
- `mac-app/OTPBridge/Pairing/PairingManager.swift`
- `mac-app/OTPBridge/Pairing/QRCodeGenerator.swift`
- `mac-app/OTPBridge/Pairing/BLEAdvertiser.swift` (`LocalAddress`, `BLEAdvertiser`, `LanBeacon`)
- `mac-app/OTPBridge/WebSocketServer/WebSocketServer.swift`
- `mac-app/OTPBridge/Clipboard/ClipboardManager.swift` (simplify: copy + optional sync)
- `mac-app/OTPBridge/Notification/NotificationManager.swift` (OTP + clipboard only; skip call UI unless you want it)

## “Close the app” — what iPadOS will do

| User action | What we must do | Apple allows? |
|-------------|-----------------|---------------|
| Home / app switcher, Bridge still in the switcher | Stay connected via **BLE central**. On OTP, iOS **wakes Bridge in the background**, copy clipboard, show notification. No UI required. | **Yes** — `bluetooth-central` + state restoration |
| iOS kills Bridge to free RAM | System **relaunches Bridge in the background** when the phone notifies over BLE (`CBCentralManagerOptionRestoreIdentifierKey`). | **Yes** |
| User **force-quits** (swipe Bridge up and away in the switcher) | Apple **will not** relaunch any app after a user swipe-kill. Next OTP is missed until they open Bridge again. | **No** — do not fake VoIP/audio to fight this |

Implement so “I closed it and went to the home screen” still works. Tell the user in Settings: *Don’t swipe Bridge away in the app switcher.*

On `scenePhase == .background`:

- Do not tear down BLE central or subscriptions.
- TCP `NWListener` may die; that is fine — BLE is the background path.
- Keep a quiet local notification or Live Activity: “Bridge is listening”.
- On BLE notify: copy + banner. App can stay in background; do not force a full-screen launch unless the user taps the notification.

## What is **not** possible (do not promise)

| Approach | Why not |
|----------|---------|
| Always-on Wi-Fi TCP server like the Mac menu-bar agent | iPadOS suspends `NWListener`. No legal background mode for “listen on LAN forever”. |
| Silent audio / fake VoIP | [App Review 2.5.4](https://developer.apple.com/app-store/review/guidelines/) rejects unused audio/VoIP background modes. |
| Cloud push (APNs) | Breaks “no cloud / local Wi-Fi only”. |

Official local path for a **locked but not force-quit** iPad: **Core Bluetooth**. See Apple’s [Core Bluetooth background guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html).

## Architecture

Two paths. Implement **both**. Wi-Fi is the Mac-identical path while the app is active. BLE is how an OTP still lands while the iPad is locked.

```
┌──────────── Android (FGS, already exists) ────────────┐
│  OTP extracted → encrypt → fan-out                     │
│    1) TCP client to each paired IP:8420  (Mac + iPad) │
│    2) BLE notify on OTP characteristic   (iPad locked) │
└────────────┬─────────────────────────────┬─────────────┘
             │ TCP :8420                   │ BLE notify
             ▼                             ▼
      iPad NWListener                 iPad CBCentral
      (app open / Split View)        (app in memory, screen locked)
             │                             │
             └──────────┬──────────────────┘
                        ▼
              UIPasteboard.general = otp
              local notification
              store last 3 codes
```

**Roles (important):**

- Do **not** make the iPad a BLE *peripheral* for Android to find while backgrounded. Apple puts background iOS advertisements in an overflow area that **Android often cannot see**.
- iPad = **BLE central** (`bluetooth-central` + restore identifier).
- Phone = **BLE peripheral** that notifies the encrypted OTP (this is new Android work for the iPad agent — see below).
- iPad **also** runs a TCP server on **8420**, same as Mac, so the existing Android `WebSocketClient` can connect when the iPad is on Wi-Fi and the app is up.

## Protocol (must match Mac)

QR pairing URL (iPad generates this, phone scans it):

```
otpbridge://<device_id>?pk=<url-safe-base64-x25519-32-bytes>&ip=<ipv4>&port=8420
```

Same as `PairingManager.getPairingURL()` on Mac.

TCP framing: `[4-byte big-endian length][payload]`. Length `0` = keepalive ping (ignore and keep reading).

Handshake (cleartext JSON):

```json
{"type":"handshake","device_id":"<android-id>","public_key":"<std-base64 32-byte x25519>"}
```

Ack:

```json
{"type":"handshake_ack","device_id":"<ipad-id>","public_key":"<std-base64 32-byte x25519>"}
```

Then all payloads are **AES-256-GCM**. Key = `SHA256(X25519 shared secret)`. Wire: nonce (12) + ciphertext + tag (16) as CryptoKit `SealedBox.combined`.

OTP JSON (after decrypt):

```json
{"type":"otp","sender":"…","otp":"484711","company":"Test","timestamp":<millis>}
```

Also handle `clipboard` and ignore `call` if you skip call UI.

On OTP:

1. `UIPasteboard.general.string = otp`
2. Local notification: title company/sender, body `484 711 — copied`
3. Prepend to in-memory + UserDefaults history; **show 3 codes max** (latest as hero + 2 recent)

## BLE fallback (locked iPad)

New on **Android** (iPad agent must add this; not done yet):

- GATT server in the existing foreground service.
- Reuse or add service UUID. Suggested:

  - Service: `F0F1F2F3-F4F5-F6F7-F8F9-FAFBFCFDFEFF` (already used for Mac IP advert)
  - OTP notify char: `F0F1F2F3-F4F5-F6F7-F8F9-FAFBFCFDFE02` (new)
  - Optional device-id read char so multi-peer IP updates stay correct

- When `WebSocketClient.sendOTP` runs, **also** notify the encrypted OTP bytes (same AES-GCM blob as TCP) on the OTP characteristic.

New on **iPad**:

- `CBCentralManager` with `CBCentralManagerOptionRestoreIdentifierKey`
- Background mode `bluetooth-central`
- Scan/connect to the phone, subscribe to the OTP characteristic
- On notify: decrypt with stored shared secret, copy, notify, save
- ~10 seconds of runtime after wake — do only those four things, then return

If the user **force-quits** the iPad app, BLE will not relaunch it. That is accepted.

## iPad UI

SwiftUI, iPad-first (`TARGETED_DEVICE_FAMILY = 2`, or 1,2 if you also want iPhone). Match current Android/Mac branding:

- Indigo `#4E4BA6`, orange `#FF8A3D`, logo from repo `logo.png`
- Home (only necessary things):
  - Logo + “Bridge” + Live/Offline chip
  - Latest OTP hero (grouped 6-digit, tap copies)
  - Up to 2 more under “Recent” (**3 total**)
  - Pair CTA if unpaired
- Settings: paired phone id, unpair, about (local Wi-Fi, X25519 + AES-GCM)
- Pairing: large QR, “Open Bridge on Android → Settings → Add Mac or iPad”
- Keep the screen awake while listening: `UIApplication.shared.isIdleTimerDisabled = true`

Do **not** dump dashboard / updates / forget / chime on the home screen.

## Project layout

Create `ipad-app/` (do not put this inside `mac-app/`; Mac is a menu-bar extra).

```
ipad-app/
  OTPBridgePad.xcodeproj
  OTPBridgePad/
    OTPBridgePadApp.swift          # @main, start server + BLE, request notifications
    Info.plist
    Assets.xcassets/               # AppIcon + Logo from ../../logo.png
    Crypto/CryptoManager.swift
    Crypto/KeyPairStore.swift
    Pairing/PairingManager.swift
    Pairing/QRCodeGenerator.swift  # UIImage
    Network/TCPServer.swift        # port from WebSocketServer.swift
    Network/LocalAddress.swift     # copy from BLEAdvertiser.swift
    BLE/BLECentral.swift           # subscribe to phone OTP char
    BLE/BLEAdvertiser.swift        # optional: advertise iPad IP like Mac (TCP reconnect)
    Clipboard/ClipboardManager.swift
    Notification/NotificationManager.swift
    Storage/OTPStore.swift         # last 3 OTPs
    UI/HomeView.swift
    UI/PairingView.swift
    UI/SettingsView.swift
    UI/Brand.swift                 # indigo / orange
```

Signing: Mac project uses `DEVELOPMENT_TEAM = M5Q7N9D29M`, bundle `io.github.alokkr016.bridge`. Use e.g. `io.github.alokkr016.bridge.ipad`.

Info.plist capabilities:

- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` if you advertise `_otpbridge._tcp`
- `NSBluetoothAlwaysUsageDescription`
- `UIBackgroundModes` = `bluetooth-central` only (no audio, no voip)
- Notifications

Minimum: iPadOS 17.

## Implementation order

1. Scaffold `ipad-app` Xcode project (iPad, SwiftUI, signing team above).
2. Port crypto + pairing + QR + TCP server. Confirm handshake with the **existing** Android app (Settings → Add Mac or iPad).
3. On OTP over TCP: clipboard + notification + hero/recent (max 3).
4. Add Android GATT notify of the same encrypted OTP (small change in `BridgeForegroundService` / new `BLEOtpPeripheral.kt`).
5. iPad BLE central + `bluetooth-central` so a **locked** iPad still copies.
6. Optional: iPad BLE IP advert + `LanBeacon` (UDP 8421, payload `OTPBRIDGE <ip> 8420`) so Android can refresh the iPad IP the same way it refreshes the Mac. Only safe to auto-apply when Android has a way to know *which* peer changed (device-id characteristic). Until then, user can re-pair if DHCP changes.
7. Test matrix below.

## Tests the implementing agent must run

- Pair Mac only — existing Mac path still works.
- Pair iPad only — OTP copies on iPad.
- Pair **both** — one SMS appears on Mac **and** iPad.
- Remove iPad in Android Settings — Mac still receives.
- iPad unlocked, Bridge in Split View — auto-copy.
- iPad locked, Bridge **not** force-quit — unlock → clipboard has the latest OTP (BLE path).
- Force-quit iPad — next OTP may be missed (accepted).
- Do not change Mac tray icon.

## Out of scope

- iPhone-only layout polish
- Incoming-call UI on iPad
- Cloud, accounts, Windows
- Fake background audio/VoIP
- Changing `OTPBridgeApp.swift` menu-bar `infinity` symbol

## Product copy for the pairing screen

> Keep Bridge open on this iPad (it can sit in the background).  
> On your phone: Settings → Add Mac or iPad → scan this code.  
> Codes copy to the clipboard as they arrive.
