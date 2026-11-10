import {pulseDamage} from './damage-pulse'

const SVG_NS = 'http://www.w3.org/2000/svg'

function effect(layer, x, y, className, shapes) {
  const svg = document.createElementNS(SVG_NS, 'svg')
  svg.classList.add('elixir-effect', className)
  svg.setAttribute('width', '1')
  svg.setAttribute('height', '1')
  svg.style.left = `${x}px`
  svg.style.top = `${y}px`
  svg.innerHTML = shapes
  layer.append(svg)
  return svg
}

function animateEffect(svg, frames, timing) {
  svg.animate(frames, timing).finished.then(() => svg.remove(), () => svg.remove())
}

function ringPoint(radius, angle, height = 0) {
  return `${(radius * Math.cos(angle)).toFixed(2)},${(radius * Math.sin(angle) * .5 - height).toFixed(2)}`
}

const beastReactions = new WeakMap()
let slayNoticeTimer

function reactBeast(defeated, slayer, delay) {
  const duration = defeated ? 900 : 610
  const beast = document.querySelector('#multi-entities .entity-monster')
  if (beast) {
    const style = getComputedStyle(beast)
    const idle = style.getPropertyValue('--beast-idle').trim()
    const kneel = style.getPropertyValue('--beast-kneel').trim()
    const puddle = style.getPropertyValue('--beast-puddle').trim()
    const hold = 'steps(1, end)'
    beastReactions.get(beast)?.cancel()
    beast.style.animationName = 'none'
    const reaction = beast.animate(defeated ? [
      {backgroundImage: idle, opacity: 1, easing: hold},
      {backgroundImage: kneel, opacity: 1, offset: .25, easing: hold},
      {backgroundImage: puddle, opacity: 1, offset: .55},
      {backgroundImage: puddle, opacity: 0},
    ] : [
      {backgroundImage: idle, easing: hold},
      {backgroundImage: kneel, offset: .14, easing: hold},
      {backgroundImage: idle, offset: .8},
      {backgroundImage: idle},
    ], {delay, duration, fill: 'backwards'})
    beastReactions.set(beast, reaction)
    pulseDamage(beast, {delay})
    reaction.finished.catch(() => {}).finally(() => {
      if (beastReactions.get(beast) === reaction) beast.style.removeProperty('animation-name')
    })
  }

  const notice = document.getElementById('frontier-slay-notice')
  if (slayer && notice) {
    clearTimeout(slayNoticeTimer)
    slayNoticeTimer = setTimeout(() => {
      notice.textContent = 'You slayed the Pitch Beast'
      slayNoticeTimer = setTimeout(() => { notice.textContent = '' }, 4000)
    }, delay + duration)
  }
}

let castShake

