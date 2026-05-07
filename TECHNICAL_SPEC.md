# 1. Executive summary

This project should be built as a two-app system:

- A native macOS controller app that captures local keyboard and pointing-device input, detects edge crossing on the Mac display, owns the session/trust model, and forwards remote-control and clipboard messages.
- A native Android companion app that provides transport, pairing, a foreground connection service, an `AccessibilityService` for gesture/global-action mediation, a companion `InputMethodService` for text entry and clipboard access, and a `ContentProvider` for clipboard-backed URIs.

This is not a display extension product and should not be designed as one. The user looks at the Galaxy Tab screen directly. The Mac acts as the control origin. When the pointer reaches a configured Mac screen edge, the system enters Android control mode. While in Android control mode, the Mac app captures keyboard and pointer events, suppresses their normal local delivery when appropriate, and sends them over a secure session to the Android app. The Android app translates those events into the closest platform-supported actions available without root or privileged system permissions.

Recommended architecture:

- MVP transport: direct USB-C using ADB-over-USB strictly as an implementation shortcut.
- Production target transport: direct USB-C using Android Open Accessory (AOA) / custom USB bulk transport, subject to an early hardware prototype gate on the target Samsung Galaxy Tab models.
- Fallback transport: Wi-Fi over the same secure session and application protocol.
- Security: application-layer pairing, mutual device trust, authenticated encryption, trusted reconnect with fresh session keys, replay-safe session protection, local secret storage, explicit revocation.
- Packaging target: one universal macOS app and one Android app.

Brutally realistic platform position:

- Android-wide touch mediation is feasible with `AccessibilityService.dispatchGesture()` and global actions.
- Android-wide arbitrary hardware-style key injection is not available to a normal third-party app. Reliable text entry requires a companion IME. Non-text key behavior is limited and app-dependent.
- Automatic clipboard read on Android 10+ is constrained by platform privacy rules. Full automatic clipboard sync requires the companion app to also act as the current/default IME, or the app to be foregrounded.
- Direct USB without ADB is not a given. It must be validated on real Samsung Galaxy Tab hardware early. If AOA proves unreliable on target devices, a fully polished USB-only production promise should be withdrawn or re-scoped.

Key risks:

- AOA transport feasibility and USB role negotiation across Samsung hardware.
- Android input limitations for non-text keyboard events, hover, secondary click, and app-specific input behavior.
- Clipboard constraints on Android unless the companion IME is installed and selected.
- Store policy/distribution friction: Android accessibility usage and macOS input-monitoring/accessibility permissions make mainstream store distribution harder than direct notarized distribution.

Phased delivery plan:

- Phase 0: feasibility spikes for AOA, Android accessibility cursor/gesture control, IME-based text/clipboard access.
- MVP: ADB-over-USB, secure pairing/session, edge-triggered control mode, basic pointer/tap/scroll/drag, text entry in editable fields, clipboard v1 (plain text + URL), Wi-Fi fallback optional.
- V2: production USB transport if AOA passes gate, reconnection hardening, image clipboard via provider/URI architecture.
- V3: video/file clipboard, clipboard history, deeper compatibility hardening, enterprise/security controls, release QA matrix.

# 2. Requirements specification

## Functional requirements

- The macOS app shall detect when the pointer reaches a user-configurable display edge.
- The macOS app shall support at least left, right, top, and bottom activation edges.
- The system shall enter Android control mode only when:
  - a trusted Android device is connected,
  - a secure session is established,
  - the user has enabled the feature in settings.
- In Android control mode, Mac keyboard input shall be forwarded to Android using the best available platform-supported mechanism.
- In Android control mode, Mac trackpad/mouse input shall be forwarded to Android and mapped to Android touch/pointer semantics.
- The user shall be able to exit Android control mode through at least one reliable explicit mechanism independent of Android UI state.
- The system shall support clipboard sync in stages:
  - v1: plain text and URL.
  - v2: image clipboard via URI/provider architecture.
  - v3: video and file clipboard via URI/provider architecture.
- The system shall support direct USB-C to USB-C as the primary connection path.
- The system may use ADB-over-USB for MVP only, with clear operator-facing disclosure.
- The system shall support pairing, trusted reconnection, and manual unpair/revoke.
- The first pairing UX shall support a simple 4-digit confirmation code entered on both devices, while the underlying trust model still relies on device key exchange and authenticated session establishment.
- The system shall expose connection state, trust state, and permission state in both apps.
- The Android app shall continue providing control functionality while its foreground service remains active and required permissions remain granted.
- The system shall support clipboard transfer for:
  - plain text,
  - URLs,
  - images,
  - video clips,
  - general files.
- The system shall provide a lightweight clipboard history view in both apps.
- The clipboard history shall show recent items with compact previews and metadata:
  - text snippet for text,
  - thumbnail for images and videos,
  - filename, size, and type for files.
- The clipboard history shall allow re-copying a prior item back into the current local clipboard.
- The system shall degrade gracefully when Android permissions are missing:
  - no accessibility service: no pointer control and no global actions.
  - no IME/default keyboard role: no full automatic clipboard sync and degraded text entry.
  - no USB debugging in MVP mode: no ADB transport.

## Non-functional requirements

- The design shall work without root, jailbreak, or privileged OEM/system app privileges.
- The design shall avoid cloud dependencies for baseline operation.
- The design shall keep the secure control channel local to the cable or local network path.
- The macOS app shall restore local input immediately on disconnect, crash, or session failure.
- The Android app shall show a persistent foreground-service notification while remote control is active.
- The system shall tolerate cable unplug/replug, Android screen lock/unlock, and Mac sleep/wake with controlled reconnection behavior.
- The system shall prefer predictable behavior over aggressive automation when platform APIs are weak.
- The implementation shall be modular enough for separate macOS, Android, protocol, and QA contractors.

## Security requirements

- All control, clipboard, and resource-transfer traffic shall be encrypted and authenticated end-to-end at the application layer.
- Pairing shall require explicit user confirmation on both devices.
- Each device shall have a long-term device identity stored locally in platform-secure storage.
- Trusted peer state shall be persisted and revocable.
- Session keys shall be ephemeral and rotated per connection.
- The protocol shall include replay protection for each session and shall support trusted reconnect using a fresh handshake after disconnect.
- Raw clipboard payload values, raw key payload values, and secrets shall not be logged by default. Metadata-only diagnostics are permitted.
- Sensitive clipboard items shall support non-persistent handling and optional user confirmation before cross-device sync.
- An unpaired device shall not be able to enter control mode or receive clipboard data.

## Platform requirements

- macOS:
  - Initial support target: a universal binary for `arm64` and `x86_64`.
  - Primary supported OS baseline: macOS 14, 15, and 26.
  - Apple Silicon support target includes current M-series Macs, including M5-class Macs.
  - Intel support target is limited to Intel Mac models still supported by Apple on macOS Tahoe 26, such as the 2019 16-inch MacBook Pro, 2020 four-port 13-inch MacBook Pro, 2020 27-inch iMac, and 2019 Mac Pro. This is an inference from Apple’s published macOS Tahoe compatibility list.
  - Requires Accessibility and Input Monitoring permissions.
  - Recommended distribution: direct notarized app, not Mac App Store in the initial release.
- Android:
  - Initial support target: Samsung Galaxy Tab S11 and Galaxy Tab S11 Ultra with USB-C data support.
  - Software baseline: current Galaxy Tab S11 family software at implementation time; validate exact Android and One UI build numbers with prototype.
  - Requires AccessibilityService enablement.
  - Requires companion IME selection for full text-entry and clipboard functionality.
  - Requires foreground service.
  - MVP USB path requires Developer Options and USB debugging enabled.

## Compatibility assumptions

- The first supported Android device family is Samsung Galaxy Tab, not all Android OEMs.
- The user can physically confirm both screens during pairing.
- The user can install both apps and grant required permissions.
- The user has a data-capable USB-C cable. Charge-only cables are unsupported.
- The user can tolerate an explicit onboarding flow for accessibility, keyboard/IME, and trust.

## Exclusions

