---
status: proposed
date: 2026-11-06
---

# Frontier becomes a multiplayer game with authoritative offline consequences

Frontier should reward staying alive and reconnecting. Players can explore remembered terrain while disconnected, but they lose health and remain subject to server validation when they return. A roaming Split Brain beast and other players make remaining online dangerous too. Moving between online and offline states therefore becomes part of the game.

This is the requested design for the separate Frontier example. It introduces game-specific client behavior and server authority. Implementation follows a later pass.

## Health and offline time

Every player has 100 total health. While offline, health drops by 10 percentage points each second until it reaches 10. At that threshold, damage drops to 1 percentage point per second. Health still reaches zero and the player dies. The accepted survival time from full health is 19 seconds offline. The multiplayer client predicts down to 1 HP and shows death or respawn when it receives the server state.

The client hook displays this countdown while disconnected. Its rules come from server-provided component parameters so the values can be changed in one place. The server enforces the same rules against authoritative player state. Reconnecting cannot reset damage or replace server health with the client's displayed health.

Starting at 100 and taking the first damage after one second, nine 10-point hits reach 10 at second 9. Ten further 1-point hits reach zero at second 19. This 19-second schedule is accepted.

“Minimum 10%” describes the end of the fast-damage phase. Health can still reach zero.

## Healing, death and respawn

While connected, living players recover 10 health per second, capped at 100. If a player moved during the tick being processed, reduce the healing rate for that tick to 5 health per second. Apply these rates using the central game's 100 ms tick duration. The server decides whether movement occurred and enforces the healing rate. Supply the same parameters to the client hook for its presentation.

At zero health, play an appropriate client-side “you died” animation. Record the authoritative tick of death. Require a five-second timeout, equivalent to 50 game ticks, during which the player continues seeing the square where they died and can see nothing else. Death and the timeout prevent travel or attacks. Connected healing does not skip the death sequence.

After the timeout, the server pushes a respawn. Clear that player's server-side exploration bitmap completely, choose a random spawn coordinate, and push an event instructing the client to clear the player's Fog of War cache. This resets exploration on both sides. Then show the new spawn square through the normal server-authorized rendering path.

Apply the death sequence, cache-reset event and respawn location consistently to every connected tab for that player. A disconnected view must receive the authoritative death or respawn state when it reconnects. A local animation ending cannot authorize respawn before the server's death-tick deadline.

The exact death animation and health assigned on respawn remain implementation choices to settle. The required sequence is death, five seconds viewing only the death square, a server-directed cache and exploration reset, and a random spawn.

## Reconnection and movement

Reconnecting should look like teleporting to whichever coordinate the player is currently viewing offline, provided the server accepts that position. The client knows its displayed position during disconnection. This is deliberately a small amount of split brain, contained in the Frontier hook and configured by the server.

Each move empties a move bar. The bar takes one second to recharge, and offline moves also empty it. The client should enforce that pacing for its presentation, while the server remains responsible for deciding whether a move is legal.

On each central game tick, process any player reconnection and compare the requested position with the previous authoritative position and the ticks elapsed since then. If the player travelled farther than that time permits, return them to their original authoritative position. Push the correction from the server and navigate their view there. A cached URL or a client-side timer cannot establish that a move was valid.

For the existing coordinate map, distance and timing can be calculated cheaply. Its current eight-neighbor movement permits diagonal steps, so the number of unobstructed steps between two coordinates is the maximum of the two absolute coordinate differences. Movement-budget boundaries, including any move already charged at disconnection, must be defined consistently with the move bar. Future maps with obstacles may require path-distance calculation. A faster NIF is a possible future option if that calculation becomes expensive.

The server needs the final viewed coordinate on reconnect, even if the reconnecting LiveView initially carries older route state. The hook can provide the requested position, but the server validates it before making it authoritative.

Reconnection acceptance requires both a valid distance budget and an explored destination in the player's existing server-side fog bitmap. Check exploration before adding any new bit for the proposed destination. A nearby coordinate is still unauthorized if it was never explored. If either check fails, retain the previous authoritative position and push the correction. This exploration check is an authorization boundary, not just a visual choice.

