# ONVIF Server – Home Assistant Add-on

[![Version](https://img.shields.io/badge/version-1.0.6-blue)](https://github.com/Kayhartmann/hassio-onvif-server/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Erstellt virtuelle ONVIF-Kameras aus bestehenden RTSP-Streams (z. B. von go2rtc oder Neolink), sodass diese in **UniFi Protect** als native ONVIF-Kameras eingebunden werden können.

Basiert auf [daniela-hase/onvif-server](https://github.com/daniela-hase/onvif-server).

---

## Features

- Wandelt beliebige RTSP-Streams in virtuelle ONVIF-Geräte um
- Automatische DHCP-IP-Vergabe für jede virtuelle Kamera (MacVLAN)
- WS-Discovery: UniFi Protect erkennt Kameras automatisch per Netzwerk-Scan
- Web-Dashboard mit Kamerastatus, ONVIF-URLs und Copy-Buttons
- Stabile UUIDs für zuverlässige Wiedererkennung in UniFi Protect
- Multi-Arch: `amd64`, `aarch64`, `armv7`

---

## Installation

1. Home Assistant → **Einstellungen → Add-ons → Add-on Store → ⋮ → Repositories verwalten**
2. URL eintragen:
   ```
   https://github.com/Kayhartmann/hassio-onvif-server
   ```
3. Speichern → **ONVIF Server** erscheint im Store → **Installieren**

---

## Konfiguration

```yaml
username: "admin"
password: "admin"
cameras:
  - name: "Garten"
    rtsp_url: "rtsp://user:pass@192.168.1.50:8556/Garten"
    port: 8001
    width: 1920
    height: 1080
    fps: 15
    bitrate: 2048
  - name: "Eingang"
    rtsp_url: "rtsp://user:pass@192.168.1.50:8556/Eingang"
    port: 8002
    width: 1920
    height: 1080
    fps: 15
    bitrate: 2048
```

| Feld       | Beschreibung                                              | Standard |
|------------|-----------------------------------------------------------|----------|
| `username` | Benutzername für UniFi Protect                           | `admin`  |
| `password` | Passwort für UniFi Protect                               | `admin`  |
| `name`     | Anzeigename der Kamera                                   | –        |
| `rtsp_url` | Vollständige RTSP-URL inkl. Credentials                  | –        |
| `port`     | ONVIF HTTP-Port (pro Kamera eindeutig)                   | –        |
| `width`    | Auflösung Breite (px)                                    | –        |
| `height`   | Auflösung Höhe (px)                                      | –        |
| `fps`      | Frames pro Sekunde                                       | –        |
| `bitrate`  | Bitrate (kbit/s)                                         | –        |

---

## Netzwerk

Das Add-on erstellt pro Kamera ein **MacVLAN-Interface** und bezieht per **DHCP** automatisch eine IP vom Router.

> **Tipp:** Im Router für die MAC-Adressen `a2:a2:a2:a2:a2:01`, `a2:a2:a2:a2:a2:02` usw. **DHCP-Reservierungen** einrichten – so bleiben die IPs stabil.

Das Web-Dashboard (Seitenleiste → ONVIF Server) zeigt die aktuell vergebenen IPs.

---

## Einbindung in UniFi Protect

1. UniFi Protect → **Kameras → Kamera hinzufügen → ONVIF-Gerät**
2. IP-Adresse aus dem Dashboard eintragen (z. B. `10.10.9.52`)
3. Port: konfigurierten `port` der Kamera (z. B. `8001`)
4. Benutzername / Passwort: wie in der Konfiguration gesetzt (Standard: `admin` / `admin`)

Alternativ erkennt UniFi Protect die Kameras automatisch per **WS-Discovery**.

---

## Dashboard

Das integrierte Web-Dashboard (HA-Seitenleiste) zeigt:

- **ONVIF-Server-Status** (Online/Offline)
- Pro Kamera: MacVLAN-IP, ONVIF-URL, RTSP-URL, Snapshot-URL mit **Copy-Button**
- **Zugangsdaten** für UniFi Protect
- Auflösung, FPS, Bitrate

---

## Port-Schema

Pro Kamera werden 3 Ports verwendet (ab dem konfigurierten `port`):

| Zweck            | Berechnung     | Beispiel (`port: 8001`) |
|------------------|----------------|--------------------------|
| ONVIF HTTP       | `port`         | `8001`                   |
| RTSP Passthrough | `port + 100`   | `8101`                   |
| Snapshot HTTP    | `port + 200`   | `8201`                   |

---

## Verwandte Projekte

- [Reolink UniFi Bridge](https://github.com/Kayhartmann/onif) – Vollständiges Add-on für Reolink-Kameras inkl. Neolink, go2rtc und ONVIF
