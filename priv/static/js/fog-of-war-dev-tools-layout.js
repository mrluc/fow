const STORE = 'fog-of-war:dev-tools-layout'
const docks = ['top-left','top','top-right','bottom-right','bottom','bottom-left']
const anchors = [[0,0],[.5,0],[1,0],[1,1],[.5,1],[0,1]]
const dockName = dock => dock.replaceAll('-', ' ')
const nearestDock = (x,y) => {
  const distances = anchors.map(([a,b]) => (x/innerWidth-a)**2+(y/innerHeight-b)**2)
  return docks[distances.indexOf(Math.min(...distances))]
}
const clamp = (x, a, b) => Math.max(a, Math.min(b, x))

export function installDevToolsLayout(el, root) {
  const panel = root.querySelector('.panel'), tools = root.querySelector('.tools')
  const grip = root.querySelector('[data-drag]'), resize = root.querySelector('.resize-handle')
  const splitter = root.querySelector('.splitter')
  let expanded = false, gesture = null, suppressClick = false, clickTimer
  const overlay = document.createElement('div')
  overlay.className = 'dock-overlay'
  overlay.hidden = true
  overlay.setAttribute('aria-hidden','true')
  overlay.innerHTML = docks.map((dock,i) => `<span class="dock-target" data-dock-target="${dock}" style="--anchor-x:${anchors[i][0]*100}%;--anchor-y:${anchors[i][1]*100}%">${dockName(dock)}</span>`).join('') + '<span class="dock-cursor"></span>'
  root.appendChild(overlay)
  const cursor = overlay.querySelector('.dock-cursor')
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
    variable('left',`${Math.round(x)}px`); variable('top',`${Math.round(y)}px`)
    variable('width',`${shownWidth}px`); variable('height',`${height}px`)
    layout.split = clamp(layout.split,20,80)
    variable('split',`${layout.split}%`)
    splitter.setAttribute('aria-valuenow',String(Math.round(layout.split)))
    tools.dataset.dock = layout.dock
    root.querySelector('[data-dock-label]').textContent = `${layout.dock} · drag header to dock`
    resize.dataset.edge = corner ? 'corner' : 'wide'
    resize.style.left = corner && right ? '0' : 'auto'
    resize.style.right = corner && right ? 'auto' : '0'
    resize.style.top = bottom ? '0' : 'auto'; resize.style.bottom = bottom ? 'auto' : '0'
    resize.style.cursor = corner ? (right === bottom ? 'nwse-resize' : 'nesw-resize') : 'ns-resize'
    resize.title = corner ? 'Drag to resize width and height' : 'Drag to resize height; dock in a corner to resize width'
  }
  const down = event => {
    const target = event.target.closest('.splitter, .resize-handle, header')
    if (!target || event.button !== 0 || gesture) return
    const kind = target === splitter ? 'split' : target === resize ? 'resize' : 'move'
    // Header controls retain normal focus and clicks until this becomes a drag.
    if (kind !== 'move') event.preventDefault()
    gesture = {target:event.target,kind,pointerId:event.pointerId,x:event.clientX,y:event.clientY,
      width:panel.offsetWidth,height:panel.offsetHeight,original:{...layout},
      box:el.getBoundingClientRect(),list:root.querySelector('.explorer').getBoundingClientRect(),moved:false}
  }
  const move = event => {
    if (!gesture || event.pointerId !== gesture.pointerId) return
    const dx = event.clientX-gesture.x, dy = event.clientY-gesture.y
    if (!gesture.moved && Math.abs(dx)+Math.abs(dy)<=4) return
    if (!gesture.moved) {
      gesture.moved = true
      gesture.target.setPointerCapture(event.pointerId)
    }
    event.preventDefault()
    if (gesture.kind === 'move') {
      tools.dataset.dragging = 'true'
      overlay.hidden = false
      const dock = nearestDock(event.clientX,event.clientY)
      overlay.querySelectorAll('[data-dock-target]').forEach(target => {
        target.dataset.active = String(target.dataset.dockTarget === dock)
      })
      cursor.textContent = `${dockName(dock)} · ${dock.includes('-') ? 'compact' : 'full width'}`
      cursor.style.left = `${clamp(event.clientX+16,8,innerWidth-190)}px`
      cursor.style.top = `${clamp(event.clientY+18,8,innerHeight-32)}px`
      // A full-width dock becomes a compact preview, so it can follow the pointer.
      const width = Math.min(gesture.width,layout.width,innerWidth-20)
      variable('width',`${width}px`)
      variable('left',`${clamp(event.clientX-(gesture.x-gesture.box.x)/gesture.width*width,0,innerWidth-width)}px`)
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
  const finish = cancelled => {
    if (!gesture) return
    const previous = gesture
    if (cancelled) layout = previous.original
    if (previous.moved) {
      // Suppress only the click generated by this gesture, never a later click.
      suppressClick = true
      clearTimeout(clickTimer)
      clickTimer = setTimeout(() => { suppressClick=false },0)
    }
    gesture = null
    if (previous.target.hasPointerCapture(previous.pointerId)) previous.target.releasePointerCapture(previous.pointerId)
    delete tools.dataset.dragging
    overlay.hidden = true
    apply(); persist()
  }
  const up = event => {
    if (!gesture || event.pointerId !== gesture.pointerId) return
    if (gesture.kind === 'move' && gesture.moved && event.type !== 'pointercancel') {
      layout.dock = nearestDock(event.clientX,event.clientY)
    }
    finish(event.type === 'pointercancel')
  }
  const click = event => { if (suppressClick) { suppressClick=false;event.preventDefault();event.stopImmediatePropagation() } }
  const key = event => {
    if (event.key === 'Escape' && gesture) { event.preventDefault();finish(true);return }
    if (!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End'].includes(event.key)) return
    if (event.target === splitter) {
      event.preventDefault()
      layout.split = event.key==='Home' ? 20 : event.key==='End' ? 80 : layout.split+(['ArrowLeft','ArrowDown'].includes(event.key)?-2:2)
    } else if (event.target === grip) {
      event.preventDefault()
      const delta = ['ArrowLeft','ArrowUp'].includes(event.key) ? -1 : 1
      layout.dock = event.key==='Home' ? docks[0] : event.key==='End' ? 'bottom' : docks[(docks.indexOf(layout.dock)+delta+docks.length)%docks.length]
    } else if (event.target === resize) {
      event.preventDefault()
      if (event.key==='ArrowLeft') layout.width-=20
      if (event.key==='ArrowRight') layout.width+=20
      if (event.key==='ArrowUp') layout.height-=20
      if (event.key==='ArrowDown') layout.height+=20
    } else return
    apply(); persist()
  }
  root.addEventListener('pointerdown',down); window.addEventListener('pointermove',move)
  window.addEventListener('pointerup',up); window.addEventListener('pointercancel',up)
  root.addEventListener('click',click,true); root.addEventListener('keydown',key)
  window.addEventListener('resize',apply)
  apply()
  return {
    expand(value) { expanded=value;apply() },
    destroy() {
      root.removeEventListener('pointerdown',down);window.removeEventListener('pointermove',move)
      window.removeEventListener('pointerup',up);window.removeEventListener('pointercancel',up)
      root.removeEventListener('click',click,true);root.removeEventListener('keydown',key)
      window.removeEventListener('resize',apply)
      clearTimeout(clickTimer);overlay.remove()
    },
  }
}
