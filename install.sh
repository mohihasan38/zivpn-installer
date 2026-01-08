#!/bin/bash
set -e

echo "======================================="
echo " ZiVPN UDP Server + Dashboard Installer "
echo " Fully Automatic (No Manual Input)     "
echo "======================================="

# -------------------------------
# STEP 1: SYSTEM UPDATE
# -------------------------------
echo "[1/6] Updating system..."
apt update -y && apt upgrade -y

# -------------------------------
# STEP 2: DEPENDENCIES (DEBIAN SAFE)
# -------------------------------
echo "[2/6] Installing dependencies..."
apt install -y \
  curl \
  wget \
  python3 \
  python3-pip \
  python3-rich \
  jq \
  cron

# -------------------------------
# STEP 3: INSTALL ZIVPN UDP SERVER
# AUTO-ENTER FOR PASSWORD PROMPT
# -------------------------------
echo "[3/6] Installing ZiVPN UDP server..."

cd /root || exit 1

wget -O zi.sh https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/zi.sh
chmod +x zi.sh

echo "Auto-confirming ZiVPN password prompt (default: zi)..."

# Auto press ENTER
printf "\n" | ./zi.sh

# -------------------------------
# STEP 4: INSTALL DASHBOARD (SAFE)
# -------------------------------
echo "[4/6] Installing ZiVPN dashboard..."

TMP_DASH="/tmp/zivpn_dashboard.tmp"

cat << 'EOF' > "$TMP_DASH"
#!/usr/bin/env python3
import json, time, os, subprocess
from rich.console import Console
from rich.table import Table

CONFIG = "/etc/zivpn/config.json"
DB = "/etc/zivpn/pass.db"

console = Console()
os.makedirs("/etc/zivpn", exist_ok=True)
open(DB, "a").close()

def load_db():
    now = int(time.time())
    data = []
    with open(DB) as f:
        for line in f:
            if "|" in line:
                p, e = line.strip().split("|")
                if int(e) > now:
                    data.append((p, int(e)))
    return data

def save_db(data):
    with open(DB, "w") as f:
        for p, e in data:
            f.write(f"{p}|{e}\n")

def sync():
    passwords = [p for p, _ in load_db()]
    tmp = "/tmp/zivpn.json"
    subprocess.run(
        ["jq", f'.password={json.dumps(passwords)}', CONFIG],
        stdout=open(tmp, "w"),
        check=True
    )
    os.replace(tmp, CONFIG)
    subprocess.run(["systemctl", "restart", "zivpn"])

while True:
    console.print("\n[bold cyan]ZiVPN UDP Dashboard[/bold cyan]")
    console.print("1) Add password")
    console.print("2) Delete password")
    console.print("3) List passwords")
    console.print("4) Clean expired")
    console.print("5) Restart ZiVPN")
    console.print("0) Exit")

    choice = input("Select: ").strip()

    if choice == "1":
        p = input("Password: ").strip()
        d = int(input("Valid days: "))
        exp = int(time.time()) + d * 86400
        data = load_db()
        data.append((p, exp))
        save_db(data)
        sync()
        console.print("[green]Password added[/green]")

    elif choice == "2":
        data = load_db()
        for i, (p, e) in enumerate(data, 1):
            print(f"{i}) {p} expires {time.strftime('%Y-%m-%d', time.localtime(e))}")
        n = int(input("Delete number: "))
        if 1 <= n <= len(data):
            data.pop(n - 1)
            save_db(data)
            sync()
            console.print("[red]Password deleted[/red]")

    elif choice == "3":
        table = Table(title="Active Passwords")
        table.add_column("No")
        table.add_column("Password")
        table.add_column("Expires")
        for i, (p, e) in enumerate(load_db(), 1):
            table.add_row(str(i), p, time.strftime("%Y-%m-%d", time.localtime(e)))
        console.print(table)

    elif choice == "4":
        save_db(load_db())
        sync()
        console.print("[yellow]Expired passwords cleaned[/yellow]")

    elif choice == "5":
        subprocess.run(["systemctl", "restart", "zivpn"])
        console.print("[cyan]ZiVPN restarted[/cyan]")

    elif choice == "0":
        break
EOF

chmod +x "$TMP_DASH"
mv "$TMP_DASH" /usr/local/bin/zivpn

# -------------------------------
# STEP 5: AUTO CLEAN CRON
# -------------------------------
echo "[5/6] Setting up auto-clean cron..."

(crontab -l 2>/dev/null; \
 echo "*/5 * * * * /usr/bin/python3 /usr/local/bin/zivpn <<< 4 >/dev/null 2>&1") | crontab -

# -------------------------------
# DONE
# -------------------------------
echo "======================================="
echo " INSTALLATION COMPLETED SUCCESSFULLY "
echo "======================================="
echo "Command to open dashboard:  zivpn"
echo "Default UDP password: zi"
echo "======================================="
