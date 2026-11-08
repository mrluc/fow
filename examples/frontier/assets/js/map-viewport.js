import {createMapCamera} from './map-camera'

// The map view changes in place as LiveView patches route state.
// Sprite fog is a CSS filter so transparent pixels stay transparent.
export function installMapViewport() {
  let scheduled = false
  const schedule = () => {
    if (scheduled) return
    scheduled = true
    requestAnimationFrame(() => {
      scheduled = false
      const scene = document.getElementById('map-scene')
      if (scene) camera.update(scene, innerWidth, innerHeight)
    })
  }
  const camera = createMapCamera(schedule)
  new ResizeObserver(schedule).observe(document.documentElement)
  new MutationObserver(schedule).observe(document.body, {
    childList:true, subtree:true, attributes:true, attributeFilter:['class'],
  })
  window.addEventListener('resize', schedule)
  schedule()
  return {refresh: schedule}
}

// LiveView owns the map contents; the camera owns only these presentation values.
// Preserve them before morphing so tick patches cannot briefly change hit geometry.
export function preserveMapPresentation(from, to) {
  if (from.id === 'map-scene') {
    for (const name of ['--camera-x', '--camera-y', '--map-scale']) {
      const value = from.style.getPropertyValue(name)
      if (value) to.style.setProperty(name, value)
    }
  }
  if (from.classList.contains('map-viewport')) {
    for (const name of ['pannable', 'is-panning']) {
      to.classList.toggle(name, from.classList.contains(name))
    }
  }
}
