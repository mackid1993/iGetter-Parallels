#!/bin/bash
set -e

echo "=== iGetter Native Messaging Bridge Installer ==="
echo ""

# --- Config ---
MAC_USER="$USER"
MAC_HOME="$HOME"
WIN_USER="david"
VM_NAME="$(prlctl list -o name --no-header | head -1 | xargs)"
RELAY_PORT=19700

if [ -z "$VM_NAME" ]; then
    echo "ERROR: No Parallels VM found."
    exit 1
fi
echo "VM: $VM_NAME"
echo ""

# Helper: run command in Windows VM
winexec() {
    prlctl exec "$VM_NAME" "$@"
}

# --- macOS: Python bridge ---
echo "[macOS] Writing Python bridge..."

cat > "$MAC_HOME/iGetter.py" << 'EOF'
#!/usr/bin/env python3
import os, socket, struct, json, subprocess, time

VM_NAME = "PLACEHOLDER_VMNAME"
VM_PORT = 19700
PRLCTL = "/usr/local/bin/prlctl"
MDNS_FALLBACK = f"{VM_NAME}.local"

def _run(args):
    """Run a command with stdin/stdout/stderr isolated from Chrome's pipes."""
    return subprocess.check_output(
        args,
        stdin=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10
    ).decode().strip()

def _call(args):
    """Call a command with stdin/stdout/stderr isolated from Chrome's pipes."""
    subprocess.call(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

def ensure_vm_running():
    try:
        status = _run([PRLCTL, "status", VM_NAME])
    except Exception:
        return
    if "running" in status:
        return
    if "suspended" in status:
        _call([PRLCTL, "resume", VM_NAME])
    else:
        _call([PRLCTL, "start", VM_NAME])
    # Wait until VM is truly running
    while True:
        try:
            status = _run([PRLCTL, "status", VM_NAME])
            if "running" in status:
                return
        except Exception:
            pass
        time.sleep(1)

def wait_for_relay():
    # Wait for Windows to be truly responsive
    while True:
        try:
            result = _run([PRLCTL, "exec", VM_NAME, "cmd", "/c", "echo ready"])
            if "ready" in result:
                break
        except Exception:
            pass
        time.sleep(2)
    # Wait for iGetter.exe process
    while True:
        try:
            result = _run([PRLCTL, "exec", VM_NAME, "cmd", "/c",
                "tasklist /fi \"imagename eq iGetter.exe\" /nh"])
            if "iGetter.exe" in result:
                time.sleep(5)
                return
        except Exception:
            pass
        time.sleep(2)

def get_vm_host():
    """Resolve VM IP at runtime via prlctl. Falls back to mDNS if unavailable."""
    try:
        out = _run([PRLCTL, "list", "-f", "-o", "ip", "--no-header", VM_NAME])
        # Pick first non-empty, non-loopback IPv4 address.
        # prlctl emits "-" when Tools isn't responsive and can list multiple IPs.
        for ip in out.split():
            if ip and ip != "-" and not ip.startswith("127.") and ":" not in ip:
                return ip
    except Exception:
        pass
    return MDNS_FALLBACK

def rewrite_path(msg_bytes):
    try:
        length = struct.unpack('<I', msg_bytes[:4])[0]
        payload = json.loads(msg_bytes[4:4+length])
        if 'path' in payload:
            mac_home = os.path.expanduser("~")
            payload['path'] = payload['path'].replace(mac_home, "\\\\Mac\\Home").replace('/', '\\')
        new_payload = json.dumps(payload).encode('utf-8')
        return struct.pack('<I', len(new_payload)) + new_payload
    except:
        return msg_bytes

def main():
    # IMMEDIATELY read Chrome's message - must happen before anything else
    msg = os.read(0, 65536)
    if not msg:
        return
    msg = rewrite_path(msg)

    # Now safe to wait for VM - message is buffered, all subprocesses use DEVNULL
    ensure_vm_running()
    wait_for_relay()

    # Resolve VM host at runtime (avoids stale mDNS cache after IP changes)
    vm_host = get_vm_host()

    # Send buffered message to relay
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((vm_host, VM_PORT))
        sock.sendall(msg)
        sock.shutdown(socket.SHUT_WR)
        response = b''
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            response += chunk
        sock.close()
        if response:
            os.write(1, response)
    except Exception:
        pass

if __name__ == "__main__":
    main()
EOF

cat > "$MAC_HOME/iGetter.sh" << 'EOF'
#!/bin/bash
exec /usr/bin/python3 "$(dirname "$0")/iGetter.py"
EOF

chmod +x "$MAC_HOME/iGetter.py" "$MAC_HOME/iGetter.sh"

# Inject VM name (IP is resolved at runtime, no hostname injection needed)
sed -i '' "s/PLACEHOLDER_VMNAME/$VM_NAME/" "$MAC_HOME/iGetter.py"

echo "  Created ~/iGetter.py and ~/iGetter.sh"

# --- macOS: Native messaging manifests ---
echo "[macOS] Installing native messaging manifests..."

MANIFEST=$(cat << MEOF
{
  "name": "com.presenta.igetter_messaging_host",
  "description": "iGetter Download Manager",
  "path": "/Users/$MAC_USER/iGetter.sh",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://kefncalcphllnknagnlnfcndlehpkpck/",
    "chrome-extension://kebcncgjkooaakehamjdfpmaggongjlm/"
  ]
}
MEOF
)

