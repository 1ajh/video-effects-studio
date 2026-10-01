# srle.ajh.wtf

The SRLE Studio store, set up like kit.ajh.wtf:

1. A buyer picks Discord, TikTok or somewhere else, types their handle and gets an order code (`SRLE-XXXX-XXXX`) and a private order page to bookmark.
2. They DM you the code and pay by Cash App or Apple Pay.
3. You find the order in `/admin` and press **Mark paid**: their order page now shows a license key and the download links.
4. They paste the key into SRLE Studio. The app activates it once online (`POST /api/activate`) and gets back an activation signed with the store's Ed25519 key, which it checks offline from then on. A key works on up to 3 computers; the app's **Deactivate this computer** frees one, and so does **Reset computers** in the admin page.

No card details, emails or cookies for buyers. Node 20 or newer, no dependencies.

## Run it on the VPS

```sh
# Copy this folder to the server, then:
cd /srv/srle-store
node tools/keygen.js            # creates data/signing-key.pem and prints the app's public key
ADMIN_PASSWORD='something long' node server.js
```

`tools/keygen.js` prints the **public key for the app**. Put it in the code repository's Actions variables as `SRLE_LICENSE_PUBLIC_KEY` (Settings → Secrets and variables → Actions → Variables): release builds are made with it, and a build without it can't unlock. Back up `data/signing-key.pem`: if it's lost, every app build has to be remade with a new key, and existing activations stop being valid on reinstall.

### Settings (environment variables)

| Variable | Default | |
| --- | --- | --- |
| `ADMIN_PASSWORD` | (required) | Password for `/admin` |
| `PORT`, `HOST` | `8787`, `127.0.0.1` | Where it listens (keep it on localhost behind your proxy) |
| `DATA_DIR` | `./data` | Orders (`orders.json`) and the signing key |
| `SIGNING_KEY_FILE` | `$DATA_DIR/signing-key.pem` | |
| `TRUST_PROXY` | off | Set `1` behind nginx/Caddy so rate limits see real addresses |
| `SITE_URL` | `https://srle.ajh.wtf` | |
| `PRICE` | `50` | |
| `PAY_WITH` | `Cash App or Apple Pay` | |
| `CONTACT_DISCORD`, `CONTACT_TIKTOK` | `ajh3d`, `ajh18` | |
| `MAX_ACTIVATIONS` | `3` | Computers per key |
| `DOWNLOAD_BASE` | `https://github.com/1ajh/srle-studio/releases/latest/download` | Where the order page's download links point |

### systemd

```ini
# /etc/systemd/system/srle-store.service
[Unit]
Description=srle.ajh.wtf store
After=network.target

[Service]
WorkingDirectory=/srv/srle-store
ExecStart=/usr/bin/node server.js
Environment=TRUST_PROXY=1
EnvironmentFile=/srv/srle-store/.env
Restart=always
User=www-data

[Install]
WantedBy=multi-user.target
```

Put `ADMIN_PASSWORD=...` in `/srv/srle-store/.env` (mode 600), then `systemctl enable --now srle-store`.

### Proxy

Caddy:

```
srle.ajh.wtf {
	reverse_proxy 127.0.0.1:8787
}
```

nginx:

```nginx
server {
    server_name srle.ajh.wtf;
    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
    }
    # listen 443 ssl; plus your certificate lines (certbot adds them)
}
```

## Tests

```sh
npm test
```
