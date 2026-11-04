import {createMapCamera} from './map-camera'

// Screen-space fog deliberately lives outside the scaled/live-patched map.
// Its 1 CSS-pixel cells never grow with terrain or rotate with the ground.
export function installMapViewport() {
  const overlay = document.createElement('canvas')
  overlay.className = 'pixel-fog'
  overlay.setAttribute('aria-hidden', 'true')
  document.body.append(overlay)
  const mask = document.createElement('canvas')
  const pine = new Image()
  const idle = new Image(), walking = new Image()
  let scheduled = false
  const schedule = () => {
    if (scheduled) return
    scheduled = true
    requestAnimationFrame(() => { scheduled = false; draw() })
  }
  const camera = createMapCamera(schedule)
  for (const image of [pine, idle, walking]) image.onload = schedule
  const asset = path => window.__fogOfWarNativeBundle?.assets?.[path] || path
  for (const image of [pine, idle, walking]) image.crossOrigin = 'anonymous'
  pine.src = asset('/images/pine.png')
  idle.src = asset('/images/scout-idle.png')
  walking.src = asset('/images/scout-walk.png')

  function draw() {
    const scene = document.getElementById('map-scene')
    const width = innerWidth, height = innerHeight
    if (scene) camera.update(scene, width, height)
    if (overlay.width !== width || overlay.height !== height) {
      overlay.width = mask.width = width
      overlay.height = mask.height = height
    }
    const ctx = overlay.getContext('2d'), m = mask.getContext('2d', {willReadFrequently:true})
    ctx.clearRect(0, 0, width, height)
    m.clearRect(0, 0, width, height)
    if (!scene) return
    const offline = document.documentElement.classList.contains('fow-offline')
    const isFogged = el => (offline || !el.classList.contains('current')) &&
      (!el.classList.contains('fow-nav-uncached') || el.classList.contains('current'))
    m.fillStyle = '#fff'
    for (const sector of scene.querySelectorAll('.sector')) {
      if (!isFogged(sector)) continue
      const r = sector.querySelector('.floor').getBoundingClientRect()
      m.beginPath()
      m.moveTo(r.x + r.width/2, r.y)
      m.lineTo(r.right, r.y + r.height/2)
      m.lineTo(r.x + r.width/2, r.bottom)
      m.lineTo(r.x, r.y + r.height/2)
      m.closePath(); m.fill()
    }
    const sprite = (image, el, fogged) => {
      if (!image.complete || !image.naturalWidth) return
      const r = el.getBoundingClientRect()
      if (!r.width || !r.height) return
      const ratio = Math.min(r.width/image.naturalWidth, r.height/image.naturalHeight)
      const w = image.naturalWidth*ratio, h = image.naturalHeight*ratio
      m.globalCompositeOperation = fogged ? 'source-over' : 'destination-out'
      m.drawImage(image, r.x+(r.width-w)/2, r.y+r.height-h, w, h)
    }
    // Match sprite depth: a live foreground tree occludes fog behind it.
    const trees = [...scene.querySelectorAll('.object .tree')].sort((a,b) =>
      Number(getComputedStyle(a).zIndex)-Number(getComputedStyle(b).zIndex))
    for (const tree of trees) sprite(pine, tree, isFogged(tree.parentElement))
    const player = document.getElementById('player')
    if (player) sprite(player.classList.contains('walking') ? walking : idle, player, false)
    m.globalCompositeOperation = 'source-over'
    const silhouette = m.getImageData(0, 0, width, height).data
    const fog = ctx.createImageData(width, height)
    // Threshold the mask and write integer pixels: no rotated gradients,
    // fractional-size cells, interpolated scaling, or antialiased fog edges.
    for (let y=0; y<height; y++) for (let x=0; x<width; x++) {
      const i=(y*width+x)*4
      if (silhouette[i+3] < 128 || (x+y)%2) continue
      fog.data[i]=70; fog.data[i+1]=76; fog.data[i+2]=70; fog.data[i+3]=190
    }
    ctx.putImageData(fog, 0, 0)
  }
  new ResizeObserver(schedule).observe(document.documentElement)
  new MutationObserver(schedule).observe(document.body, {
    childList:true, subtree:true, attributes:true, attributeFilter:['class'],
  })
  window.addEventListener('resize', schedule)
  window.addEventListener('fog-of-war:snapshot', schedule)
  schedule()
  return {refresh: draw}
}
