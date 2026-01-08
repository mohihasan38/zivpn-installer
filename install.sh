#!/bin/bash
set -e

echo "======================================="
echo " ZiVPN UDP Server + Dashboard Installer "
echo " Format-Preserved • zi Locked         "
echo "======================================="

# -------------------------------
# STEP 1: SYSTEM UPDATE
# -------------------------------
apt update -y && apt upgrade -y

# -------------------------------
# STEP 2: DEPENDENCIES
# -------------------------------
apt install -y curl wget python3 python3-rich jq cron

# -------------------------------
# STEP 3: INSTALL ZIVPN
# -------------------------------
cd /root || exit 1
wget -O zi.sh https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/zi.sh
chmod +x zi.sh
printf "\n" | ./zi.sh

# -------------------------------
# STEP 4: INSTALL DASHBOARD
# -------------------------------
TMP="/tmp/zivpn_dashboard.tmp"

cat << 'EOF' > "$TMP"
#!/usr/bin/env python3
import time, os, re, subprocess
from rich.console import Console
from rich.table import Table

CONFIG = "/etc/zivpn/config.json"
DB = "/etc/zivpn/pass.db"
PERMANENT = "zi"

console = Console()
os.makedirs("/etc/zivpn", exist_ok=True)
open(DB, "a").close()

def load_passwords():
    now = int(time.time())
    out = []
    with open(DB) as f:
        for line in f:
            if "|" in line:
                p, e = line.strip().split("|")
                if int(e) > now:
                    out.append(p)
    return out

def write_config(passwords):
    # zi always first, unique, preserved
    final = [PERMANENT] + [p for p in passwords if p != PERMANENT]
    array = "[" + ",".join(f"\"{p}\"" for p in final) + "]"

    with open(CONFIG) as f:
        text = f.read()

    new_text = re.sub(
        r'"config"\s*:\s*\[[^\]]*\]',
        f'"config": {array}',
        text,
        flags=re.S
    )

    with open(CONFIG, "w") as f:
        f.write(new_text)

    subprocess.run(["systemctl", "restart", "zivpn"])

while True:
    console.print("\n[bold cyan]ZiVPN UDP Dashboard[/bold cyan]")
    console.print("1) Add password")
    console.print("2) Delete password")
    console.print("3) List passwords")
    console.print("4) Clean expired")
    console.print("5) Restart ZiVPN")
    console.print("0) Exit")

    c = input("Select: ").strip()

    if c == "1":
        p = input("Password: ").strip()
        if not p or p == PERMANENT:
            console.print("[red]Invalid password[/red]")
            continue
        d = int(input("Valid days: "))
        exp = int(time.time()) + d * 86400
        with open(DB, "a") as f:
            f.write(f"{p}|{exp}\n")
        write_config(load_passwords())
        console.print("[green]Password added[/green]")

    elif c == "2":
        pw = load_passwords()
        if not pw:
            console.print("[yellow]No removable passwords[/yellow]")
            continue
        for i, p in enumerate(pw, 1):
            print(f"{i}) {p}")
        n = int(input("Delete number: "))
        pw.pop(n - 1)
        with open(DB, "w") as f:
            for p in pw:
                f.write(f"{p}|9999999999\n")
        write_config(pw)
        console.print("[red]Password deleted[/red]")

    elif c == "3":
        table = Table(title="Active Passwords")
        table.add_column("Password")
        table.add_row(PERMANENT)
        for p in load_passwords():
            table.add_row(p)
        console.print(table)

    elif c == "4":
        write_config(load_passwords())
        console.print("[yellow]Expired cleaned[/yellow]")

    elif c == "5":
        subprocess.run(["systemctl", "restart", "zivpn"])

    elif c == "0":
        break
EOF

chmod +x "$TMP"
mv "$TMP" /usr/local/bin/zivpn

# -------------------------------
# STEP 5: CRON
# -------------------------------
(crontab -l 2>/dev/null; \
 echo "*/5 * * * * /usr/bin/python3 /usr/local/bin/zivpn <<< 4 >/dev/null 2>&1") | crontab -

echo "======================================="
echo " INSTALLATION COMPLETED SUCCESSFULLY "
echo "======================================="
echo "Dashboard command : zivpn"
echo "Permanent password: zi"
echo "======================================="
