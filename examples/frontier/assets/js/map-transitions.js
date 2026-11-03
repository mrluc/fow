// Let the browser interpolate the named scout's geometry, rather than sliding the map.
// Before/after snapshots contain different poses; CSS alternates them while it moves.
export function createMapTransitions(refreshViewport = () => {}) {
  let pending = null
  let current = location.pathname
  let queue = Promise.resolve()
  let active
  window.addEventListener('phx:page-loading-start', event => {
    if (event.detail?.to) pending = new URL(event.detail.to, location.href).pathname
  })
  const move = (update, url) => {
    const target = url?.pathname || pending || current
    pending = null
    const changed = target !== current
    current = target
    const run = () => {
      if (!changed || !document.getElementById('player') || !document.startViewTransition || matchMedia('(prefers-reduced-motion: reduce)').matches) {
        const result = update()
        refreshViewport()
        return result
      }
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
