---
status: accepted
date: 2026-11-07
---

# FoW Demo UI

Frontier is the hero demo. Give it a prominent connection control that makes disconnecting and reconnecting part of the experience, alongside the map, logo and game UI.

Place a large pair of SVG play and pause controls near the upper-right corner. Both icons remain visible at once. Use an appropriate off-white for the active state and a very dim version for the inactive state. Their relative brightness communicates the present state, while the labels communicate both state and available action.

| Actual connection state | Play control | Pause control |
| --- | --- | --- |
| Connected | Bright, “Connected” | Very dim, “Disconnect” |
| Disconnected | Very dim, “Connect” | Bright, “Disconnected” |

Clicking Connect requests reconnection. Clicking Disconnect closes the connection through FoW's existing connection control. Both icons remain in their positions during state changes. The display must follow actual connection state, including unexpected transport loss, rather than treating a click as proof of connection.

Keep the controls large enough to operate on a phone, clear of the logo and DevTools, and usable from a keyboard. Provide accessible names and a state indication beyond icon brightness. Preserve the two-icon arrangement so the user can distinguish what is happening now from what clicking will do.

## Pirata One

Download and self-host Pirata One for Frontier's old-timey display lettering, including these connection labels. Make its use opt-in through an explicit display-text class or equivalent component choice. Loading the font must not change the default font of FoW, DevTools, or every element in a consuming application.

The font belongs in the native bundle as well as the online example. Capture its local asset references during bundle preparation and verify that its chosen delivery format loads on a first offline start. Inlining CSS alone does not embed the font file.

Font requests need their own WebKit loading check. Do not assume that the custom scheme's successful image display also permits font loading. Embedding the font bytes in an @font-face data URL is a candidate for the Apple bundle, while other platform paths can retain their working asset delivery. Choose and verify the format during implementation.

Pirata One is published in the Google Fonts repository as PirataOne-Regular.ttf under the SIL Open Font License 1.1. Include the copyright and license with the downloaded font and retain them in distributed bundles. The license permits bundling and embedding subject to its terms.

Sources are the [font metadata](https://raw.githubusercontent.com/google/fonts/main/ofl/pirataone/METADATA.pb) and [license](https://raw.githubusercontent.com/google/fonts/main/ofl/pirataone/OFL.txt).

## Project links

Include compact GitHub and Hex links to FoW in the demo UI. The intended destinations are https://github.com/mrluc/fow and https://hex.pm/packages/fow. Keep them available around the map without adding a large explanatory page.

The GitHub repository is currently private, and publication of the Hex package has not been established here. Make the public-demo links accurately reflect availability when implementing or publishing this UI. The links must behave sensibly inside native wrappers, where external project pages should open through the host's external-link behavior.

Offline DevTools are covered separately in ADR-0005. The connection control is part of Frontier's demo UI and should remain available when the developer panel is omitted.

## Implemented

Frontier's root layout includes the fixed connection pair and project links. The controls use FoW's existing connection-toggle behavior and subscribe to coordinator state. The currently active state is disabled as an action and remains bright. The other control remains available.

Pirata One and its OFL license are stored under Frontier's static fonts directory. Only the explicit frontier-display class selects the font. The font copyright and license are also retained in the distributed stylesheet. Apple bundle preparation embeds gathered CSS font resources as data URLs. The native HTTPS font probe loaded one font face successfully from the prepared CSS.

Desktop WebKit opens the GitHub and Hex links in the system browser. Browser navigation leaves the map in its current tab. Verification covers the narrow-viewport controls, local font loading, manual disconnection, cached navigation, external project link and reconnect.
