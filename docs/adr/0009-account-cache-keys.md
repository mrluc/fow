# Account keys for offline snapshots

Status: implemented as an opt-in. See the README for the endpoint and session lifecycle contract.

Keep the current device-key cache as the default. Apps that share a browser
profile across accounts can opt into server-derived keys for private snapshots.

## App integration

Configure FoW with an authenticated, same-origin key endpoint. Keep using the
existing region user ID for cache scope. The endpoint derives the scope from
the authenticated session and returns that scope and its key. Use the same
scope on both sides, including a tenant identifier where applicable.

FoW will send a random device UUID stored separately from the device encryption
key. The endpoint can use `FogOfWar.AccountKey.derive!/4` with a dedicated
server secret. Authenticate and authorize each request, use the application's
CSRF protection, and return `Cache-Control: no-store`. Phoenix continues to
own session cookies and cross-tab logout behavior.

After login, FoW will store one active account and its non-exportable key in
IndexedDB to support offline restarts. The app must await FoW's local lock
operation during explicit logout. The lock deletes the active account and key
without deleting ciphertext. A subsequent login can recover the same key.
An account change also replaces the shared slot.

## Browser behavior

Each private read checks the active slot in IndexedDB, and checks its generation
again before displaying decrypted content. A stale tab bound to a different
account can use public fallback. A fresh offline document can use the active
slot. Private writes wait for the matching key and must never fall back to the
device key or plaintext. Use a distinct record marker for account encryption.
Public snapshots and bundled pages continue to work with the default policy.

## Upgrading and rolling back

When opting in, purge existing private snapshots written under the shared
device key, including plaintext and fallback storage copies. Keep public
snapshots. Do not treat those old private records as eligible for reads in the
new mode. New visits populate the protected cache. Switching back to the
device-key mode requires wiping FoW storage before bringing the older client
back into use. Plan for tabs still running the previous client during rollout.

An unlocked browser can display the same content it can decrypt. The stronger
policy protects retained ciphertext after logout removes the key. It cannot
revoke copies made while a session was unlocked. Offline lock with deferred
server logout is outside this change.
