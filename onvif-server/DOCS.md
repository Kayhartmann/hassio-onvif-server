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

Die Kameras werden unter **Konfiguration** des Add-ons eingetragen:

```yaml
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

> **Hinweis:** Ports 8554 (Neolink) und 8555 (go2rtc WebRTC) sind belegt – ONVIF-Ports ab 8001 verwenden.

---

## Netzwerk-Vorbereitung (wichtig!)

### Statische IPs für virtuelle Kamera-Interfaces

Das Add-on erstellt beim Start für jede Kamera ein virtuelles MacVLAN-Netzwerkinterface und weist ihm eine **statische IP-Adresse** zu:

| Kamera (Reihenfolge) | MAC               | Statische IP     |
|----------------------|-------------------|------------------|
| 1. Kamera            | `a2:a2:a2:a2:a2:01` | `<Subnet>.241` |
| 2. Kamera            | `a2:a2:a2:a2:a2:02` | `<Subnet>.242` |
| 3. Kamera            | `a2:a2:a2:a2:a2:03` | `<Subnet>.243` |

`<Subnet>` wird automatisch aus der IP deines Home-Assistant-Hosts abgeleitet.
Beispiel: Host-IP `10.10.9.33` → Kamera-IPs `10.10.9.241`, `10.10.9.242`, `10.10.9.243`

> **Pflichtschritt im Router:** Schließe die Adressen `.241`, `.242` und `.243` aus dem DHCP-Pool deines Routers aus, damit kein anderes Gerät im Netzwerk diese IPs zugewiesen bekommt und es zu IP-Konflikten kommt.
>
> - **Fritzbox:** Heimnetz → Netzwerk → IPv4-Adressen → DHCP-Einstellungen → „Von … bis …" so begrenzen, dass .241–.243 außerhalb liegen (z. B. Pool bis .240).
> - **UniFi/UDM:** Networks → LAN → DHCP Range → End auf z. B. `…240` setzen.
> - **OpenWRT:** Network → Interfaces → DHCP-Server → Limit auf z. B. 240 Adressen setzen.

### Warum kein DHCP?

MacVLAN-Interfaces im Bridge-Mode können den DHCP-Server des Hosts nicht erreichen (bekannte Linux-Netzwerkeinschränkung). Statische IPs umgehen dieses Problem zuverlässig.

---

## Netzwerk-Anforderungen

Das Add-on läuft mit `host_network: true`, was für **WS-Discovery** (UDP Multicast Port 3702) zwingend erforderlich ist. UniFi Protect kann die virtuellen Kameras damit automatisch per Netzwerk-Scan finden.

---

## Einbindung in UniFi Protect

1. UniFi Protect → **Kameras → Kamera hinzufügen → ONVIF-Gerät**
2. IP-Adresse des Home-Assistant-Hosts eingeben
3. Port: den konfigurierten `port` der gewünschten Kamera (z. B. `8001`)
4. Kein Benutzername/Passwort erforderlich (virtuelles Gerät ohne Auth)

Alternativ erkennt UniFi Protect die Kameras automatisch über WS-Discovery.

---

## Persistenz

UUIDs werden beim ersten Start generiert und in `/data/uuids.json` gespeichert. Dadurch bleiben die virtuellen Geräte-IDs bei Neustart des Add-ons stabil – UniFi Protect erkennt die Kameras als bekannte Geräte wieder.

---

## Logs

Logs sind in Home Assistant unter **Einstellungen → Add-ons → ONVIF Server → Log** einsehbar.
