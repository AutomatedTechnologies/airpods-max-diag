# AirPods Max Diagnostics

A Detroit Automation Academy utility for macOS High Sierra (10.13): diagnose a
USB-connected, non-responsive **AirPods Max (Lightning generation)** — Apple
USB VID 0x05ac / PID 0x1109 — and recover it.

GUI successor to the `airpods-max-diag.sh` command-line utility (2026-11-08);
the probe set and verdict branches are the same, implemented natively in
Objective-C/AppKit against stock macOS tools (`system_profiler`, `ioreg`,
`pmset`, `log`, `networksetup`).

## What it does

- **Run Diagnostics** — five-section report: USB enumeration + power,
  IORegistry device node, CoreAudio device list, Bluetooth pairing/link,
  recent bluetoothd/coreaudiod log evidence, and a branching verdict.
- **Restart AirPods Max…** — guided sheet for the physical restart
  (noise-control button + Digital Crown until the status light flashes amber).
- **Factory Reset…** — guided sheet with a 15-second hold countdown
  (amber → white), then re-pair steps.
- **Restart Services** — restarts `coreaudiod` and `bluetoothd` with an
  administrator prompt, for the enumerated-and-connected-but-silent case.
- **Firmware Update…** — reads the device's firmware over Bluetooth and
  compares it with the latest for this model (**6F25**, Apple Support
  “About firmware updates for AirPods”, 106340, checked 2026-11-08); shows
  Apple's automatic-delivery conditions evaluated live (charging over USB,
  Bluetooth connected, host on Wi-Fi). Apple ships no manual installer;
  the panel says so and links the support page.
- **Save Report** — writes the diagnostic report to a text file.

First launch presents the Academy welcome sheet (SDS-8 form: animated mark +
the library startup sound). Icon per the amended SDS-3 construction (white
tile + ink glyph, no black field).

## Identity

- Bundle: `AirPodsMaxDiag.app` · `com.detroitautomationacademy.airpodsmaxdiag`
- Minimum system: macOS 10.13 · Architecture: x86_64 · Unsigned CI test build
  (Gatekeeper first launch: right-click → Open)
- Carries the Academy audit entry in Info.plist and the Academy License
  (revocable) + NOTICE in Resources. Academy-original code — see
  `LICENSE-ACADEMY.md` and `NOTICE` at the repo root.
- AirPods Max is a trademark of Apple Inc.; this utility is not affiliated
  with or endorsed by Apple Inc.

## Build

CI (`.github/workflows/build-airpods-max-diag.yml`, macos-15) compiles with
clang at a 10.13 deployment target, stamps `apd-test-<run>`, and publishes a
prerelease zip — the Distro catalog pipeline consumes that release.

BUILD STAMP — Built: 2026-11-08 · Build: apd source v1 · Agent: Forge · Authorized: J. Spencer Smith, directive of 2026-11-08 (GUI update + Distro publication)
