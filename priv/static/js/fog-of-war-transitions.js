// One update boundary for LiveView patches and cached-page navigation.
// CSS chooses the animation; unsupported browsers and reduced motion update directly.
export function createFogOfWarTransitions() {
  let current = location.pathname
  const visited = [current]
  let pending = null
  let queue = Promise.resolve()
  let active = null
  window.addEventListener('phx:page-loading-start', event => {
    if (event.detail?.to) pending = new URL(event.detail.to, location.href).pathname
  })
  const transition = (update, path) => {
    const previous = current
    const index = visited.indexOf(path)
    const oldIndex = visited.indexOf(previous)
    const back = index !== -1 ? index < oldIndex : path.split('/').length < previous.split('/').length
    if (index === -1) visited.push(path)
    current = path
    const run = () => {
      if (path === previous || !document.startViewTransition || matchMedia('(prefers-reduced-motion: reduce)').matches) return update()
      active?.skipTransition()
      document.documentElement.dataset.fogOfWarDirection = back ? 'back' : 'forward'
      active = document.startViewTransition(update)
      active.ready.catch(() => {}) // Rapid navigations can legitimately skip an animation.
      return active.updateCallbackDone
    }
    queue = queue.then(run, run)
    return queue
  }
  return {
    onDocumentPatch(update) {
      const path = pending || current
      pending = null
      return transition(update, path)
    },
    navigate(update, url) { return transition(update, url.pathname) },
  }
}
