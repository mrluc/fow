---
status: proposed
date: 2026-11-01
---

# Preserve normal LiveView startup before adding host-specific recovery

A native app must be useful on its first offline opening and become live automatically when its server becomes reachable. Preserve the complete anonymously rendered LiveView document and its normal client code, supply its public assets locally, and let LiveView retry and perform its existing stale-session page refresh. Add host-specific presentation protection only where a demonstrated failure or UX requirement warrants it. Do not require an “Open live site” button, ship a user's session, disable Phoenix verification, or invent a separate token-refresh protocol.

This ADR proposes the recovery contract before rollout. The seamless experience is a requirement; the host presentation mechanism and configuration below remain proposed until their platform tests pass. No runtime/generator behavior is changed by this ADR. The current generated wrappers still have the rejected manual handoff and must not be described as satisfying this decision.

## What actually needs recovery

A normal LiveView begins with an HTTP response, not just a WebSocket. That response establishes the browser cookie session and includes a CSRF value and signed LiveView/static data. The JavaScript sends the DOM's signed values when joining the channel. These are separate from a user's login: a public anonymous page still uses the handshake. A token baked into HTML is not a permanent bootstrap credential. The two-week limit is a join-token verification limit, not a shelf life for displaying or navigating the offline public bundle. An expired token can only be diagnosed by a reachable verifier; an unreachable socket alone does not establish expiration.

Our pinned LiveView 1.2.13 verifies the signed data with a two-week age limit. Invalid/expired/missing signed data and unusable connection session data reach a `stale` join response. The client handles `stale` by requesting the page again. That ordinary request can establish a fresh anonymous cookie/CSRF pair and return new signed HTML. Other join failures can lead to jittered reloads. Network failure is not a promise that an HTTP refresh will succeed merely because a WebSocket was reachable.

This corrects an overly broad earlier explanation: **LiveView already performs automatic recovery for these stale-session cases.** Fog of War does not inherently need a new session-refresh endpoint. The missing guarantee is preserving usable content if the page request or subsequent mount fails.

## Evidence, with its limits

### Full LiveView cold-start experiment: the new baseline

`test/browser/cold-liveview.spec.cjs` now tests the previously missing setup: complete server-rendered HTML, original LiveView/application JS and CSS, signed session/static values reissued 30 days in the past, an empty browser cookie/storage state, and no transfer of build-time response cookies. No LiveView code, tokens or CSRF metadata are stripped. No fake socket, parallel staged document, custom token-refresh endpoint or forced `liveSocket.connect()` is used.

Both tests pass. In the first, the browser is put into actual offline mode before the bundled application script is allowed to execute. The page remains visible across multiple real socket attempts, without a `stale` reply while the server is unreachable. When browser connectivity is restored, the normal client receives `stale`, requests the current page exactly once, mounts with fresh server state and completes a real counter increment. In the second, the backend rejects WebSocket requests with HTTP 503 while a native-loader fixture serves the baked pages. Links navigate through those pages; bringing the backend back up leads to automatic refresh and interaction at the final route, not the original route.

The delivery method is explicit: a real loopback test listener serves stored bundle bytes for the initial document without calling Phoenix or setting cookies. Bundled JS/CSS are supplied through request interception. Actual browser offline mode begins before application JavaScript executes, after that loader document has been delivered. This models host delivery; it is not a successful online visit to the LiveView site. The navigation test uses backend unavailability rather than making the browser itself offline, so the local bundle supplier can deliver successive documents. It proves normal disconnected-navigation fallback plus host-supplied public files; it does not prove FoW's snapshot presenter mounted unconnected hooks or did a same-document offline patch.

An initial synthetic-document version was blocked on reconnect by Chrome's local-network access checks. An attempted test-only permission grant was rejected by automatic approval review and removed. The passing fixture uses ordinary HTTP delivery to establish the intended local document origin; it does not grant browser permissions, disable checks, or warm the browser with a real LiveView visit. Native WebViews and deployed HTTPS origins still require their own loading/asset checks.

This result changes the architectural baseline: **do not require a custom bootstrap or two WebViews for the normal successful-recovery path.** Preserve and test normal LiveView behavior first. The previously demonstrated failed-HTTP-refresh window is a separate protection problem, not evidence that cold-offline LiveView startup inherently needs replacement machinery. These tests check visibility while offline and successful recovery; they do not measure frame-by-frame visual continuity during a normal full-page refresh.

The durable Playwright tests now live in `test/browser/startup-session.spec.cjs` and `test/browser/startup-model.spec.cjs`; run them with `bash test/browser/run.sh startup-session.spec.cjs startup-model.spec.cjs`. All six pass. See [browser test instructions](../../test/browser/README.md) for the complete suite and visible-browser commands.

