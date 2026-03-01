'use strict';

const express = require('express');
const net = require('net');
const fs = require('fs');
const path = require('path');

const PORT = process.env.DASHBOARD_PORT || '8098';
const OPTIONS_FILE = '/data/options.json';
const STATE_FILE = '/tmp/onvif-state.json';

const app = express();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * TCP reachability check.
 * @param {string} host
 * @param {number} port
 * @param {number} [timeoutMs=2000]
 * @returns {Promise<boolean>}
 */
function checkPort(host, port, timeoutMs = 2000) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    let settled = false;

    const done = (result) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(result);
    };

    socket.setTimeout(timeoutMs);
    socket.once('connect', () => done(true));
    socket.once('timeout', () => done(false));
    socket.once('error', () => done(false));
    socket.connect(port, host);
  });
}

/**
 * Read and parse a JSON file. Returns null on any error.
 * @param {string} filePath
 * @returns {object|null}
 */
function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (_) {
    return null;
  }
}

/**
 * Mask the password in an RTSP URL.
 * e.g. rtsp://admin:secret@host:port/path → rtsp://admin:***@host:port/path
 * Falls back to returning the original string if parsing fails.
 * @param {string} rtspUrl
 * @returns {string}
 */
function maskRtspPassword(rtspUrl) {
  try {
    const u = new URL(rtspUrl);
    if (u.password) {
      u.password = '***';
    }
    // URL encodes '***' as '%2A%2A%2A' – restore it for readability
    return u.toString().replace('%2A%2A%2A', '***');
  } catch (_) {
    return rtspUrl;
  }
}

// ---------------------------------------------------------------------------
// Ingress path middleware
// Strips the HA ingress prefix from the request path so that static files
// and API routes work regardless of the ingress base path.
// ---------------------------------------------------------------------------
app.use((req, _res, next) => {
  const ingressPath = req.headers['x-ingress-path'];
  if (ingressPath && req.url.startsWith(ingressPath)) {
    req.url = req.url.slice(ingressPath.length) || '/';
  }
  next();
});

// ---------------------------------------------------------------------------
// Static files
// ---------------------------------------------------------------------------
app.use(express.static(path.join(__dirname, 'public')));

// ---------------------------------------------------------------------------
// GET /api/status
// ---------------------------------------------------------------------------
app.get('/api/status', async (req, res) => {
  let onvifRunning = false;

  const state = readJson(STATE_FILE);
  if (state && Array.isArray(state.cameras) && state.cameras.length > 0) {
    const first = state.cameras[0];
    if (first.ip && first.onvif_port) {
      onvifRunning = await checkPort(first.ip, first.onvif_port);
    }
  }

  res.json({
    services: {
      onvif: { running: onvifRunning },
    },
    timestamp: new Date().toISOString(),
  });
});

// ---------------------------------------------------------------------------
// GET /api/cameras
// ---------------------------------------------------------------------------
app.get('/api/cameras', async (req, res) => {
  const state = readJson(STATE_FILE);
  if (!state || !Array.isArray(state.cameras)) {
    return res.json([]);
  }

  const results = await Promise.all(
    state.cameras.map(async (cam) => {
      const online = cam.ip && cam.onvif_port
        ? await checkPort(cam.ip, cam.onvif_port)
        : false;

      return {
        name: cam.name || '',
        ip: cam.ip || '',
        onvif_port: cam.onvif_port || null,
        rtsp_port: cam.rtsp_port || null,
        snapshot_port: cam.snapshot_port || null,
        rtsp_url_masked: cam.rtsp_url ? maskRtspPassword(cam.rtsp_url) : '',
        onvif_url: cam.ip && cam.onvif_port
          ? `http://${cam.ip}:${cam.onvif_port}`
          : '',
        rtsp_forward_url: cam.ip && cam.rtsp_port
          ? `rtsp://${cam.ip}:${cam.rtsp_port}`
          : '',
        snapshot_url: cam.ip && cam.snapshot_port
          ? `http://${cam.ip}:${cam.snapshot_port}/snapshot`
          : '',
        width: cam.width || null,
        height: cam.height || null,
        fps: cam.fps || null,
        bitrate: cam.bitrate || null,
        online,
        username: state.username || 'admin',
        password: state.password || 'admin',
      };
    })
  );

  res.json(results);
});

// ---------------------------------------------------------------------------
// GET /api/config
// ---------------------------------------------------------------------------
app.get('/api/config', (req, res) => {
  const options = readJson(OPTIONS_FILE);
  if (!options) {
    return res.status(503).json({ error: 'Options file not available' });
  }

  // Return only camera config with masked RTSP passwords
  const cameras = Array.isArray(options.cameras)
    ? options.cameras.map((cam) => {
        const masked = Object.assign({}, cam);
        if (masked.rtsp_url) {
          masked.rtsp_url = maskRtspPassword(masked.rtsp_url);
        }
        return masked;
      })
    : [];

  res.json({ cameras });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
const server = app.listen(PORT, () => {
  console.log(`[dashboard] ONVIF Server Dashboard running on port ${PORT}`);
});

process.on('SIGTERM', () => {
  server.close(() => {
    process.exit(0);
  });
});
