import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { after, before, describe, test } from 'node:test';

import { createApp } from '../lib/app.js';
import { loadConfig } from '../lib/config.js';
import { Store } from '../lib/db.js';
import {
  loadSigningKey,
  normalizeKey,
  normalizeOrderCode,
  publicKeyString,
  signActivation,
  verifyActivation,
} from '../lib/licensing.js';

const MACHINE_A = 'a'.repeat(64);
const MACHINE_B = 'b'.repeat(64);
const MACHINE_C = 'c'.repeat(64);

let server, base, dir, store, signingKey, cookie, csrf;

async function request(method, p, { body, form, headers = {} } = {}) {
  const init = { method, headers: { ...headers }, redirect: 'manual' };
  if (form) {
    init.body = new URLSearchParams(form).toString();
    init.headers['content-type'] = 'application/x-www-form-urlencoded';
  } else if (body !== undefined) {
    init.body = typeof body === 'string' ? body : JSON.stringify(body);
    init.headers['content-type'] = 'application/json';
  }
  const res = await fetch(base + p, init);
  return { status: res.status, headers: res.headers, text: await res.text() };
}

async function order(handle = 'buyer') {
  const r = await request('POST', '/buy', { form: { platform: 'discord', handle } });
  assert.equal(r.status, 303);
  return r.headers.get('location');
}

async function adminPost(p, form = {}) {
  return request('POST', p, { form: { csrf, ...form }, headers: { cookie } });
}

before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'srle-store-'));
  const config = { ...loadConfig({ DATA_DIR: dir, ADMIN_PASSWORD: 'hunter2', SITE_URL: 'http://localhost' }), maxActivations: 2 };
  signingKey = loadSigningKey(config.signingKeyFile);
  store = new Store(path.join(dir, 'orders.json'));
  server = http.createServer(createApp({ config, store, signingKey }));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('keys and codes', () => {
  test('typed keys and codes are read the forgiving way', () => {
    assert.equal(normalizeKey('srle abcde-fghjk mnpqr stvwx'), 'SRLE-ABCDE-FGHJK-MNPQR-STVWX');
    assert.equal(normalizeKey('SRLE-0O1IL-22222-33333-44444'), 'SRLE-00111-22222-33333-44444');
    assert.equal(normalizeKey('SRLE-ABCD-EFGH'), null);
    assert.equal(normalizeKey('hello'), null);
    assert.equal(normalizeOrderCode('srle-abcd-efgh'), 'SRLE-ABCD-EFGH');
  });

  test('an activation verifies with the public key and only with it', () => {
    const token = signActivation(signingKey, { v: 1, key: 'K', machine: MACHINE_A });
    assert.deepEqual(verifyActivation(publicKeyString(signingKey), token), { v: 1, key: 'K', machine: MACHINE_A });
    const [body, sig] = token.split('.');
    const forged = Buffer.from(JSON.stringify({ v: 1, key: 'K', machine: MACHINE_B })).toString('base64url');
    assert.equal(verifyActivation(publicKeyString(signingKey), `${forged}.${sig}`), null);
    assert.equal(verifyActivation(publicKeyString(signingKey), `${body}.${'A'.repeat(86)}`), null);
  });

  test('the signing key is created once and kept', () => {
    const again = loadSigningKey(path.join(dir, 'signing-key.pem'));
    assert.equal(publicKeyString(again), publicKeyString(signingKey));
    assert.equal(fs.statSync(path.join(dir, 'signing-key.pem')).mode & 0o777, 0o600);
  });
});

