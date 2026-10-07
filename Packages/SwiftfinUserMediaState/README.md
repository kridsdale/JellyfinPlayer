# SwiftfinUserMediaState

Owns scoped played/favorite commands, response item-identity validation and
mutation completion epochs. UI adapters retain optimistic display changes and
notifications; only the newest operation for the displayed item may publish or
roll back. Exact session checks reject account/connection replacement. This is
Jellyfin user state; KidsPersistence local/cloud storage remains separate.
