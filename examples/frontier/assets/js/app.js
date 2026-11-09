import {FrontierEntities} from "./entities"
import {installGameBars, FrontierPlayer} from "./game-bars"
import {installDemoUI} from "./demo-ui"
import {installMapViewport, preserveMapPresentation} from "./map-viewport"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {FogOfWar, installFogOfWar, FOG_OF_WAR_BUILD} from "fow"
import {createMapTransitions} from "./map-transitions"
import {installPaperModal} from "./paper-modal"

const viewport = installMapViewport()
const transitions = createMapTransitions(viewport.refresh)
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: document.querySelector("meta[name='csrf-token']").content},
  hooks: {FogOfWar, FrontierEntities, FrontierPlayer}, dom: {onBeforeElUpdated: preserveMapPresentation, onDocumentPatch: transitions.onDocumentPatch},
})
const fogOfWar = installFogOfWar(liveSocket, {transition: transitions.navigate})
window.liveSocket = liveSocket
window.fogOfWar = fogOfWar
installDemoUI(fogOfWar)
installGameBars(fogOfWar)
installPaperModal()

// Real public HTTP renders, not invented client states. This is example-specific preloading.
// Never move the current tab's route protection while saving these neighboring pages.
async function seedSurroundings() {
  await fogOfWar.cache.ready
  const prefix = location.pathname.startsWith('/multi') ? '/multi' : ''
  const rules = JSON.parse(document.getElementById('frontier-bars').dataset.gameRules)
  for (const path of rules.preloaded_squares.map(([lat, lon]) => `${prefix}/lat/${lat}/lon/${lon}`)) {
    if (fogOfWar.cache.find(new URL(path, location.href))) continue
    const response = await fetch(path, {credentials:'same-origin', headers:{Accept:'text/html'}})
    if (!response.ok) throw new Error(`Preload ${path}: ${response.status}`)
    const doc = new DOMParser().parseFromString(await response.text(), 'text/html')
    const region = doc.querySelector('#frontier-map')
    if (region?.dataset.fogOfWarPath !== path) throw new Error('Unexpected preload route')
    await fogOfWar.cache.save({schema:1, build:FOG_OF_WAR_BUILD, path, regionId:region.id,
      title:doc.title, savedAt:new Date().toISOString(), html:region.outerHTML}, {protectRoute:false})
  }
  localStorage.setItem('frontier:seed:v2', 'complete')
}
window.addEventListener('fog-of-war:snapshot', () => {
  window.frontierPreload = seedSurroundings().catch(error => console.warn('[Frontier] Preload deferred:', error.message))
}, {once:true})
liveSocket.connect()