## Online and offline dangers

The giant **Split Brain beast** moves randomly from square to square on the server. Its state and movement continue independently of the player's client. Players cannot determine its real position by inventing local state. Seeing the beast appear or move is driven by server state.

Other players are also dangerous. A player can attack only with a full move bar. Attacking consumes that charge completely and costs the attacker 20 health, meaning 20% of the total 100. An attack deals 100 damage to another player on the attacker's square.

A future extension could deal 20 damage to a target on an adjoining square. That extension is separate from the initial same-square attack.

The server validates attack eligibility, applies the health cost and target damage, records the attack tick, and publishes the resulting event. Beast damage, movement cadence, attack targeting among several occupants, and the effect of an attacker spending their last 20 health still need rules. The current request establishes the beast's roaming behavior but does not assign it a damage amount.

Online players can face the beast and other players. Offline players face the health countdown and uncertainty about the current occupants of a square. Rapid disconnects, reconnects, moves and attacks must all be evaluated against the same server health and tick history.

## Player identity and tabs

Key player state by a user ID where one exists, otherwise by a stable session ID. The intended desktop-web behavior is that tabs belonging to the same player share health, location, movement charge, attack history and fog of war. Moving in one tab should move that player's view in the other tabs.

The session ID should be supplied by the server session and reused across tabs. Separate LiveView process IDs would create separate players and would not meet this requirement. The native mobile and desktop wrappers do not currently have the same multiple-tab interaction, but should use the same player model.

A remaining connection rule needs definition. If one tab disconnects while another remains live, decide whether “offline” belongs to the player or to that tab's speculative view. Track the connected views so a closing or reconnecting tab cannot incorrectly overwrite the player's connection state. Client countdown display and server damage must agree with the selected rule.

## Central game process and ticks

Use a central game GenServer with a 100 ms periodic tick. Measure gameplay time in ticks, with ten ticks representing one second.

The game server owns authoritative state and writes it to ETS after every change. A Player module holds the rules for whether a player can move, attack, survive, reconnect or accept a requested destination. Consult those rules when handling action attempts.

Keep these fields together in each player's record:

- Player identity, using the user ID or stable session ID.
- Health.
- Fog-of-war bitmap.
- Last known authoritative coordinate as a `{lat, lon}` tuple, accepting its storage overhead.
- Last move tick.
- Last attack tick.
- Last offline tick.
- Last online tick.
- Tick of death, when dead, to enforce the five-second respawn timeout.

Other state needed to track connected views, entities and beast position belongs alongside the game's authoritative state as appropriate. Any client-supplied value is an action request, rather than an authoritative update.

Elapsed-time policy for a delayed tick, server restart or complete server outage needs a separate decision. The client can keep displaying its countdown while the server is unreachable, but enforcing that interval after the game process itself has stopped requires a defined clock and persistence policy.

## Compact exploration state

The 4 × 4 world needs one explored bit per square. Represent each player's exploration as a 16-bit bitmap, a two-byte logical payload, kept with the rest of the player's record. The actual ETS record also has Erlang term overhead.

Use a deterministic mapping from coordinates to bits, for example `lat * 4 + lon`. Accumulate exploration on the server when an accepted server navigation lets that player see the square. Share this mask across the player's tabs.

Configured public preload squares are trusted initial knowledge. Game.Rules supplies the same square list to server player registration and browser preloading. Grant those squares when a player connects, including existing player records created before this rule. Other reconnect destinations still require authoritative exploration. Respawn clears remembered routes and the server bitmap; presenting the new spawn records that square, and a later fresh connection grants the configured public baseline again.

## Cheap map reads and entity visibility

A coordinate LiveView should call a Map module to obtain the relevant state from ETS. The game server writes that same ETS table. Both the initial static render and subsequent live renders should use cheap, deterministic reads, without calling the game GenServer synchronously for each rendered item.

