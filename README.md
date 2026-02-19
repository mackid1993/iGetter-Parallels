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
