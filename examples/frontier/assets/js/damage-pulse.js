const damageAnimations = new WeakMap()

export function pulseDamage(target, {hud = false, delay = 0} = {}) {
  if (!target) return
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
  damageAnimations.get(target)?.cancel()
  const base = getComputedStyle(target).filter
  const tint = hud ? base : 'sepia(1) saturate(6) hue-rotate(315deg) brightness(1.25)'
  const flash = hud ? {boxShadow: '0 0 18px 5px #ef514880', backgroundColor: '#a722222b'} : {}
  const frames = [
    {offset: 0, filter: base, translate: '0 0', boxShadow: '0 0 0 0 transparent'},
    {offset: .12, filter: tint, translate: reduced ? '0 0' : '0 -4px', ...flash},
    {offset: .32, filter: base, translate: '0 0', boxShadow: '0 0 0 0 transparent'},
    {offset: .48, filter: tint, translate: reduced ? '0 0' : '0 -2px', ...flash},
    {offset: 1, filter: base, translate: '0 0', boxShadow: '0 0 0 0 transparent', backgroundColor: 'transparent'},
  ]
  damageAnimations.set(target, target.animate(frames, {duration: reduced ? 200 : 650, easing: 'ease-out', delay}))
}