Render moving player and AI entities only on the viewing player's square. The server must not include their positions elsewhere on the map and depend on CSS to hide them. Per-player server exploration is possible because seeing a square required an accepted server navigation.

The current example renders the whole map and hides unexplored terrain with CSS. Revisit that arrangement now that tile contents are dynamic. The current square may render whatever is appropriate there. A deliberately small “cool!” text in an undiscovered black square would be a playful demonstration of content being covered by the client's unexplored-square styling. That demonstration must not reveal moving entities outside the viewing player's square.

Cached content can retain an older presentation of a previously viewed square. Its entities are remembered observations until the server supplies current state. The policy for showing those stale entity observations offline should be explicit.

## ETS indexes, events and LiveView streams

The game can maintain a coordinate-to-occupants index alongside the player records, analogous to keeping both sides of an entry. A query for “which sessions occupy this coordinate?” should return an ordered list. Update the player location and the coordinate index consistently when moving, reconnecting, correcting a position or removing a dead player.

The game server broadcasts moves and attacks. Initially every LiveView can subscribe to all game events and decide whether an event pertains to its player or current square. Do not broadcast a complete map to every player on each update.

When an event concerns the current square, its viewing LiveViews update the affected markup or push the required Phoenix events. An event for the same player in another tab must also move or correct that tab. Each connected view can read fresh state from ETS without blocking on the game process.

Use LiveView streams for rendered tiles and their contents so each player LiveView does not retain its own full copy of the rendered map and entity data. The map is small, but per-player copies of all render input should not become the design. Streams need stable tile and entity IDs and updates scoped to the affected entries.

## Multiple occupants and animation

Several entities can share a square. Give them deterministic visual jitter entirely on the client. A simple implementation is a deterministically ordered server list rendered as list markup, with CSS `nth-child` offsets. The client derives display positions from that order.

Animate entity transitions deterministically, using the same general approach already used for the scout. Stable entity identities let a move be recognized across updates even when several entities share a tile.

Entities leaving the visible square should disappear. Their departure animation can send them in a consistent direction or to a fixed exit location while fading them out. The server should not reveal their actual subsequent positions outside the viewer's square merely to animate a departure.

Account for list reordering when occupants arrive or leave so jitter remains predictable. Exact offsets, exit direction, animation durations and the choice of a fixed ordering key remain presentation details.

## Decisions still needed

Before implementation, resolve player-wide versus per-tab connection status and movement-budget boundaries. Define the remaining combat and beast rules, choose respawn health, and decide how to account for time when the game server itself is down. The 19-second offline damage schedule, connected healing rates, five-second death timeout, random respawn, cache reset and explored-destination authorization are established above.

These questions do not change the core arrangement. The server owns player state and gameplay outcomes. A parameterized client hook presents offline progress, and the server reconciles the viewed position when connectivity returns.

## First implementation slice

The example now has a supervised shadow Game process ticking every 100 ms and writing observations to protected ETS. The read module exposes player and occupant queries. Connected LiveViews echo coordinate changes under the WebSocket cookie session ID and the game monitors their lifecycles. Static export renders do not create players.

The server component supplies the move recharge duration and maximum health to the client. The orange move bar recharges visually after online or cached navigation. Purple health stays at its initial full value, and the gray connection bar reflects socket state. This slice adds no gameplay enforcement or synchronization of other tabs.

## Rule engine and development inspection

Player implements the gameplay rules and State implements deterministic dispatch and stepping. Game owns a State instance, enforces echoed actions through it, and atomically publishes state and player records to ETS. The player-facing LiveView continues its existing navigation without consuming authoritative corrections yet.

A player is online while at least one registered view remains. A disconnected view cannot execute live move or attack commands. Respawn currently restores full health as an explicit initial engine default. Beast damage and roaming behavior remain to be implemented.

