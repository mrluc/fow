import {createLogoutHook} from "./fog-of-war-logout"
import {installFogOfWarCoordinator} from "./fog-of-war-coordinator"
import {createDevToolsHook} from "./fog-of-war-dev-tools"
// Maintained extension seam: upstream LiveView stays pinned by demo/mix.lock.
export {LiveSocket} from "phoenix_live_view"
export const FOG_OF_WAR_BUILD = "fog-of-war-2"
let coordinator
export {createFogOfWarTransitions} from "./fog-of-war-transitions"
export function installFogOfWar(liveSocket, options = {}) {
  if (coordinator) return coordinator
  const managedKeys = Boolean(document.querySelector('[data-fog-of-war-account-keys="true"]'))
  coordinator = installFogOfWarCoordinator(liveSocket, FOG_OF_WAR_BUILD, {
    ...(managedKeys ? {accountKeyEndpoint: '/_fow/account-key'} : {}),
    ...options,
  })
  liveSocket.hooks.FogOfWarDevTools = createDevToolsHook(coordinator)
  liveSocket.hooks.FogOfWarLogout = createLogoutHook(coordinator.lockAccount)
  window.addEventListener('phx:fow:logout', async () => {
    try {
      await coordinator.lockAccount()
      window.dispatchEvent(new CustomEvent('fog-of-war:account-locked'))
    } catch (error) {
      console.error('[FogOfWar] Could not clear the account key', error)
    }
  })
  const bundle = window.__fogOfWarNativeBundle
  if (bundle) {
    const readAsset = window.__fogOfWarNativeReadAsset
    window.fogOfWarStartup = coordinator.cache.importBundle(bundle.indexURL, {
      ...(typeof readAsset === 'function' ? {readAsset: (path, options) => readAsset(path, options)} : {}),
    }).then(result => {
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
    this.onNavigate = () => this.scheduleCapture()
    window.addEventListener("phx:navigate", this.onNavigate)
    this.scheduleCapture()
  },
  updated() { this.scheduleCapture() },
  destroyed() { window.removeEventListener("phx:navigate", this.onNavigate) },
  scheduleCapture() {
    if (this.captureScheduled) return
    this.captureScheduled = true
    queueMicrotask(() => {
      this.captureScheduled = false
      if (this.el.isConnected) this.capture()
    })
  },
  async capture() {
    if (coordinator && !coordinator.canCapture()) return
    const {fogOfWarUserId, fogOfWarRequireUserId, fogOfWarPath} = this.el.dataset
    const userId = fogOfWarUserId?.trim() || null
    coordinator.cache.setIdentity(userId)
    if (fogOfWarRequireUserId === "true" && !userId) return
    if (!fogOfWarPath && location.search) return
    const path = fogOfWarPath || location.pathname
    const now = Date.now()
    const maxAge = Number(this.el.dataset.fogOfWarMaxAgeMs)
    const snapshot = {
      schema: 1, build: FOG_OF_WAR_BUILD, path, userId, regionId: this.el.id, title: document.title,
      savedAt: new Date(now).toISOString(),
      ...(Number.isSafeInteger(maxAge) && maxAge > 0 ? {expiresAt: now + maxAge} : {}),
      html: this.el.outerHTML,
    }
    try {
      if (userId && this.el.dataset.fogOfWarAccountKeys === 'true' &&
          !await coordinator.cache.ensureAccount(userId)) return
      if (!this.el.isConnected || !coordinator.canCapture() ||
          (this.el.dataset.fogOfWarUserId?.trim() || null) !== userId) return
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
