import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {FogOfWar, installFogOfWar, createFogOfWarTransitions} from "fow"

const csrfToken = document.querySelector("meta[name='csrf-token']").content
const transitions = createFogOfWarTransitions()
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken}, hooks: {FogOfWar},
  dom: {onDocumentPatch: transitions.onDocumentPatch},
})
const fogOfWar = installFogOfWar(liveSocket, {transition: transitions.navigate})
liveSocket.connect()
window.liveSocket = liveSocket
window.fogOfWar = fogOfWar
