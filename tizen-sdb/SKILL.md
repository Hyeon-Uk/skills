---
name: tizen-sdb
description: Tizen SDB (Smart Development Bridge) tool for managing Tizen devices and emulators. Use when working with Tizen development tasks that require: (1) checking connected devices/emulators, (2) installing or uninstalling .tpk apps, (3) pushing/pulling files to/from a device, (4) running shell commands on a device, (5) viewing device logs via dlogutil, (6) port forwarding, or (7) toggling root mode. SDB is the Tizen equivalent of Android's adb. Triggers on: "sdb", "Tizen device", "Tizen emulator", "install tpk", "launch app on Tizen", "Tizen logs".
---

# Tizen SDB

SDB binary: `~/tizen-studio/tools/sdb`

## Device Management

```bash
sdb devices                          # List connected devices/emulators
sdb connect 127.0.0.1:26101         # Connect to emulator (default port)
sdb disconnect                       # Disconnect all
sdb disconnect 127.0.0.1:26101      # Disconnect specific device
```

Emulator SDB ports: 1st VM=26101, 2nd=26102, 3rd=26103

## App Management

```bash
sdb install app.tpk                        # Install tpk package
sdb uninstall <package-id>                 # Uninstall by package ID
sdb shell app_launcher -s <package-id>    # Launch app
sdb shell app_launcher -k <package-id>    # Kill app
sdb shell pkginfo --list                   # List installed packages
```

## File Transfer

```bash
sdb push <local-path> <device-path>       # PC → Device
sdb pull <device-path> <local-path>       # Device → PC
```

Common device paths:
- Apps: `/opt/usr/apps/<package-id>/`
- Shared: `/opt/usr/home/owner/media/`
- Temp: `/tmp/`

## Shell & Logs

```bash
sdb shell                                  # Interactive shell
sdb shell <command>                        # Single command
sdb shell dlogutil                         # All logs (real-time)
sdb shell dlogutil -s <Tag>               # Filter by tag
sdb shell dlogutil *:E                    # Error level only
sdb shell dlogutil -c                      # Clear log buffer
```

## Root & Port Forwarding

```bash
sdb root on                                          # Enable root (emulator only)
sdb root off                                         # Disable root
sdb forward tcp:<local-port> tcp:<device-port>      # Port forwarding
sdb forward --list                                   # List forwards
sdb forward --remove tcp:<local-port>               # Remove specific forward
```

## Multiple Devices

```bash
sdb -s emulator-26101 <command>   # Target specific serial
sdb -e <command>                   # Target emulator
sdb -d <command>                   # Target physical device
```

## References

- See `references/workflows.md` for common Tizen dev workflows (build → install → log).
