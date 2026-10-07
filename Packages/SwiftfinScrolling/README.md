# SwiftfinScrolling

Owns synchronized native UIKit horizontal/vertical scroll observations, weak registrations, recursion guards, centering/reset and connect/disconnect generations. No app factories, settings, account or media SDK dependencies. Seven main-actor commands register platform scroll views and manage their lifetime; internal native handles never leave the owner. ScrollCentering is a pure finite-input geometry helper.

Two explicit KVO bridges preserve synchronous recursion guards when UIKit delivers on the main thread. UIKit scroll-view mutations are main-actor APIs; a defensive off-thread notification hops through a main-actor task. Both paths check connection generation and current registration before reading or mutating UI. Disconnect invalidates all native leases before reconnecting. These are narrowly documented synchronous SDK bridges, not blanket concurrency suppressions.

Foundation geometry contracts run through SwiftPM. Adjacent UIKit contracts exercise real KVO synchronization, tolerance/axis independence, duplicate registration, disconnect/reconnect, centering/reset and owner release in the tvOS validation host. A macOS SwiftPM pass does not establish UIKit acceptance.
