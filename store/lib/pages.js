// HTML for every page. No scripts: the store works with JavaScript off.

export function esc(value) {
  return String(value ?? '').replace(
    /[&<>"']/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c],
  );
}

const CSS = `
:root{color-scheme:dark;--bg:#000;--panel:#0e0e12;--line:#26262f;--text:#ececf3;--muted:#9a9aae;--accent:#ff5a36;--accent2:#7c5cff;--ok:#22c55e;--warn:#f5a524}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.55 Verdana,Geneva,sans-serif;-webkit-font-smoothing:antialiased}
main{max-width:640px;margin:0 auto;padding:28px 16px 48px}
a{color:var(--text)}
a:hover{color:var(--accent)}
header{display:flex;align-items:center;gap:10px;margin-bottom:28px}
header a{text-decoration:none;display:flex;align-items:center;gap:10px}
header img{width:34px;height:34px}
.brand{font-weight:bold;font-size:18px}
.brand b{background:linear-gradient(90deg,var(--accent),var(--accent2));-webkit-background-clip:text;background-clip:text;color:transparent}
h1{font-size:24px;margin:0 0 8px}
h2{font-size:17px;margin:28px 0 8px}
p{margin:0 0 12px}
.muted{color:var(--muted)}
.small{font-size:13px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px;margin:16px 0}
.price{font-size:28px;font-weight:bold}
.btn{display:inline-block;background:var(--accent);color:#000;font-weight:bold;text-decoration:none;border:0;border-radius:8px;padding:10px 18px;font:bold 15px Verdana,Geneva,sans-serif;cursor:pointer}
.btn:hover{background:#ff8a5c;color:#000}
.btn.alt{background:transparent;color:var(--text);border:1px solid var(--line)}
label{display:block;margin:14px 0 6px;font-weight:bold}
input,select,textarea{width:100%;background:#000;color:var(--text);border:1px solid var(--line);border-radius:8px;padding:10px;font:15px Verdana,Geneva,sans-serif}
input:focus,select:focus,textarea:focus{outline:2px solid var(--accent2);border-color:transparent}
.hp{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden}
.code{font:bold 26px/1.2 ui-monospace,Menlo,Consolas,monospace;letter-spacing:1px}
.key{font:bold 18px ui-monospace,Menlo,Consolas,monospace;text-align:center}
.pill{display:inline-block;border-radius:99px;padding:2px 10px;font-size:12px;font-weight:bold}
.pill.pending{background:#2a2312;color:var(--warn)}
.pill.paid{background:#10291a;color:var(--ok)}
.pill.cancelled{background:#2a1218;color:#f43f5e}
ul{padding-left:20px;margin:0 0 12px}
li{margin:4px 0}
footer{margin-top:40px;padding-top:16px;border-top:1px solid var(--line);font-size:13px;color:var(--muted)}
footer a{color:var(--muted);margin-right:14px}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{text-align:left;padding:8px 6px;border-bottom:1px solid var(--line);vertical-align:top}
td form{display:inline}
td .btn{padding:4px 10px;font-size:12px;margin:2px 0}
.wide{max-width:1100px}
.err{color:#f43f5e}
`;

export function layout(title, body, { wide = false, description = 'SRLE Studio: Sparta remixes and logo-editing effects on your computer.' } = {}) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<link rel="icon" href="/logo.png">
<style>${CSS}</style>
</head>
<body>
<main${wide ? ' class="wide"' : ''}>
<header><a href="/"><img src="/logo.png" alt=""><span class="brand"><b>SRLE</b> Studio</span></a></header>
${body}
<footer><a href="/">Home</a><a href="/buy">Buy</a><a href="/contact">Contact</a><a href="/license">License</a><a href="/terms">Terms</a><a href="/privacy">Privacy</a></footer>
</main>
</body>
</html>`;
}

export function home(c) {
  return layout(
    'SRLE Studio',
    `<h1>Sparta remixes and logo-editing effects, on your computer.</h1>
<p>SRLE Studio (Sparta Remix &amp; Logo Editing) makes a Sparta remix from a video of anyone talking, following a real base exactly, and has 265 logo-editing effects: G-Majors, vocoders, CoNfUsIoN, Low Voice, Luig Group and the rest.</p>
<div class="card">
<p class="price">$${esc(c.price)}</p>
<p class="muted">One payment. Windows, macOS and Linux. Your key works on up to ${esc(c.maxActivations)} of your computers.</p>
<p><a class="btn" href="/buy">Get SRLE Studio</a></p>
</div>
<h2>What's in it</h2>
<ul>
<li><b>Sparta Remix Generator</b>: pick a base (560 real bases, or your own audio or FL Studio project), add your videos, pick the line, and it plays your samples on the base's own hits, bass line, chords and drums, with the classic box video.</li>
<li><b>265 effects</b>, level-matched, with the recipes from the Logo Editing Wiki, plus compilations ("X in 40 effects").</li>
<li><b>No account, no subscription.</b> Enter your key once with internet on; after that it works offline.</li>
</ul>`,
  );
}

export function buy(c, { error = '' } = {}) {
  return layout(
    'Buy SRLE Studio',
    `<h1>Get SRLE Studio</h1>
<p>This form does not take any money and does not ask for an email. It creates an order code so I know which DM is yours.</p>
${error ? `<p class="err">${esc(error)}</p>` : ''}
<form method="post" action="/buy" class="card">
<label for="platform">Where should I look for you?</label>
<select id="platform" name="platform" required>
<option value="discord">Discord</option>
<option value="tiktok">TikTok</option>
<option value="other">Somewhere else</option>
</select>
<label for="handle">Your handle there</label>
<input id="handle" name="handle" maxlength="64" required autocomplete="off" placeholder="Exactly as it is spelled">
<p class="small muted">Exactly as it is spelled, so I can match your DM to this order. If it's somewhere else, say where too (for example "insta: name").</p>
<div class="hp" aria-hidden="true"><label for="website">Leave this field empty</label><input id="website" name="website" tabindex="-1" autocomplete="off"></div>
<p><button class="btn" type="submit">Get my order code</button></p>
</form>
<h2>Then</h2>
<ul>
<li>Your order page opens with a code. Bookmark it: that page is where your license key and downloads will show up.</li>
<li>DM me the code and pay $${esc(c.price)} by ${esc(c.payWith)}: <b>${esc(c.discord)}</b> on Discord or <b>${esc(c.tiktok)}</b> on TikTok.</li>
<li>Once I confirm the payment, your key appears on your order page.</li>
</ul>
<p class="small muted">No card details are ever typed into this site, because this site cannot take them. Digital goods are final: once your key is issued, there are no refunds.</p>`,
  );
}

function when(iso) {
  return iso ? `${new Date(iso).toISOString().replace('T', ' ').slice(0, 16)} UTC` : '';
}

export function order(c, o) {
  const status = `<span class="pill ${esc(o.status)}">${esc(o.status)}</span>`;
  let body;
  if (o.status === 'paid') {
    const used = (o.activations ?? []).length;
    body = `<div class="card">
<p>Your license key</p>
<input class="key" readonly value="${esc(o.licenseKey)}" aria-label="License key">
<p class="small muted">Used on ${used} of ${esc(c.maxActivations)} computers.</p>
</div>
<h2>Download</h2>
<ul>
<li><a href="${esc(c.downloadBase)}/SRLEStudio-windows.zip">Windows</a> (zip: unzip anywhere and run <b>srle_studio.exe</b>)</li>
<li><a href="${esc(c.downloadBase)}/SRLEStudio-macos.dmg">macOS</a> (dmg: drag SRLE Studio to Applications)</li>
<li><a href="${esc(c.downloadBase)}/SRLEStudio-linux.tar.gz">Linux</a> (tar.gz)</li>
</ul>
<p class="small muted">Older versions and release notes: <a href="${esc(c.releasesUrl)}">releases</a>.</p>
<h2>Unlock it</h2>
<ul>
<li>Open SRLE Studio and paste your key. It needs internet that one time; after that it works offline.</li>
<li>New computer? Choose <b>Deactivate this computer</b> in the app's Settings on the old one first, or DM me and I'll reset your key.</li>
</ul>`;
  } else if (o.status === 'cancelled') {
    body = `<div class="card"><p>This order was cancelled. DM me if that's a mistake.</p></div>`;
  } else {
    body = `<div class="card">
<p>Your order code</p>
<p class="code">${esc(o.code)}</p>
</div>
<ul>
<li>DM this code to <b>${esc(c.discord)}</b> on Discord or <b>${esc(c.tiktok)}</b> on TikTok, and pay <b>$${esc(c.price)}</b> by ${esc(c.payWith)}.</li>
<li>Bookmark this page. Once I confirm the payment, your license key and downloads show up here.</li>
</ul>`;
  }
  return layout(
    `Order ${o.code}`,
    `<h1>Order ${esc(o.code)} ${status}</h1>
<p class="small muted">Placed ${esc(when(o.createdAt))}${o.paidAt ? ` · paid ${esc(when(o.paidAt))}` : ''} · for ${esc(o.platform)} ${esc(o.handle)}</p>
${body}`,
  );
}

