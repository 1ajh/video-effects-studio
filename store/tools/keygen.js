// Prints the public key the app has to be built with, creating the signing
// key on first use. Run on the server: node tools/keygen.js
import { loadConfig } from '../lib/config.js';
import { loadSigningKey, publicKeyString } from '../lib/licensing.js';

const config = loadConfig();
const key = loadSigningKey(config.signingKeyFile);
console.log(`signing key: ${config.signingKeyFile} (keep it secret, back it up)`);
console.log(`public key for the app: ${publicKeyString(key)}`);
