---
status: proposed
date: 2026-11-07
---

# Make explicitly included DevTools usable before LiveView connects

A development bundle that includes FoW DevTools should display its launcher and let the developer inspect its local cache while the server is unreachable. Keep the existing server-side inclusion setting. This is a development scenario, including first offline startup of a native bundle.

## Current behavior

The Frontier startup bundle examined for this ADR contains the DevTools host and one template containing its UI. The panel is outside the saved FogOfWar region, but the full startup document includes it. Region-only cache entries are a separate artifact.

FogOfWar.dev_tools renders the sticky DevToolsLive child when enabled. DevToolsLive places the controls and their styles inside a template. The template is inert until JavaScript clones it into a shadow root.

In fog-of-war-dev-tools.js, the LiveView hook's mounted callback calls mountDevTools. That function attaches the shadow root, clones the template, initializes controls, and subscribes to the coordinator. A cold offline page cannot depend on that connected LiveView lifecycle. Consequently, the included host has no visible launcher while waiting for its first connection.

Relevant source files are lib/fow.ex, lib/fog_of_war/dev_tools_live.ex and priv/static/js/fog-of-war-dev-tools.js. CacheExport saves the full startup HTML independently of its extracted region records.

## Required behavior

Render the included launcher so its initial visibility does not require a successful LiveView mount. Its appearance and disconnected state should be represented in the static markup and styles, with an offline initializer attaching the local behavior. Resolve how to expose the visible markup alongside the shadow-root styling during implementation.

Mount the interactive DevTools against FoW's browser coordinator during normal client startup. This should work with the native bundle importer and the local cache before a socket joins. The current controls primarily operate through browser JavaScript and the coordinator, so they should not need a live server merely to open or inspect storage.

Use one idempotent initialization path shared by startup and the LiveView hook. If startup has already initialized a host, a later hook mount must reuse its controller and shadow root. Avoid duplicate listeners, timers, coordinator registrations, panels or state subscriptions.

Preserve layout, transparency and expanded state as appropriate across offline route changes. Hand off correctly when reconnecting replaces or patches the host. Dispose controllers when their host is genuinely removed, while retaining those intentionally preserved across snapshot navigation.

Keep DevTools outside ordinary route snapshot payloads. Their development inclusion and lifetime belong to the surrounding application and full startup document. Preserve the existing opt-in controls, including the :fow application setting and explicit component override. A bundle captured with DevTools disabled should not gain a panel through the offline initializer.

## Verification

Start a development bundle with a fresh WebView data store and the server stopped. The included launcher must be visible, open successfully, show disconnected status and inspect the imported cache. Navigate among cached routes and operate the connection controls.

Restore connectivity and require one functioning panel after the routed LiveView joins. Repeat connection loss, reconnection and cached navigation and check that initialization does not duplicate resources. Also verify that a bundle captured with DevTools disabled displays no developer UI.

This ADR records the proposed fix. The current template-only markup and hook initialization have not been changed by writing it.