- Full Apple Universal Control parity.
- Screen mirroring or display extension.
- Root-only or jailbreak-only capabilities.
- Guaranteed compatibility with all Android apps.
- Ultra-low-latency gaming.
- Guaranteed hardware-mouse parity on Android.
- Cross-account/cloud clipboard relay.

# 3. System architecture

## macOS app architecture

The macOS side should be a per-user menu bar agent with a settings window and a background control runtime. It owns edge detection, global event capture, cursor locking/hiding, transport selection, secure session establishment, trust storage, clipboard monitoring, and user-visible status.

Primary macOS responsibilities:

- Detect configured activation edge crossing.
- Enter and exit Android control mode.
- Capture keyboard, mouse, trackpad, and scroll events with low latency.
- Suppress or redirect local event delivery while remote mode is active.
- Manage trusted devices, pairing, and reconnect.
- Monitor the macOS pasteboard and publish eligible clipboard changes.
- Render status UI and permission guidance.

## Android app architecture

The Android side should be a single application containing several cooperating components:

- `MainActivity` for onboarding, permission UX, pairing UI, trusted-device management, and diagnostics.
- `ConnectionForegroundService` to own the transport/session lifecycle.
- `RemoteAccessibilityService` to:
  - maintain an optional remote cursor overlay,
  - translate pointer/tap/drag/scroll events into accessibility gestures,
  - invoke global actions such as Back and Home,
  - inspect focused nodes when needed for fallback text actions.
- `RemoteInputMethodService` as the companion keyboard/IME for:
  - reliable text insertion,
  - delete/enter handling in editable fields,
  - clipboard access on Android 10+.
- `RemoteClipboardProvider` / `RemoteTransferProvider` to expose image/file clipboard payloads as `content://` URIs with short-lived grants.
- `ClipboardHistoryRepository` to maintain a compact recent-history index for text, image, video, and file clips.
- Transport adapters for ADB, AOA, and Wi-Fi.

## Communication architecture

The communication stack should be layered:

1. Physical/link transport:
   - USB via ADB port forward in MVP.
   - USB via AOA bulk endpoints in production target.
   - Wi-Fi TCP as fallback.
2. Framed byte stream:
   - length-prefixed frames.
3. Secure session:
   - authenticated key exchange and AEAD.
4. Application protocol:
   - control-mode, input, clipboard, resource transfer, errors, diagnostics.

The application protocol must remain transport-agnostic so the same higher layers run unchanged over ADB, AOA, or Wi-Fi.

## Pairing/authentication architecture

- Each device generates a long-term device identity on first launch.
- First pairing uses an interactive authenticated handshake plus a user-entered 4-digit confirmation code on both devices.
- On successful confirmation, each device stores:
  - peer public identity,
  - peer user-visible name,
  - first-paired timestamp,
  - last-seen timestamp,
  - peer capability flags,
  - trust status.
- Subsequent connections use the stored identity to authenticate automatically without repeating the pairing ceremony unless trust state changed.
- The 4-digit code is an operator-friendly confirmation factor only. It must not replace long-term identity keys or authenticated session establishment.

## Clipboard architecture

Clipboard sync should use a staged model:

- v1:
  - text and URL are transferred as small inline payloads.
- v2:
  - image clipboards are transferred as resource descriptors plus binary content over the secure channel.
  - Android reconstructs them as `content://` URIs backed by an app `ContentProvider`.
- v3:
  - video and files use the same provider-based pattern with file metadata, chunked transfer, and temporary cache materialization.

Clipboard history should be local-first and compact:

- bounded recent-item list on each device,
- preview-first UI,
- metadata-heavy storage for large media and files,
- re-copy action back into the active clipboard,
- TTL and LRU cleanup for cached binary payloads.

No platform raw file paths should be treated as a stable cross-platform wire primitive.

## Control-mode switching architecture

macOS owns the control-mode state machine:

- `MacControlMode`: normal local input delivery.
- `PendingRemoteEntry`: edge threshold crossed, trusted session verified, transition guard checks.
- `AndroidControlMode`: local cursor hidden/pinned, events forwarded remotely, local delivery suppressed.
- `Recovery`: disconnect or fault; restore local cursor and exit remote mode.

Exit paths:

- explicit global hotkey on Mac,
- transport disconnect,
- Android permission loss detected mid-session,
- optional edge-return gesture if implemented later.

## Component diagram in ASCII

```text
+--------------------------- macOS ---------------------------+
| Menu Bar UI / Settings                                     |
|   - Pairing UI                                             |
|   - Trust Store UI                                         |
|   - Diagnostics                                            |
|                                                            |
| ControlModeCoordinator                                     |
|   + EdgeCrossingDetector                                   |
|   + GlobalEventTapMonitor                                  |
|   + CursorLockManager                                      |
|   + ClipboardMonitor                                       |
|   + SessionManager                                         |
|   + TransportBroker                                        |
|        |- AdbTransportAdapter                              |
|        |- AoaTransportAdapter                              |
|        |- WifiTransportAdapter                             |
|   + TrustStore / KeychainStore                             |
+-------------------------------|----------------------------+
                                | secure framed protocol
+--------------------------- Android ------------------------+
| MainActivity / Onboarding                                  |
| ConnectionForegroundService                                |
|   + SessionManager                                         |
|   + TransportBroker                                        |
|        |- AdbLoopbackListener                              |
|        |- UsbAccessoryTransport                            |
|        |- WifiTransportAdapter                             |
|   + ClipboardRepository                                    |
|                                                            |
| RemoteAccessibilityService                                 |
|   + OverlayCursorController                                |
|   + GestureDispatcher                                      |
|   + GlobalActionRouter                                     |
|   + FocusInspector                                         |
|                                                            |
| RemoteInputMethodService                                   |
|   + TextInputBridge                                        |
|   + ClipboardAccessBridge                                  |
|                                                            |
| RemoteClipboardProvider / RemoteTransferProvider           |
+------------------------------------------------------------+
```

## Sequence diagram in ASCII: first pairing

```text
Mac App                      Android App                    User
  |                              |                           |
  | detect transport             |                           |
  |----------------------------->| transport available       |
  | start handshake              |                           |
  |<---------------------------->| ephemeral key exchange    |
  | show 4-digit entry UI        | show 4-digit entry UI     |
  |                              |<------------------------->| enter same 4-digit code
  | validate entered code        | validate entered code     |
  |----------------------------->| confirm pairing           |
  | store peer identity          | store peer identity       |
  |<-----------------------------| pairing success           |
  | session established          | session established       |
```

## Sequence diagram in ASCII: entering Android control mode

```text
User / Mac Pointer       macOS App                 Android App
      |                     |                          |
      | move to edge        |                          |
      |-------------------->| edge threshold hit       |
      |                     | verify trusted session   |
      |                     | hide/pin Mac cursor      |
      |                     | enter Android mode       |
      |                     |------------------------->| control_mode_enter
      | continue moving     |                          |
      |-------------------->| capture deltas           |
      |                     |------------------------->| pointer_move
      | click               |------------------------->| tap/gesture dispatch
      | type text           |------------------------->| key/text routing
      | exit hotkey         |------------------------->| control_mode_exit
      |                     | restore Mac cursor       |
```

## Sequence diagram in ASCII: clipboard sync event

```text
Source Device App       Local Clipboard Bridge      Secure Session      Peer Clipboard Bridge
      |                          |                       |                        |
      | clipboard changed        |                       |                        |
      |------------------------->| classify clip         |                        |
      |                          | build clip descriptor |                        |
      |                          |---------------------->| clipboard_update       |
      |                          |                       |----------------------->| validate trust/capability
      |                          |                       |                        | materialize clip
      |                          |                       |<-----------------------| ack
      |                          |<----------------------| ack                    |
```

# 4. Transport design

## Option comparison

