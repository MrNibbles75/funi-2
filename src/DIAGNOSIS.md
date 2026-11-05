# Matthew's game: read-only multiplayer diagnosis
Checked November 5, 2026, approximately 4:34–4:37 PM EST (America/New_York).

## The answer in kid/parent language
The website is delivering the game, but the game's “listen for the other players” code is broken. Sending and listening use different code, so sending can work while receiving does not. Matthew already has a backend: a Google Firebase database. This is NOT an ENet game and there is no evidence that he needs to buy a Godot server to fix this particular version.

There is also a separate address/version problem: `/game/` currently returns 404. The newer multiplayer version is at the site's root `/`. PR #2 is still open and contains an older, single-player export. Merging that old export is not the multiplayer fix.

## What I inspected, and what I did not change
- Fresh clone at `/tmp/funi-2-diag`, as explicitly requested; main commit `02859973a67b49f7dba76e8925ad1be1e8a9815d`.
- All three remote branches: main, add-godot-export (`5f0b244`), add-rick-site (`ec9e7ce`). Reviewed all PRs: #2 open; #1 closed/merged, unrelated Rick Astley site.
- No `.gd`, `.tscn`, or `project.godot` source in any of those branch trees. I extracted both exported PCKs with a Python v4 PCK parser; every embedded file passed MD5. GDRE Tools v2.7.4 recovered scripts, scenes, and project settings. PCK engine version is 4.7.2, bytecode revision 4.5.0-stable (`ebc36a7`).
- Current main and the live root PCK are byte-identical: 46,708 bytes, SHA256 `3b5680b602329ffd4c272678ecdf73b59d5ee0e4f59056a3ae2ff2e674e4b1b1`.
- PR #2 pack is 9,376 bytes, SHA256 `593f4f9ade91b88c84e416e94fc998ee59238faf73c5e1ff2e24d620c6d7b28f`, only one script, just left/right movement.
- Searched visible repositories for both accounts. Other candidates: MrNibbles75/Shoot-With-Friends-ALPHA- is Python/Pygame (Main:1–6), not this Godot project; MrNibbles75/nfiguhdfiguhdf contains only a README. The old MrNibbles75/funi-2 URL resolves to ejniehaus/funi-2. Other visible ejniehaus repositories are unrelated web apps, Minecraft/Java, Python, or releases. No separate Godot source repository surfaced; this is not proof no private/unlisted/local source exists.
- No pushes, commits, PRs, merges, deployments, Firebase writes/deletes, purchases, or server configuration changes. I did NOT run the game itself, since it automatically writes player data. Runtime console reproduction remains a testing step.

## Live website checks
Base: https://matthew-game-git-ninetybound.vercel.app

| Path | GET result | Content type / size |
|---|---|---|
| /game/ | 404 | text/plain; Vercel NOT_FOUND |
| /game/index.html, index.js, index.pck, index.wasm | all 404 | text/plain |
| / | 200 | text/html; 5,438 bytes |
| /index.js | 200 | application/javascript; 315,645 bytes |
| /index.wasm | 200 | application/wasm; 37,902,138 bytes |
| /index.pck | 200 | application/octet-stream; 46,708 bytes |
| /index.audio.worklet.js | 200 | application/javascript; 7,298 bytes |
| /index.audio.position.worklet.js | 200 | application/javascript; 2,973 bytes |
| /index.png, index.icon.png, index.apple-touch-icon.png | all 200 | image/png |

No COOP/COEP headers were present. That is not the bug: live `index.html:115` says `const GODOT_THREADS_ENABLED = false;`; line 114 disables ensureCrossOriginIsolationHeaders. WASM MIME is correct. Files needed by the root version download successfully. This confirms delivery, not a complete browser runtime test.

## Existing backend is real and reachable
Recovered `Database.gd:3`:
```gdscript
var host = "https://godot-mmo-thang-default-rtdb.firebaseio.com"
```
`Database.gd:5–9` builds `/players/<id>.json` and `/players.json` URLs. This is Google Firebase Realtime Database, HTTPS port 443, not a WebSocket/Godot headless server. No ws/wss URL, IP, or custom port exists in these scripts, so a WebSocket handshake is not the appropriate probe.