window.addEventListener('phx:frontier:elixir_strike', ({detail}) => {
  const layer = document.getElementById('elixir-effects')
  const actor = document.getElementById(detail.sprite_id)
  const sprite = actor?.querySelector('.entity-sprite') || actor
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
  const impact = reduced ? 0 : 260
  reactBeast(detail.defeated, detail.slayer, impact)
  if (!layer || !sprite) return

  // Read the sprite's feet in map space, before levitation moves the art.
  const scene = layer.parentElement
  const map = scene.getBoundingClientRect()
  const feet = sprite.getBoundingClientRect()
  const scale = map.width / scene.offsetWidth
  const x = (feet.left + feet.width / 2 - map.left) / scale
  const y = (feet.bottom - map.top) / scale
  const depth = Math.round(y)
  const filter = getComputedStyle(sprite).filter
  const glow = 'brightness(1.28) drop-shadow(0 0 5px #ef9fff) drop-shadow(0 0 12px #a22cff)'

  sprite.animate(reduced
    ? [{filter}, {filter: glow}, {filter}]
    : [
      {translate: '0 0', filter},
      {translate: '0 -28px', filter: glow, offset: .28},
      {translate: '0 -25px', filter: glow, offset: .68},
      {translate: '0 0', filter},
    ], {duration: reduced ? 450 : 940, easing: 'ease-in-out'})

  if (!reduced) {
    if (detail.sprite_id === 'player') {
      // Shake the viewport so the terrain, sprites and beam move together.
      castShake?.cancel()
      castShake = scene.parentElement.animate([
        {translate: '0 0'},
        {translate: '-5px 3px', offset: .12},
        {translate: '4px -2px', offset: .27},
        {translate: '-2px 1px', offset: .48},
        {translate: '1px 0', offset: .68},
        {translate: '0 0'},
      ], {duration: 180})
    }

    const style = getComputedStyle(sprite)
    const walk = style.getPropertyValue('--elixir-walk-frame').trim()
    const idle = style.backgroundImage
    sprite.animate([
      {backgroundImage: idle, offset: 0, easing: 'steps(1, end)'},
      {backgroundImage: walk, offset: .5, easing: 'steps(1, end)'},
      {backgroundImage: idle, offset: 1},
    ], {duration: 160, iterations: 5})
  }

  const beam = effect(layer, x, y, 'elixir-beam', `
    <path fill="#922dff" opacity=".48" d="M-28 -280H32L17 -26 34 0 3 12 -30 2 -14 -25Z"/>
    <path fill="#cb62ff" opacity=".86" d="M-12 -280H21L9 -31 19 0 0 8 -16 1 -7 -26Z"/>
    <path fill="#f8e8ff" d="M-4 -280H8L4 -17 9 1 0 5 -6 0Z"/>
    <path fill="#d799ff" opacity=".78" d="M-40 -162L-18 -84 -26 -49Z M42 -209L24 -121 28 -60Z"/>
  `)
  beam.style.zIndex = String(depth - 2)
  animateEffect(beam, [
    {opacity: .85, transform: reduced ? 'none' : 'scaleX(.55)'},
    {opacity: .95, transform: 'none', offset: .08},
    {opacity: .55, transform: reduced ? 'none' : 'scaleX(.8)', offset: .58},
    {opacity: 0, transform: reduced ? 'none' : 'scaleX(.45)'},
  ], {duration: reduced ? 310 : 450, easing: 'ease-out'})

  const ground = effect(layer, x, y, 'elixir-ground', `
    <ellipse rx="96" ry="48" fill="#b241fa" fill-opacity=".25" stroke="#cc77ff" stroke-width="3"/>
    <ellipse rx="83" ry="41.5" fill="none" stroke="#f6daff" stroke-opacity=".8" stroke-width="1.5"/>
  `)
  animateEffect(ground, [
    {opacity: .9, transform: reduced ? 'none' : 'scale(.1)'},
    {opacity: 0, transform: reduced ? 'none' : 'scale(1.45)'},
  ], {delay: impact, duration: 520, easing: 'ease-out'})

  // Each segment has its own map depth so the far and near arcs can straddle sprites.
  for (let i = 0; i < 12; i++) {
    const start = i * Math.PI / 6
    const end = start + Math.PI / 6 - .025
    const angle = (start + end) / 2
    const offset = Math.sin(angle) * 52
    const outer = [ringPoint(102, start), ringPoint(102, end)]
    const crest = ringPoint(91, angle, 22 + (i % 3) * 6)
    const inner = [ringPoint(76, start), ringPoint(76, end)]
    const shard = effect(layer, x, y, 'elixir-shard', `
      <polygon points="${outer.join(' ')} ${crest}" fill="#9f46ff" fill-opacity=".66"/>
      <polygon points="${inner[0]} ${outer[0]} ${crest}" fill="#f4c6ff" fill-opacity=".85"/>
      <polygon points="${inner[0]} ${crest} ${outer[1]} ${inner[1]}" fill="#c772ff" fill-opacity=".62"/>
    `)
    animateEffect(shard, [
      {opacity: .95, transform: reduced ? 'none' : 'scale(.14)', zIndex: Math.round(depth + offset * (reduced ? 1 : .14))},
      {opacity: .72, offset: .35},
      {opacity: 0, transform: reduced ? 'none' : 'scale(1.35)', zIndex: Math.round(depth + offset * (reduced ? 1 : 1.35))},
    ], {delay: impact, duration: reduced ? 320 : 570, easing: 'ease-out'})
  }
})