describe('buying', () => {
  test('pages load', async () => {
    for (const p of ['/', '/buy', '/contact', '/license', '/terms', '/privacy']) {
      const r = await request('GET', p);
      assert.equal(r.status, 200, p);
      assert.match(r.text, /SRLE/);
    }
    assert.equal((await request('GET', '/nope')).status, 404);
    assert.equal((await request('GET', '/logo.png')).status, 200);
  });

  test('the buy form makes an order code and a private order page', async () => {
    const loc = await order('Tester#1');
    assert.match(loc, /^\/order\/[\w-]{22}$/);
    const page = await request('GET', loc);
    assert.equal(page.status, 200);
    assert.match(page.text, /SRLE-[0-9A-Z]{4}-[0-9A-Z]{4}/);
    assert.match(page.text, /pending/);
    assert.match(page.text, /ajh3d/);
    assert.match(page.text, /Tester#1/);
    assert.doesNotMatch(page.text, /License key|SRLE-\w{5}-\w{5}/);
    assert.equal((await request('GET', '/order/not-a-real-token-xxxxx')).status, 404);
  });

  test('the honeypot and an empty handle make no order', async () => {
    const before = store.orders.length;
    const bot = await request('POST', '/buy', { form: { platform: 'discord', handle: 'bot', website: 'spam.example' } });
    assert.equal(bot.headers.get('location'), '/buy');
    const empty = await request('POST', '/buy', { form: { platform: 'tiktok', handle: '  ' } });
    assert.equal(empty.status, 400);
    assert.equal(store.orders.length, before);
  });

  test('handles are shown escaped', async () => {
    const page = await request('GET', await order('<script>x</script>'));
    assert.doesNotMatch(page.text, /<script>x/);
    assert.match(page.text, /&lt;script&gt;x/);
  });
});

describe('admin and activation', () => {
  test('admin needs the password', async () => {
    assert.match((await request('GET', '/admin')).text, /Password/);
    assert.equal((await request('POST', '/admin/login', { form: { password: 'nope' } })).status, 401);
    const ok = await request('POST', '/admin/login', { form: { password: 'hunter2' } });
    assert.equal(ok.status, 303);
    cookie = ok.headers.get('set-cookie').split(';')[0];
    assert.match(ok.headers.get('set-cookie'), /HttpOnly; SameSite=Strict/);
    const page = await request('GET', '/admin', { headers: { cookie } });
    csrf = /name="csrf" value="([^"]+)"/.exec(page.text)[1];
    assert.match(page.text, /Mark paid/);
  });

  test('marking paid shows the key on the order page; the app activates it on 2 computers', async () => {
    const loc = await order('payer');
    const o = store.byToken(loc.split('/').pop());
    assert.equal((await request('POST', `/admin/orders/${o.id}/paid`, { form: { csrf: 'wrong' }, headers: { cookie } })).status, 403);
    assert.equal((await adminPost(`/admin/orders/${o.id}/paid`)).status, 303);
    const page = await request('GET', loc);
    assert.match(page.text, /paid/);
    assert.ok(page.text.includes(o.licenseKey));
    assert.match(page.text, /SRLEStudio-windows\.zip/);

    const pub = publicKeyString(signingKey);
    const typed = o.licenseKey.toLowerCase().replaceAll('-', ' ');
    const a = await request('POST', '/api/activate', { body: { key: typed, machine: MACHINE_A, platform: 'windows' } });
    assert.equal(a.status, 200);
    const payload = verifyActivation(pub, JSON.parse(a.text).token);
    assert.equal(payload.key, o.licenseKey);
    assert.equal(payload.machine, MACHINE_A);
    // The same computer again doesn't use another slot.
    assert.equal((await request('POST', '/api/activate', { body: { key: o.licenseKey, machine: MACHINE_A } })).status, 200);
    assert.equal((await request('POST', '/api/activate', { body: { key: o.licenseKey, machine: MACHINE_B } })).status, 200);
    const third = await request('POST', '/api/activate', { body: { key: o.licenseKey, machine: MACHINE_C } });
    assert.equal(third.status, 403);
    assert.equal(JSON.parse(third.text).error, 'limit');
    assert.match((await request('GET', loc)).text, /Used on 2 of 2/);

    // Deactivating frees a slot.
    await request('POST', '/api/deactivate', { body: { key: o.licenseKey, machine: MACHINE_B } });
    assert.equal((await request('POST', '/api/activate', { body: { key: o.licenseKey, machine: MACHINE_C } })).status, 200);

    // A key turned off stops activating.
    await adminPost(`/admin/orders/${o.id}/revoke`);
    const off = await request('POST', '/api/activate', { body: { key: o.licenseKey, machine: MACHINE_A } });
    assert.equal(off.status, 403);
    assert.equal(JSON.parse(off.text).error, 'revoked');
    await adminPost(`/admin/orders/${o.id}/unrevoke`);
    await adminPost(`/admin/orders/${o.id}/reset`);
    assert.equal(store.byId(o.id).activations.length, 0);

    // Saved to disk.
    const disk = JSON.parse(fs.readFileSync(path.join(dir, 'orders.json'), 'utf8'));
    assert.equal(disk.orders.find((x) => x.id === o.id).licenseKey, o.licenseKey);
  });

  test('the key API explains wrong keys', async () => {
    const pending = store.byToken((await order('unpaid')).split('/').pop());
    const code = await request('POST', '/api/activate', { body: { key: pending.code, machine: MACHINE_A } });
    assert.equal(code.status, 400);
    assert.match(JSON.parse(code.text).message, /order code/);
    const unknown = await request('POST', '/api/activate', { body: { key: 'SRLE-AAAAA-AAAAA-AAAAA-AAAAA', machine: MACHINE_A } });
    assert.equal(unknown.status, 404);
    assert.equal((await request('POST', '/api/activate', { body: { key: 'SRLE-AAAAA-AAAAA-AAAAA-AAAAA', machine: 'short' } })).status, 400);
    assert.equal((await request('POST', '/api/activate', { body: '{not json' })).status, 400);
  });

  test('admin can find an order by code and sign out', async () => {
    const o = store.orders[0];
    const found = await request('GET', `/admin?q=${encodeURIComponent(o.code.toLowerCase())}`, { headers: { cookie } });
    assert.ok(found.text.includes(o.code));
    assert.equal((await adminPost('/admin/logout')).status, 303);
    assert.match((await request('GET', '/admin', { headers: { cookie } })).text, /Password/);
  });
});
