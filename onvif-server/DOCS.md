# ONVIF Server – Home Assistant Add-on

Erstellt virtuelle ONVIF-Kameras aus bestehenden RTSP-Streams (z. B. von go2rtc/Neolink), sodass diese in **UniFi Protect** als native ONVIF-Kameras eingebunden werden können.

Basiert auf [daniela-hase/onvif-server](https://github.com/daniela-hase/onvif-server).

---

## Installation

1. In Home Assistant: **Einstellungen → Add-ons → Add-on Store → ⋮ → Repositories verwalten**
2. URL eintragen: `https://github.com/Kayhartmann/hassio-onvif-server`
3. Repo speichern → **ONVIF Server** erscheint im Store → Installieren

---

## Konfiguration

```yaml
username: "admin"
password: "admin"
cameras:
  - name: "Garten"
    rtsp_url: "rtsp://user:pass@10.10.9.33:8556/Garten"
    port: 8001
    width: 1920
    height: 1080
    fps: 15
    bitrate: 2048
  - name: "Eingang"
    rtsp_url: "rtsp://user:pass@10.10.9.33:8556/Eingang"
    port: 8002
    width: 1920
    height: 1080
    fps: 15
    bitrate: 2048
```

| Feld       | Beschreibung                                              |
|------------|-----------------------------------------------------------|
| `username` | Benutzername für UniFi Protect (Standard: `admin`)       |
| `password` | Passwort für UniFi Protect (Standard: `admin`)           |
| `name`     | Anzeigename der Kamera in UniFi Protect                  |
| `rtsp_url` | Vollständige RTSP-URL inkl. Credentials und Pfad         |
| `port`     | ONVIF HTTP-Port (jede Kamera braucht einen eigenen Port) |
| `width`    | Videobreite in Pixeln                                     |
| `height`   | Videohöhe in Pixeln                                       |
| `fps`      | Frames pro Sekunde                                        |
| `bitrate`  | Bitrate in kbit/s                                         |

### Port-Schema

Pro Kamera werden automatisch **3 Ports** verwendet:

| Zweck              | Port-Berechnung      | Beispiel (port: 8001) |
|--------------------|----------------------|-----------------------|
| ONVIF HTTP         | `port`               | 8001                  |
| RTSP Passthrough   | `port + 100`         | 8101                  |
| Snapshot HTTP      | `port + 200`         | 8201                  |

> **Hinweis:** Ports 8554 (Neolink) und 8555/8556 (go2rtc) sind belegt – ONVIF-Ports ab 8001 verwenden.

---

## Netzwerk

Das Add-on erstellt beim Start für jede Kamera ein virtuelles **MacVLAN-Netzwerkinterface** und bezieht per **DHCP** automatisch eine IP-Adresse vom Router.

| Kamera (Reihenfolge) | MAC                   | IP-Vergabe |
|----------------------|-----------------------|------------|
| 1. Kamera            | `a2:a2:a2:a2:a2:01`  | DHCP       |
| 2. Kamera            | `a2:a2:a2:a2:a2:02`  | DHCP       |
| 3. Kamera            | `a2:a2:a2:a2:a2:03`  | DHCP       |

Die vergebenen IPs sind im **Dashboard** des Add-ons sichtbar (Seitenleiste → ONVIF Server).

> **Empfehlung:** Im Router für die MAC-Adressen oben eine **DHCP-Reservierung** einrichten, damit die IPs stabil bleiben.
> - **Fritzbox:** Heimnetz → Netzwerk → IP-Adressen → DHCP-Reservierungen
> - **UniFi/UDM:** Networks → LAN → DHCP → Static Leases
> - **OpenWRT:** Network → DHCP & DNS → Static Leases

Das Add-on läuft mit `host_network: true`, was für **WS-Discovery** (UDP Multicast Port 3702) erforderlich ist.

---

## Einbindung in UniFi Protect

Das Dashboard des Add-ons (Seitenleiste → ONVIF Server) zeigt pro Kamera die vollständige **ONVIF-URL** sowie die Zugangsdaten für UniFi Protect.

1. UniFi Protect → **Kameras → Kamera hinzufügen → ONVIF-Gerät**
2. IP-Adresse der Kamera eintragen (aus dem Dashboard, z. B. `10.10.9.52`)
3. Port: den konfigurierten `port` der gewünschten Kamera (z. B. `8001`)
4. Benutzername und Passwort: wie in der Konfiguration gesetzt (Standard: `admin` / `admin`)

Alternativ erkennt UniFi Protect die Kameras automatisch über **WS-Discovery** beim Netzwerk-Scan.

---

## Persistenz

UUIDs werden beim ersten Start generiert und in `/data/uuids.json` gespeichert. Dadurch bleiben die virtuellen Geräte-IDs bei Neustart des Add-ons stabil – UniFi Protect erkennt die Kameras als bekannte Geräte wieder.

---

## Dashboard

Das integrierte Web-Dashboard zeigt:
- Status des ONVIF-Servers (Online/Offline)
- Pro Kamera: MacVLAN-IP, ONVIF-URL, RTSP-URL, Snapshot-URL (mit Copy-Button)
- Zugangsdaten für UniFi Protect
- Auflösung, FPS, Bitrate

---

## Logs

Logs sind in Home Assistant unter **Einstellungen → Add-ons → ONVIF Server → Log** einsehbar.
