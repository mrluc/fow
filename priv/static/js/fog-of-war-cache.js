// Keep route metadata readable, compress only the repetitive HTML payload.
async function encodeSnapshot(snapshot) {
  const plain = JSON.stringify(snapshot)
  if (typeof CompressionStream === 'undefined' || typeof DecompressionStream === 'undefined') return plain
  const input = new TextEncoder().encode(snapshot.html)
  const bytes = new Uint8Array(await new Response(new Blob([input]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer())
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  const {html, ...metadata} = snapshot
  const packed = JSON.stringify({...metadata, htmlEncoding:'gzip-base64', htmlBytes:input.length, htmlGzip:btoa(binary)})
  return packed.length < plain.length ? packed : plain
}

async function decodeSnapshot(snapshot) {
  if (typeof snapshot.html === 'string') return snapshot
  const bytes = Uint8Array.from(atob(snapshot.htmlGzip), c => c.charCodeAt(0))
  const html = await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'))).text()
  const {htmlEncoding, htmlGzip, htmlBytes, ...metadata} = snapshot
  return {...metadata, html}
}

const PREFIX = 'fog-of-war:page:'
const OPEN = 'fog-of-war:open:'
const MAINTENANCE = 'fog-of-war:cache-maintenance'

// Web Locks identify live documents without guessing from an expiring heartbeat.
// Both route registration and deletion cross the same maintenance lock.
export function createFogOfWarCache(build) {
  let currentPath = location.pathname
  let heldPath, releasePath
  let protection = Promise.resolve()
  let lockError = null
  let writes = Promise.resolve()
  const locks = navigator.locks
  const supported = Boolean(locks?.request && locks?.query)
  const listeners = new Set()
  const changed = () => listeners.forEach(fn => fn())
  window.addEventListener('storage', event => {
    if (event.key === null || event.key.startsWith(PREFIX)) changed()
  })

  const entries = () => Object.keys(localStorage).filter(key => key.startsWith(PREFIX)).map(key => {
    const raw = localStorage.getItem(key) || ''
    let snapshot
    try { snapshot = JSON.parse(raw) } catch (_) { /* Keep corrupt entries visible, never guess their route. */ }
    const valid = snapshot && typeof snapshot.path === 'string' && snapshot.path.startsWith('/') && (typeof snapshot.html === 'string' ||
      (snapshot.htmlEncoding === 'gzip-base64' && typeof snapshot.htmlGzip === 'string' && typeof DecompressionStream !== 'undefined'))
    return {key, raw, snapshot, valid: Boolean(valid), path: valid ? snapshot.path : '(unreadable)',
      bytes: 2 * (key.length + raw.length)}
  }).sort((a, b) => a.path.localeCompare(b.path) || a.key.localeCompare(b.key))

  function protect(path) {
    currentPath = path
    if (!supported) return Promise.resolve()
    protection = protection.then(() => locks.request(MAINTENANCE, async () => {
      if (heldPath === path) return
      let release, acquired, failed
      const ready = new Promise((resolve, reject) => { acquired = resolve; failed = reject })
      const lifetime = new Promise(resolve => { release = resolve })
      locks.request(OPEN + path, {mode: 'shared'}, () => { acquired(); return lifetime }).catch(failed)
      await ready // Acquire the new route before releasing the previous route.
      releasePath?.()
      releasePath = release
      heldPath = path
    })).catch(error => { lockError = error })
    return protection
  }

  const openPaths = async () => {
    if (!supported || lockError) return new Set([currentPath])
    const {held} = await locks.query()
    return new Set(held.filter(lock => lock.name.startsWith(OPEN)).map(lock => lock.name.slice(OPEN.length)))
  }

  return {
    protect,
    save(snapshot, {protectRoute = true} = {}) {
      const job = writes.then(async () => {
        if (protectRoute) await protect(snapshot.path)
        const encoded = await encodeSnapshot(snapshot)
        const write = () => {
          const key = `${PREFIX}${snapshot.path}`
          localStorage.setItem(key, encoded)
          for (const row of entries()) {
            if (row.valid && row.path === snapshot.path && row.key !== key) localStorage.removeItem(row.key)
          }
        }
        if (supported && !lockError) await locks.request(MAINTENANCE, write)
        else write()
        changed()
        return encoded
      })
      // Compression is async; preserve capture order even when views update rapidly.
      writes = job.catch(() => {})
      return job
    },
    decode: decodeSnapshot,
    async load(url) {
      const snapshot = this.find(url)
      return snapshot ? decodeSnapshot(snapshot) : null
    },
    find(url) {
      if (url.origin !== location.origin || url.search) return null
      return entries().filter(entry => entry.valid && entry.path === url.pathname &&
        entry.snapshot.schema === 1 && entry.snapshot.build === build &&
        Number.isFinite(Date.parse(entry.snapshot.savedAt)))
        .sort((a, b) => Date.parse(b.snapshot.savedAt) - Date.parse(a.snapshot.savedAt))[0]?.snapshot || null
    },
    async inspect() {
      await protection
      const open = await openPaths()
      const rows = entries().map(entry => ({...entry, open: open.has(entry.path) || entry.path === currentPath}))
      return {rows, bytes: rows.reduce((sum, row) => sum + row.bytes, 0),
        canClear: supported && !lockError,
        reason: lockError?.message || 'Safe clearing requires the browser Web Locks API.'}
    },
    async clearUnused() {
      await protection
      if (!supported || lockError) throw new Error('Safe clearing is unavailable in this browser.')
      const result = await locks.request(MAINTENANCE, async () => {
        const open = await openPaths()
        open.add(currentPath)
        let removed = 0, bytes = 0, protectedCount = 0, unreadable = 0
        for (const row of entries()) {
          if (!row.valid) { unreadable++; continue }
          if (open.has(row.path)) { protectedCount++; continue }
          localStorage.removeItem(row.key)
          removed++; bytes += row.bytes
        }
        return {removed, bytes, protectedCount, unreadable}
      })
      changed()
      return result
    },
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn) },
  }
}