Read-only curl probes from the box:
- GET `/players.json?shallow=true` returned 200 and nine player keys.
- GET `/players.json` with `Accept: text/event-stream` returned 200, `Content-Type: text/event-stream`, and an initial `event: put` snapshot containing player position/color data.
- Both responses allowed the exact Vercel Origin via Access-Control-Allow-Origin. SSE probe intentionally stopped after four seconds; curl's timeout after receiving the snapshot is expected for an open stream, not backend failure.
- No auth token was used for those reads. Writes/rules, account ownership, Firebase billing tier, and whether the records are fresh were NOT verified. Do not “fix” permissions by opening all writes publicly.

## Ranked root causes and evidence
All source paths below are recovered from CURRENT `/index.pck`, under `/tmp/funi-2-evidence/recovered-main/`. Line numbers refer to recovered readable source, not GitHub source files (they are not in GitHub).

### 1. Confirmed web receive blocker: full URL supplied where HTTPClientWeb requires a path
`SyncPlayerRemote.gd:25–29`:
```gdscript
http_client.request(
    HTTPClient.METHOD_POST,
    URLS.get_all_player_urls(),
    ["accept: text/event-stream"]
)
```
`URLS.get_all_player_urls()` returns `https://godot-mmo-thang-default-rtdb.firebaseio.com/players.json` (`Database.gd:8–9`). Godot **4.7.2's web implementation** rejects request URLs that do not begin with `/`, before making a fetch:
`platform/web/http_client_web.cpp:94`:
```cpp
ERR_FAIL_COND_V(!p_url.begins_with("/"), ERR_INVALID_PARAMETER);
```
Line 101 constructs scheme+host+port+path itself. This is a precise browser-specific explanation for why HTTPRequest sending can work while this HTTPClient receiving fails. The send side uses the higher-level HTTPRequest, for which full URLs are correct.

The return value is discarded. `SyncPlayerRemote.gd:31` prints “connection Succsesful!” even if request() just returned an error. This success message is not proof of a working receive stream.

### 2. Confirmed independent receive bug: POST is not a subscription
Same call uses METHOD_POST. Firebase SSE listening is a **GET** with `Accept: text/event-stream`. POST means create a new child record, not listen. Do NOT test the broken POST on production; it is a write. Changing only headers, CORS, or Vercel settings will not repair this method mismatch.

### 3. Confirmed stream/parser weaknesses, after fixing 1–2
- `SyncPlayerRemote.gd:41–46,93–103`: treats each network chunk as whole SSE messages. Network chunks may cut a JSON string in half. It discards partial messages rather than buffering across frames.
- `:100`: only accepts `put`; ignores Firebase `patch`, disconnect/cancel/auth_revoked events.
- `:63`: takes the last path component as player ID; nested `/123/position_x` updates would be misidentified. Current full-player PUTs generally generate `/123`, so this is a future/edge bug, not the first blocker.
- `:83–91`: queue_free() without `player_remote.erase(player_id)`. Later updates can target a freed node.
- No reconnect/backoff or response-code check in receive path.
- `:17–19`: synchronous polling loop without yielding. Avoid blocking in browser code, but do NOT claim this is the confirmed freeze here: 4.7.2 HTTPClientWeb poll changes resolving→connecting→connected in two synchronous polls. The rejected request URL is the much stronger finding.
- Godot web docs list HTTP streaming/chunk restrictions; don't assume a native SSE implementation will behave identically in browsers. Exact streaming behavior after fixing the definite errors still needs a browser test. A finite GET polling fallback is simpler to validate, or use the Firebase web SDK through JavaScriptBridge.

### 4. Separate confirmed deployment/version mismatch
Current `/game/` is missing, while root has multiplayer. PR #2 is an obsolete single-player snapshot: recovered-pr2/player.gd:1–12 only handles left/right motion; its node_2d.tscn has no networking nodes. Do not merge PR #2 as a “fix” without replacing its old export with the intended current build and deliberately choosing root or /game/.