| Option | Feasibility | Implementation complexity | Security posture | Latency expectation | Deployment practicality | MVP or production suitability | Notes |
|---|---|---:|---|---|---|---|---|
| USB-C direct with ADB MVP | High | Low to medium | Medium by itself; strong if wrapped in app-layer crypto | Low | Poor for end users because it requires Developer Options and USB debugging | MVP only | Fastest path to a working cable prototype. Must be explicitly marked non-production UX. |
| USB-C direct with custom transport (AOA) | Medium, validate on target Samsung hardware | High | Strong with app-layer pairing and encryption | Low | Medium if the hardware consistently supports accessory mode; poor if role negotiation is inconsistent | Production target only after prototype gate | Best fit for a cable-first product if it works reliably on target devices. |
| USB network interface with TCP/TLS | Medium | Medium | Strong | Low to medium | Poor because users may need to enable USB tethering or vendor-specific networking | Secondary fallback / contingency | Simpler than raw USB if the OS exposes a usable network interface, but not reliably app-provisionable. |
| USB network interface with UDP/DTLS | Medium | High | Strong | Potentially low | Poor | Not recommended | Added protocol complexity without a strong product reason in this scope. |
| Wi-Fi fallback | High | Medium | Strong with same app-layer security | Medium and variable | High | Recommended fallback | Necessary for resilience and debugging, but not the primary architecture. |
| Bluetooth fallback | Low to medium | Medium | Acceptable but weaker UX profile | Higher / variable | Medium | Not recommended as primary or early fallback | Adds pairing and throughput complexity with limited benefit for this product. |

## Recommendation

### Recommended MVP transport

Use ADB-over-USB with the secure application protocol layered on top.

Reason:

- It is the fastest realistic route to an executable MVP.
- It avoids blocking the whole program on raw USB R&D.
- It allows early validation of the harder parts:
  - Android gesture mediation,
  - IME-based text entry,
  - clipboard behavior,
  - macOS control-mode switching,
  - security/session model.

Constraints:

- Must be labeled MVP-only in the product and contract documents.
- Requires Developer Options and USB debugging.
- Must not be described to stakeholders as the final consumer UX.

Implementation pattern:

- Android app listens on localhost only.
- macOS app uses `adb forward` to expose that local Android port to the Mac host.
- All useful security still happens inside the app-layer secure channel, not by trusting ADB.

### Recommended production transport

Use custom USB transport over Android Open Accessory (AOA), if and only if an early prototype passes on the target Samsung Galaxy Tab models.

Reason:

- It is the most credible direct cable architecture that avoids permanent ADB dependency.
- It maps better to a user-facing cable product than USB debugging.
- It avoids relying on manual tethering UX or vendor network exposure.

Hard gate:

- If AOA fails reliability, enumeration, resume, or permission testing on target tablets, do not promise a production USB-only path without re-scoping.
- In that case, the production fallback should be:
  - Wi-Fi secure transport as the supported production path.
  - USB ADB retained only as a developer/beta path.

# 5. Security design

## Trust model

- Trust is local, explicit, and pairwise.
- No cloud identity provider is required for baseline operation.
- The user physically controls both devices at first pairing.
- A trusted device may reconnect automatically until revoked.

## Threat model

In scope:

- Passive eavesdropping on Wi-Fi fallback traffic.
- Active MITM attempts during first connection.
- Replay of old session frames.
- Unauthorized control attempts from an unpaired host/device.
- Leakage of clipboard contents through logs or insecure local storage.
- ADB transport misuse in MVP mode.
- Stale trust after device loss or resale.

Partially in scope / cannot be fully prevented:

- Malware with user-level accessibility privileges on Android.
- Malware with Accessibility/Input Monitoring privileges on macOS.
- Fully compromised/rooted devices.

Out of scope:

- Nation-state or kernel-level compromise.
- Physical hardware implants in the cable path.

## Attack surfaces

- USB transport attach and enumeration.
- ADB port forwarding in MVP.
- Wi-Fi listener/discovery endpoints.
- Pairing ceremony and SAS confirmation.
- Android clipboard and provider URIs.
- Local caches for image/file clipboard payloads.
- macOS and Android permission misuse.

## Pairing flow

Recommended pairing:

1. Both devices generate long-term device identity material on first launch.
2. The devices establish an unauthenticated ephemeral handshake over the current transport.
3. Both devices show a pairing screen that asks the user to enter the same 4-digit confirmation code on both devices.
4. The entered code is checked on both sides as part of pairing confirmation.
5. If the confirmation step succeeds, the devices mark each other trusted and store peer identity.

Pairing must fail closed if:

- the 4-digit code is not confirmed on both devices,
- handshake transcript mismatch occurs,
- peer capability negotiation is invalid,
- device clock or timestamps are nonsensical in a way that indicates corruption.

Important note:

- The 4-digit code is a UX simplification for the operator. It is not the sole authenticator and must not be treated as the long-term shared secret.

## Long-term device identity

Generate on each device:

- `device_id`: random 128-bit identifier for local bookkeeping only.
- `static_identity_keypair`: X25519 keypair used as the long-term cryptographic identity for the Noise-style secure channel.
- `device_label`: user-visible name, editable.

Storage:

- macOS:
  - store the long-term private key in Keychain.
  - store non-secret peer metadata in an encrypted app database or preferences file.
- Android:
  - store a wrapping key in Android Keystore.
  - store the X25519 private key wrapped by the Keystore-backed key in app-private storage.
  - disable backup/export of the secure store.

Rotation:

- Rotate only on explicit user action or trust reset.
- On rotation, invalidate all existing pairings.

## Session key establishment

Recommended approach:

- First contact: Noise XX pattern over the selected transport.
- Trusted reconnect: Noise IK or XX fallback if peer state is missing or inconsistent.
- Per-session ephemeral X25519 keys generated fresh every connection.
- Session AEAD:
  - `ChaCha20-Poly1305` preferred for cross-platform consistency, or
  - `AES-256-GCM` if the chosen crypto library stack is simpler and well tested on both platforms.

Session lifetime:

- New handshake on every transport reconnect.
- Trusted reconnect is expected behavior and does not require re-pairing unless trust state changed.
- Rekey after:
  - 8 hours, or
  - 1 GiB of traffic,
  - whichever comes first.

## Replay protection

- Maintain an independent 64-bit monotonically increasing sequence number for each direction.
- Bind the sequence number into the AEAD nonce and associated data.
- Reject duplicate or stale sequence numbers.
- Replay protection applies to old or duplicated frames only; it must not block trusted reconnect that establishes a new session with new keys and fresh counters.
- For stream transports, enforce strict in-order delivery.
- For any future datagram transport, add a small replay window and duplicate suppression map.

## Sensitive clipboard handling

Classification rules:

- Respect Android `ClipDescription.EXTRA_IS_SENSITIVE` when present.
- Apply local heuristics for high-risk text:
  - password-like single tokens,
  - OTP-like short numeric strings,
  - payment-card-like patterns.

Policy:

- Sensitive clips are encrypted in transit like everything else.
- Sensitive clips should not be persisted beyond short-lived in-memory handling unless required for provider-backed reconstruction.
- Add a user setting:
  - `Sync sensitive clipboard automatically` = off by default.

## Revocation flow

User-triggered revoke:

- Remove peer trust record.
- Delete peer capability state.
- Delete any peer-specific resource cache.
- Force full re-pair on next connection.

Emergency local reset:

- Rotate local long-term identity.
- Invalidate all peer pairings.
- Clear session cache.

## Logging restrictions

Must never log:

- clipboard payload values,
- keystroke content,
- raw provider URIs containing secrets,
- session keys,
- long-term private keys,
- full file paths from user clipboard data.

Allowed logs:

- event type,
- payload size,
- hashed clip identifier,
- device identifier suffix,
- transport type,
- error codes,
- performance counters.

## Local secret storage strategy

### macOS

- Key storage:
  - Keychain item service: `com.mtog.identity`
  - Access class: current user only.
- Trust metadata:
  - app-private file under Application Support, encrypted or integrity-protected.
- Session keys:
  - memory only.

### Android

- Wrapping key alias:
  - `mtog_device_wrap_v1`
- Store in Android Keystore.
- Wrapped private identity:
  - app-private file in internal storage.
- Trust metadata:
  - app-private database or DataStore, encrypted with the wrapping-key-derived content key.
- Session keys:
  - memory only.
- `android:allowBackup="false"` and explicit data-extraction exclusions for secure files.

