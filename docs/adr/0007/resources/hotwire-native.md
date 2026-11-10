# Hotwire Native prior art

Hotwire Native is the 37signals web-first mobile framework in the Rails/Hotwire ecosystem. Older references may call the navigation layer Turbo Native and the bridge layer Strada. The current docs call the latter Bridge Components. [Hotwire Native](https://native.hotwired.dev/) · [Bridge Components overview](https://native.hotwired.dev/overview/bridge-components)

| Idiom | What to study |
| --- | --- |
| Native shell and tabs | Tab destinations are URLs. iOS and Android provide native tab chrome, with a navigator per tab and support for lazy loading tab roots. Compare those stacks with the proposed single-WebView history. [iOS tabs](https://native.hotwired.dev/ios/tabs) · [Android tabs](https://native.hotwired.dev/android/tabs) |
| Path configuration | Rules match URLs and select presentation behavior. Bundle a configuration for startup and optionally refresh it from the server. Version the files for compatibility with installed app builds. [Path configuration](https://native.hotwired.dev/overview/path-configuration) · [Rules reference](https://native.hotwired.dev/reference/path-configuration) |
| Named bridge components | A Stimulus controller pairs with a named native counterpart, checks capability, and exchanges JSON messages and replies. The reference's native submit button example is a useful fallback and event-routing model. [Bridge reference](https://native.hotwired.dev/reference/bridge-components) |
| DOM lifecycle | Stimulus connects and disconnects controllers as their elements enter and leave the document. This is prior art for the local component lifecycle that FoW would need when swapping cached regions. [Stimulus lifecycle callbacks](https://stimulus.hotwired.dev/reference/lifecycle-callbacks) |
| Native escape hatch | Some destinations can open native screens. Study the route matching and fallback model before adding a native-only route to the pilot. [Native screens](https://native.hotwired.dev/overview/native-screens) |

These sources describe native enhancement and navigation. FoW's cache availability, offline lifecycle, and live handoff need their own contract.
