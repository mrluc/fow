// Desktop uses a named scout snapshot. Narrow screens animate the live map/scout
// so the screen-space fog and fixed logo keep their normal stacking order.
export function createMapTransitions(refreshViewport = () => {}) {
  let pending = null
  let current = location.pathname
  let queue = Promise.resolve()
  let active
  let respawning = false
  window.addEventListener('frontier:respawning', () => {
    respawning = true
    active?.skipTransition()
    liveGeneration++
    liveAnimations.forEach(animation => animation.cancel())
    liveAnimations = []
    document.getElementById('player')?.classList.remove('walking')
  })
  window.addEventListener('phx:frontier:player', ({detail}) => {
    if (!detail.dead) respawning = false
  })
  let liveAnimations = [], liveGeneration = 0
  const moveInPage = async update => {
    const beforePlayer = getComputedStyle(document.getElementById('player'))
    const from = {left: beforePlayer.left, top: beforePlayer.top,
      transform: getComputedStyle(document.getElementById('map-scene')).transform}
    const generation = ++liveGeneration
    liveAnimations.forEach(animation => animation.cancel())
    active?.skipTransition()
    update()
    await Promise.resolve()
    const scene = document.getElementById('map-scene'), player = document.getElementById('player')
    player.classList.add('walking')
    refreshViewport()
    const destination = getComputedStyle(player)
    const timing = {duration:650, easing:'linear'}
    liveAnimations = [
      scene.animate([{transform:from.transform}, {transform:getComputedStyle(scene).transform}], timing),
      player.animate([{left:from.left, top:from.top}, {left:destination.left, top:destination.top}], timing),
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
      if (teleport || !changed || !document.getElementById('player') || !document.startViewTransition || matchMedia('(prefers-reduced-motion: reduce)').matches) {
        const result = update()
        refreshViewport()
        return result
      }
      if (innerWidth < 800) return moveInPage(update)
      active?.skipTransition()
      active = document.startViewTransition(async () => {
        update()
        // Flush class observers without waiting on the rendering clock.
        await Promise.resolve()
        document.getElementById('player')?.classList.add('walking')
        refreshViewport()
      })
      const running = active
      running.ready.catch(() => {})
      running.finished.catch(() => {}).then(() => {
        if (active === running) document.getElementById('player')?.classList.remove('walking')
      })
      return running.updateCallbackDone
    }
    queue = queue.then(run, run)
    return queue
  }
  return {onDocumentPatch: update => move(update), navigate: move}
}
