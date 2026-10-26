'use strict';
const nodeInput = document.getElementById('node');
const status = document.getElementById('status');
const list = document.getElementById('nodes');
nodeInput.value = new URLSearchParams(location.search).get('node_id') || '';

function render(names) {
  list.replaceChildren();
  if (!names.length) {
    const item = document.createElement('li');
    item.textContent = 'No nodes registered yet.';
    list.append(item);
  }
  for (const name of names) {
    const item = document.createElement('li');
    item.textContent = name;
    list.append(item);
  }
}

async function request(options) {
  const response = await fetch('/api/nodes', { cache: 'no-store', ...options });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
  render(data.node_ids);
  return data;
}

async function refresh() {
  try {
    const data = await request();
    status.textContent = `${data.node_ids.length} known node name(s).`;
  } catch (error) { status.textContent = error.message; }
}

document.getElementById('join').addEventListener('submit', async event => {
  event.preventDefault();
  try {
    const data = await request({ method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ node_id: nodeInput.value.trim() }) });
    status.textContent = `Registered ${data.registered_node_id}. Returned ${data.node_ids.length} node name(s).`;
  } catch (error) { status.textContent = error.message; }
});
document.getElementById('refresh').addEventListener('click', refresh);

const joinURL = `${location.origin}/`;
const link = document.getElementById('join-url');
link.href = joinURL;
link.textContent = joinURL;
try {
  const qr = qrcode(0, 'M');
  qr.addData(joinURL);
  qr.make();
  document.getElementById('qr').innerHTML = qr.createSvgTag({ scalable: true, margin: 4 });
} catch (_) { document.getElementById('qr').textContent = 'QR unavailable. Use the link below.'; }
document.getElementById('network-note').textContent = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname)
  ? 'This localhost link works on this Mac only. For a phone QR, explicitly bind the reception desk to your Mac’s private LAN address and open that address here first. A QR opens this form; it cannot obtain the phone’s Erlang node name itself.'
  : 'Other devices need access to this private LAN address. The QR opens this form; an installed app must provide its own node name.';
refresh();
