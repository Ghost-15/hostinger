#!/usr/bin/env python3
"""
Lit le mot de passe partagé généré par Terraform et l'envoie à l'ESP32.

Usage:
    pip install pyserial
    python3 esp32_send_password.py
    python3 esp32_send_password.py --port /dev/ttyUSB0
    python3 esp32_send_password.py --port COM3           # Windows
    python3 esp32_send_password.py --port /dev/cu.usbserial-0001  # Mac
"""

import subprocess
import sys
import time
import argparse

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("Erreur: pyserial non installé. Lance: pip install pyserial")
    sys.exit(1)

DEFAULT_BAUD = 115200

SERVICES = [
    ("WP Multisite", "wp_user",  ":8080"),
    ("WordPress",    "wp_user",  ":8081"),
    ("Node.js",      "-",        ":8082"),
    ("VPS SSH",      "admin",    ":2222"),
    ("MySQL",        "wp_user",  ":3306"),
]


def get_terraform_password() -> str:
    result = subprocess.run(
        ["terraform", "output", "-raw", "shared_password"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"Erreur terraform output: {result.stderr.strip()}")
        sys.exit(1)
    password = result.stdout.strip()
    if not password:
        print("Erreur: terraform output shared_password est vide")
        sys.exit(1)
    return password


def detect_esp32_port() -> str:
    ports = list(serial.tools.list_ports.comports())
    esp_keywords = ["CP210", "CH340", "FTDI", "USB Serial", "ESP32", "Silicon Labs"]
    for port in ports:
        if any(k.lower() in port.description.lower() for k in esp_keywords):
            print(f"ESP32 détecté sur: {port.device} ({port.description})")
            return port.device
    if ports:
        print("Ports série disponibles:")
        for p in ports:
            print(f"  {p.device} — {p.description}")
    print("\nAucun ESP32 détecté automatiquement. Spécifie le port avec --port")
    sys.exit(1)


def send_to_esp32(port: str, baud: int, password: str) -> None:
    print(f"Connexion sur {port} à {baud} baud...")
    with serial.Serial(port, baud, timeout=5) as ser:
        time.sleep(2)

        print("Attente de l'ESP32...")
        deadline = time.time() + 6
        while time.time() < deadline:
            line = ser.readline().decode("utf-8", errors="replace").strip()
            if line == "READY":
                print("ESP32 prêt.")
                break
            elif line:
                print(f"ESP32: {line}")

        # Envoi du mdp + liste des services
        # Format: PASS:<mdp>|<service>:<user>:<port>,<service>:<user>:<port>,...
        services_str = ",".join(f"{s[0]}:{s[1]}:{s[2]}" for s in SERVICES)
        payload = f"PASS:{password}|{services_str}\n"
        ser.write(payload.encode("utf-8"))
        print(f"Envoyé → mdp + {len(SERVICES)} services")

        deadline = time.time() + 5
        while time.time() < deadline:
            line = ser.readline().decode("utf-8", errors="replace").strip()
            if line:
                print(f"ESP32 ← {line}")
                if line.startswith("OK:"):
                    print("Affiché sur l'écran.")
                    return
                elif line.startswith("ERR:"):
                    print(f"Erreur ESP32: {line}")
                    sys.exit(1)

        print("Timeout: pas de confirmation de l'ESP32.")


def main():
    parser = argparse.ArgumentParser(description="Envoie le mdp partagé à l'ESP32 après terraform apply")
    parser.add_argument("--port", default=None)
    parser.add_argument("--baud", default=DEFAULT_BAUD, type=int)
    args = parser.parse_args()

    password = get_terraform_password()
    print(f"Mot de passe récupéré ({len(password)} caractères)")

    port = args.port or detect_esp32_port()
    send_to_esp32(port, args.baud, password)


if __name__ == "__main__":
    main()
