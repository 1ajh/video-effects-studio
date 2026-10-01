import path from 'node:path';

/** Settings from the environment (see README.md). */
export function loadConfig(env = process.env) {
  const dataDir = path.resolve(env.DATA_DIR || './data');
  return {
    port: Number(env.PORT || 8787),
    host: env.HOST || '127.0.0.1',
    dataDir,
    signingKeyFile: path.resolve(env.SIGNING_KEY_FILE || path.join(dataDir, 'signing-key.pem')),
    adminPassword: env.ADMIN_PASSWORD || '',
    trustProxy: env.TRUST_PROXY === '1',
    siteUrl: (env.SITE_URL || 'https://srle.ajh.wtf').replace(/\/+$/, ''),
    price: env.PRICE || '50',
    payWith: env.PAY_WITH || 'Cash App or Apple Pay',
    discord: env.CONTACT_DISCORD || 'ajh3d',
    tiktok: env.CONTACT_TIKTOK || 'ajh18',
    maxActivations: Number(env.MAX_ACTIVATIONS || 3),
    downloadBase: (env.DOWNLOAD_BASE || 'https://github.com/1ajh/srle-studio/releases/latest/download').replace(/\/+$/, ''),
    releasesUrl: env.RELEASES_URL || 'https://github.com/1ajh/srle-studio/releases',
  };
}
