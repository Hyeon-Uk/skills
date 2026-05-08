# Tizen SDB Common Workflows

## 1. Deploy TizenFX App to Emulator

```bash
# Check emulator is connected
sdb devices

# Enable root mode (emulator only)
sdb root on

# Install tpk
sdb install /path/to/app.tpk

# Launch app
sdb shell app_launcher -s <package-id>

# View logs
sdb shell dlogutil -s <AppTag>
```

## 2. Update App (Reinstall)

```bash
sdb shell app_launcher -k <package-id>   # Stop running app
sdb uninstall <package-id>               # Remove old version
sdb install new-version.tpk              # Install new version
sdb shell app_launcher -s <package-id>   # Relaunch
```

## 3. Run TCT Tests

```bash
# Install test package
sdb install Tizen.XXX.Tests.tpk

# Launch test app
sdb shell app_launcher -s org.tizen.xxx.tests

# Collect test logs
sdb shell dlogutil -s TCT > tct-results.log

# Pull result file
sdb pull /opt/usr/apps/org.tizen.xxx.tests/data/result.xml ./
```

## 4. Browse Device Files

```bash
sdb root on
sdb shell ls /opt/usr/apps/             # List installed apps
sdb pull /opt/usr/apps/<pkg>/data/ ./   # Pull app data
```

## 5. Port Forwarding for Remote Debugging

```bash
sdb forward tcp:4711 tcp:4711          # VS debugger port
sdb forward --list                      # Verify forwarding
```

## Find Package ID

```bash
sdb shell pkginfo --list | grep <app-name>
sdb shell pkginfo --query <package-id>
```
