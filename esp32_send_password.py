#!/usr/bin/env python3
"""
Lit le mot de passe partagé généré par Terraform et l'envoie à l'ESP32-S3 via HTTP.

L'ESP32 doit être sur le même réseau Wi-Fi. Son IP est affichée sur l'écran OLED
au démarrage.

Usage:
    python3 esp32_send_password.py --ip 192.168.1.42
    python3 esp32_send_password.py --ip 192.168.1.42 --port 80
"""

import subprocess
import sys
import argparse
import time
import urllib.request
import urllib.parse
import urllib.error

SERVICES = [
    ("WP Multisite", "wp_user", "8080"),
    ("WordPress",    "wp_user", "8081"),
    ("Node.js",      "",        "8082"),
    ("VPS SSH",      "admin",   "2222"),
    ("MySQL",        "wp_user", "3306"),
]


def get_terraform_password() -> str:
    result = subprocess.run(
        ["terraform", "output", "-raw", "shared_password"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"Erreur terraform output:\n{result.stderr.strip()}")
        sys.exit(1)
    password = result.stdout.strip()
    if not password:
        print("Erreur: terraform output shared_password est vide")
        sys.exit(1)
    return password


def send_to_esp32(ip: str, port: int, password: str, retries: int = 5, retry_delay: float = 2.0, request_timeout: float = 5.0) -> None:
    services_str = ",".join(f"{s[0]}:{s[1]}:{s[2]}" for s in SERVICES)
    url = f"http://{ip}:{port}/password"

    data = urllib.parse.urlencode({
        "password": password,
        "services": services_str,
    }).encode("utf-8")

    print(f"Envoi vers {url} ...")
    req = urllib.request.Request(url, data=data, method="POST")

    last_error = None
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=request_timeout) as resp:
                body = resp.read().decode("utf-8").strip()
                if body == "OK":
                    print("Mot de passe affiché sur l'écran de l'ESP32.")
                    return

                print(f"Réponse inattendue : {body}")
                sys.exit(1)
        except urllib.error.URLError as e:
            last_error = e
            reason = getattr(e, "reason", e)
            print(f"Tentative {attempt}/{retries} échouée : {reason}")
            if attempt < retries:
                time.sleep(retry_delay)

    print(f"Erreur de connexion vers l'ESP32 ({ip}:{port}) : {getattr(last_error, 'reason', last_error)}")
    print("Vérifie que l'ESP32 est bien connecté au Wi-Fi, que l'IP est correcte, et que le serveur HTTP a bien démarré.")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Envoie le mdp Terraform à l'ESP32-S3 via HTTP")
    parser.add_argument("--ip",   required=True, help="IP de l'ESP32 (affichée sur l'écran OLED au démarrage)")
    parser.add_argument("--port", default=80, type=int, help="Port HTTP de l'ESP32 (défaut : 80)")
    parser.add_argument("--retries", default=5, type=int, help="Nombre de tentatives d'envoi HTTP")
    parser.add_argument("--retry-delay", default=2.0, type=float, help="Délai entre les tentatives, en secondes")
    parser.add_argument("--timeout", default=5.0, type=float, help="Timeout par tentative, en secondes")
    args = parser.parse_args()

    password = get_terraform_password()
    print(f"Mot de passe récupéré ({len(password)} caractères)")
    send_to_esp32(args.ip, args.port, password, retries=args.retries, retry_delay=args.retry_delay, request_timeout=args.timeout)


if __name__ == "__main__":
    main()
