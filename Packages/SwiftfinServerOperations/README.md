# SwiftfinServerOperations

Swift 6 actor-owned administration API. Composition injects one authenticated request executor; the owner never resolves a global account, stores credentials or imports UI. Existing administrative actions are invoked only by their explicit UI actions. All tests use synthetic request senders; no server maintenance or media operation runs during validation.

Dependencies: SwiftfinNetworking, SwiftfinCollections, exact Jellyfin SDK 3.2.0/Get 2.2.1. User administration and server operations are separate peers with no edge between them.

ServerOperationsPolicy owns remote-session control availability from immutable session/user capability inputs. Native confirmation/menus remain composition; originating models retain one bound command client.
