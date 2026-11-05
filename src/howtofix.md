# How to fix web multiplayer (funi-2) 🇩🇪🥨

**Symptom:** Multiplayer works on your computer. On the website, the game sends player data but never receives anyone else's.

Your game doesn't use a Godot server. It uses a Google Firebase Realtime Database:
`https://godot-mmo-thang-default-rtdb.firebaseio.com`. The database is up and working.
Sending your position uses `HTTPRequest`, and listening for other players uses a different piece of code (`HTTPClient` in `SyncPlayerRemote.gd`). That listener is what's broken.

> Note: your `.gd` and `.tscn` source files aren't in GitHub. I rebuilt this code from the exported game (`index.pck`), so line numbers are approximate.

## 1. Root causes (in `SyncPlayerRemote.gd`, around lines 25-31)
```gdscript
http_client.request(HTTPClient.METHOD_POST, URLS.get_all_player_urls(), ["accept: text/event-stream"])
print("connection Succsesful!")
```
- **It uses POST instead of GET.** POST tells Firebase to *create a new record*. To *subscribe* to live updates, you need GET with `Accept: text/event-stream`.
- **It uses a full URL instead of a path.** In the browser build (Godot 4.7.2), `HTTPClient.request()` only accepts a path that starts with `/`, like `/players.json`. A full `https://...` URL gets rejected on the web, even though desktop allows it.
- **It hides the error.** The code ignores what `request()` returns and prints "connection Succsesful!" no matter what happened.

## 2. Smaller bugs
- Incoming data isn't buffered, so a message that arrives split across two chunks gets thrown away.
- Only `put` events are handled. Firebase `patch` events are ignored.
- When a player leaves, the node is freed but stays in the `player_remote` list, so later updates can crash on it. Use `erase()` to remove it.
- The color is read as text but never converted. Use `Color.from_string(...)`.
- Positions are sent as fast as possible. Cap that at about 5-10 times per second.
- Failed saves aren't checked: an HTTP 401 or 403 error counts as "success".
- Nothing reconnects if the connection drops.

## 3. Deployment mix-up
- The current multiplayer build is live at the site root: https://matthew-game-git-ninetybound.vercel.app/
- PR #2 holds an older **single-player** build, and `/game/` shows "not found". **Don't merge PR #2.**

## 4. Fix steps
```gdscript
var err = http_client.connect_to_host("godot-mmo-thang-default-rtdb.firebaseio.com", 443, TLSOptions.client())
# ...poll until STATUS_CONNECTED, then:
err = http_client.request(HTTPClient.METHOD_GET, "/players.json", ["Accept: text/event-stream"])
if err != OK:
    push_error("Listen failed: %s" % err)
```
1. Make the change above, and always check the value that comes back.
2. Add a text buffer. Keep the leftover text from each chunk and only parse complete `event:` / `data:` blocks.
3. Handle `patch` events the same way as `put` events.
4. Erase players from the list when they leave, convert colors with `Color.from_string()`, cap sends at 5-10 per second, check HTTP status codes, and reconnect if the connection drops.
5. **Fallback:** if live streaming still acts up in browsers, use `HTTPRequest` to fetch `/players.json` about 5 times per second. It's simple and reliable.

**No new server and no money needed.** Prost! 🍺