### 5. Reliability/rendering bugs that can hide players or stale state
- `remote_player.gd:10` assigns JSON string color directly to Sprite2D.modulate (a Color). Explicitly parse using `Color.from_string(...)` rather than relying on conversion.
- `sync_player_local.gd:31–33` checks transport result but not HTTP status. A 401/403 HTTP response can arrive with successful transport.
- `:50–55`: advances last-sent JSON and sets pending before checking request() return. If request fails immediately, pending can stay true forever; if an HTTP write fails, unchanged state is not retried. Only acknowledge successful writes after a 2xx result, with backoff.
- `:35–37`: writes as fast as each request finishes while moving. Add a 5–10 Hz cap for this prototype; Firebase is not an ideal high-frequency action-game transport.
- `:14–23`: relies on desktop window-close notification and awaiting DELETE before quit. Browser tabs are not guaranteed to deliver this. Add server timestamp/last_seen and expire ghosts, or Firebase SDK presence/onDisconnect. Never rely on tab-close DELETE.
- `player.gd:4`: random six-digit IDs can collide. Prefer authenticated unique IDs plus session IDs.

## Requested killer checklist: what actually applies
- ENetMultiplayerPeer: absent, not the diagnosis.
- Browser create_server: absent.
- localhost/127.0.0.1/LAN address: absent.
- ws:// mixed content: absent; current backend is HTTPS.
- No backend deployed: false for this build; reachable Firebase backend exists.
- Wrong custom ports: no custom port present; HTTPS uses 443.
- Missing multiplayer_peer, wrong RPC annotations/authority, peer-1 assumptions: not applicable to current architecture. It uses HTTP JSON/SSE, not MultiplayerAPI.
- MultiplayerSpawner/Synchronizer: absent. Remote players are manually instantiated by SyncPlayerRemote.gd:77–78; local/remote scene references are present in node_2d.tscn:27–30 and player.tscn:29–31.
- poll(): DOES exist in receiver (:37) and startup (:18); the issue is not simply forgetting poll().
- WebSocket packet buffers: no WebSocket transport present.
- Audio gesture: no AudioStreamPlayer/audio logic in recovered scenes/scripts. Browsers may require a click for sound, but that cannot explain one-way player data here.

## Recommended fix plan A: repair the existing Firebase prototype first
This is the smallest, cheapest change. Edit Matthew's ORIGINAL Godot project; recovered project is a fallback if original source is lost. Store source and export presets in Git going forward. Do not edit generated WASM/JS or hand-patch the live pack.

1. In SyncPlayerRemote.gd, request **GET /players.json**, not POST/full URL. Check every Error and the HTTP response status, and show connection state on screen.
2. Yield between connection/request polls (or make it a per-frame state machine); keep the receiver asynchronous with timeout/reconnect/backoff.
3. Buffer complete SSE frames across chunks and decode only complete frames. Preserve partial UTF-8 safely. Handle put/patch/cancel/auth_revoked and redirect behavior. OR, for the first working version, replace long-lived SSE with a separate HTTPRequest that GETs the finite full snapshot every 0.25–0.5 seconds; compare snapshots, skip self, update others, remove absent players. Do not share that HTTPRequest with the PUT node.
4. Parse color explicitly, erase freed player entries, validate data shapes, add retry/error handling and throttling, fix presence.
5. Use authenticated Firebase identities and narrowly scoped security rules. Do not embed service account/admin secrets in a web export. Existing unauthenticated reads were observed, not unauthenticated writes.

Core receive request correction (inside an asynchronous state machine, once connected):
```gdscript
var err := http_client.request(
    HTTPClient.METHOD_GET,
    "/players.json",
    PackedStringArray(["Accept: text/event-stream"])
)
if err != OK:
    push_error("Player subscription failed: %s" % error_string(err))
    return
# Don't announce success until actual HTTP response is 200.
```

Other small corrections:
```gdscript
# remote_player.gd, update_from_event:
$Sprite2D.modulate = Color.from_string(str(player_data.get("color", "ffffff")), Color.WHITE)

# SyncPlayerRemote.gd, delete_player after retrieving the node:
player_remote.erase(player_id)
player.queue_free()
```