# 6. macOS implementation design

## Recommended language/frameworks

- Language: Swift 5.9+.
- UI: AppKit with selective SwiftUI for settings screens.
- Event capture/control: CoreGraphics / Quartz Event Services.
- Clipboard: `NSPasteboard`.
- Transport/session:
  - Network framework for Wi-Fi TCP.
  - bundled `adb` process management for MVP.
  - user-space USB bridge via a C wrapper or `libusb` for AOA prototype and production path.
- Cryptography:
  - use a mature cross-platform crypto library shared conceptually with Android.
  - Do not invent custom cryptography.

## App type

Recommended form:

- Menu bar application with:
  - background runtime active while logged in,
  - settings/preferences window,
  - optional login-item support for launch at login.

Do not design this as a system daemon. Input capture is tied to the user session and permission model.

## Input capture module

Responsibilities:

- Install a global event tap for keyboard, mouse move, drag, click, and scroll.
- Observe events in normal mode.
- In remote mode, suppress local delivery for captured events that are being forwarded.
- Track modifier-key state transitions.

Suggested classes:

- `GlobalEventTapMonitor`
- `KeyboardCaptureRouter`
- `PointerCaptureRouter`
- `ModifierStateTracker`

Notes:

- Use a low-level event tap instead of local event monitors.
- Validate exact permission UX with prototype.

## Edge detection module

Responsibilities:

- Track cursor position across multi-display setups.
- Determine active edge and threshold crossing.
- Support configurable dead zone and hysteresis so the user does not flap in and out of remote mode.

Suggested classes:

- `EdgeCrossingDetector`
- `DisplayTopologySnapshot`
- `RemoteEntryPolicy`

Recommended rules:

- activation threshold: pointer reaches chosen edge and continues moving outward by N pixels.
- exit by explicit hotkey in MVP.
- optional edge-return exit can be evaluated later, but should not replace explicit exit.

## Event forwarding module

Responsibilities:

- Convert native macOS events into protocol messages.
- Coalesce high-frequency pointer motion into a bounded send rate.
- Preserve discrete click/drag/scroll state.

Suggested classes:

- `RemoteInputForwarder`
- `PointerDeltaCoalescer`
- `RemoteKeyMapper`

Implementation notes:

- Prefer relative pointer deltas over absolute Mac coordinates.
- Send scroll deltas in normalized units.
- Keep a local state machine for drag start / drag continue / drag end.

## Clipboard monitoring module

Responsibilities:

- Observe `NSPasteboard.general.changeCount`.
- Read and classify supported pasteboard types.
- Ignore app-self-originated updates to avoid loops.

Suggested classes:

- `ClipboardMonitor`
- `ClipboardClassifier`
- `ClipboardLoopGuard`
- `MacClipboardMaterializer`

Polling strategy:

- Use lightweight polling with adaptive intervals rather than expensive broad observation.
- Suggested interval:
  - active session: 100 to 250 ms.
  - idle: 500 ms.

## Secure session module

Responsibilities:

- Run handshake, session rekey, sequencing, and message framing.
- Select a transport adapter.
- Persist trust state.

Suggested classes:

- `SessionManager`
- `SecureChannel`
- `TrustStore`
- `TransportBroker`
- `HandshakeCoordinator`

## Settings/preferences UI

Required settings:

- activation edge,
- remote-entry threshold,
- exit hotkey,
- clipboard sync enable/disable,
- sync sensitive clipboard enable/disable,
- Wi-Fi fallback enable/disable,
- launch at login,
- trusted devices management,
- diagnostics export without sensitive payloads.

Suggested classes:

- `SettingsWindowController`
- `PermissionsStatusViewModel`
- `TrustedDevicesViewModel`

## Error handling and reconnection behavior

Rules:

- Any transport/session failure while in Android control mode must immediately:
  - exit remote mode,
  - restore the Mac cursor,
  - re-enable local input,
  - show a concise failure notification.
- Auto-reconnect only to trusted devices.
- Retry policy:
  - exponential backoff,
  - reset backoff on cable reattach,
  - stop retrying after a bounded window until user action or new attach event.

Suggested classes:

- `ReconnectSupervisor`
- `FailureRecoveryCoordinator`

# 7. Android implementation design

## Recommended language/frameworks

- Language: Kotlin.
- UI: Jetpack Compose for app screens if the team is comfortable with it; otherwise XML is acceptable.
- Concurrency: Kotlin coroutines and flows.
- Background work: foreground service plus WorkManager only for cleanup/non-real-time tasks.
- Storage: Room or DataStore for non-secret metadata.

## App components

Suggested components:

- `MainActivity`
- `ConnectionForegroundService`
- `RemoteAccessibilityService`
- `RemoteInputMethodService`
- `RemoteClipboardProvider`
- `ClipboardHistoryRepository`
- `TransportBroker`
- `SessionManager`
- `PeerTrustRepository`

## Foreground service

`ConnectionForegroundService` should:

- own the active transport and session,
- expose persistent notification state,
- survive normal background transitions,
- coordinate reconnect and cleanup,
- broker messages between transport and the accessibility/IME/clipboard modules,
- expose clipboard history availability and cache state to the UI.

Failure rules:

- if the service is killed, local Android state should fall back safely.
- on restart, do not auto-enter remote control mode until a trusted session is re-established.

## Accessibility service

`RemoteAccessibilityService` should:

- maintain an optional `TYPE_ACCESSIBILITY_OVERLAY` cursor overlay,
- translate pointer deltas into overlay cursor motion,
- dispatch taps, long presses, drags, and scroll gestures,
- invoke `performGlobalAction()` for Back/Home/Recents where supported,
- inspect the current focused node for text-field fallback behavior.

Suggested classes:

- `OverlayCursorController`
- `GestureDispatcher`
- `GlobalActionRouter`
- `FocusedNodeInspector`

Important limitation:

- This is not true system mouse injection. It is gesture mediation plus optional overlay cursor.

## Clipboard module

`ClipboardRepository` should:

- read and write `ClipboardManager` state,
- classify clips by type,
- attach loop-prevention metadata,
- coordinate with the IME for Android 10+ clipboard reads.

Suggested classes:

- `ClipboardRepository`
- `ClipboardClassifier`
- `ClipboardLoopGuard`
- `AndroidClipboardMaterializer`
- `ClipboardHistoryRepository`
- `ClipboardHistoryPruner`

## Content provider module

`RemoteClipboardProvider` should:

- expose short-lived `content://` URIs for image/file clipboard payloads,
- expose short-lived `content://` URIs for image/video/file clipboard payloads,
- serve MIME-typed streams from app-private cache,
- support time-bounded tokens,
- support cleanup of expired entries.

Suggested classes:

- `RemoteClipboardProvider`
- `ProviderGrantManager`
- `TransferCacheManager`

Validate with prototype:

- exact provider export/grant behavior when clipboard consumers in other apps read the URI.

## Transport/session module

Suggested classes:

- `TransportBroker`
- `AdbLoopbackListener`
- `UsbAccessoryTransport`
- `WifiTransportAdapter`
- `SessionManager`
- `HandshakeCoordinator`

Design rules:

- ADB listener binds only to localhost.
- AOA transport reads/writes through the accessory file descriptor.
- All transports feed the same framed secure channel.

## Onboarding and permission UX

Required onboarding steps:

1. Install and launch app.
2. Enable accessibility service.
3. Enable companion keyboard/IME and set it current if full feature set is desired.
4. Start foreground service.
5. In MVP mode only:
   - enable Developer Options,
   - enable USB debugging,
   - authorize host.
6. Pair with Mac and enter the same 4-digit confirmation code on both devices.

UX rules:

- Explain why each permission is needed in plain language.
- Show degraded-feature status if the user skips IME or accessibility.
- Do not silently fail.

## Failure/recovery behavior

- If accessibility is disabled mid-session:
  - terminate pointer control immediately,
  - keep session alive only for capabilities that still work.
- If IME is no longer current:
  - disable automatic clipboard read and reliable text entry,
  - show in-app and notification warning.
