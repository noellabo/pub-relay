pub-relay
=========

...is a service-type ActivityPub actor that will re-broadcast anything sent to it to anyone who subscribes to it.

![](https://i.imgur.com/5q8db54.jpg)

Endpoints:

- `GET /actor`
- `POST /inbox`
- `GET /.well-known/webfinger`

Operations:

- Send a Follow activity to the inbox to subscribe
  (Object: `https://www.w3.org/ns/activitystreams#Public`)
- Send an Undo of Follow activity to the inbox to unsubscribe
  (Object of object: `https://www.w3.org/ns/activitystreams#Public`)
- Send anything else to the inbox to broadcast it
  (Supported types: `Create`, `Update`, `Delete`, `Announce`, `Undo`)

Requirements:

- All requests must be HTTP-signed with a valid actor
- Only payloads that contain a linked-data signature will be re-broadcast
- Only payloads addressed to `https://www.w3.org/ns/activitystreams#Public` will be re-broadcast

## Installation

Download the binaries.

## Usage

TODO

## Contributors

- [RX14](https://source.joinmastodon.org/RX14) creator, maintainer
