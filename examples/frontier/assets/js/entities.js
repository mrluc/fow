// The server provides stable IDs and order. All display offsets live in CSS.
function capture(el) {
  return new Map([...el.children].map(node => {
    const sprite = node.querySelector('.entity-sprite')
    return [node.id, {
      sprite, rect: sprite.getBoundingClientRect(), copy: sprite.cloneNode(true),
    }]
  }))
}

const reducedMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches

export const FrontierEntities = {
  mounted() {
    this.positions = new Map()
    this.updated()
  },
  beforeUpdate() { this.positions = capture(this.el) },
  updated() {
    const current = capture(this.el)
    if (!reducedMotion()) {
      for (const [id, {sprite, rect}] of current) {
        const previous = this.positions.get(id)
        if (previous) {
          const scale = rect.width / sprite.offsetWidth || 1
          sprite.animate([
            {transform: `translate(${(previous.rect.x - rect.x) / scale}px, ${(previous.rect.y - rect.y) / scale}px)`},
            {transform: 'translate(0, 0)'},
          ], {duration: 400, easing: 'ease-out'})
        } else {
          sprite.animate([
            {opacity: 0, transform: 'translateY(8px)'},
            {opacity: 1, transform: 'translateY(0)'},
          ], {duration: 400, easing: 'ease-out'})
        }
      }
      for (const [id, previous] of this.positions) {
        if (!current.has(id)) depart(previous)
      }
    }
    this.positions = current
  },
  destroyed() {
    if (!reducedMotion()) for (const previous of this.positions.values()) depart(previous)
    this.positions.clear()
  },
}

function depart({copy, rect}) {
  copy.classList.add('entity-departure')
  Object.assign(copy.style, {
    position: 'fixed', left: rect.x + 'px', top: rect.y + 'px', width: rect.width + 'px',
    height: rect.height + 'px', margin: '0', zIndex: '3', pointerEvents: 'none',
  })
  copy.setAttribute('aria-hidden', 'true')
  document.body.append(copy)
  copy.animate([
    {opacity: 1, transform: 'translate(0, 0)'},
    {opacity: 0, transform: 'translate(16px, -12px)'},
  ], {duration: 350, easing: 'ease-out'})
    .finished.catch(() => {}).finally(() => copy.remove())
}