- If transport disconnects:
  - hide overlay cursor,
  - clear transient provider grants if appropriate,
  - remain ready for trusted reconnect.

# 8. Protocol design

## Protocol choice

Use protobuf messages carried inside a simple length-prefixed frame stream.

Reason:

- Strong cross-platform tooling for Swift and Kotlin.
- Good binary efficiency without designing a custom serializer.
- Explicit field numbering and forward compatibility.
- Easier contractor implementation than a hand-rolled binary format.

Use JSON only for logs, diagnostics, and documentation examples. Do not use JSON as the primary wire format.

## Framing assumptions

- Primary protocol profile assumes a reliable ordered byte stream.
- Each frame:
  - 4-byte big-endian unsigned length,
  - serialized protobuf envelope,
  - optional binary payload section for resource chunks if needed.
- Maximum control frame size: 64 KiB.
- Large resources are chunked separately.

## Message categories

- `SESSION`
  - hello
  - capability advertisement
  - rekey
  - heartbeat
  - goodbye
- `CONTROL`
  - enter control mode
  - exit control mode
  - cursor bounds update
  - Android metrics update
- `INPUT`
  - pointer move
  - tap/click
  - scroll
  - drag
  - key event
  - text commit
  - global action request
- `CLIPBOARD`
  - clipboard update descriptor
  - clipboard ack
  - clipboard fetch request
  - clipboard fetch response
- `RESOURCE`
  - resource begin
  - resource chunk
  - resource end
  - resource cancel
- `ERROR`
  - permission missing
  - unsupported capability
  - protocol violation
  - transport degraded
- `DIAGNOSTIC`
  - latency sample
  - version info
  - debug counters

## Required fields

Every envelope should include:

- `protocol_major`
- `protocol_minor`
- `session_id`
- `message_id`
- `message_type`
- `sent_monotonic_ms`
- `origin_device_id`
- `requires_ack`

Selected messages also include:

- `correlation_id`
- `sequence_no`
- `capability_bits`
- `resource_id`
- `clip_id`
- `history_eligible`

## Versioning strategy

- Major mismatch:
  - fail handshake.
- Minor mismatch:
  - continue if mandatory capabilities still intersect.
- Unknown fields:
  - ignore per protobuf norms.
- Capability negotiation:
  - explicit bitset exchanged during session startup.

## Idempotency/retry expectations

- Reliable stream transports do not require blanket per-message retransmission.
- Control/state transitions requiring certainty should use application-level ack.
- Clipboard/resource begin and end messages should be idempotent by `clip_id` / `resource_id`.
- Pointer motion and scroll are best-effort and should not be retried if stale.
- Duplicate `enter_control_mode` and `exit_control_mode` messages must be safely ignored.

## Example messages

Readable examples below are JSON-shaped for documentation only. Actual wire format should be protobuf.

### Pointer move

```json
{
  "type": "INPUT_POINTER_MOVE",
  "session_id": "6d9f4e0c",
  "message_id": 10421,
  "sequence_no": 5510,
  "delta_x": 18.5,
  "delta_y": -6.0,
  "pointer_source": "TRACKPAD",
  "sent_monotonic_ms": 3455512
}
```

### Key down

```json
{
  "type": "INPUT_KEY_DOWN",
  "session_id": "6d9f4e0c",
  "message_id": 10422,
  "sequence_no": 5511,
  "logical_key": "KEY_A",
  "modifiers": ["SHIFT"],
  "text": "A",
  "sent_monotonic_ms": 3455516
}
```

### Scroll

```json
{
  "type": "INPUT_SCROLL",
  "session_id": "6d9f4e0c",
  "message_id": 10423,
  "sequence_no": 5512,
  "axis_x": 0.0,
  "axis_y": -42.0,
  "phase": "CHANGED",
  "sent_monotonic_ms": 3455520
}
```

### Enter control mode

```json
{
  "type": "CONTROL_ENTER_MODE",
  "session_id": "6d9f4e0c",
  "message_id": 10400,
  "edge": "RIGHT",
  "android_display_width": 2800,
  "android_display_height": 1752,
  "cursor_mode": "OVERLAY_CURSOR",
  "requires_ack": true
}
```

### Clipboard text update

```json
{
  "type": "CLIPBOARD_UPDATE",
  "session_id": "6d9f4e0c",
  "message_id": 10510,
  "clip_id": "clip-8f21",
  "clip_kind": "TEXT",
  "mime_types": ["text/plain"],
  "is_sensitive": false,
  "text": "https://developer.android.com",
  "text_subtype": "URL"
}
```

### Clipboard image URI update

```json
{
  "type": "CLIPBOARD_UPDATE",
  "session_id": "6d9f4e0c",
  "message_id": 10511,
  "clip_id": "clip-8f22",
  "clip_kind": "IMAGE",
  "mime_types": ["image/png"],
  "is_sensitive": false,
  "resource": {
    "resource_id": "res-91aa",
    "size_bytes": 582193,
    "sha256": "3f8b...e1",
    "filename": "clipboard.png"
  }
}
```

### Error event

```json
{
  "type": "ERROR_EVENT",
  "session_id": "6d9f4e0c",
  "message_id": 10901,
  "code": "ANDROID_IME_NOT_CURRENT",
  "severity": "WARN",
  "user_visible": true,
  "retryable": false,
  "message": "Full clipboard sync disabled until the companion keyboard is selected."
}
```

# 9. Clipboard design

## Design principles

- v1 should be small, reliable, and loop-safe.
- Rich clipboard data on Android should be designed around `ClipData` and `content://` URIs, not raw paths.
- Large payloads should be sent as resources, not embedded inline.
- Every clipboard update must carry an origin marker to prevent sync loops.

## Explicit data-type distinctions

| Type | Definition in this product | Initial handling |
|---|---|---|
| Plain text | Arbitrary UTF-8 text not classified as a URL | v1 supported |
| URL | Absolute web/app URL carried as text plus URL subtype metadata | v1 supported |
| Image bytes | Raw PNG/JPEG/WebP bytes transferred over secure channel | v2 internal transfer form |
| Image URI / content URI | Android clipboard representation backed by provider URI | v2 destination representation on Android |
| Video bytes | Raw MP4/MOV/WebM bytes transferred over secure channel | v3 internal transfer form |
| Video URI / content URI | Android clipboard representation backed by provider URI | v3 destination representation on Android |
| File URI | Provider-backed URI representing an arbitrary file payload | v3 destination representation on Android |
| App-specific rich content | Styled text, proprietary clip metadata, app-internal references | Not preserved end-to-end in initial scope |

## v1: text + URL

### Source-side detection

- macOS:
  - detect plain string and URL pasteboard types.
- Android:
  - detect `ClipData` items containing text or URI text representations.
  - automatic background read requires current/default IME or foreground status.

### Wire representation

- Inline clipboard descriptor message with:
  - `clip_id`
  - `kind = TEXT`
  - `text`
  - `text_subtype = PLAIN | URL`
  - `is_sensitive`

### Destination-side reconstruction

- macOS:
  - write `NSString` and URL-compatible pasteboard types.
- Android:
  - plain text: `ClipData.newPlainText()`
  - URL: `ClipData.newRawUri()` when appropriate, plus text fallback if needed

### Permission model

- No extra platform permission beyond clipboard access constraints already described.

### Security constraints

- Maximum inline size in v1: 64 KiB.
- Over that threshold, reject or truncate with explicit user-visible error.
- Never log payload values.

### Fallback behavior

- If URL classification is uncertain, send as plain text.
- If Android cannot read clipboard automatically, allow:
  - push from Mac to Android,
  - manual pull from Android app UI.

### Incompatibility cases

- Stylized/spanned text loses formatting.
- Secure-entry fields may not expose clipboard behavior predictably.

## v2: image

### Source-side detection

- macOS:
  - detect image pasteboard types or image file URLs.
- Android:
  - detect `ClipData` items containing image-capable `content://` URIs or MIME types resolvable as images.

### Wire representation

- Clipboard descriptor with:
  - `clip_id`
  - `kind = IMAGE`
  - MIME type
  - dimensions if known
  - `resource_id`
  - size and digest