The development-only /dev/game route inspects the default FogOfWarFrontier.Game process. It shows the entire map, players, records and recent action results. Clicking squares selects their contents. Clicking players follows their authoritative position. The inspector updates each tick and supports pause, single-step and reset controls. Production access is disabled unless explicitly enabled with HTTP Basic Auth credentials.

Tests may run a separate named Game with automatic: false, then call Game.step/2 to advance one tick with action inputs. Two real inspector LiveViews subscribe to that same instance in the integration test. Pure State.step/2 tests require no process or timers.

## Offline session expiry

Remove a player after 1,200 consecutive game ticks with no connected views, equivalent to two minutes. Count from the last transition to zero connected views. Repeated death and respawn must preserve this timestamp. Reconnecting ends that offline period, and a later disconnect starts a new one. Remove expired player records from ETS along with the authoritative snapshot. A later connection using the same session ID creates a fresh player.

## Local countdown presentation

The bars now predict offline health loss and connected healing using the shared Game.Rules parameters serialized by the server component. The gray bar displays the remaining offline survival window. Full health gives a 19-second window. Prediction state is kept in sessionStorage across the recovery page reload, so reconnecting does not visually reset health to full. These bar predictions remain separate from authoritative game state until that UI integration is enabled.

## Monster and multiplayer route staging

The game now moves the Split Brain beast to a random valid neighboring square every thirty ticks (three seconds). Running processes use a cryptographic seed for their random generator. Pure state tests supply a fixed seed. The inspector marks the monster with a red dot and shows its 256 px source image when that square is selected. Tile labels show a green player count. Full IDs remain in the player list and selected records.

The current single-player LiveView receives no monster rendering. Build the multiplayer presentation at /multi/lat/:lat/lon/:lon, preserving the existing navigation, cached/offline behavior, HUD and camera features before replacing the current route.

The pinned LiveView stream API requires a uniquely identified parent with phx-update="stream" and stable generated IDs on its immediate item children. Tile and entity streams can discard server-side item payloads after rendering while FoW captures the resulting DOM for offline presentation. Stream insert/delete updates can retain entity identity for movement and departure animation. Deterministic ordered entities and CSS offsets belong in this multiplayer view. Render moving entities only on the viewer's square.

The gray connection reserve drains offline and replenishes at twice that rate online. Its current full capacity is 19 seconds. It carries its depleted value across reconnects and recovery reloads.

The inspector and player map now share the MapTerrain component, including the procedural terrain atlas and tree placement. The inspector removes fog styling and adds selection hit areas and compact count/monster markers above those same layers.

## Streamed multiplayer presentation

The /multi/lat/:lat/lon/:lon route now uses separate ground, tree and entity streams. It reuses the single-player scene and controls. The multiplayer route filters entities to the viewed square, excludes the viewer's own entity, and sends stable IDs and kinds. Client CSS nth-child selectors assign the offsets. Client hooks animate entry, redistribution and departure without transmitting off-square destinations.

The default running game's tick had stalled during development while its process was still alive. Its clock now uses an OTP periodic timer. A test requires an automatic instance to keep publishing ticks across reads and actions. Manual instances run without a timer. The live inspector was checked for advancing ticks and monster movement.


## Connected multiplayer reconciliation

The /multi view now applies authoritative player health, move charge and position. Navigation uses LiveView patches so a move does not replace the process or its game registration. Each tick notification reads ETS, updates ordinary assigns for the viewer and incrementally inserts/deletes changed entity stream entries. A synchronous move submission returns the accepted game snapshot so rejected destinations are never presented as accepted online moves. Other tabs sharing the session follow the accepted position. Offline presentation still predicts locally; reconnect and tab visibility restoration request fresh server health, including recovery from a stale zero-health prediction. The legacy single-player route remains independent.

Per-view entity comparison state is proportional to occupants of the viewed square. If N players all occupy one square, aggregate comparison state and entity fan-out can grow quadratically. Square-scoped subscriptions reduce irrelevant traffic but do not remove that crowded-square cost; a future visible-entity cap would bound it.


## Death, lives and respawn presentation

