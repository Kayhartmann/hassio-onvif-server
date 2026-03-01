#!/usr/bin/env bash
set -e

OPTIONS_FILE="/data/options.json"
UUID_FILE="/data/uuids.json"
ONVIF_CONFIG="/data/onvif.yaml"

echo "[onvif-server] Reading options from ${OPTIONS_FILE}..."
if [ ! -f "${OPTIONS_FILE}" ]; then
  echo "[onvif-server] ERROR: ${OPTIONS_FILE} not found. Is the add-on running inside Home Assistant?"
  exit 1
fi

# ─── Step 1: Detect primary network interface ────────────────────────────────
IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "${IFACE}" ]; then
  echo "[onvif-server] ERROR: Could not detect primary network interface."
  exit 1
fi
echo "[onvif-server] Primary network interface: ${IFACE}"

# ─── Step 2: Read host IP and derive /24 subnet prefix ──────────────────────
HOST_IP=$(ip addr show "${IFACE}" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
if [ -z "${HOST_IP}" ]; then
  echo "[onvif-server] ERROR: Could not determine host IP on ${IFACE}."
  exit 1
fi
SUBNET=$(echo "${HOST_IP}" | cut -d. -f1,2,3)
echo "[onvif-server] Host IP: ${HOST_IP}  →  Subnet prefix: ${SUBNET}.0/24"

# ─── Step 3: Read camera count ───────────────────────────────────────────────
CAMERA_COUNT=$(node -e "
const o = JSON.parse(require('fs').readFileSync('/data/options.json', 'utf8'));
process.stdout.write(String(o.cameras.length));
")
echo "[onvif-server] Cameras configured: ${CAMERA_COUNT}"

# ─── Step 4: Create MacVLAN interfaces and assign IPs via DHCP ───────────────
for i in $(seq 1 "${CAMERA_COUNT}"); do
  IDX=$(printf "%02d" "${i}")
  MAC="a2:a2:a2:a2:a2:${IDX}"
  VLAN="onvif-cam-${i}"

  # Remove stale interface from a previous (crashed) run
  if ip link show "${VLAN}" > /dev/null 2>&1; then
    echo "[onvif-server] Removing stale interface ${VLAN}..."
    ip link delete "${VLAN}" 2>/dev/null || true
  fi

  ip link add "${VLAN}" link "${IFACE}" address "${MAC}" type macvlan mode bridge
  ip link set "${VLAN}" up

  echo "[onvif-server] ${VLAN}  MAC=${MAC} — requesting DHCP lease..."
  if udhcpc -i "${VLAN}" -s /usr/bin/udhcpc-onvif-script -n -q -t 10 -T 3 2>/dev/null; then
    ASSIGNED=$(ip addr show "${VLAN}" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
    echo "[onvif-server] ${VLAN}  MAC=${MAC}  IP=${ASSIGNED}"
  else
    echo "[onvif-server] WARNING: DHCP failed for ${VLAN} (MAC=${MAC}) – camera may be unreachable"
  fi
done

# foscam – hardcoded 4th virtual camera (640×480, go2rtc path /foscam)
if ip link show "onvif-cam-4" > /dev/null 2>&1; then
  echo "[onvif-server] Removing stale interface onvif-cam-4..."
  ip link delete "onvif-cam-4" 2>/dev/null || true
fi
ip link add "onvif-cam-4" link "${IFACE}" address "a2:a2:a2:a2:a2:04" type macvlan mode bridge
ip link set "onvif-cam-4" up
echo "[onvif-server] onvif-cam-4  MAC=a2:a2:a2:a2:a2:04 — requesting DHCP lease..."
if udhcpc -i "onvif-cam-4" -s /usr/bin/udhcpc-onvif-script -n -q -t 10 -T 3 2>/dev/null; then
  FOSCAM_IP=$(ip addr show "onvif-cam-4" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
  echo "[onvif-server] onvif-cam-4  MAC=a2:a2:a2:a2:a2:04  IP=${FOSCAM_IP}"
else
  echo "[onvif-server] WARNING: DHCP failed for onvif-cam-4 (foscam) – camera may be unreachable"
fi

# ─── Step 6: Generate /data/onvif.yaml ──────────────────────────────────────
echo "[onvif-server] Generating ONVIF configuration..."

node - << 'NODEJS'
const fs     = require('fs');
const crypto = require('crypto');

const OPTIONS_FILE = '/data/options.json';
const UUID_FILE    = '/data/uuids.json';
const ONVIF_CONFIG = '/data/onvif.yaml';

// Read Home Assistant add-on options
const options = JSON.parse(fs.readFileSync(OPTIONS_FILE, 'utf8'));

// Load persisted UUIDs or start fresh
let uuids = {};
if (fs.existsSync(UUID_FILE)) {
  try {
    uuids = JSON.parse(fs.readFileSync(UUID_FILE, 'utf8'));
  } catch (e) {
    console.warn('[onvif-server] Could not parse uuids.json – regenerating UUIDs.');
  }
}

// Build onvif.yaml manually (no external library required).
// The onvif-server resolves the IP for each entry by looking up the MAC
// address on the host's network interfaces – so the MAC must match the
// MacVLAN interface we created in the shell section above.
let yaml = 'onvif:\n';

options.cameras.forEach((camera, index) => {
  // Assign or reuse a stable UUID per camera name
  if (!uuids[camera.name]) {
    uuids[camera.name] = crypto.randomUUID();
    console.log(`[onvif-server] Generated UUID for "${camera.name}": ${uuids[camera.name]}`);
  }

  // Parse the full RTSP URL (rtsp://user:pass@host:port/path)
  let url;
  try {
    url = new URL(camera.rtsp_url);
  } catch (e) {
    console.error(`[onvif-server] Invalid rtsp_url for "${camera.name}": ${camera.rtsp_url}`);
    process.exit(1);
  }

  const rtspPath   = url.pathname || '/';
  const rtspPort   = parseInt(url.port, 10) || 554;
  // target.hostname must be a plain IP/hostname – no credentials.
  // The tcp proxy forwards raw TCP; RTSP auth is handled by UniFi Protect
  // in the RTSP handshake, not by the proxy itself.
  const targetHost = url.hostname;

  // Port layout per camera (no overlap with Neolink:8554 or go2rtc:8555/8556):
  //   server   = camera.port        (e.g. 8001) → ONVIF HTTP (UniFi Protect connects here)
  //   rtsp     = camera.port + 100  (e.g. 8101) → RTSP passthrough
  //   snapshot = camera.port + 200  (e.g. 8201) → Snapshot HTTP
  const serverPort   = camera.port;
  const rtspFwdPort  = camera.port + 100;
  const snapshotPort = camera.port + 200;

  // MAC must match the MacVLAN interface created above
  const macSuffix = String(index + 1).padStart(2, '0');
  const mac = `a2:a2:a2:a2:a2:${macSuffix}`;

  yaml += `  - mac: ${mac}\n`;
  yaml += `    ports:\n`;
  yaml += `      server: ${serverPort}\n`;
  yaml += `      rtsp: ${rtspFwdPort}\n`;
  yaml += `      snapshot: ${snapshotPort}\n`;
  yaml += `    name: ${camera.name}\n`;
  yaml += `    uuid: ${uuids[camera.name]}\n`;
  yaml += `    highQuality:\n`;
  yaml += `      rtsp: ${rtspPath}\n`;
  yaml += `      width: ${camera.width}\n`;
  yaml += `      height: ${camera.height}\n`;
  yaml += `      framerate: ${camera.fps}\n`;
  yaml += `      bitrate: ${camera.bitrate}\n`;
  yaml += `      quality: 4\n`;
  // lowQuality mirrors highQuality – go2rtc exposes a single stream per path
  yaml += `    lowQuality:\n`;
  yaml += `      rtsp: ${rtspPath}\n`;
  yaml += `      width: ${camera.width}\n`;
  yaml += `      height: ${camera.height}\n`;
  yaml += `      framerate: ${camera.fps}\n`;
  yaml += `      bitrate: ${camera.bitrate}\n`;
  yaml += `      quality: 1\n`;
  yaml += `    target:\n`;
  yaml += `      hostname: ${targetHost}\n`;
  yaml += `      ports:\n`;
  yaml += `        rtsp: ${rtspPort}\n`;
  yaml += `        snapshot: 80\n`;

  console.log(`[onvif-server] Camera "${camera.name}": ONVIF=${serverPort}, RTSP fwd=${rtspFwdPort}, MAC=${mac}`);
});

// foscam – hardcoded 4th camera (640x480, go2rtc path /foscam)
if (!uuids['foscam']) {
  uuids['foscam'] = crypto.randomUUID();
  console.log(`[onvif-server] Generated UUID for "foscam": ${uuids['foscam']}`);
}
yaml += `  - mac: a2:a2:a2:a2:a2:04\n`;
yaml += `    ports:\n`;
yaml += `      server: 8004\n`;
yaml += `      rtsp: 8104\n`;
yaml += `      snapshot: 8204\n`;
yaml += `    name: foscam\n`;
yaml += `    uuid: ${uuids['foscam']}\n`;
yaml += `    highQuality:\n`;
yaml += `      rtsp: /foscam\n`;
yaml += `      width: 640\n`;
yaml += `      height: 480\n`;
yaml += `      framerate: 15\n`;
yaml += `      bitrate: 512\n`;
yaml += `      quality: 4\n`;
yaml += `    lowQuality:\n`;
yaml += `      rtsp: /foscam\n`;
yaml += `      width: 640\n`;
yaml += `      height: 480\n`;
yaml += `      framerate: 15\n`;
yaml += `      bitrate: 512\n`;
yaml += `      quality: 1\n`;
yaml += `    target:\n`;
yaml += `      hostname: 10.10.9.33\n`;
yaml += `      ports:\n`;
yaml += `        rtsp: 8556\n`;
yaml += `        snapshot: 80\n`;
console.log(`[onvif-server] Camera "foscam": ONVIF=8004, RTSP fwd=8104, MAC=a2:a2:a2:a2:a2:04`);

// Persist UUIDs across container restarts
fs.writeFileSync(UUID_FILE, JSON.stringify(uuids, null, 2));
console.log(`[onvif-server] UUIDs saved to ${UUID_FILE}`);

// Write the final config
fs.writeFileSync(ONVIF_CONFIG, yaml);
console.log(`[onvif-server] Config written to ${ONVIF_CONFIG} (${options.cameras.length + 1} camera(s))`);
NODEJS

# ─── Step 6b: Write runtime state for dashboard ──────────────────────────────
echo "[onvif-server] Writing dashboard state..."
export HOST_IP SUBNET
node - << 'STATEJS'
const fs  = require('fs');
const os  = require('os');
const opts = JSON.parse(fs.readFileSync('/data/options.json', 'utf8'));
const hostIp = process.env.HOST_IP;
const subnet  = process.env.SUBNET;

// Look up the IP assigned to a MacVLAN interface by its MAC address.
// This works regardless of DHCP or static assignment.
function getIpByMac(mac) {
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const iface of (ifaces[name] || [])) {
      if (iface.family === 'IPv4' &&
          iface.mac  &&
          iface.mac.toLowerCase() === mac.toLowerCase()) {
        return iface.address;
      }
    }
  }
  return null;
}

const username = opts.username || 'admin';
const password = opts.password || 'admin';

const cameras = (opts.cameras || []).map((cam, i) => {
  const idx = String(i + 1).padStart(2, '0');
  const mac = `a2:a2:a2:a2:a2:${idx}`;
  return {
    name:          cam.name,
    mac,
    ip:            getIpByMac(mac),
    onvif_port:    cam.port,
    rtsp_port:     cam.port + 100,
    snapshot_port: cam.port + 200,
    rtsp_url:      cam.rtsp_url,
    width:         cam.width,
    height:        cam.height,
    fps:           cam.fps,
    bitrate:       cam.bitrate,
  };
});

// foscam (hardcoded 4th camera)
const foscamMac = 'a2:a2:a2:a2:a2:04';
cameras.push({
  name:          'foscam',
  mac:           foscamMac,
  ip:            getIpByMac(foscamMac),
  onvif_port:    8004,
  rtsp_port:     8104,
  snapshot_port: 8204,
  rtsp_url:      'rtsp://' + hostIp + ':8556/foscam',
  width:         640,
  height:        480,
  fps:           15,
  bitrate:       512,
});

const state = { host_ip: hostIp, subnet, username, password, cameras };
fs.writeFileSync('/tmp/onvif-state.json', JSON.stringify(state, null, 2));
console.log(`[onvif-server] Dashboard state written to /tmp/onvif-state.json (${cameras.length} camera(s))`);
STATEJS

# ─── Step 7: Start dashboard in background ───────────────────────────────────
echo "[onvif-server] Starting dashboard on port 8099..."
node /dashboard/server.js &

# ─── Step 8: Start the ONVIF server (main process) ───────────────────────────
echo "[onvif-server] Starting node /app/main.js ${ONVIF_CONFIG}..."
exec node /app/main.js "${ONVIF_CONFIG}"