- Binary image transferred as chunked resource data.

### Destination-side reconstruction

- macOS:
  - materialize image in memory or temp cache and publish as native image pasteboard item.
- Android:
  - write image bytes to app-private cache,
  - mint short-lived `content://` URI from `RemoteClipboardProvider`,
  - publish clipboard via `ClipData.newUri(contentResolver, label, uri)`,
  - grant temporary read access through provider/clipboard semantics.

### Permission model

- Android provider grant behavior must be validated with prototype.
- No broad storage permission should be required for app-private cached clipboard items.

### Security constraints

- Enforce size cap, for example 20 MiB initial default.
- Cache lifetime short, for example 10 minutes or until clipboard replaced.
- Sensitive images should not persist longer than necessary.

### Fallback behavior

- If the destination cannot reconstruct the image safely, fall back to:
  - a text notice in the app UI,
  - manual import/export option.

### Incompatibility cases

- App-specific image references that are not readable through a resolvable URI cannot always be copied.
- Animated image formats may be flattened depending on source representation.

## v3: video and file

### Source-side detection

- macOS:
  - detect video file URLs and video pasteboard representations.
  - detect file URLs on the pasteboard.
- Android:
  - detect video-capable `content://` URIs and `video/*` MIME types.
  - detect file-like `content://` URIs or clipboard items that resolve to document/file MIME types.

### Wire representation

- Clipboard descriptor with:
  - `clip_id`
  - `kind = VIDEO` or `kind = FILE`
  - filename
  - MIME type
  - size
  - digest
  - `resource_id`
- Video or file bytes transferred as chunked resource data.

### Destination-side reconstruction

- macOS:
  - materialize temp file under app cache and place file URL on pasteboard.
- Android:
  - materialize temp file in app-private cache,
  - expose provider-backed URI,
  - set clipboard via URI-based `ClipData`.

### Permission model

- No broad external-storage permission should be required for baseline functionality.
- Use app-private cache plus provider grants instead of raw file-system exposure.

### Security constraints

- File allowlist for v3 initial release:
  - documents,
  - images,
  - common video formats such as MP4 and MOV,
  - common archives only if explicitly accepted.
- Block executable formats by default in consumer builds unless product requirements demand them.
- Size cap should be configurable but start conservative, for example 100 MiB.

### Fallback behavior

- If the destination app cannot use provider-backed URIs from clipboard, the data remains accessible through the companion app UI for manual export.

### Incompatibility cases

- Some Android apps paste only text and ignore file clipboard URIs.
- Some Android apps handle video clips as share targets rather than clipboard paste targets.
- Some macOS apps may expect file promises or richer drag-and-drop semantics rather than clipboard file URLs.

## Clipboard history design

Clipboard history should be local-first and compact.

Required behavior:

- Store recent successful clipboard items on each device in a bounded local history.
- Default history size:
  - 30 items on macOS
  - 30 items on Android
- Store compact metadata for every item:
  - type
  - created timestamp
  - origin device
  - filename if present
  - MIME type
  - byte size if present
- Store previews:
  - first 120 characters for text
  - thumbnail for image and video when practical
  - generic icon plus filename for files

Efficiency rules:

- Text entries may be stored inline up to a bounded size.
- Image, video, and file history entries should store preview metadata plus a cache handle, not duplicate unlimited full payloads.
- History cache should use TTL plus LRU cleanup.

User actions:

- tap or click a history item to copy it back to the current local clipboard,
- clear a single item,
- clear all history,
- optionally pin selected history items in a later release.

## App-specific rich content

Out of scope for initial versions:

- styled spans,
- custom MIME bundles,
- proprietary app payload objects,
- multi-item semantic clip bundles.

Fallback:

- degrade to plain text if coercible,
- otherwise do not sync automatically.

# 10. Control semantics

| Mac input | Android mapping | Reliability | Notes |
|---|---|---|---|
| Pointer move | Move remote overlay cursor by relative delta | Reliable inside product model | Not true OS mouse hover injection. |
| Primary click | Single tap gesture at overlay cursor location | Reliable | Best general-purpose click mapping. |
| Secondary click | Long press at cursor location, or context-click action if available | Approximate / app-dependent | Android apps vary widely in context-menu behavior. |
| Tap | Same as primary click | Reliable | |
| Scroll | Swipe/scroll gesture around cursor or focused scrollable node | Approximate | Works for many apps, not all custom views. |
| Drag | Press-hold-move-release gesture chain | Moderate | Long drags or custom canvases may behave inconsistently. |
| Long press | Hold gesture with configurable duration | Reliable to moderate | Depends on target app gesture recognition. |
| Text entry | IME `commitText`, composing text, delete/enter where focused editable target exists | Reliable in text fields | Requires companion IME for best results. |
| Modifier keys | Local state tracked and translated only for supported combinations | Limited | Android does not expose universal modifier semantics to third-party apps. |
| Escape | Map to Android Back | Reliable | Use `performGlobalAction(BACK)` when accessibility active. |
| Arrow / tab keys | Send through IME or accessibility fallback where possible | App-dependent | Useful in some text fields, not universal. |
| Switching back to Mac | Dedicated Mac hotkey, disconnect fail-safe | Reliable | Must not depend on Android UI state. |

Additional rules:

- Hover semantics are not guaranteed.
- True right-click behavior is not guaranteed.
- Android apps that depend on raw mouse hover or hardware key events may not behave like they do with a physical mouse/keyboard.
- Text entry outside editable fields is not guaranteed.
- Password and secure-entry surfaces may reject accessibility/IME-driven automation.

Recommended default exit behavior:

- Mac hotkey: configurable, but ship a hard default such as `Control` + `Option` + `Command` + `Left Arrow`.
- Also exit immediately on:
  - cable disconnect,
  - secure session failure,
  - accessibility service loss.

# 11. Delivery roadmap

## MVP scope

- macOS menu bar app with settings and trust UI.
- Android app with foreground service, accessibility service, companion IME, and onboarding.
- ADB-over-USB transport only.
- Secure pairing and trusted reconnect.
- Edge-triggered entry into Android control mode.
- Pointer move, primary click, scroll, drag, Back action.
- Text entry in editable fields via IME.
- Clipboard v1: plain text and URL.
- Manual unpair and diagnostics.

## V2 scope

- Production USB transport attempt using AOA.
- Wi-Fi fallback.
- Image clipboard via provider/URI architecture.
- Better reconnect behavior across sleep/wake and cable flaps.
- Compatibility hardening for Samsung One UI variants.
- Clipboard history foundation with text and image previews.

## V3 scope

- Video and file clipboard via provider/URI architecture.
- Full clipboard history for text, image, video, and file clips.
- Better enterprise controls and admin-friendly logging/privacy options.
- Expanded device QA matrix.
- Performance tuning and telemetry dashboards.

## Recommended milestones

1. Milestone 0: feasibility prototypes
2. Milestone 1: protocol/security skeleton and ADB transport
3. Milestone 2: macOS control mode and Android gesture control
4. Milestone 3: IME text entry and clipboard v1
5. Milestone 4: MVP stabilization and contract acceptance
6. Milestone 5: AOA transport gate
7. Milestone 6: image clipboard, history foundation, and fallback hardening
8. Milestone 7: video/file clipboard and release hardening

## Contractor work split

- Contractor A, macOS:
  - event tap,
  - edge detection,
  - cursor state,
  - settings UI,
  - transport process management.
- Contractor B, Android:
  - accessibility service,
  - overlay cursor,
  - IME,
  - clipboard/provider modules,
  - onboarding UX.
- Contractor C, cross-platform/security:
  - protocol schema,
  - secure channel,
  - transport abstraction,
  - trust store model,
  - integration test harness.
- Contractor D, QA/automation:
  - test matrix,
  - failure injection,
  - hardware lab validation,
  - regression suites.

## Rough dependency order

1. Validate AOA, accessibility cursor, and IME/clipboard assumptions.
2. Finalize secure protocol and trust model.
3. Implement ADB MVP transport.
4. Implement macOS control-mode switching.
5. Implement Android gesture mediation.
6. Implement IME text entry and clipboard v1.
7. Harden reconnection and diagnostics.
8. Attempt production AOA transport.
9. Build image/video/file clipboard and history on top of stable session/transport layers.