Players start with three lives. A transition from positive health to zero spends one life, once; lives can become negative. Respawn preserves the lives balance and increments a life-generation number, so reconnecting views can detect a respawn they missed. Killing a monster will earn one life when player attacks and monster kills are implemented; those actions are still pending.

The HUD has a Lives row above Move. It shows the number and scout icons: remaining lives are colored, the three original spent lives are gray, and negative lives append red scout silhouettes. Death makes the player's scout partly transparent and desaturated, disables movement and displays “You died” with the remaining five-second timeout. Offline prediction can show the same death presentation, then “Reconnect to respawn”; it never grants a respawn locally.

After the server respawns a player, the view keeps the old square visible and pushes a respawn event carrying the life generation. The hook clears only multiplayer Frontier route records, then acknowledges that generation. The view then applies server health and patches to the random spawn square, with a short “Respawned” notice. During the acknowledgement barrier, entity rendering is frozen so it cannot recapture the old square while its cache is being cleared. A per-tab acknowledgement marker avoids repeating a completed cache reset on page reload. The server exploration bitmap is already cleared by the game respawn.

## Occupied-square monster decisions

Every three seconds the monster checks for living players on its square. If any remain, it stays there in the exploding state. Otherwise it chooses a neighboring square and returns to idle. The streamed entity carries this state; CSS plays three equally timed explosion/flat/recovery frames followed by two idle frame intervals, totaling three seconds, and repeats until the next state change. Existing 256-pixel artwork supplies all frames. Each explosion deals 49 HP to every living occupant on that square at the server decision tick, once per three-second cycle. The amount is centralized in Game.Rules.monster_damage/0; connected healing restores at most 30 HP between blasts, so staying put is lethal over repeated cycles. Damage uses Player.damage/3 so death and lives are accounted once. Dead players and players on other squares are not hit. Clicking the beast casts an elixir strike. The beast has 200 HP, so two hits banish it. The last hit earns one life, and the beast returns on a different square after six seconds.


Respawn is a teleport, not a movement animation. Before clearing the cache, the player hook signals the camera/transition controller to retire active scout snapshots and animations. The respawn patch bypasses walking snapshots and does not deplete the move bar. Normal movement resumes after the living player status arrives. The living scout explicitly declares grayscale(0), matching the death filter's function list, so returning to life resets desaturation rather than relying on removal of the grayscale filter. Browser tests cover restored opacity/color and bypassing the walking path; the native WKWebView probe also verifies the live scout's styles and captures its appearance after connected death and respawn.


## Game process recovery and explicit reset

Game.Cache now owns the protected ETS table independently of Game. Every published transition checkpoints the complete pure game state, including its random generator, and the player/view PID pairs. Game restores that checkpoint on process restart, reinstalls monitors for surviving views, and accounts for views which died during the interruption. Connected LiveViews retain their PubSub subscriptions and consume the restored snapshot through the ordinary tick notification. Recovery does not reset exploration or re-register living views as extra connections. The cache is in-memory only; application shutdown still discards the match.

The development inspector has a Reset game button. This is an explicit new match, not a Phoenix restart: reset ticks and monster state, randomly respawn all existing players with full health and three lives, preserve their identities and connection counts, clear exploration, and advance their life generations. Connected clients use the existing cache-clear acknowledgement before accepting the new spawn. The reset is checkpointed, so a subsequent Game process crash restores the reset match. Presenting the spawn square marks that current square explored, even though the pre-presentation respawn bitmap is empty.


## Reconnecting views versus live movement

A newly registered view always submits its viewed position through reconnect validation, even when another view of the same player remains online. Previously that case incremented the connection count and then treated the endpoint as an ordinary adjacent move, incorrectly rejecting valid multi-square offline journeys. Only parameter changes from an already registered view use the ordinary live-move rule.

