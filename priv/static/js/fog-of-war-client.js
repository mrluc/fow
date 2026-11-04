import {installFogOfWarCoordinator} from "./fog-of-war-coordinator"
import {createDevToolsHook} from "./fog-of-war-dev-tools"
// Maintained extension seam: upstream LiveView stays pinned by demo/mix.lock.
export {LiveSocket} from "phoenix_live_view"
export const FOG_OF_WAR_BUILD = "fog-of-war-2"
let coordinator
export {createFogOfWarTransitions} from "./fog-of-war-transitions"
export function installFogOfWar(liveSocket, options = {}) {
  if (coordinator) return coordinator
  coordinator = installFogOfWarCoordinator(liveSocket, FOG_OF_WAR_BUILD, options)
  liveSocket.hooks.FogOfWarDevTools = createDevToolsHook(coordinator)
  const bundle = window.__fogOfWarNativeBundle
  if (bundle) {
    window.fogOfWarStartup = coordinator.cache.importBundle(bundle.indexURL).then(result => {
      window.dispatchEvent(new CustomEvent('fog-of-war:snapshot', {detail: {source: 'bundle'}}))
      return result
    }).catch(error => { console.error('[FogOfWar] Native bundle import failed', error); throw error })
  }
  return coordinator
}
console.info("[FogOfWar] client initialized", FOG_OF_WAR_BUILD)

// Capture opted-in rendered HTML; the application chooses its caching policy.
// The presenter restores only allowlisted markup.
export const FogOfWar = {
  mounted() {
    const owner = this.el.closest("[data-phx-main]")
    if (!owner || this.el.parentElement !== owner) {
      console.warn("[FogOfWar] Put FogOfWar on the top-level routed content. Offline navigation restores only this element, not its enclosing layout.")
    }
    this.capture()
  },
  updated() { this.capture() },
  async capture() {
    if (coordinator && !coordinator.canCapture()) return
    const path = this.el.dataset.fogOfWarPath
    if (!path) throw new Error("FogOfWar regions require an explicit server-declared route")
    const snapshot = {
      schema: 1, build: FOG_OF_WAR_BUILD, path, regionId: this.el.id, title: document.title,
      savedAt: new Date().toISOString(), html: this.el.outerHTML,
    }
    try {
      await coordinator.cache.save(snapshot)
      if (coordinator.cache.find(new URL(path, location.href))?.savedAt === snapshot.savedAt) {
        const preview = document.getElementById("snapshot-source")
        if (preview) preview.textContent = JSON.stringify(snapshot, null, 2)
        const status = document.getElementById("snapshot-status")
        if (status) status.textContent = `Snapshot saved · ${path} · ${FOG_OF_WAR_BUILD}`
      }
      window.dispatchEvent(new CustomEvent("fog-of-war:snapshot", {detail: {savedAt: snapshot.savedAt}}))
    } catch (error) {
      console.warn("[FogOfWar] Snapshot unavailable (storage quota or policy)", error.name)
    }
  },
}
