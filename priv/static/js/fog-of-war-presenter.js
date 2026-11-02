// Deliberately small, read-only offline presentation. No scripts, hooks, resource loads or
// LiveView owner/session attributes are carried into the offline presentation.
const TAGS = new Set(['SECTION', 'DIV', 'HEADER', 'MAIN', 'SPAN', 'H1', 'H2', 'H3', 'P', 'OUTPUT',
  'ASIDE', 'FOOTER', 'I', 'NAV', 'A', 'BUTTON', 'STRONG', 'EM', 'CODE', 'PRE', 'UL', 'OL', 'LI', 'BR'])
const ATTRS = new Set(['id', 'class', 'aria-label', 'aria-labelledby', 'role', 'data-fog-of-war-path', 'data-fog-of-war-to'])

export function readOnlyRegion(html) {
  const template = document.createElement('template')
  template.innerHTML = html // Template content is inert; only allowlisted nodes are adopted.
  const copy = node => {
    if (node.nodeType === Node.TEXT_NODE) return document.createTextNode(node.textContent)
    if (node.nodeType !== Node.ELEMENT_NODE || !TAGS.has(node.tagName)) return null
    const el = document.createElement(node.tagName.toLowerCase())
    for (const attr of node.attributes) if (ATTRS.has(attr.name)) el.setAttribute(attr.name, attr.value)
    if (node.tagName === 'A') {
      const href = node.getAttribute('href')
      if (href) {
        const url = new URL(href, location.origin)
        if (url.origin === location.origin && ['http:', 'https:'].includes(url.protocol)) el.setAttribute('href', href)
      }
    }
    if (node.tagName === 'BUTTON') {
      el.disabled = true
      el.setAttribute('aria-disabled', 'true')
    }
    for (const child of node.childNodes) {
      const safe = copy(child)
      if (safe) el.append(safe)
    }
    return el
  }
  const root = template.content.firstElementChild
  if (!root || template.content.children.length !== 1) throw new Error('Snapshot must have one region')
  const region = copy(root)
  if (!region) throw new Error('Unsupported snapshot region')
  region.dataset.fogOfWarMode = 'snapshot'
  return region
}

export function presentSavedPage(host, snapshot) {
  const region = readOnlyRegion(snapshot.html)
  host.replaceChildren(region)
  if (snapshot.title) document.title = snapshot.title
  window.scrollTo(0, 0)
}