Record the latest view-disconnect tick independently of the player-wide transition to fully offline. The reconnect movement budget starts at the later of that departure tick and the outstanding charge-ready tick: one available move plus one per completed recharge interval afterward. Online idle time cannot bank extra movement. A new connection consumes the departure credit, including on rejection, so opening more views cannot reuse it. The existing exploration and life checks remain enforced. Inspector action records include requested and accepted positions. Deterministic tests cover too-fast versus sufficiently paced reconnects; a browser regression explicitly waits between two cached moves and keeps a second tab connected.


The live reconnect at tick 7231 requested (1,0) after leaving (0,2) at tick 7193. Its distance fit the movement budget; it was rejected as unexplored because (1,0) was preloaded only on the client. The prior browser test explicitly expected that rejection, encoding the wrong demo behavior. Server registration now grants the configured public preload set, and browser prefetching derives from the same server-supplied list. An exact route/timing regression and the corrected browser expectation require acceptance.


## Socket-only reconnection is not a live player

The reported stuck desktop had repeated DevToolsLive mounts in the server log and no MultiLive mount. A sticky developer-tools root can reconnect on the shared socket after the routed player owner has disappeared. The old indicator called that socket Live, while the game correctly remained disconnected; Connect also blindly toggled the transport instead of recovering the missing page.

FoW now determines page readiness from the actual routed owner and its joined channel. DevTools text, dot and play/pause state use that readiness rather than transport openness alone. Explicit Connect means connect; if the page owner is absent, destroyed, detached or not joined on an open socket, it loads the current URL to establish a fresh routed LiveView. Socket reopening also recovers a missing main page when the document originally had one. Tests leave sticky DevTools connected while retiring the player owner, then require manual and automatic recovery.


## Camera ownership during LiveView patches

Health updates patched the scout's markup every 100 ms. Morphing its ancestor removed the camera's inline CSS variables because the server template did not declare them; the next animation frame restored them. A DOM observer counted 12 scale losses in 1.2 seconds of healing, making the hover/click targets jump. The LiveSocket onBeforeElUpdated callback now preserves only the three client-owned camera variables and the viewport's panning classes. LiveView still owns map content. The same healing probe now records zero scale losses.


### Inspector pause and authenticated access

Game snapshots now include a checkpointed `paused` flag. Automatic timer messages do nothing while paused; manual `Game.step/2` still advances exactly one tick. Moves and attacks are rejected while paused. Connection ownership is maintained, but existing players cannot reconnect to a new position during the pause. Reset preserves pause. Connected multiplayer clients receive pause in the player status event, stop predicted HUD time and freeze entity animations. Disconnected clients cannot receive a new pause state until they reconnect.

The inspector renders every square using MapTerrain and the same entity sprite classes/CSS offsets as the player map. All players, including dead scouts, and the monster can be selected directly. Counts and coordinate labels remain available; exploration does not limit this administrative view.

The inspector route has its own HTTP pipeline and live_session with an on_mount check. Development is open by default. Production requires FRONTIER_INSPECTOR_ENABLED=true plus a nonempty FRONTIER_INSPECTOR_PASSWORD; the username defaults to admin. The HTTP Basic Auth plug stamps a signed-session credential proof, which the socket mount verifies against current configuration. Credentials are runtime settings and are never embedded in source or bundles. This change does not enable the public Fly inspector automatically.


Monster decisions and explosion damage now require a living player with connected_views > 0 on the square. Disconnected player records remain for offline movement reconciliation and health decay but do not attract or receive beast explosions. Connection ownership is updated by monitoring the LiveView process; clean transport closure is observed through process termination, while a lost network can require transport timeout. Another connected tab keeps the player present.


A player ID absent from the current game triggers the cache-clear acknowledgement on join, including after the two-minute offline reaper removed its record. The fresh-join flag forces clearing even if an old browser marker already says life zero; it suppresses the respawn notification. Reconnecting to an existing player does not clear remembered routes. This is Frontier game policy and leaves generic FoW caching unchanged.

The inspector is a viewport-sized workbench: compact toolbar, full-map pane and independently scrolling memory, player, selection and action panes. Recent actions use small monospace text with one unwrapped event per line and horizontal scrolling.
