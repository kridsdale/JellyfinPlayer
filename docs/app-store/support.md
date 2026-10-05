# KidsJellyFin support

KidsJellyFin is maintained by Kevin Ridsdale. Contact the maintainer by [opening a support issue](https://github.com/kridsdale/KidsJellyFin/issues/new) or reviewing [existing reports](https://github.com/kridsdale/KidsJellyFin/issues).

Please describe your Apple TV model, tvOS version, app version, and the steps that led to the problem. Do not publish passwords, access tokens, private server addresses, media paths, private media titles, or information about children.

## Setup

You need your own compatible Jellyfin server and a non-administrator account with access restricted to two libraries named **Kid TV** and **Kid Movies**. Add only media you want available to children to those libraries. Setup and library management are a parent's responsibility. Connect to the server and choose a parent PIN in the app. This app does not supply media or subscription content.

## Playback and connection help

Confirm your Apple TV can reach the server on the same network or your configured remote connection. Verify playback with the same restricted account in Jellyfin's web client. Open Parents > Connection & Help in KidsJellyFin to inspect the connection and playback-state sync status. If a title cannot be played, report the behavior without posting the media file or credentials.

See the [build and recovery guide](../kids-release-guide.md), [privacy policy](privacy.md), and [current validation record](../kids-validation.md). This project is under active development; physical-device, format, and cross-device iCloud verification remain release checks.