export function notFound() {
  return layout('Not found', `<h1>Not found</h1><p>There's nothing here. <a href="/">Home</a></p>`);
}

export function contact(c) {
  return layout(
    'Contact',
    `<h1>Contact</h1>
<p>DM me: <b>${esc(c.discord)}</b> on Discord or <b>${esc(c.tiktok)}</b> on TikTok. Put your order code in the message if it's about an order.</p>`,
  );
}

export function license() {
  return layout(
    'License',
    `<h1>License</h1>
<p>Your key lets you install and use SRLE Studio on up to the number of your own computers shown on your order page. It's for you: don't share, resell or publish the key or the app.</p>
<p>What you make with it is yours: remixes and edits you export are free of any claim from SRLE Studio. The samples, bases and videos you put in still belong to whoever made them; crediting base makers is good manners and often required.</p>
<p>SRLE Studio includes FFmpeg, which is licensed under the GPL; its license and a link to its source come with every download. The Sparta Remix Wiki patterns it uses are CC BY-SA and keep that license.</p>`,
  );
}

export function terms(c) {
  return layout(
    'Terms',
    `<h1>Terms</h1>
<ul>
<li>The price is $${esc(c.price)}, paid by ${esc(c.payWith)} through DM. Your key is issued once I've confirmed the payment.</li>
<li>Digital goods are final: once your key is issued, there are no refunds. If it doesn't work on your computer, DM me and I'll help.</li>
<li>A key works on up to ${esc(c.maxActivations)} of your computers at a time. Keys that are shared or resold can be turned off.</li>
<li>Updates in the same major version (2.x) are included.</li>
<li>SRLE Studio is provided as is.</li>
</ul>`,
  );
}

