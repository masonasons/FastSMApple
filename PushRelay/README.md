# FastSM push relay

Stateless bridge: Mastodon Web Push → APNs. The device's APNs token is encoded
in the endpoint URL, so there's no database. Runs as a small Python service
behind Apache on masonasons.me.

## Endpoint

```
https://masonasons.me/relay/push/<env>/<apns-hex-token>
```

`<env>` is `sandbox` (dev builds) or `production` (TestFlight/App Store). The app
builds this URL from its APNs token and registers it as the Mastodon push
subscription endpoint.

## One-time server setup (run on the VPS)

```sh
# code + venv (no root)
mkdir -p ~/fastsm-push-relay && cd ~/fastsm-push-relay
# copy relay.py + requirements.txt here (rsync from the repo's PushRelay/)
python3 -m venv venv
./venv/bin/pip install -r requirements.txt

# secrets / config (chmod 600; never commit)
cat > relay.env <<'ENV'
APNS_KEY_PATH=/home/mew/fastsm-push-relay/AuthKey_XXXXXXXXXX.p8
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=9QBYDAX396
APNS_TOPIC=me.masonasons.fastsm
RELAY_HOST=127.0.0.1
RELAY_PORT=8787
ENV
chmod 600 relay.env
# put the APNs .p8 key next to it (chmod 600)
```

### systemd service (needs sudo)

```sh
sudo cp fastsm-push.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now fastsm-push
systemctl status fastsm-push          # verify running
curl -s localhost:8787/relay/health   # -> ok
```

### Apache reverse proxy (needs sudo)

Add to the masonasons.me **:443** vhost (enable modules first:
`sudo a2enmod proxy proxy_http`), then `sudo systemctl reload apache2`:

```apache
ProxyPass        /relay/ http://127.0.0.1:8787/relay/
ProxyPassReverse /relay/ http://127.0.0.1:8787/relay/
```

Verify externally: `curl https://masonasons.me/relay/health` → `ok`.

## Notes

- APNs token environment must match the build: dev installs use `sandbox`,
  TestFlight/App Store use `production`. The app picks the right `<env>` segment.
- Payload: the encrypted Web Push body is forwarded base64 in `fastsm_payload`;
  the app's Notification Service Extension decrypts it with the subscription's
  private key.