for dir in \
    "Google/Chrome" \
    "Chromium" \
    "Vivaldi" \
    "BraveSoftware/Brave-Browser" \
    "Microsoft Edge"; do
    dest="$MAC_HOME/Library/Application Support/$dir/NativeMessagingHosts"
    mkdir -p "$dest"
    echo "$MANIFEST" > "$dest/com.presenta.igetter_messaging_host.json"
done
echo "  Installed for Chrome, Vivaldi, Brave, Edge, Chromium"

# --- Windows: Write C# relay source to Mac filesystem ---
echo ""
echo "[Windows] Writing relay source..."

STAGING="$MAC_HOME/.igetter-bridge-staging"
mkdir -p "$STAGING"

cat > "$STAGING/igetter-relay.cs" << 'EOF'
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading;

class IGetterRelay
{
    static void Main(string[] args)
    {
        int port = 19700;
        string igetterPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs", "iGetter", "iGetter_x86.exe");

        var listener = new TcpListener(IPAddress.Any, port);
        listener.Start();

        while (true)
        {
            TcpClient client = listener.AcceptTcpClient();
            ThreadPool.QueueUserWorkItem(_ => HandleClient(client, igetterPath));
        }
    }

    static void HandleClient(TcpClient client, string igetterPath)
    {
        try
        {
            using (client)
            using (NetworkStream net = client.GetStream())
            {
                var psi = new ProcessStartInfo
                {
                    FileName = igetterPath,
                    Arguments = "chrome chrome-extension://kefncalcphllnknagnlnfcndlehpkpck/",
                    UseShellExecute = false,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                };

                using (Process proc = Process.Start(psi))
                {
                    Stream stdin = proc.StandardInput.BaseStream;
                    Stream stdout = proc.StandardOutput.BaseStream;

                    Thread t1 = new Thread(() =>
                    {
                        try
                        {
                            byte[] buf = new byte[65536];
                            int n;
                            while ((n = net.Read(buf, 0, buf.Length)) > 0)
                            {
                                stdin.Write(buf, 0, n);
                                stdin.Flush();
                            }
                            stdin.Close();
                        }
                        catch { }
                    });
                    t1.IsBackground = true;
                    t1.Start();

                    try
                    {
                        byte[] buf = new byte[65536];
                        int n;
                        while ((n = stdout.Read(buf, 0, buf.Length)) > 0)
                        {
                            net.Write(buf, 0, n);
                            net.Flush();
                        }
                    }
                    catch { }

                    try { proc.Kill(); } catch { }
                    proc.WaitForExit();
                }
            }
        }
        catch { }
    }
}
EOF

# --- Windows: Compile and install via prlctl ---
echo "[Windows] Stopping existing relay..."
winexec cmd /c "taskkill /f /im igetter-relay.exe 2>nul & exit /b 0"

echo "[Windows] Compiling relay..."
winexec powershell -Command "& 'C:\\Windows\\Microsoft.NET\\Framework\\v4.0.30319\\csc.exe' /nologo /target:winexe /out:'C:\\Users\\$WIN_USER\\AppData\\Local\\igetter-relay.exe' '\\\\Mac\\Home\\.igetter-bridge-staging\\igetter-relay.cs'"

echo "[Windows] Copying relay to Startup folder..."
winexec cmd /c "copy \"C:\\Users\\$WIN_USER\\AppData\\Local\\igetter-relay.exe\" \"C:\\Users\\$WIN_USER\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\igetter-relay.exe\" /Y"

echo "[Windows] Adding firewall rule..."
winexec powershell -Command "Remove-NetFirewallRule -DisplayName 'iGetter Relay' -ErrorAction SilentlyContinue; New-NetFirewallRule -DisplayName 'iGetter Relay' -Direction Inbound -LocalPort $RELAY_PORT -Protocol TCP -Action Allow -Profile Any | Out-Null"

# --- Cleanup ---
rm -rf "$STAGING"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Notes:"
echo "  - Restart your browser for the extension to detect the native host"
echo "  - iGetter must be running in the VM for downloads to work"
echo "  - The relay starts automatically on Windows login via Startup folder"
echo "  - Downloads save to Mac filesystem via \\\\Mac\\Home"
echo "  - VM IP is resolved at runtime via prlctl (survives DHCP/IP changes)"
echo ""
read -p "Reboot Windows VM now? [y/N] " answer < /dev/tty
if [[ "$answer" =~ ^[Yy]$ ]]; then
    winexec cmd /c "shutdown /r /t 0"
    echo "Windows is rebooting..."
fi
