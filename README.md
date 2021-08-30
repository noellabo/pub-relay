pub-relay (fork by noellabo)
=========

...is a service-type ActivityPub actor that will re-broadcast anything sent to it to anyone who subscribes to it.

![](https://i.imgur.com/5q8db54.jpg)

Endpoints:

- `GET /actor`
- `POST /inbox`
- `GET /.well-known/webfinger`
- `GET /.well-known/nodeinfo`
- `GET /nodeinfo/2.0`
- `GET /stats`

Operations:

- for Mastodon or compatible implementation
    - Send a Follow activity to the inbox to subscribe
        - Object: `https://www.w3.org/ns/activitystreams#Public`
    - Send an Undo of Follow activity to the inbox to unsubscribe
        - Object of object: `https://www.w3.org/ns/activitystreams#Public`
- for Pleroma or compatible implementation
    - Follow `actor` with mix command or pleroma_ctl
        - `MIX_ENV=prod mix pleroma.relay follow https://your.relay.hostname/actor`
        - `./bin/pleroma_ctl relay follow https://your.relay.hostname/actor`
    - Unfollow `actor` with mix command or pleroma_ctl
        - `MIX_ENV=prod mix pleroma.relay unfollow https://your.relay.hostname/actor`
        - `./bin/pleroma_ctl relay unfollow https://your.relay.hostname/actor`
- Send anything else to the inbox to broadcast it
    - Supported types: `Create`, `Update`, `Delete`, `Announce`, `Undo`, `Move`, `Like`, `Add`, `Remove`

Requirements:

- All requests must be HTTP-signed with a valid actor
- Only payloads that contain a linked-data signature will be re-broadcast
    - If the relay cannot re-broadcast, deliver an announce activity
- Only payloads addressed to `https://www.w3.org/ns/activitystreams#Public` will be re-broadcast
    - Deliver all activities except `Create`

## Installation

Download the binaries.

## Usage

TODO

## Contributors

- [RX14](https://source.joinmastodon.org/RX14) creator, maintainer
- [noellabo](https://github.com/noellabo)
