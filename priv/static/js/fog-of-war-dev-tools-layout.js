const STORE = 'fog-of-war:dev-tools-layout'
const docks = ['top-left','top','top-right','right','bottom-right','bottom','bottom-left','left']
const clamp = (x, a, b) => Math.max(a, Math.min(b, x))

export function installDevToolsLayout(el, root) {
  const panel = root.querySelector('.panel'), tools = root.querySelector('.tools')
  const grip = root.querySelector('[data-drag]'), resize = root.querySelector('.resize-handle')
  const splitter = root.querySelector('.splitter')
  let expanded = false, gesture = null, suppressClick = false
  let layout = {dock:'bottom', width:560, height:250, split:58}
  try {
    const saved = JSON.parse(sessionStorage.getItem(STORE))
    if (saved && docks.includes(saved.dock) && ['width','height','split'].every(k => Number.isFinite(saved[k]))) layout = saved
  } catch (_) {}
  const variable = (key,value) => el.style.setProperty(`--dev-tools-${key}`,value)
  const persist = () => { try { sessionStorage.setItem(STORE,JSON.stringify(layout)) } catch (_) {} }
  const apply = () => {
    const corner = layout.dock.includes('-'), right = layout.dock.includes('right'), bottom = layout.dock.includes('bottom')
    const width = corner ? clamp(layout.width,Math.min(350,innerWidth-20),innerWidth-20) : innerWidth-20
    const height = clamp(layout.height,Math.min(150,innerHeight-20),innerHeight-20)
    const shownWidth = expanded ? width : 124, shownHeight = expanded ? height : 28
    let x = right || !corner ? innerWidth-shownWidth-10 : 10
    let y = bottom ? innerHeight-shownHeight-10 : 10
    if (layout.dock === 'left' || layout.dock === 'right') y = (innerHeight-shownHeight)/2
    variable('left',`${Math.round(x)}px`); variable('top',`${Math.round(y)}px`)
    variable('width',`${shownWidth}px`); variable('height',`${height}px`)
    layout.split = clamp(layout.split,20,80)
    variable('split',`${layout.split}%`)
    splitter.setAttribute('aria-valuenow',String(Math.round(layout.split)))
    tools.dataset.dock = layout.dock
    root.querySelector('[data-dock-label]').textContent = `${layout.dock} · drag grip to dock`
    resize.style.left = right ? '0' : 'auto'; resize.style.right = right ? 'auto' : '0'
    resize.style.top = bottom ? '0' : 'auto'; resize.style.bottom = bottom ? 'auto' : '0'
    resize.style.cursor = right === bottom ? 'nwse-resize' : 'nesw-resize'
  }
  const down = event => {
    const target = event.target.closest('[data-drag], .splitter, .resize-handle')
    if (!target || event.button !== 0) return
    event.preventDefault()
    const kind = target === splitter ? 'split' : target === resize ? 'resize' : 'move'
    gesture = {target,kind,x:event.clientX,y:event.clientY,width:panel.offsetWidth,height:panel.offsetHeight,
      box:el.getBoundingClientRect(),list:root.querySelector('.explorer').getBoundingClientRect(),moved:false}
    target.setPointerCapture(event.pointerId)
  }
  const move = event => {
    if (!gesture) return
    const dx = event.clientX-gesture.x, dy = event.clientY-gesture.y
    gesture.moved ||= Math.abs(dx)+Math.abs(dy)>4
    if (gesture.kind === 'move') {
      if (!gesture.moved) return
      tools.dataset.dragging = 'true'
      variable('left',`${clamp(gesture.box.x+dx,0,Math.max(0,innerWidth-gesture.box.width))}px`)
      variable('top',`${clamp(gesture.box.y+dy,0,Math.max(0,innerHeight-gesture.box.height))}px`)
    } else if (gesture.kind === 'split') {
      layout.split = (event.clientX-gesture.list.x)/gesture.list.width*100
      apply()
    } else {
      if (layout.dock.includes('-')) layout.width = gesture.width + (layout.dock.includes('right') ? -dx : dx)
      layout.height = gesture.height + (layout.dock.includes('bottom') ? -dy : dy)
      apply()
    }
  }
  const up = event => {
    if (!gesture) return
    if (gesture.kind === 'move' && gesture.moved && event.type !== 'pointercancel') {
      const anchors = [[0,0],[.5,0],[1,0],[1,.5],[1,1],[.5,1],[0,1],[0,.5]]
      const x = event.clientX/innerWidth, y = event.clientY/innerHeight
      const distances = anchors.map(([a,b]) => (x-a)**2+(y-b)**2)
      layout.dock = docks[distances.indexOf(Math.min(...distances))]
      suppressClick = true
    }
    delete tools.dataset.dragging
    gesture = null; apply(); persist()
  }
  const click = event => { if (suppressClick) { suppressClick=false;event.preventDefault();event.stopImmediatePropagation() } }
  const key = event => {
    if (!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End'].includes(event.key)) return
    if (event.target === splitter) {
      event.preventDefault()
      layout.split = event.key==='Home' ? 20 : event.key==='End' ? 80 : layout.split+(['ArrowLeft','ArrowDown'].includes(event.key)?-2:2)
    } else if (event.target === grip) {
      event.preventDefault()
      const delta = ['ArrowLeft','ArrowUp'].includes(event.key) ? -1 : 1
      layout.dock = event.key==='Home' ? docks[0] : event.key==='End' ? 'bottom' : docks[(docks.indexOf(layout.dock)+delta+8)%8]
    } else if (event.target === resize) {
      event.preventDefault()
      if (event.key==='ArrowLeft') layout.width-=20
      if (event.key==='ArrowRight') layout.width+=20
      if (event.key==='ArrowUp') layout.height-=20
      if (event.key==='ArrowDown') layout.height+=20
    } else return
    apply(); persist()
  }
  root.addEventListener('pointerdown',down); root.addEventListener('pointermove',move)
  root.addEventListener('pointerup',up); root.addEventListener('pointercancel',up)
  root.addEventListener('click',click,true); root.addEventListener('keydown',key)
  window.addEventListener('resize',apply)
  apply()
  return {
    expand(value) { expanded=value;apply() },
    destroy() {
      root.removeEventListener('pointerdown',down);root.removeEventListener('pointermove',move)
      root.removeEventListener('pointerup',up);root.removeEventListener('pointercancel',up)
      root.removeEventListener('click',click,true);root.removeEventListener('keydown',key)
      window.removeEventListener('resize',apply)
    },
  }
}
