'use strict';

/* ── Utilities ── */

function qs(sel) {
    return document.querySelector(sel);
}

function escapeHtml(str) {
    if (str == null) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function copyToClipboard(text, btn) {
    const originalText = btn.textContent;

    function markCopied() {
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(() => {
            btn.textContent = originalText;
            btn.classList.remove('copied');
        }, 2000);
    }

    if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(markCopied).catch(() => fallbackCopy(text, markCopied));
    } else {
        fallbackCopy(text, markCopied);
    }
}

function fallbackCopy(text, onSuccess) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    try {
        document.execCommand('copy');
        onSuccess();
    } catch (e) {
        console.warn('Copy failed', e);
    }
    document.body.removeChild(ta);
}

async function fetchJSON(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    return res.json();
}

/* ── Render helpers ── */

function renderServiceChip(id, running) {
    const el = qs(`#svc-${id}`);
    if (!el) return;
    el.className = `service-chip ${running ? 'running' : 'stopped'}`;
}

function renderCameraCard(cam) {
    const isOnline = cam.online !== false;
    const statusClass = isOnline ? 'online' : 'offline';
    const statusLabel = isOnline ? 'Online' : 'Offline';

    const name = escapeHtml(cam.name || cam.id || 'Unknown Camera');

    // Meta rows
    const ip = cam.ip ? escapeHtml(cam.ip) : '<span class="waiting">DHCP ausstehend…</span>';
    const width = cam.width || 0;
    const height = cam.height || 0;
    const fps = cam.fps || 0;
    const bitrate = cam.bitrate || 0;
    const resolution = (width && height) ? `${width}×${height}` : '—';
    const fpsLabel = fps ? `${fps} fps` : '—';
    const bitrateLabel = bitrate ? `${bitrate} kbit/s` : '—';

    // URLs
    const onvifUrl      = escapeHtml(cam.onvif_url || '');
    const rtspFwdUrl    = escapeHtml(cam.rtsp_forward_url || '');
    const snapshotUrl   = escapeHtml(cam.snapshot_url || '');
    const rtspMasked    = escapeHtml(cam.rtsp_url_masked || '');
    const rtspRaw       = cam.rtsp_url_masked || '';  // used for copy (unescaped)

    // Info chips
    const chips = [];
    if (width && height) chips.push(`${width}×${height}`);
    if (fps)             chips.push(`${fps} fps`);
    if (bitrate)         chips.push(`${bitrate} kbit/s`);
    const chipsHtml = chips.map(c => `<span class="info-chip">${escapeHtml(c)}</span>`).join('');

    // Credentials for UniFi Protect adoption
    const credHtml = `
    <div class="cred-block">
        <div class="cred-title">UniFi Protect – Zugangsdaten</div>
        <div class="cred-row">
            <span class="cred-label">Benutzer</span>
            <span class="cred-value">${escapeHtml(cam.username || 'admin')}</span>
        </div>
        <div class="cred-row">
            <span class="cred-label">Passwort</span>
            <span class="cred-value">${escapeHtml(cam.password || 'admin')}</span>
        </div>
    </div>`;

    // Build URL rows
    function urlRow(label, display, copyText) {
        if (!display) return '';
        return `
            <div class="url-row">
                <span class="url-label">${label}</span>
                <span class="url-text" title="${display}">${display}</span>
                <button class="copy-btn" data-copy="${escapeHtml(copyText || display)}">Copy</button>
            </div>`;
    }

    return `
        <div class="camera-card">
            <div class="camera-card-header">
                <span class="camera-name">${name}</span>
                <span class="status-badge ${statusClass}">${statusLabel}</span>
            </div>

            <div class="camera-meta">
                <div class="camera-meta-row">
                    <span class="camera-meta-label">MacVLAN IP</span>
                    <span class="camera-meta-value">${ip}</span>
                </div>
                <div class="camera-meta-row">
                    <span class="camera-meta-label">Resolution</span>
                    <span class="camera-meta-value">${resolution} @ ${fpsLabel}</span>
                </div>
                <div class="camera-meta-row">
                    <span class="camera-meta-label">Bitrate</span>
                    <span class="camera-meta-value">${bitrateLabel}</span>
                </div>
            </div>

            ${credHtml}

            ${chips.length ? `<div class="info-chips">${chipsHtml}</div>` : ''}

            <div class="url-block">
                ${urlRow('ONVIF',    onvifUrl,   cam.onvif_url)}
                ${urlRow('RTSP',     rtspFwdUrl, cam.rtsp_forward_url)}
                ${urlRow('Snapshot', snapshotUrl, cam.snapshot_url)}
                ${urlRow('Source',   rtspMasked, rtspRaw)}
            </div>
        </div>`;
}

/* ── Copy button delegation ── */

document.addEventListener('click', (e) => {
    const btn = e.target.closest('.copy-btn');
    if (!btn) return;
    const text = btn.dataset.copy || '';
    copyToClipboard(text, btn);
});

/* ── Update functions ── */

async function updateStatus() {
    const data = await fetchJSON('/api/status');
    const onvifRunning = data && data.services && data.services.onvif
        ? data.services.onvif.running
        : false;
    renderServiceChip('onvif', onvifRunning);
}

async function updateCameras() {
    const data = await fetchJSON('/api/cameras');
    const grid = qs('#cameras-grid');
    if (!grid) return;

    const cameras = Array.isArray(data) ? data : (data.cameras || []);

    if (!cameras.length) {
        grid.innerHTML = '<div class="empty-state">No cameras configured.</div>';
        return;
    }

    grid.innerHTML = cameras.map(renderCameraCard).join('');
}

function updateTimestamp() {
    const el = qs('#last-update');
    if (!el) return;
    const now = new Date();
    el.textContent = `Updated ${now.toLocaleTimeString()}`;
}

/* ── Main refresh loop ── */

async function refresh() {
    await Promise.allSettled([updateStatus(), updateCameras()]);
    updateTimestamp();
}

refresh();
setInterval(refresh, 10_000);
