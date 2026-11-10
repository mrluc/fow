---
status: proposed
date: 2026-11-09
---

# Progressively enhance server-driven UI on mobile

Phoenix LiveView renders the web experience. FoW preserves selected routes as read-only cached pages when the server is unavailable. A Mob host can enhance that experience with platform controls while the same routes and actions remain available in a browser.

[Hotwire Native prior art](0007/resources/hotwire-native.md) gives us three patterns to evaluate: native navigation around web routes, declarative path rules for presentation, and named bridge components with web fallbacks.

## Proposed decision

Start with a persistent Mob shell around one WebView. On mobile web, the demo reserves layout space for a bottom bar. In Mob, the native host floats the bar above the WebView and supplies a bottom inset so content can scroll clear of it. Use iOS glass or material and an Android translucent surface. Verify compositing and safe-area behavior on devices.

Keep the displayed route authoritative. A native tab tap requests a known destination through the bridge. The web client uses its normal LiveView navigation online and FoW's cached navigation offline. The host highlights the tab only after the destination commits. Back, reconnect, and unavailable cached destinations follow the same rule. Bundle the tab roots with the demo for cold offline starts.

Use the Hotwire Native pattern of capability-gated enhancements for page-specific controls. Render a working HTML fallback and expose a small, validated component descriptor for opted-in pages. Hide the fallback after the host confirms it can provide the equivalent control. The host dispatches only known commands and validates route and payload data. Tie requests to the active page so a reply from a previous page cannot revive its native UI.

The persistent tab bar belongs to the shell. An exhibit-specific control belongs to the page. Give the latter a shared mount, update, and dispose contract that a live hook can call and a cached page can opt into. FoW currently retires LiveView owners during cached navigation, and the snapshot presenter strips hook bindings. A future adapter would mount registered local behavior after insertion and dispose of it before replacement. Live server actions remain owned by the live page. See the [coordinator](../../priv/static/js/fog-of-war-coordinator.js) and [snapshot presenter](../../priv/static/js/fog-of-war-presenter.js).

## Trade-offs

Hotwire Native gives each tab a navigator and its own stack. For the pilot, one WebView and one history keep native taps, ordinary links, cached navigation, and Back on the same route model. Separate stacks would add per-tab history and scroll restoration. Revisit them when the demo needs to preserve independent journeys.

Use a small bundled mapping from routes to tabs in the pilot. Hotwire Native's bundled and remote path configuration offers a model for versioned presentation rules once several apps need them. Cached routes and native capabilities have independent lifetimes, so any future remote rules must work with the installed host and its available cache.

## Pilot

Use the proposed museum guide with Explore, Saved, and Visit as tab roots. First verify tab selection, cold offline launch, Back, and reconnect. Then add one exhibit-specific native sheet with an HTML fallback. Verify it dismisses on route change and that an unavailable bridge leaves the fallback usable.

[Further research on the coordinator lifecycle and native renderers](research/research-heavyweight-sdui.md).
