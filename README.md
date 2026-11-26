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
control              # Debian control file
```

## Build

Requires Theos on macOS:

```bash
export THEOS=$HOME/theos
make package
```

Produces `com.kilo.wifibruter_1.0-1_iphoneos-arm64.deb`.

## GitHub Actions

Pushes to `main` trigger a build via `.github/workflows/build.yml`. The `.deb` is uploaded as a workflow artifact.

## Install

1. Copy the `.deb` to your jailbroken device.
2. `dpkg -i com.kilo.wifibruter_*.deb`
3. Configure in **Settings > WiFi Bruter**, place your wordlist at the configured path, then respring.

## Warning

For authorized security testing only, on devices you own or have explicit written permission to test. Requires a jailbroken device and private CoreWLAN entitlements.
