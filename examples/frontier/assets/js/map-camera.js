// Local presentation state survives both LiveView patches and offline region replacements.
// No route or server state is changed by panning.
export function createMapCamera(schedule) {
  let x = 0, y = 0, route = null, narrowBefore = false, drag = null, suppressClickUntil = 0
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value))
  const set = (scene, name, value) => {
    const text = `${value.toFixed(2)}px`
    if (scene.style.getPropertyValue(name) !== text) scene.style.setProperty(name, text)
  }
  function update(scene, width, height) {
    const viewport = scene.closest('.map-viewport')
    const narrow = width < 800
    viewport?.classList.toggle('pannable', narrow)
    // This is a CSS setting so the example's zoom can be tuned independently.
    const zoom = parseFloat(getComputedStyle(scene).getPropertyValue('--narrow-map-zoom')) || 1.65
    const scale = narrow ? zoom : Math.max(.25, Math.min((width - 48) / 560, (height - 80) / 360, 4))
    const player = scene.querySelector('#player')
    const nextRoute = `${scene.dataset.lat}/${scene.dataset.lon}`
    if (!narrow) { x = 0; y = 0 }
    else if (player && (!narrowBefore || route === null)) {
      const style = getComputedStyle(player)
      x = -(parseFloat(style.left) - 320) * scale
      y = -(parseFloat(style.top) - 176) * scale
    } else if (player && route !== nextRoute) {
      const style = getComputedStyle(player)
      const px = width / 2 + x + (parseFloat(style.left) - 320) * scale
      const py = height / 2 + y + (parseFloat(style.top) - 176) * scale
      // Follow only when the scout leaves the central safe area, not every step.
      x += clamp(px, width * .25, width * .75) - px
      y += clamp(py, height * .35, height * .65) - py
    }
    if (narrow) {
      // Keep part of the world reachable even after a long drag.
      x = clamp(x, -272 * scale - width / 2 + 80, 272 * scale + width / 2 - 80)
      y = clamp(y, -210 * scale - height / 2 + 100, 210 * scale + height / 2 - 100)
    }
    set(scene, '--camera-x', x); set(scene, '--camera-y', y)
    const value = scale.toFixed(4)
    if (scene.style.getPropertyValue('--map-scale') !== value) scene.style.setProperty('--map-scale', value)
    route = nextRoute; narrowBefore = narrow
  }
  document.addEventListener('pointerdown', event => {
    const viewport = event.target.closest?.('.map-viewport.pannable')
    if (!viewport || !event.isPrimary || event.button !== 0) return
    suppressClickUntil = 0
    drag = {id:event.pointerId, viewport, startX:event.clientX, startY:event.clientY, x, y, moved:false}
  }, true)
  document.addEventListener('dragstart', event => {
    if (event.target.closest?.('.map-viewport.pannable')) event.preventDefault()
  }, true)
  document.addEventListener('pointermove', event => {
    if (!drag || event.pointerId !== drag.id) return
    const dx = event.clientX - drag.startX, dy = event.clientY - drag.startY
    if (!drag.moved && Math.hypot(dx, dy) < 7) return
    if (!drag.moved) {
      drag.moved = true
      drag.viewport.setPointerCapture(event.pointerId)
      drag.viewport.classList.add('is-panning')
    }
    event.preventDefault()
    x = drag.x + dx; y = drag.y + dy
    schedule()
  }, {capture:true, passive:false})
  const release = event => {
    if (!drag || event.pointerId !== drag.id) return
    if (drag.moved) suppressClickUntil = performance.now() + 400
    drag.viewport.classList.remove('is-panning')
    drag = null
  }
  document.addEventListener('pointerup', release, true)
  document.addEventListener('pointercancel', release, true)
  // Installed before FoW/LiveView's click handlers: a drag must never navigate.
  document.addEventListener('click', event => {
    if (performance.now() < suppressClickUntil && event.target.closest?.('.map-viewport')) {
      event.preventDefault(); event.stopImmediatePropagation(); suppressClickUntil = 0
    }
  }, true)
  return {update}
}
