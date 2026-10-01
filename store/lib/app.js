import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { newLicenseKey, newOrderCode, newToken, normalizeKey, normalizeOrderCode, signActivation } from './licensing.js';
import * as pages from './pages.js';

const PUBLIC_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'public');
const PLATFORMS = { discord: 'Discord', tiktok: 'TikTok', other: 'Elsewhere' };
const ADMIN_COOKIE = 'srle_admin';
const SESSION_MS = 12 * 60 * 60 * 1000;

/** Fixed-window limits per client address. */
class RateLimiter {
  constructor(limit, windowMs) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.hits = new Map();
  }

  allow(key, now = Date.now()) {
    const recent = (this.hits.get(key) ?? []).filter((t) => now - t < this.windowMs);
    if (recent.length >= this.limit) {
      this.hits.set(key, recent);
      return false;
    }
    recent.push(now);
    this.hits.set(key, recent);
    return true;
  }
}

function sha256(s) {
  return createHash('sha256').update(s).digest();
}

/** The request handler: pages, the buy form, admin and the key API. */
export function createApp({ config, store, signingKey, now = () => new Date() }) {
  const sessions = new Map(); // session id → { expires, csrf }
  const limits = {
    orders: new RateLimiter(10, 60 * 60 * 1000),
    activate: new RateLimiter(30, 60 * 60 * 1000),
    login: new RateLimiter(10, 15 * 60 * 1000),
  };

  function clientIp(req) {
    if (config.trustProxy) {
      const fwd = req.headers['x-forwarded-for'];
      if (fwd) return String(fwd).split(',')[0].trim();
    }
    return req.socket.remoteAddress ?? '';
  }

  function send(res, status, body, type = 'text/html; charset=utf-8', headers = {}) {
    res.writeHead(status, {
      'content-type': type,
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
      'x-frame-options': 'DENY',
      'content-security-policy': "default-src 'self'; style-src 'unsafe-inline'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
      ...headers,
    });
    res.end(body);
  }

  const json = (res, status, obj) => send(res, status, JSON.stringify(obj), 'application/json');
  const redirect = (res, to, headers = {}) => send(res, 303, '', 'text/plain', { location: to, ...headers });

  async function readBody(req, limit = 16 * 1024) {
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > limit) throw Object.assign(new Error('too large'), { status: 413 });
      chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString('utf8');
  }

  async function form(req) {
    return Object.fromEntries(new URLSearchParams(await readBody(req)));
  }

  function cookies(req) {
    const out = {};
    for (const part of String(req.headers.cookie ?? '').split(';')) {
      const i = part.indexOf('=');
      if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
    }
    return out;
  }

  function session(req) {
    const id = cookies(req)[ADMIN_COOKIE];
    const s = id && sessions.get(id);
    if (!s || s.expires < Date.now()) return null;
    return { id, ...s };
  }

  function passwordOk(given) {
    if (!config.adminPassword) return false;
    return timingSafeEqual(sha256(given ?? ''), sha256(config.adminPassword));
  }

  // --- buyers ---------------------------------------------------------------

  async function createOrder(req, res) {
    const f = await form(req);
    if (f.website) return redirect(res, '/buy'); // the honeypot: bots fill every field
    const platform = PLATFORMS[f.platform] ? f.platform : 'other';
    const handle = String(f.handle ?? '').trim().slice(0, 64);
    if (!handle) return send(res, 400, pages.buy(config, { error: 'Type your handle so I can find your DM.' }));
    if (!limits.orders.allow(clientIp(req))) {
      return send(res, 429, pages.buy(config, { error: 'Too many orders from here. Try again in an hour.' }));
    }
    let code;
    do code = newOrderCode();
    while (store.byCode(code));
    const order = {
      id: randomUUID(),
      code,
      token: newToken(),
      platform: PLATFORMS[platform],
      handle,
      createdAt: now().toISOString(),
      status: 'pending',
      activations: [],
    };
    await store.add(order);
    return redirect(res, `/order/${order.token}`);
  }

  // --- the app's key API ----------------------------------------------------

  async function activate(req, res) {
    if (!limits.activate.allow(clientIp(req))) return json(res, 429, { error: 'rate', message: 'Too many tries. Wait an hour.' });
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      return json(res, 400, { error: 'bad_request', message: 'Bad request.' });
    }
    const key = normalizeKey(body.key);
    const machine = typeof body.machine === 'string' && /^[0-9a-f]{64}$/.test(body.machine) ? body.machine : null;
    if (!machine) return json(res, 400, { error: 'bad_request', message: 'Bad request.' });
    if (!key) {
      const message = normalizeOrderCode(body.key)
        ? "That's your order code. Your license key shows on your order page once the payment is confirmed."
        : "That isn't a license key. Copy it from your order page.";
      return json(res, 400, { error: 'not_a_key', message });
    }
    const o = store.byKey(key);
    if (!o || o.status !== 'paid') return json(res, 404, { error: 'unknown', message: "That key doesn't exist. Check it against your order page." });
    if (o.revoked) return json(res, 403, { error: 'revoked', message: 'This key has been turned off. DM me with your order code.' });
    o.activations ??= [];
    let a = o.activations.find((x) => x.machine === machine);
    if (!a) {
      if (o.activations.length >= config.maxActivations) {
        return json(res, 403, {
          error: 'limit',
          message: `This key is already on ${config.maxActivations} computers. Deactivate one in its Settings, or DM me with your order code to reset it.`,
        });
      }
      a = { machine, platform: String(body.platform ?? '').slice(0, 16), at: now().toISOString() };
      o.activations.push(a);
      await store.save();
    }
    const token = signActivation(signingKey, { v: 1, key, machine, order: o.code, at: a.at });
    return json(res, 200, { token });
  }

  async function deactivate(req, res) {
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      return json(res, 400, { error: 'bad_request' });
    }
    const o = store.byKey(normalizeKey(body.key));
    if (o && o.activations?.some((x) => x.machine === body.machine)) {
      o.activations = o.activations.filter((x) => x.machine !== body.machine);
      await store.save();
    }
    return json(res, 200, { ok: true });
  }

  // --- admin ----------------------------------------------------------------

  async function adminLogin(req, res) {
    const f = await form(req);
    if (!limits.login.allow(clientIp(req))) return send(res, 429, pages.adminLogin({ error: 'Too many tries. Wait 15 minutes.' }));
    if (!passwordOk(f.password)) return send(res, 401, pages.adminLogin({ error: 'Wrong password.' }));
    const id = randomBytes(24).toString('base64url');
    sessions.set(id, { expires: Date.now() + SESSION_MS, csrf: randomBytes(16).toString('base64url') });
    const secure = config.siteUrl.startsWith('https:') ? '; Secure' : '';
    return redirect(res, '/admin', {
      'set-cookie': `${ADMIN_COOKIE}=${id}; Path=/admin; HttpOnly; SameSite=Strict; Max-Age=${SESSION_MS / 1000}${secure}`,
    });
  }

  async function adminAction(req, res, s, id, action) {
    const f = await form(req);
    if (f.csrf !== s.csrf) return send(res, 403, pages.adminLogin({ error: 'Session expired. Sign in again.' }));
    if (action === 'logout') {
      sessions.delete(s.id);
      return redirect(res, '/admin', { 'set-cookie': `${ADMIN_COOKIE}=; Path=/admin; Max-Age=0` });
    }
    const o = store.byId(id);
    if (!o) return send(res, 404, pages.notFound());
    switch (action) {
      case 'paid':
        o.status = 'paid';
        o.paidAt ??= now().toISOString();
        if (!o.licenseKey) {
          let key;
          do key = newLicenseKey();
          while (store.byKey(key));
          o.licenseKey = key;
        }
        break;
      case 'pending':
        o.status = 'pending';
        break;
      case 'cancel':
        o.status = 'cancelled';
        break;
      case 'revoke':
        o.revoked = true;
        break;
      case 'unrevoke':
        o.revoked = false;
        break;
      case 'reset':
        o.activations = [];
        break;
      case 'note':
        o.note = String(f.note ?? '').slice(0, 500);
        break;
      default:
        return send(res, 404, pages.notFound());
    }
    await store.save();
    return redirect(res, '/admin');
  }

  function adminList(url) {
    const q = (url.searchParams.get('q') ?? '').trim();
    const code = normalizeOrderCode(q);
    const key = normalizeKey(q);
    const needle = q.toLowerCase();
    return [...store.orders]
      .filter(
        (o) =>
          !q ||
          o.code === code ||
          o.licenseKey === key ||
          o.handle.toLowerCase().includes(needle) ||
          (o.note ?? '').toLowerCase().includes(needle),
      )
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  // --- routing --------------------------------------------------------------

  return async function handle(req, res) {
    try {
      const url = new URL(req.url, config.siteUrl);
      const p = url.pathname;
      const get = req.method === 'GET' || req.method === 'HEAD';
      const post = req.method === 'POST';

      if (get && p === '/') return send(res, 200, pages.home(config));
      if (get && p === '/buy') return send(res, 200, pages.buy(config));
      if (post && p === '/buy') return await createOrder(req, res);
      if (get && p.startsWith('/order/')) {
        const o = store.byToken(p.slice('/order/'.length));
        return o ? send(res, 200, pages.order(config, o)) : send(res, 404, pages.notFound());
      }
      if (get && p === '/contact') return send(res, 200, pages.contact(config));
      if (get && p === '/license') return send(res, 200, pages.license(config));
      if (get && p === '/terms') return send(res, 200, pages.terms(config));
      if (get && p === '/privacy') return send(res, 200, pages.privacy(config));
      if (get && p === '/logo.png') {
        return send(res, 200, fs.readFileSync(path.join(PUBLIC_DIR, 'logo.png')), 'image/png', {
          'cache-control': 'public, max-age=86400',
        });
      }
      if (get && p === '/healthz') return json(res, 200, { ok: true });
      if (post && p === '/api/activate') return await activate(req, res);
      if (post && p === '/api/deactivate') return await deactivate(req, res);

      if (p === '/admin' || p.startsWith('/admin/')) {
        if (post && p === '/admin/login') return await adminLogin(req, res);
        const s = session(req);
        if (!s) return send(res, get ? 200 : 401, pages.adminLogin());
        if (get && p === '/admin') return send(res, 200, pages.admin(config, adminList(url), { q: url.searchParams.get('q') ?? '', csrf: s.csrf }));
        if (post && p === '/admin/logout') return await adminAction(req, res, s, null, 'logout');
        const m = /^\/admin\/orders\/([\w-]+)\/(\w+)$/.exec(p);
        if (post && m) return await adminAction(req, res, s, m[1], m[2]);
      }
      return send(res, 404, pages.notFound());
    } catch (e) {
      if (e.status === 413) return send(res, 413, 'Too large', 'text/plain');
      console.error(e);
      return send(res, 500, 'Something went wrong.', 'text/plain');
    }
  };
}
