#!/usr/bin/env python3
"""
FastSM push relay.

Mastodon delivers notifications via Web Push (RFC 8030/8291): an HTTP POST with
an end-to-end-encrypted body to a subscription endpoint. Apple devices can only
receive background notifications through APNs. This stateless relay bridges the
two: the device's APNs token is encoded into the endpoint URL, so no database is
needed. The encrypted body is forwarded verbatim (base64) inside the APNs
payload; the app's Notification Service Extension decrypts it on-device with the
subscription's private key.

Endpoint shape (registered with Mastodon by the app):
    https://<host>/relay/push/<env>/<apns-hex-token>
where <env> is "sandbox" (development builds) or "production" (TestFlight/App
Store), matching the device token's APNs environment.

Config via environment variables:
    APNS_KEY_PATH   path to the APNs auth key (.p8)
    APNS_KEY_ID     the key's ID (10 chars)
    APNS_TEAM_ID    Apple developer team id (e.g. 9QBYDAX396)
    APNS_TOPIC      app bundle id (me.masonasons.fastsm)
    RELAY_HOST      bind host (default 127.0.0.1)
    RELAY_PORT      bind port (default 8787)
"""

import base64
import os

from aiohttp import web
from aioapns import APNs, NotificationRequest, PushType

KEY_PATH = os.environ["APNS_KEY_PATH"]
# aioapns hands `key` straight to jwt.encode(), which needs the PEM key material
# itself — a file path would fail to parse ("Unable to load PEM file"). So read
# the .p8 contents here rather than passing the path through.
with open(KEY_PATH) as _key_file:
    KEY_PEM = _key_file.read()
KEY_ID = os.environ["APNS_KEY_ID"]
TEAM_ID = os.environ["APNS_TEAM_ID"]
TOPIC = os.environ["APNS_TOPIC"]
HOST = os.environ.get("RELAY_HOST", "127.0.0.1")
PORT = int(os.environ.get("RELAY_PORT", "8787"))

# One APNs client per environment; created lazily.
_clients: dict[str, APNs] = {}


def client_for(env: str) -> APNs:
    if env not in _clients:
        _clients[env] = APNs(
            key=KEY_PEM,
            key_id=KEY_ID,
            team_id=TEAM_ID,
            topic=TOPIC,
            use_sandbox=(env == "sandbox"),
        )
    return _clients[env]


async def handle_push(request: web.Request) -> web.Response:
    env = request.match_info["env"]
    token = request.match_info["token"]
    if env not in ("sandbox", "production"):
        return web.Response(status=400, text="bad env")

    body = await request.read()
    encoding = request.headers.get("Content-Encoding", "aes128gcm")

    # The aps alert is a placeholder; the Notification Service Extension replaces
    # it after decrypting. mutable-content=1 is what triggers the extension.
    message = {
        "aps": {
            "alert": {"title": "FastSM", "body": "New notification"},
            "mutable-content": 1,
            "sound": "default",
        },
        # Encrypted Web Push payload + its content encoding, for the extension.
        "fastsm_payload": base64.b64encode(body).decode("ascii"),
        "fastsm_encoding": encoding,
    }
    # Older aesgcm encoding carries keys in headers; forward them too.
    if "Encryption" in request.headers:
        message["fastsm_encryption"] = request.headers["Encryption"]
    if "Crypto-Key" in request.headers:
        message["fastsm_cryptokey"] = request.headers["Crypto-Key"]

    request_obj = NotificationRequest(
        device_token=token,
        message=message,
        push_type=PushType.ALERT,
    )
    try:
        result = await client_for(env).send_notification(request_obj)
    except Exception as exc:  # network/APNs transport error
        return web.Response(status=502, text=f"apns error: {exc}")

    if result.is_successful:
        return web.Response(status=201)
    # 410 = the token is no longer valid; tell Mastodon to drop the subscription.
    status = 410 if result.description == "Unregistered" else 502
    return web.Response(status=status, text=result.description or "apns failed")


async def handle_health(_: web.Request) -> web.Response:
    return web.Response(text="ok")


def make_app() -> web.Application:
    app = web.Application()
    app.router.add_post("/relay/push/{env}/{token}", handle_push)
    app.router.add_get("/relay/health", handle_health)
    return app


if __name__ == "__main__":
    web.run_app(make_app(), host=HOST, port=PORT)
