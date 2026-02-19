# iGetter Native Messaging Bridge

Routes Chrome extension download intercepts from a macOS browser to iGetter running inside a Parallels Windows VM.

```
Browser (macOS) → Native Messaging → Python bridge → TCP:19700 → C# relay (Windows) → iGetter
```

## How It Works

The Chrome extension sends downloads to a native messaging host. Since iGetter runs in Windows, a Python bridge on macOS connects over TCP to a C# relay inside the VM. The relay spawns `iGetter_x86.exe` and pipes the message through. Download paths are rewritten from `/Users/you/...` to `\\Mac\Home\...` so iGetter saves files to the Mac filesystem via Parallels shared folders.

If the VM is paused, suspended, or stopped, the bridge automatically starts it and waits for iGetter to be ready before forwarding the download.

## Prerequisites

- macOS with Parallels Desktop
- Windows VM with iGetter installed (`%LOCALAPPDATA%\Programs\iGetter\`)
- iGetter Chrome extension installed in your browser
- .NET Framework 4.0+ in the VM (included with Windows)
- Python 3 on macOS (included with macOS)

## Install

```bash
chmod +x install-igetter-bridge.sh
./install-igetter-bridge.sh
```

The installer auto-detects your VM name and hostname, then:

1. Writes the Python bridge and shell wrapper to `~/`
2. Installs native messaging manifests for Chrome, Vivaldi, Brave, Edge, and Chromium
3. Compiles and installs the C# relay in the VM
4. Copies the relay to the Windows Startup folder
5. Adds a firewall rule for TCP 19700

Restart your browser after installing.

## Config

Edit the top of `install-igetter-bridge.sh` before running:

- `WIN_USER` — Windows username
- `RELAY_PORT` — TCP port for the bridge (default: `19700`)

# iGetter Native Messaging Bridge — Installed Files

## macOS

- `~/iGetter.py` — Python bridge (handles VM wake, waits for iGetter, rewrites paths, forwards to relay via TCP)
- `~/iGetter.sh` — Shell wrapper (just execs Python, called by browser native messaging)
- `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.presenta.igetter_messaging_host.json`
- `~/Library/Application Support/Chromium/NativeMessagingHosts/com.presenta.igetter_messaging_host.json`
- `~/Library/Application Support/Vivaldi/NativeMessagingHosts/com.presenta.igetter_messaging_host.json`
- `~/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.presenta.igetter_messaging_host.json`
- `~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/com.presenta.igetter_messaging_host.json`

## Windows

- `%LOCALAPPDATA%\igetter-relay.exe` — TCP relay (listens on port 19700, spawns iGetter_x86.exe, compiled as winexe — no console window)
- `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\igetter-relay.exe` — Copy of relay for auto-start at logon
- Firewall rule: **iGetter Relay** (TCP 19700 inbound, all profiles)

## Uninstall

### macOS
```bash
rm ~/iGetter.py ~/iGetter.sh
rm ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/com.presenta.igetter_messaging_host.json
rm ~/Library/Application\ Support/Chromium/NativeMessagingHosts/com.presenta.igetter_messaging_host.json
rm ~/Library/Application\ Support/Vivaldi/NativeMessagingHosts/com.presenta.igetter_messaging_host.json
rm ~/Library/Application\ Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.presenta.igetter_messaging_host.json
rm ~/Library/Application\ Support/Microsoft\ Edge/NativeMessagingHosts/com.presenta.igetter_messaging_host.json
```

### Windows
```cmd
taskkill /f /im igetter-relay.exe
del "%LOCALAPPDATA%\igetter-relay.exe"
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\igetter-relay.exe"
netsh advfirewall firewall delete rule name="iGetter Relay"
```

**This project is not affilaited with or supported by Presenta Ltd. iGetter is a trademark of Presenta Ltd.** Please purchase iGetter at https://igetter.net. It is an excellent piece of software.