The session fixture renders a normal public page, re-signs the original LiveView/static data with a timestamp 30 days in the past, and asserts both that unlimited-age signature verification succeeds and that LiveView verification returns `{:error, :expired}`. Cookies and CSRF remain fresh for that test, so age is isolated as the cause. Missing-cookie and mismatched-CSRF cases run separately; those values are not assumed to share the LiveView token's lifetime. Nothing changes the production server's expiry policy or secret.

The browser model uses two iframe documents in one browser context to exercise the proposed two-WebView policy. The cached document uses the exported, token-free public HTML and inline local styling. The live candidate makes real Phoenix requests. Playwright holds actual LiveView join replies to prove that HTTP/transport success alone does not permit handoff. Tests cover failed loads, cached link/Back navigation, automatic retry on a controlled connectivity signal, a real root-mount event, post-handoff server actions, and rejection of a late callback from a cancelled route attempt. The model code is exclusively test support, not package/generator implementation. It does not prove native z-order, focus, cookie-store transfer, browser-history behavior, first-install asset delivery or production retry/backoff; those remain platform rollout gates.

The characterization probe in [probes/liveview-bootstrap.cjs](probes/liveview-bootstrap.cjs) uses the real Counter test endpoint and stock LiveView client. It supplies HTML to an established same-origin browser document, observes automatic document requests and channel replies, then verifies a real server increment. [Recorded results](../../results/liveview-bootstrap-characterization.json):

| Supplied page/session condition | Observed stock behavior |
|---|---|
| Fresh HTML with its matching cookie | Joins and handles a server action; no refresh |
| Fresh HTML with the cookie removed | `stale`, one automatic page request, then a working server action |
| Invalid signed LiveView token | `stale`, one automatic page request, then a working server action |
| Invalid token, but the refresh's HTTP request is blocked | A refresh is attempted; the supplied Counter content is lost |

The earlier invalid-token probe exercises the same server rejection branch as expiration; it does not pretend to time-travel a signed token. The permanent session tests above now add a genuinely expired signed token. The failed-refresh observation is Chromium behavior and must also be measured in each supported native WebView. The test's internal `main.isConnected()` inspection is characterization code, not a supported production extension point. A subsequent server action supplies stronger evidence than transport connectivity alone.

Native macOS probes also established two useful facts. `WKWebView.loadHTMLString` with a configured HTTPS base URL reported that URL/origin, a secure context and usable localStorage in this environment. Loading fresh Counter HTML at its HTTP test URL, after transferring the fresh response cookies into a nonpersistent WebView cookie store, joined a real LiveView and completed a server increment. See [probes/webkit-origin.swift](probes/webkit-origin.swift) and [probes/webkit-liveview.swift](probes/webkit-liveview.swift). These are macOS findings, not iOS/Android verification or proof of an offline-to-online handoff. Their assets were available online; they do not prove offline asset delivery.

Android documents HTTP(S) `loadDataWithBaseURL` origin behavior. That makes expected-origin boot a candidate worth testing on both Mob platforms. It does not establish that every host offers the same loading, history, cookie, asset or failure behavior. A base URL also does not fetch fresh cookies or prove a server was contacted.

## Proposed decision

**Preserve the complete public LiveView page, without assuming its session will still be valid.** It must render and navigate among its bundled routes without any successful request. Offline server actions stay disabled and are never queued for replay. A first installation must require no existing cookie, localStorage entry, previous WebView visit or unexpired build-time token.

**Let normal LiveView startup and recovery run first.** Keep the original application/LiveView JavaScript and anonymous signed DOM/CSRF data, and supply its required public assets from the bundle. The native loader supplies each baked document at its expected website URL. The stock client attempts a join and retries; when stale state is rejected it performs its existing HTTP page request. Let Phoenix issue fresh cookies, CSRF state, signed HTML and current assets through that request. No mandatory fresh-page preflight, special token API or independently implemented session protocol is required by the demonstrated successful path. Never bundle response cookies or a logged-in user's session.

**If adding a staged/retained host presentation, commit only a ready page, not an attempted navigation.** HTTP 200, `didFinish`, `DOMContentLoaded`, `navigator.onLine` and `LiveSocket.isConnected()` individually are insufficient: the transport can connect while the root view is rejected. Readiness must identify a successfully joined routed root for the current attempt and route. For participating LiveViews, a package integration using the real routed hook's mounted lifecycle is a candidate for this signal; it must be tested for redirects, sticky child views and late callbacks. It is not enough for a persistent dev panel to mount. Production code must not depend on the private `main.isConnected()` field merely because the probe uses it.

