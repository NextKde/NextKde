# Network status architecture

`modules/bar/NetworkService.qml` is the only adapter between shell UI and
NetworkManager in this project. It polls `nmcli` asynchronously every three
seconds and performs only explicit user-requested writes. No Bar component may invoke
`nmcli` or parse its output directly.

## Public state contract

Consumers use these properties:

- `available`: whether NetworkManager/nmcli could be queried.
- `networkingEnabled`, `wifiEnabled`: global radio state.
- `connectionType`: `wifi`, `ethernet`, or `none`.
- `deviceState`: `connected`, `connecting`, `disconnected`, `disabled`, or
  `unknown`.
- `connectivity`: `full`, `portal`, `limited`, `none`, or `unknown`.
- `deviceName`, `connectionName`, `ssid`, `signalStrength`, `ipv4`.

`deviceState` means a link/profile state. `connectivity` is the independent
NetworkManager Internet reachability check; UI must preserve that distinction.
For example, a connected Wi-Fi device with `limited` connectivity receives an
orange warning badge instead of an offline icon.

## UI ownership

- `NetworkStatus.qml` renders the passive Bar indicator and hover details.
- `NetworkTraffic.qml` samples the active interface's kernel RX/TX byte
  counters and renders only presentation-friendly transfer rates.
- `NetworkPanel.qml` is the read-only Wi-Fi card that will later be embedded
  into the iOS-style top control centre.
- `BarWindow.qml` only places the component.
- Future quick settings, Wi-Fi picker, and connection dialogs consume
  `NetworkService` rather than duplicating state logic.

## Planned write API

`connectWifi(ssid, password)` connects normal WPA/open networks. Enterprise
networks use `connectEnterpriseWifi(ssid, identity, password, eapMethod,
anonymousIdentity)`;
currently the explicit supported choices are PEAP/MSCHAPv2 and TTLS/PAP. The
service exposes `wifiConnectInProgress`, `wifiConnectError`, and
`wifiConnectionFinished` for all UI surfaces. Passwords are positional process
arguments only and are never logged or persisted in QML. The enterprise method
creates only a shell-owned `quickshell-8021x-…` NetworkManager profile, so it
does not overwrite an unrelated profile with the same SSID.

TLS and CA-certificate policy remain a follow-up because they need a certificate
picker and must not be guessed. `setWifiEnabled(enabled)` is the radio write
method used by the Wi-Fi panel. `disconnectActiveWifi()` intentionally removes
only the active device connection and preserves its saved NetworkManager
profile. `forgetWifiProfile(ssid, profileUuid)` deletes only the UUID resolved
from the selected scan row, after the panel's explicit confirmation.

`refreshWifiNetworks()` returns de-duplicated nearby SSIDs (the strongest AP per
name) only when the user opens the panel. Each candidate also carries the UUID
of a matching saved Wi-Fi profile, resolved from NetworkManager; reconnect uses
that UUID rather than assuming the editable profile name equals the SSID.
