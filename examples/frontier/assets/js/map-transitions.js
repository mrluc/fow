// Animate the live map and scout so screen-space overlays keep their stacking order.
export function createMapTransitions(refreshViewport = () => {}) {
  let pending = null
  let current = location.pathname
  let queue = Promise.resolve()
  let respawning = false
  window.addEventListener('frontier:respawning', () => {
    respawning = true
    liveGeneration++
    liveAnimations.forEach(animation => animation.cancel())
    liveAnimations = []
    document.getElementById('player')?.classList.remove('walking')
  })
  window.addEventListener('phx:frontier:player', ({detail}) => {
    if (!detail.dead && !detail.clearing_cache) respawning = false
  })
  let liveAnimations = [], liveGeneration = 0
  const moveInPage = async update => {
    const initialPlayer = document.getElementById('player'), initialScene = document.getElementById('map-scene')
    if (!initialPlayer || !initialScene) return update()
    const beforePlayer = getComputedStyle(initialPlayer)
    const from = {left: beforePlayer.left, top: beforePlayer.top,
      zIndex: beforePlayer.zIndex, transform: getComputedStyle(initialScene).transform}
    const generation = ++liveGeneration
    liveAnimations.forEach(animation => animation.cancel())
    update()
    await Promise.resolve()
    const scene = document.getElementById('map-scene'), player = document.getElementById('player')
    if (!scene || !player) return
    player.classList.add('walking')
    refreshViewport()
    const destination = getComputedStyle(player)
    const timing = {duration:650, easing:'linear'}
    liveAnimations = [
      scene.animate([{transform:from.transform}, {transform:getComputedStyle(scene).transform}], timing),
      player.animate([
        {left:from.left, top:from.top, zIndex:from.zIndex},
        {left:destination.left, top:destination.top, zIndex:destination.zIndex},
      ], timing),
    ]
    const animations = liveAnimations
    const paint = () => {
      if (generation !== liveGeneration) return
      refreshViewport()
      if (animations.some(animation => !['finished','idle'].includes(animation.playState))) requestAnimationFrame(paint)
    }
    requestAnimationFrame(paint)
    Promise.all(animations.map(animation => animation.finished.catch(() => {}))).then(() => {
      if (generation !== liveGeneration) return
      player.classList.remove('walking')
      refreshViewport()
    })
  }
  window.addEventListener('phx:page-loading-start', event => {
    if (event.detail?.to) pending = new URL(event.detail.to, location.href).pathname
  })
  const move = (update, url) => {
    const target = url?.pathname || pending || current
    pending = null
    const changed = target !== current
    current = target
    const teleport = respawning
    const run = () => {
      if (changed && !teleport) window.dispatchEvent(new Event("frontier:moved"))
      if (teleport || !changed || !document.getElementById('player') || matchMedia('(prefers-reduced-motion: reduce)').matches) {
        const result = update()
        refreshViewport()
        return result
      }
      return moveInPage(update)
    }
    queue = queue.then(run, run)
    return queue
  }
  return {onDocumentPatch: update => move(update), navigate: move}
}
