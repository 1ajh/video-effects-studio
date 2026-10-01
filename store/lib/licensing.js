import { createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes, sign, verify } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

// Crockford base32: no I, L, O or U, so codes read back unambiguously.
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/** [n] random Crockford base32 characters (256 is a multiple of 32, so uniform). */
export function randomChars(n) {
  return [...randomBytes(n)].map((b) => ALPHABET[b % 32]).join('');
}

/** Order codes look like the kit store's: SRLE-XXXX-XXXX. */
export function newOrderCode() {
  return `SRLE-${randomChars(4)}-${randomChars(4)}`;
}

/** License keys: four groups of five (100 random bits). */
export function newLicenseKey() {
  return `SRLE-${randomChars(5)}-${randomChars(5)}-${randomChars(5)}-${randomChars(5)}`;
}

/** Secret part of an order page URL. */
export function newToken() {
  return randomBytes(16).toString('base64url');
}

/**
 * A typed or pasted key in its canonical form, or null when it isn't one.
 * Case, spaces and dashes don't matter; O reads as 0 and I/L as 1.
 */
export function normalizeKey(input) {
  if (typeof input !== 'string') return null;
  let s = input.toUpperCase().replace(/[\s-]/g, '');
  if (!s.startsWith('SRLE')) return null;
  s = s.slice(4).replace(/O/g, '0').replace(/[IL]/g, '1');
  if (s.length !== 20 || [...s].some((c) => !ALPHABET.includes(c))) return null;
  return `SRLE-${s.slice(0, 5)}-${s.slice(5, 10)}-${s.slice(10, 15)}-${s.slice(15)}`;
}

/** Same for order codes (SRLE-XXXX-XXXX). */
export function normalizeOrderCode(input) {
  if (typeof input !== 'string') return null;
  let s = input.toUpperCase().replace(/[\s-]/g, '');
  if (!s.startsWith('SRLE')) return null;
  s = s.slice(4).replace(/O/g, '0').replace(/[IL]/g, '1');
  if (s.length !== 8 || [...s].some((c) => !ALPHABET.includes(c))) return null;
  return `SRLE-${s.slice(0, 4)}-${s.slice(4)}`;
}

/** Loads the Ed25519 signing key, creating it on first run. */
export function loadSigningKey(file) {
  if (!fs.existsSync(file)) {
    const { privateKey } = generateKeyPairSync('ed25519');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, privateKey.export({ format: 'pem', type: 'pkcs8' }), { mode: 0o600 });
  }
  return createPrivateKey(fs.readFileSync(file));
}

/** The raw 32-byte public key, base64url: what the app is built with. */
export function publicKeyString(privateKey) {
  return createPublicKey(privateKey).export({ format: 'jwk' }).x;
}

/**
 * An activation: the payload's JSON bytes and their Ed25519 signature,
 * both base64url, joined by a dot. The app checks the signature with the
 * public key it was built with, so it works offline afterwards.
 */
export function signActivation(privateKey, payload) {
  const bytes = Buffer.from(JSON.stringify(payload), 'utf8');
  const signature = sign(null, bytes, privateKey);
  return `${bytes.toString('base64url')}.${signature.toString('base64url')}`;
}

/** The payload of a valid activation token, or null. */
export function verifyActivation(publicKey, token) {
  const [body, sig] = String(token).split('.');
  if (!body || !sig) return null;
  const bytes = Buffer.from(body, 'base64url');
  const key =
    typeof publicKey === 'string'
      ? createPublicKey({ key: { kty: 'OKP', crv: 'Ed25519', x: publicKey }, format: 'jwk' })
      : publicKey;
  if (!verify(null, bytes, key, Buffer.from(sig, 'base64url'))) return null;
  return JSON.parse(bytes.toString('utf8'));
}