A finite snapshot request uses a FULL URL because HTTPRequest is higher-level:
```gdscript
# Dedicated HTTPRequest node, not the existing write node.
# Call from a 0.5s Timer only when no read is pending.
var err := $ReadPlayers.request(URLS.get_all_player_urls())
# On request_completed: require RESULT_SUCCESS and HTTP 200,
# JSON.parse_string(body.get_string_from_utf8()), validate Dictionary,
# reconcile full snapshot; clear pending on every completion/error.
```

## Optional plan B: real Godot multiplayer over secure WebSockets
This is an architectural replacement, not a required fix for the present Firebase bug. Use it for a faster game/server-authoritative gameplay. Vercel keeps serving the static web export. A separate always-running Linux Godot headless process hosts WebSocketMultiplayerPeer. Browser clients cannot host ENet or WebSocket servers. Both ends must use compatible Godot versions and the same RPC scene/path layout. Remove/disable Firebase sync if replacing it; do not run two conflicting replication systems.

Shared Network.gd startup skeleton (not full player spawning/gameplay):
```gdscript
extends Node
var peer := WebSocketMultiplayerPeer.new()

func _ready() -> void:
    multiplayer.connected_to_server.connect(_connected)
    multiplayer.connection_failed.connect(_failed)
    multiplayer.server_disconnected.connect(_failed)
    if DisplayServer.get_name() == "headless":
        start_server()
    # Web UI's Join button calls join_server(). Never host in the browser.

func start_server() -> void:
    if OS.has_feature("web"):
        return
    var text := OS.get_environment("PORT")
    var port := 8080 if text.is_empty() else int(text)
    var err := peer.create_server(port, "0.0.0.0")
    if err != OK:
        push_error(error_string(err))
        return
    multiplayer.multiplayer_peer = peer
    print("Server listening on ", port)

func join_server() -> void:
    var err := peer.create_client("wss://YOUR-APP-HOST/")
    if err != OK:
        push_error(error_string(err))
        return
    multiplayer.multiplayer_peer = peer
    # create_client OK means started, NOT connected.

func _connected() -> void:
    print("Connected as ", multiplayer.get_unique_id())

func _failed() -> void:
    push_warning("Disconnected; show Retry button")
```
SceneTree polls MultiplayerAPI by default; do not add a busy loop. If auto-poll is deliberately disabled, call multiplayer.poll() once per frame. Keep real references to the peer.

Authority/RPC plan:
- Server is peer 1 in Godot's high-level client/server API. Do not reuse Firebase random player IDs as network peer IDs.
- Server owns spawning and authoritative state. Add MultiplayerSpawner whose spawn_path points to the identical Players container on all peers, and configure the player scene as spawnable. Server instantiates with stable peer-ID names and sets identity/authority BEFORE add_child. Late joiners must receive all current players.
- Keep movement/state MultiplayerSynchronizer authority on server. If using client-authoritative input, put that input synchronizer under a separate node whose authority is set to the owning peer consistently on every peer. Changing authority on one machine alone is insufficient.
- Client input RPC must permit any_peer, then server validates sender, bounds, rate, and maps it to the correct player. Server state RPC should be authority-only. Example shape:
```gdscript
@rpc("any_peer", "call_remote", "reliable")
func submit_input(direction: Vector2) -> void:
    if not multiplayer.is_server():
        return
    var sender := multiplayer.get_remote_sender_id()
    # Verify sender is a connected player; reject nonfinite/invalid input.
    # Simulate only that sender's player; clamp direction/speed.
    # Then server broadcasts authoritative state, not just an echo to sender.

# Client, only after connected:
# submit_input.rpc_id(1, direction)
```
- For a minimal prototype, use reliable RPCs; WebSocket is TCP, so unreliable flags do not remove TCP head-of-line delay. Send bounded updates at 10–20 Hz, not giant world packets every frame. Monitor queued bytes and disconnects before increasing buffers.