export function privacy() {
  return layout(
    'Privacy',
    `<h1>Privacy</h1>
<ul>
<li>An order stores the platform and handle you typed, the time, and its status. No email, no name, no card details.</li>
<li>Unlocking the app sends your key, a one-way fingerprint of your computer (so a key isn't used on more computers than allowed) and which system it runs. Nothing else is sent, before or after.</li>
<li>The site sets no cookies for buyers and has no trackers or analytics.</li>
<li>DM me to have an order deleted.</li>
</ul>`,
  );
}

export function adminLogin({ error = '' } = {}) {
  return layout(
    'Admin',
    `<h1>Admin</h1>
${error ? `<p class="err">${esc(error)}</p>` : ''}
<form method="post" action="/admin/login" class="card">
<label for="password">Password</label>
<input id="password" name="password" type="password" required autocomplete="current-password">
<p><button class="btn" type="submit">Sign in</button></p>
</form>`,
  );
}

export function admin(c, orders, { q = '', csrf }) {
  const rows = orders
    .map((o) => {
      const act = (path, label, cls = 'alt') =>
        `<form method="post" action="/admin/orders/${esc(o.id)}/${path}"><input type="hidden" name="csrf" value="${esc(csrf)}"><button class="btn ${cls}">${label}</button></form>`;
      const actions = [
        o.status !== 'paid' ? act('paid', 'Mark paid', '') : '',
        o.status === 'paid' ? act('pending', 'Back to pending') : '',
        o.status !== 'cancelled' ? act('cancel', 'Cancel') : '',
        o.licenseKey && !o.revoked ? act('revoke', 'Turn key off') : '',
        o.revoked ? act('unrevoke', 'Turn key on') : '',
        (o.activations ?? []).length ? act('reset', 'Reset computers') : '',
      ].join(' ');
      const acts = (o.activations ?? [])
        .map((a) => `${esc(a.platform || '?')} ${esc(when(a.at))}`)
        .join('<br>');
      return `<tr>
<td><b>${esc(o.code)}</b><br><span class="muted">${esc(when(o.createdAt))}</span></td>
<td>${esc(o.platform)}<br>${esc(o.handle)}</td>
<td><span class="pill ${esc(o.status)}">${esc(o.status)}</span>${o.revoked ? '<br><span class="err">key off</span>' : ''}</td>
<td>${o.licenseKey ? `<code>${esc(o.licenseKey)}</code>` : ''}<br>${acts}</td>
<td>${actions}
<form method="post" action="/admin/orders/${esc(o.id)}/note"><input type="hidden" name="csrf" value="${esc(csrf)}"><input name="note" value="${esc(o.note ?? '')}" placeholder="Note" style="margin-top:4px;padding:4px"></form></td>
</tr>`;
    })
    .join('');
  const paid = orders.filter((o) => o.status === 'paid').length;
  return layout(
    'Admin',
    `<h1>Orders</h1>
<form method="get" action="/admin" style="display:flex;gap:8px;margin:12px 0"><input name="q" value="${esc(q)}" placeholder="Order code, key or handle"><button class="btn alt">Find</button></form>
<p class="small muted">${orders.length} shown · ${paid} paid · <form method="post" action="/admin/logout" style="display:inline"><input type="hidden" name="csrf" value="${esc(csrf)}"><button class="btn alt">Sign out</button></form></p>
<table><thead><tr><th>Order</th><th>Buyer</th><th>Status</th><th>Key / computers</th><th></th></tr></thead><tbody>${rows || '<tr><td colspan="5" class="muted">No orders.</td></tr>'}</tbody></table>`,
    { wide: true },
  );
}
