// Let the browser interpolate the named scout's geometry, rather than sliding the map.
// Before/after snapshots contain different poses; CSS alternates them while it moves.
export function createMapTransitions() {
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
      if (!changed || !document.getElementById('player') || !document.startViewTransition || matchMedia('(prefers-reduced-motion: reduce)').matches) return update()
      active?.skipTransition()
      active = document.startViewTransition(() => {
        update()
        document.getElementById('player')?.classList.add('walking')
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