**Keep the last good cached presentation until commit.** A failed HTTP load, asset failure, rejected join, timeout or stale callback cannot replace it with a blank view, a network-error page, or a mandatory spinner. Automatic retries continue with capped backoff and jitter, one active attempt, and cancellation/pausing appropriate to app lifecycle. Connectivity/foreground signals may prompt an earlier attempt; they are hints, not proof of recovery. Exact retry values remain implementation choices. Tests must wait for observed attempts/readiness/failures rather than sleep for an arbitrary duration.

**Recover the route the user is viewing now.** If a user opens `/`, browses offline to `/help`, and the old `/` attempt finishes, it must not replace `/help`. Each attempt carries the current navigation generation and requested route. Navigation invalidates older attempts. Handoff preserves the logical route/history and, where practical, scroll position; Back must not revisit an internal bootstrap URL or add a duplicate user navigation. Server-directed canonical redirects need explicit handling and tests. Cross-origin redirects/authentication require a separate policy; do not silently widen the origin allowlist.

**Keep cold startup separate from reconnecting a live form.** Once a real page owns the view, ordinary LiveView reconnect/form recovery remains the default. A transient disconnect must not trigger this cold-start replacement protocol and discard a user's draft. The initial public preload is read-only; supporting editable offline startup forms would require a separate state-transfer decision.

## What “preserve the presentation” requires from a host

The standard single-document baseline is now demonstrated. If we choose to protect the narrower failed-refresh case or require uninterrupted presentation through every document load, there must be somewhere for the cached page to remain while a new document is being prepared. Merely setting `window.location` and hoping the old pixels remain is not an adequate implementation. There are two plausible mechanisms:

- Stage a fresh real-site WebView with the same intended website data store, laid out at the actual viewport but excluded from interaction/accessibility until ready; then swap it into view and retire the cached presenter. This is a reference candidate, not a mandate to keep two live apps running indefinitely. Failed/cancelled candidates must be destroyed. Hooks that measure layout or request focus need explicit testing.
- Use a single WebView with native presentation retention or controlled reload/navigation handling that demonstrably preserves both the cached experience and route semantics throughout a failed attempt. A screenshot alone is inadequate when the user should still be able to navigate cached pages. A single-DOM bootstrap using public LiveView integration would also be acceptable if it meets the same tests without depending on unstable internals or replaying saved hook state.

Choose the simplest mechanism each adapter can actually prove. Do not commit to single-view DOM surgery or staged WebViews just from API names. Mob's screen component, Android native WebView, iOS WKWebView and the ElixirKit/Tauri host have different constraints. Shared Fog of War policy owns route/attempt validity and readiness semantics; host adapters own document loading, data-store continuity, asset delivery and presentation retention. Applications should not reimplement those rules in app.js.

An implementation must preserve normal cookie behavior, including HttpOnly/Secure/SameSite handling and Set-Cookie ordering. Prefer a normal navigation in the actual WebView data store. A separate native HTTP client does not automatically share that store: the macOS probe explicitly transferred cookies and is not a complete production cookie-sync design. Fetching only a token and splicing it into an old DOM is rejected because the fresh cookie, CSRF state, signed data, root identity, assets and deployed client may need to change together.

## Origin and bundled assets

Prefer the configured real website URL as the logical URL/origin of a bundled page where the native adapter can support and verify it. The earlier two-origin design is not a required user experience or a proven platform necessity. Origin separation remains an implementation option only if the adapter can make its handoff genuinely transparent and preserve the required cookie/storage/history behavior.

The preload's complete presentation must also be available offline. Giving HTML a remote base URL while leaving relative styles/fonts/images to download from that site does not meet the requirement. The adapter/export pipeline must deliver those assets locally (for example, self-contained public HTML or a supported allowlisted resource mechanism), without relying on undocumented HTTPS scheme interception. The trusted startup code needs an appropriate resource/connect policy; the current export's `connect-src 'none'` and removed LiveView scripts are deliberately static and cannot simply be relabeled as a connecting app.

Online application assets should come from the fresh server response. Do not mount a months-old bundled client against a changed deployment without a compatibility policy. The complete public bundle can display and run its own client while disconnected even when its signed join data has expired. A fresh HTTP recovery normally supplies the current deployed client. Cross-version wire compatibility still needs testing; the experiment used the same pinned client/server release with old tokens.

## Proposed configuration and manifest relationship

The source application's `config/config.exs` should describe its explicit public preload and desired startup presentation. For discussion, not an implemented interface:

```elixir
config :fow,
  preload: [
    start_path: "/",
    paths: ["/about", "/help"]
  ],
  startup: [mobile: :prerendered, desktop: :loading]
```

