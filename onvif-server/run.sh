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

echo "[onvif-server] Generating ONVIF configuration..."

# Use Node.js for JSON/YAML handling (no extra libraries needed)
node - << 'NODEJS'
const fs = require('fs');
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
    console.warn('[onvif-server] Could not parse uuids.json, regenerating UUIDs.');
  }
}

// Build onvif.yaml content manually (no js-yaml dependency needed)
let yaml = 'onvif:\n';

options.cameras.forEach((camera, index) => {
  // Assign or reuse a stable UUID per camera name
  if (!uuids[camera.name]) {
    uuids[camera.name] = crypto.randomUUID();
    console.log(`[onvif-server] Generated new UUID for "${camera.name}": ${uuids[camera.name]}`);
  }

  // Parse the full RTSP URL (e.g. rtsp://user:pass@host:port/path)
  let url;
  try {
    url = new URL(camera.rtsp_url);
  } catch (e) {
    console.error(`[onvif-server] Invalid rtsp_url for camera "${camera.name}": ${camera.rtsp_url}`);
    process.exit(1);
  }

  const rtspPath    = url.pathname || '/';
  const rtspPort    = parseInt(url.port, 10) || 554;
  // Embed credentials into hostname if present, so the onvif-server
  // constructs: rtsp://user:pass@host:port/path
  const targetHost  = (url.username && url.password)
    ? `${url.username}:${url.password}@${url.hostname}`
    : url.hostname;

  // Each camera gets three consecutive ports:
  //   server   = user-defined port (e.g. 8001)  → ONVIF HTTP (what UniFi Protect connects to)
  //   rtsp     = server port + 100  (e.g. 8101)  → RTSP passthrough port
  //   snapshot = server port + 200  (e.g. 8201)  → Snapshot HTTP port
  const serverPort   = camera.port;
  const rtspFwdPort  = camera.port + 100;
  const snapshotPort = camera.port + 200;

  // Locally-administered unicast MAC (a2:a2:a2:a2:a2:XX)
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
  yaml += `    lowQuality:\n`;
  yaml += `      rtsp: ${rtspPath}\n`;
  yaml += `      width: 640\n`;
  yaml += `      height: 360\n`;
  yaml += `      framerate: ${camera.fps}\n`;
  yaml += `      bitrate: 512\n`;
  yaml += `      quality: 1\n`;
  yaml += `    target:\n`;
  yaml += `      hostname: ${targetHost}\n`;
  yaml += `      ports:\n`;
  yaml += `        rtsp: ${rtspPort}\n`;
  yaml += `        snapshot: 80\n`;

  console.log(`[onvif-server] Camera "${camera.name}" → ONVIF port ${serverPort}, RTSP fwd port ${rtspFwdPort}`);
});

// Persist UUIDs so they survive container restarts
fs.writeFileSync(UUID_FILE, JSON.stringify(uuids, null, 2));
console.log(`[onvif-server] UUIDs saved to ${UUID_FILE}`);

// Write the final onvif.yaml
fs.writeFileSync(ONVIF_CONFIG, yaml);
console.log(`[onvif-server] Config written to ${ONVIF_CONFIG}`);
console.log(`[onvif-server] ${options.cameras.length} camera(s) configured.`);
NODEJS

echo "[onvif-server] Starting node /app/main.js ${ONVIF_CONFIG}..."
exec node /app/main.js "${ONVIF_CONFIG}"