# 12. Acceptance criteria

## Pairing

- Given fresh installs on both devices, when the user initiates pairing over a supported transport, both devices show a pairing screen and accept the same 4-digit confirmation code.
- Pairing fails if the user declines or if the 4-digit code does not match on both devices.
- After successful pairing, each device shows the other as trusted.
- After unpairing either side, automatic reconnect is blocked until re-pair.

## USB connection behavior

- With a data-capable cable and supported device, the system detects cable attach within 5 seconds.
- In MVP mode, if USB debugging is disabled, the Android app and macOS app both show a clear blocked-state message.
- On cable disconnect during remote mode, local Mac input is fully restored within 250 ms.

## Control switching

- When the pointer crosses the configured edge and a trusted session is active, Android control mode activates within 150 ms in the USB MVP path.
- When the configured exit hotkey is pressed, the system exits Android control mode within 150 ms and restores normal local input.
- The system does not enter Android control mode if there is no trusted active session.

## Keyboard input

- In a test Android text field with the companion IME active, printable ASCII, Unicode text, backspace, and enter from the Mac are reproduced correctly in at least 99% of 500 automated test inputs.
- If the IME is not current, the UI indicates degraded text-entry support.
- Unsupported non-text key behavior is surfaced as unsupported, not silently claimed as supported.

## Pointer input

- In an instrumented Android test surface, pointer movement latency from Mac event capture to Android gesture dispatch median is:
  - <= 40 ms in MVP USB mode,
  - target <= 25 ms in production transport mode.
- Primary click, drag, and vertical scroll complete successfully in the test surface at least 98% of the time over 200 runs.

## Clipboard sync

- Plain text up to 64 KiB syncs from Mac to Android and Android to Mac within 500 ms median over USB in supported permission states.
- URL clips are classified and reconstructed as URL-capable clipboard entries where the destination platform supports it.
- Clipboard loops are prevented across at least 100 repeated same-content sync events.
- Image clips up to the configured size cap are reconstructed as valid clipboard items on both devices, or surfaced in the companion app for manual reuse if the destination app cannot paste them directly.
- Video and file clips are transferred as provider-backed or file-backed clipboard resources and remain available for re-copy from history even when direct paste is app-dependent.

## Clipboard history

- The clipboard history UI shows at least the 20 most recent clipboard items with type-appropriate preview metadata.
- Re-copying an item from history places that item back onto the current local clipboard within 500 ms median for text and within 2 seconds for cached media/file items.
- History cleanup prevents unbounded growth of local cache storage.

## Reconnection

- After cable unplug/replug, a trusted device reconnects without re-pairing within 5 seconds in the supported transport mode.
- After Mac sleep/wake or Android screen lock/unlock, the system either reconnects automatically or presents a clear reconnect state without leaving the Mac in a captured-input condition.

## Security verification

- Unpaired peers cannot establish a control session.
- All protocol frames captured on Wi-Fi fallback are unreadable without session keys.
- Replayed old frames from a prior session are rejected.
- After disconnect and trusted reconnect, a new session is established and replay checks do not block the new session.
- Revoking trust on one device prevents further automatic reconnect from the revoked peer.

## Logging/privacy compliance

- Diagnostic logs contain no clipboard values, no key values, no raw file contents, and no session keys.
- Temp clipboard resource files are cleaned on expiry and on app restart.
- Secure-store files are excluded from backup/export.

# 13. QA test plan

## OS and device matrix

| Category | Required coverage |
|---|---|
| macOS | 14.x, 15.x |
| Mac hardware | Apple Silicon primary; Intel if contracted |
| Android OS | 12, 13, 14, 15 |
| Android device family | At least 2 Samsung Galaxy Tab models, including the primary target model |
| Android UI layer | Relevant One UI versions on the selected tablets |

## Cable and connectivity cases

| Case | Expected result |
|---|---|
| Known-good USB-C data cable | Full supported behavior |
| USB 2-only data cable | Supported if transport works; measure degraded throughput |
| Charge-only cable | Clear unsupported-state message |
| Through USB-C hub/dock | Validate or explicitly mark unsupported |
| Cable unplug mid-drag | Immediate safe exit to Mac |
| Reversed cable orientation | Same result as normal |

## Permission-state cases

| Case | Expected result |
|---|---|
| All permissions granted | Full feature set |
| macOS Accessibility denied | No control mode; clear prompt |
| macOS Input Monitoring denied | No keyboard capture; clear prompt |
| Android accessibility disabled | No pointer/global actions; degraded state |
| Android IME enabled but not current | Text/clipboard degraded state |
| Android USB debugging off in MVP | No ADB session; clear blocked state |
| Android battery optimization active | Confirm whether service survives target usage; document if exemption required |

## Supported and unsupported app cases

Supported acceptance set:

- Android Settings
- Chrome
- Gmail
- Samsung Notes
- A simple instrumented test app with editable fields and scroll containers

Explicit unsupported/edge set:

- games with custom rendering/input loops
- DRM video apps
- camera previews
- secure-entry/password-heavy apps
- apps with custom canvas-only interaction

Expected result:

- supported set must pass acceptance criteria,
- unsupported set must fail predictably without corrupting local Mac input state.

## Clipboard content-type cases

| Type | Cases |
|---|---|
| Text | ASCII, Unicode, emoji, multiline, very long text, password-like text |
| URL | http, https, custom app schemes |
| Image | PNG, JPEG, large image, image from app-private URI |
| File | PDF, TXT, ZIP, large file, unsupported executable |
| Unsupported rich content | styled text, multi-item proprietary clips |

## Reconnect scenarios

- cable unplug/replug
- Android app process killed and restarted
- macOS app restarted
- Mac sleep/wake
- Android screen off/on
- Android unlock after biometric/PIN
- switching transports from USB to Wi-Fi fallback

## Failure injection

- corrupt frame length
- corrupt AEAD tag
- replay old frame
- duplicate `enter_control_mode`
- stale clipboard resource fetch
- expired provider token
- low-storage condition on Android
- ADB server restart during session

## Security regression tests

- verify no plaintext clipboard/key payload in app logs
- verify unpaired peer cannot control device
- verify trust reset invalidates reconnect
- verify session rekey occurs after threshold
- verify temp resource cleanup on app restart

# 14. Known limitations

- This product does not mirror the Android display.
- Without root or privileged system permissions, Android does not allow a normal third-party app to inject arbitrary system-wide hardware key events. Text entry is therefore centered on a companion IME, not raw key injection parity.
- Pointer control is implemented as an overlay cursor plus accessibility gesture mediation, not true OS mouse injection.
- Hover, secondary click, and app-specific pointer semantics are not guaranteed.
- Full automatic clipboard read on Android 10+ requires the companion app to be the current/default IME or to be foregrounded.
- The MVP USB path requires USB debugging and ADB authorization.
- Production direct USB without ADB depends on AOA feasibility on target Samsung hardware and must be validated, not assumed.
- Video and file clipboard support rely on provider-backed URI reconstruction and are app-dependent at paste time.
- Public app-store distribution may be difficult due to accessibility and input-monitoring requirements.
- Some Android apps intentionally restrict accessibility, clipboard, or input behavior; these will not be made fully compatible.

# 15. Contractor handoff appendix

## Recommended repository structure

```text
/docs
  /architecture
  /qa
/apps
  /macos-controller
  /android-companion
/packages
  /protocol
  /session-core
  /crypto-abstractions
  /test-fixtures
/tools
  /adb
  /proto-gen
  /benchmarks
```

## Suggested package/module names

- macOS:
  - `MacControllerApp`
  - `ControlModeCoordinator`
  - `GlobalEventTapMonitor`
  - `ClipboardMonitor`
  - `SessionManager`
  - `TransportBroker`
- Android:
  - `com.mtog.app`
  - `connection.ConnectionForegroundService`
  - `accessibility.RemoteAccessibilityService`
  - `ime.RemoteInputMethodService`
  - `clipboard.ClipboardRepository`
  - `provider.RemoteClipboardProvider`
  - `session.SessionManager`
