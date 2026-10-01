import http from 'node:http';
import path from 'node:path';

import { createApp } from './lib/app.js';
import { loadConfig } from './lib/config.js';
import { Store } from './lib/db.js';
import { loadSigningKey, publicKeyString } from './lib/licensing.js';

const config = loadConfig();
if (!config.adminPassword) {
  console.error('Set ADMIN_PASSWORD (see README.md).');
  process.exit(1);
}
const signingKey = loadSigningKey(config.signingKeyFile);
const store = new Store(path.join(config.dataDir, 'orders.json'));
const server = http.createServer(createApp({ config, store, signingKey }));
server.listen(config.port, config.host, () => {
  console.log(`srle store on http://${config.host}:${config.port}`);
  console.log(`app public key: ${publicKeyString(signingKey)}`);
});
