# WiFiBruter

Jailbroken iOS tweak that attempts WiFi passcodes from a wordlist. Configurable from the **Settings app** via a PreferenceBundle. Primarily targets **iOS 12** and **iOS 15** (best-effort on 15 due to tighter sandboxing).

## iOS version support

| iOS | Status | Notes |
|-----|--------|-------|
| iOS 12 | Supported | SpringBoard hook + private CoreWLAN APIs generally accessible |
| iOS 13–14 | Likely works | Same approach as iOS 12, minor API shifts possible |
| iOS 15 | Best-effort | Tighter sandboxing; CoreWLAN private methods may be stripped. Tweak uses `NSClassFromString` + `respondsToSelector` checks to avoid crashes. Logs to `/var/mobile/Documents/wifibruter_log.txt` for debugging |

iOS versions before 12 or after 15 are untested.

## How it works

- Hooks `SpringBoard` and, on launch, scans for the configured target SSID using the private `CoreWLAN` API (`CWInterface`).
- Attempts each password from the wordlist via `joinNetwork:withPassword:error:` / `associateToNetwork:password:error:`.
- On success, writes the result to `/var/mobile/Documents/wifibruter_result.txt` and shows an alert.
- All settings (enabled toggle, target SSID, wordlist path, delay) are editable in **Settings > WiFi Bruter**.

## Project layout

```
WiFiBruter/          # Main tweak (MobileSubstrate dylib)
WiFiBruterPrefs/     # PreferenceBundle (Settings app pane)
.github/workflows/   # GitHub Actions build (macOS, Theos)
wordlist.txt         # Sample wordlist
control              # Debian control file (Package: dungx.wifibruter)
```

## Sileo / Cydia repo

Add the **dungxrepo** source to Sileo or Cydia:

```
https://dung-x.github.io/dungxrepo/
```

Package: **dungx.wifibruter**

## Build

Requires Theos on macOS. Builds three variants:

| Variant | Install Prefix | Package | Use Case |
|---------|---------------|---------|----------|
| rootful | `/` | `dungx.wifibruter` | checkra1n, palera1n rootful |
| rootless | `/var/jb` | `dungx.wifibruter-rootless` | Dopamine, palera1n rootless |
| roothide | `/var/jb` | `dungx.wifibruter-roothide` | roothide jailbreak |

```bash
export THEOS=$HOME/theos

# Rootful (default)
make package

# Rootless
THEOS_PACKAGE_INSTALL_PREFIX=/var/jb make package

# Roothide
THEOS_PACKAGE_INSTALL_PREFIX=/var/jb make package
```

Produces:
- `dungx.wifibruter_1.0-1_iphoneos-arm64.deb`
- `dungx.wifibruter-rootless_1.0-1_iphoneos-arm64.deb`
- `dungx.wifibruter-roothide_1.0-1_iphoneos-arm64.deb`

## GitHub Actions

Pushes to `main` trigger a matrix build via `.github/workflows/build.yml` producing all three `.deb` variants as workflow artifacts.

## Install

Choose the `.deb` matching your jailbreak type:

```bash
# Rootful
dpkg -i dungx.wifibruter_*.deb

# Rootless / Roothide
dpkg -i dungx.wifibruter-rootless_*.deb
# or
dpkg -i dungx.wifibruter-roothide_*.deb
```

Configure in **Settings > WiFi Bruter**, place your wordlist at the configured path, then respring.

## Warning

For authorized security testing only, on devices you own or have explicit written permission to test. Requires a jailbroken device and private CoreWLAN entitlements.