- Shared:
  - `protocol`
  - `sessioncore`
  - `cryptocore`

## API boundary definitions

- `protocol`:
  - protobuf schema only,
  - no platform APIs.
- `session-core`:
  - framing,
  - handshake,
  - AEAD,
  - sequencing,
  - transport abstraction interface.
- `transport adapters`:
  - implement `DuplexByteChannel`.
- `platform control layers`:
  - translate native events into protocol messages and vice versa.
- `clipboard layer`:
  - type classification and materialization,
  - resource transfer coordination,
  - provider/cache management on Android.

## Example backlog / epics

- Epic 1: Feasibility spikes
- Epic 2: Shared protocol and secure session
- Epic 3: macOS event capture and control-mode switching
- Epic 4: Android accessibility control plane
- Epic 5: Android IME and clipboard v1
- Epic 6: MVP USB transport via ADB
- Epic 7: Reconnect, diagnostics, and acceptance harness
- Epic 8: AOA production transport
- Epic 9: Clipboard v2/v3
- Epic 10: QA matrix and release hardening

## Example task breakdown by platform

### macOS

- build menu bar shell and preferences
- implement event tap capture
- implement edge detector and cursor lock
- implement ADB process wrapper
- integrate secure session stack
- implement pasteboard classifier/materializer

### Android

- build onboarding/settings UI
- implement foreground service
- implement accessibility overlay cursor and gesture dispatch
- implement global action routing
- implement companion IME
- implement clipboard repository and provider

### Shared/security

- define protobuf schema
- implement secure framing/channel
- implement pairing/trust state
- implement replay protection and rekey
- build integration fixtures

### QA

- build instrumented Android test app
- build latency measurement harness
- build cable/permission/state regression suites
- maintain hardware compatibility matrix

## What should be prototyped first

1. AOA transport on the exact target Samsung tablet models.
2. Android accessibility overlay cursor plus tap/drag/scroll fidelity.
3. Companion IME viability for text entry and clipboard access on target Android versions.

These three items are the program’s technical gates.

## What should not be promised to the client

- “Works like Universal Control on every Android app.”
- “No special Android permissions required.”
- “No keyboard-role requirement for automatic clipboard sync.”
- “Production USB without ADB is guaranteed.”
- “Hardware mouse parity.”
- “All video and file clipboard targets will paste identically across every app.”
- “App Store distribution is straightforward.”

# Contractor brief

Build a two-app system, not a mirroring product. The Mac app is the control origin; the Android app is a companion that translates remote input into platform-supported Android actions. The target packaging is one universal macOS app supporting Apple Silicon and supported Intel Macs, plus one Android app targeting the Galaxy Tab S11 family over USB-C. The first release should be engineered around security, recoverability, and explicit platform limits, not around marketing parity claims.

The fastest viable MVP uses ADB-over-USB as the cable transport, but this must be treated as an implementation shortcut only. The real production goal is a direct USB transport using Android Open Accessory, and that path must be validated immediately on the target Samsung Galaxy Tab hardware. If AOA fails its prototype gate, the contract should not promise polished USB-only production delivery without re-scoping.

The Android architecture must include both an `AccessibilityService` and a companion `InputMethodService`. The accessibility service handles tap/drag/scroll/global actions and can render a remote cursor overlay. The IME is required for realistic text entry and for full automatic clipboard sync on Android 10+ because background clipboard access is restricted unless the app is the current/default keyboard or is foregrounded. Clipboard scope should cover text, image, video, and file clips, with a compact local history UI on both devices.

Security is non-negotiable. Pairing must require explicit confirmation on both devices. The requested simple UX is a 4-digit confirmation code entered on both devices, but the real trust model must still use long-term device identity keys under the hood. Every session must use authenticated encryption, trusted reconnect with fresh session keys, replay protection against old frames, and local device trust. Raw clipboard contents, raw key contents, and secrets must not be logged by default. The design assumes direct notarized Mac distribution and a carefully disclosed Android permission flow.

Contractor execution should start with three prototypes: AOA transport, Android accessibility cursor fidelity, and IME/clipboard behavior. Only after those are proven should the team lock scope and schedule for production delivery.

# Milestone-based estimate breakdown

## Planning assumptions

- Team:
  - 1 macOS engineer
  - 1 Android engineer
  - 1 cross-platform/security engineer
  - 0.5 QA engineer
- Estimates are rough order-of-magnitude ranges, not fixed bids.
- Calendar assumes partial parallelization.

| Milestone | Scope | Duration | Primary roles | Output |
|---|---|---:|---|---|
| M0 | Feasibility prototypes: AOA, accessibility cursor, IME/clipboard | 3 to 4 weeks | Android, macOS, security | Go/no-go report and prototype code |
| M1 | Shared protocol, pairing, trust store, ADB transport skeleton | 2 to 3 weeks | Security, macOS, Android | Working secure channel over ADB |
| M2 | macOS edge switching and Android pointer control | 3 to 4 weeks | macOS, Android | Basic remote control loop |
| M3 | IME text entry and clipboard v1 | 2 to 3 weeks | Android, macOS | Text input and text/URL clipboard sync |
| M4 | MVP hardening, reconnect, diagnostics, QA pass | 2 to 3 weeks | All | Contract-grade MVP |
| M5 | AOA production transport implementation and hardware validation | 4 to 6 weeks | macOS, Android, security | Production transport or explicit fallback decision |
| M6 | Image clipboard, Wi-Fi fallback hardening | 3 to 4 weeks | Android, macOS | V2 feature set |
| M7 | File clipboard, expanded QA matrix, release hardening | 3 to 4 weeks | All | V3 feature set |

Estimated calendar:

- MVP: approximately 12 to 17 weeks.
- V2 with production USB path: approximately 16 to 23 weeks total.
- V3: approximately 20 to 27 weeks total.

If AOA fails and the team must pivot to Wi-Fi as the production-grade transport, calendar risk decreases slightly but product positioning changes materially.

# Risk register with mitigation plan

| ID | Risk | Probability | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R1 | AOA transport is unreliable or unsupported on target Samsung hardware | Medium to high | Critical | Prototype first on exact hardware; make AOA a gated milestone, not a promise | Architect / Android |
| R2 | Android cannot deliver acceptable non-text keyboard fidelity without privileged APIs | High | High | Scope keyboard support around IME text entry; clearly mark non-text keys as limited | Android |
| R3 | Android clipboard automation is blocked unless app is current/default IME | High | High | Make IME part of baseline architecture and onboarding; define degraded mode if user declines | Android |
| R4 | Accessibility-based pointer semantics feel inconsistent across apps | Medium | High | Acceptance-test a supported app set; document unsupported app classes; do not promise parity | Android / QA |
| R5 | ADB MVP is mistaken for production architecture by stakeholders | Medium | High | Put MVP-only label in contract and UI; require written gate review before production claims | PM / Architect |
| R6 | macOS permissions friction reduces usability or complicates distribution | Medium | Medium | Use direct notarized distribution and strong onboarding; avoid Mac App Store assumption | macOS |
| R7 | Google Play or Android policy scrutiny on accessibility usage blocks store distribution | Medium | High | Assume direct distribution or enterprise distribution first; validate store path separately | PM / Android |
| R8 | Clipboard or key data leaks into logs or temp files | Medium | Critical | Strict log policy, secure code review, automated log scanning, temp-file TTL cleanup | Security |
| R9 | Sleep/wake and cable flap leave Mac input in a captured state | Low to medium | Critical | Design fail-safe local restore path first; add watchdog tests | macOS |
| R10 | USB cable quality and hub behavior create intermittent failures | Medium | Medium | Test with certified cables and hubs; detect and message unsupported states | QA |
| R11 | Testing matrix expands beyond team capacity | Medium | Medium | Lock initial support to named Samsung models and OS versions | PM / QA |
| R12 | Provider-based image/file clipboard fails in some paste targets | Medium | Medium | Validate with prototype, keep manual export fallback, limit supported clip classes | Android |