`start_path` is included automatically; `paths` adds other concrete public routes. `:prerendered` means show usable bundled content immediately and recover in the background. `:loading` permits an initial loading presentation while a normal page boots, with an explicit offline fallback policy; it does not introduce a manual handoff. Mobile defaults should favor prerendered content. Desktop may choose either presentation. The names/defaults above are proposed and must not be documented as existing options yet.

The manifest task should derive these values, endpoint/origin and conventional branding into `.fow.json`; the manifest remains a reviewable build artifact and a place for native overrides. The exporter should visit the configured public routes automatically during build, without requiring manual visits. Neither route discovery nor “no login form found” proves that a page is safe to distribute; explicit public selection is still required. Authenticated snapshots learned during use are a separate cache policy and never become a distributable public preload.

## Alternatives rejected or deferred

- **Manual “Open live site”: rejected.** It makes native startup a separate product experience the user did not ask for.
- **Only retry the baked socket forever: rejected as the correctness path.** Missing/mismatched cookies and expired/invalid tokens require fresh server state; retries reuse DOM values until another recovery path intervenes.
- **Just let stock LiveView reload: insufficient on its own.** It recovers the demonstrated successful-network cases but does not preserve cached content when the HTTP refresh fails.
- **Exported browser cookies, extended token lifetimes, disabled CSRF/signature/origin checks, or a shared authenticated session: rejected.** Public content does not require weakening normal Phoenix verification.
- **Service worker as the universal first-install solution: deferred.** It can be useful after installation at a web origin, but a native first install must have its public preload before any successful visit/worker installation. It is a separate possible adapter design, not an assumed prerequisite.
- **Private account cache encryption/namespace design: separate ADR.** This ADR covers public first-opening content and normal browser session establishment, not shipping logged-in content or deciding logout retention.

## Rollout gate: tests required before enabling this on a platform

The golden startup test starts with an empty website data store and a deliberately unusable/absent build-time session. All network access fails. Launch the actual native host and prove a styled public page renders from bundled assets; navigate to another included route and back; server actions cannot run and no server-rendered process supplies the offline content. Begin recovery while HTTP still fails and prove the cached page remains visible and navigable. While an older route attempt is pending, move to another cached route. Restore HTTP but initially withhold the LiveView join: the cached page must remain until the current route's real root mounts. Release that join; handoff happens automatically at the current route, without a manual button, duplicate history entry, blank/error document, or replayed offline action. A server-side increment must then work. Repeat after a failed candidate and an app background/foreground cycle, checking candidates/listeners are cleaned up.

Run additional cases for first online launch, stale cookie/CSRF pairs, rejected tokens, a signing-key/deployment change, failed or mismatched application assets, HTTP-works/WebSocket-fails, server 5xx, canonical redirects, rapid offline route changes, reload failures, and fresh-but-unjoined DOM. Keep existing warm-page form-reconnect tests independent. Test the actual cookie, storage, expected URL/history, offline assets and readiness behavior separately on Mob Android, Mob iOS and the chosen ElixirKit desktop WebView. Desktop loading mode needs its own simpler startup assertion; it does not waive recovery correctness.

Only advertise a platform as first-offline-visit-capable after those tests pass there. Current generator compilation, the stock-client characterization and the macOS probes are supporting evidence, not completion of that gate.

## Source references

Pinned source inspected locally: LiveView 1.2.13 `Static.verify_token/2`, `Static.sign_root_session/5`, `Session.verify_session/4`, `Channel.mount/3`, and the bundled JavaScript `View.getSession`, `View.onJoinError`, `LiveSocket.reloadWithJitter`; Phoenix 1.8.16 `Socket.Transport.connect_session` and `csrf_token_valid?`.

Primary upstream references: [LiveView lifecycle](https://phoenix-live-view.hexdocs.pm/1.2.13/Phoenix.LiveView.html), [signed static/session data](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.13/lib/phoenix_live_view/static.ex), [session verification](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.13/lib/phoenix_live_view/session.ex), [server mount rejection](https://github.com/phoenixframework/phoenix_live_view/blob/v1.2.13/lib/phoenix_live_view/channel.ex), [Phoenix transport session verification](https://github.com/phoenixframework/phoenix/blob/v1.8.16/lib/phoenix/socket/transport.ex), [Android local WebView content](https://developer.android.com/develop/ui/views/layout/webapps/load-local-content), and [WKWebView HTML loading](https://developer.apple.com/documentation/webkit/wkwebview/loadhtmlstring(_:baseurl:)). Native findings above are explicitly empirical rather than inferred guarantees from Apple's baseURL documentation.