TLS/ports: public browser URL must be `wss://host/` on 443. Provider proxy terminates TLS and forwards WebSocket Upgrade to the Godot process on its private `$PORT`/8080. Bind 0.0.0.0, match the provider's target port, and permit Upgrade/Connection headers. Plain internal ws behind a trusted proxy is fine; do not put ws:// in the HTTPS web client or use insecure certificate bypasses. Use one server instance initially; random load balancing across unrelated in-memory rooms breaks shared state. Ensure provider health checks work (TCP where supported, otherwise an HTTP health endpoint/proxy).

Potential hosts, approximate currently published USD prices, NOT purchases:
- Render: Docker web service, built-in TLS/WebSockets. Free 512 MB prototype tier has limits/sleep/cold starts; paid 512 MB compute is $7/month, plus any overages. Simple route for a family prototype, but sleeping/redeploying disconnects games.
- Railway: Docker service and generated HTTPS domain/WebSocket routing; listen on PORT. Free plan currently $1/month usage credit is limited, not a promise of a continuously running free Godot server. Hobby $5/month includes $5 usage; extra usage can cost more.
- Fly.io: Linux Machine, TLS proxy, internal port mapping; 512 MB shared CPU example about $3.69/month in cheapest US regions, 1 GB about $6.70, plus traffic/storage/other charges. Size from measured memory, not smallest advertised instance.
No service was created and no money spent. Eric must explicitly approve any spending/deployment. Repairing Firebase first avoids assuming a new paid server is necessary.

Headless deployment shape: export a dedicated Linux server build using the matching Godot version, package it in Docker, run `./server.x86_64 --headless`, load a network/world scene without local-only camera/input dependencies, log joins/leaves/RPCs/errors. Don't simply run the existing Firebase client scene headless and expect it to become a server.

## Testing plan (future, requires an approved test environment for writes)
1. Agree the canonical URL and version. Re-export the CURRENT project, not PR #2's old pack. Verify root or /game/ page and every asset is 200; check correct MIME and new pack hash. Hard refresh/unregister an old service worker if relevant.
2. Start with a separate Firebase test database/room. Browser DevTools Console and Network open. Confirm send returns 2xx; receive appears as GET /players.json, not POST, with 200. Absence of a receive network request strongly matches the URL validation bug.
3. Two different browser windows/devices, both visible (background tabs may pause). Move each independently and verify the OTHER window sees movement and color. Include desktop editor ↔ browser. A local moving character alone proves nothing about receiving.
4. Test initial snapshot, late join, simultaneous movement, disconnect/tab-close, reconnect, temporary network loss, malformed data, expired auth/rules denial, and fragmented/coalesced SSE frames. Verify no ghosts or freed-node errors.
5. If switching to WebSockets: verify TLS certificate and successful 101 Upgrade on actual host/path, server logs both peer IDs, bidirectional RPCs, late join/spawn, authority, and state broadcast. A handshake alone doesn't prove Godot multiplayer packets work. Check traffic from another network, not just localhost.
6. Record explicit pass criteria: both players appear within one second on a stable connection, both movement directions replicate, disconnect cleanup works, no console errors, no continuous retry flood, and no writes to production during diagnosis.

## Sources and evidence locations
- Whole evidence directory: `/tmp/funi-2-evidence/`.
- Recovered current source: `recovered-main/`; old PR source: `recovered-pr2/`.
- Raw extracted files and MD5-checked parser: `unpacked/`, `unpack.py`.
- Saved live assets/headers: `live/`; backend read/SSE evidence: `firebase-*.headers`, `firebase-sse.txt` (contains game state; keep local, don't publish unnecessarily).
- Exact web URL validation: https://github.com/godotengine/godot/blob/4.7.2-stable/platform/web/http_client_web.cpp#L94 (also saved locally).
- HTTPClient API path semantics: https://docs.godotengine.org/en/stable/classes/class_httpclient.html
- Firebase GET/SSE and event semantics: https://firebase.google.com/docs/database/rest/retrieve-data#section-rest-streaming
- Browser networking/audio/header restrictions: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
- WebSocket peer API: https://docs.godotengine.org/en/stable/classes/class_websocketmultiplayerpeer.html
- Host pricing: https://render.com/pricing ; https://railway.com/pricing ; https://docs.fly.io/about/pricing
