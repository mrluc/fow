const bytes = value => value < 1024 ? `${value} B` : value < 1024 ** 2 ? `${(value / 1024).toFixed(1)} KiB` : `${(value / 1024 ** 2).toFixed(2)} MiB`

export function createDevToolsHook(coordinator) {
  return {
    mounted() { this.tools = mountDevTools(this.el, coordinator) },
    destroyed() { this.tools?.destroy() },
  }
}

function mountDevTools(el, coordinator) {
  const root = el.attachShadow({mode: 'open'})
  root.append(el.querySelector('template').content.cloneNode(true))
  const get = selector => root.querySelector(selector)
  const tools = get('.tools')
  let retained = false, expanded = false, tab = 'connection', selected = null, rows = []
  let refreshVersion = 0, cacheSignature = null

  const notice = (text, kind = '') => {
    const node = get('[data-cache-message]')
    node.textContent = text
    node.title = text
    node.dataset.kind = kind
  }
  const select = key => {
    selected = key
    root.querySelectorAll('tbody tr').forEach(row => { row.dataset.selected = String(row.dataset.key === key) })
    const entry = rows.find(row => row.key === key)
    if (!entry) {
      get('[data-detail]').textContent = 'Select a page to inspect its metadata and HTML.'
      return
    }
    const {html, ...metadata} = entry.snapshot || {}
    get('[data-detail]').textContent = JSON.stringify({key: entry.key, storageBytes: entry.bytes,
      openInTab: entry.open, ...metadata}, null, 2) + '\n\n' + (html || entry.raw)
  }
  const refreshCache = async () => {
    const version = ++refreshVersion
    try {
      const result = await coordinator.cache.inspect()
      if (version !== refreshVersion) return
      rows = result.rows
      get('[data-count]').textContent = String(rows.length)
      get('[data-summary]').textContent = `${rows.length} entries · ${bytes(result.bytes)}`
      get('[data-total]').textContent = `${rows.length} entries · ${bytes(result.bytes)}`
      get('[data-total]').title = 'Estimated localStorage bytes: UTF-16 keys and values. Fog of War entries only.'
      const clear = get('[data-action="clear"]')
      clear.disabled = !result.canClear || !rows.some(row => row.valid && !row.open)
      clear.title = result.canClear ? 'Clear saved pages except routes open in Fog of War tabs' : result.reason
      const signature = JSON.stringify(rows.map(row => [row.key, row.raw, row.open]))
      if (signature === cacheSignature) return // Keep text selection, scroll and keyboard focus stable.
      cacheSignature = signature
      const body = get('[data-rows]')
      const fragment = document.createDocumentFragment()
      rows.forEach(entry => {
        const row = document.createElement('tr')
        row.dataset.key = entry.key
        row.tabIndex = 0
        row.setAttribute('aria-label', `Inspect ${entry.path}`)
        const saved = entry.snapshot?.savedAt
        const values = [entry.path, bytes(entry.bytes), saved ? new Date(saved).toLocaleTimeString() : 'Invalid',
          entry.snapshot?.build || '—', entry.open ? '●' : '']
        values.forEach(value => { const cell = document.createElement('td'); cell.textContent = value; cell.title = value; row.append(cell) })
        row.lastElementChild.title = entry.open ? 'Protected: this route is open in a Fog of War tab' : 'Not open'
        fragment.append(row)
      })
      body.replaceChildren(fragment)
      get('[data-empty]').hidden = rows.length > 0
      select(selected)
    } catch (error) {
      notice(`Cache unavailable: ${error.message}`, 'error')
      get('[data-action="clear"]').disabled = true
    }
  }
  const showTab = name => {
    tab = name
    root.querySelectorAll('[role="tab"]').forEach(button => {
      const active = button.dataset.tab === name
      button.setAttribute('aria-selected', String(active))
      button.tabIndex = active ? 0 : -1
    })
    get('#connection-pane').hidden = name !== 'connection'
    get('#cache-pane').hidden = name !== 'cache'
    if (name === 'cache') refreshCache()
  }
  const setExpanded = value => {
    expanded = value
    get('.launcher').hidden = value
    get('.launcher').setAttribute('aria-expanded', String(value))
    get('.panel').hidden = !value
    if (value) { refreshCache(); get(`[data-tab="${tab}"]`).focus() }
    else get('.launcher').focus()
  }
  const click = async event => {
    const target = event.target.closest('[data-action], [data-tab], [data-key]')
    if (!target) return
    if (target.dataset.tab) { showTab(target.dataset.tab); return }
    if (target.dataset.key) { select(target.dataset.key); return }
    switch (target.dataset.action) {
      case 'expand': setExpanded(true); break
      case 'collapse': setExpanded(false); break
      case 'connection': coordinator.toggleConnection(); break
      case 'refresh': notice(''); await refreshCache(); break
      case 'clear':
        target.disabled = true
        target.setAttribute('aria-busy', 'true')
        try {
          const result = await coordinator.cache.clearUnused()
          notice(`Cleared ${result.removed} · ${bytes(result.bytes)}; kept ${result.protectedCount} open` +
            (result.unreadable ? `, ${result.unreadable} unreadable` : ''), 'success')
        } catch (error) { notice(error.message, 'error') }
        finally { target.removeAttribute('aria-busy'); await refreshCache() }
        break
    }
  }
  const keydown = event => {
    if (event.key === 'Escape' && expanded) { event.preventDefault(); setExpanded(false) }
    const button = event.target.closest('[role="tab"]')
    if (button && ['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) {
      event.preventDefault()
      const name = event.key === 'Home' ? 'connection' : event.key === 'End' ? 'cache' : tab === 'cache' ? 'connection' : 'cache'
      showTab(name); get(`[data-tab="${name}"]`).focus()
    }
    const row = event.target.closest('[data-key]')
    if (row && ['Enter', ' '].includes(event.key)) { event.preventDefault(); select(row.dataset.key) }
  }
  root.addEventListener('click', click)
  root.addEventListener('keydown', keydown)
  const unsubscribeStatus = coordinator.subscribe(status => {
    tools.dataset.connection = status.connection
    get('[data-state]').textContent = status.text + (status.snapshotMode ? ' · cached page' : '')
    get('[data-action="connection"]').textContent = status.toggleLabel
    get('[data-message]').textContent = status.message || (status.snapshotMode ? 'Read-only HTML. Reconnect loads this route from the server.' : 'Pause closes this tab’s LiveView socket.')
    get('[data-message]').title = get('[data-message]').textContent
  })
  const unsubscribeCache = coordinator.cache.subscribe(refreshCache)
  const timer = window.setInterval(() => { if (expanded && tab === 'cache') refreshCache() }, 2000)
  const controller = {
    el,
    retain() { retained = true },
    destroy() {
      // Offline browsing explicitly transfers this DOM/listener lifetime from LV to the coordinator.
      if (retained) return
      unsubscribeStatus(); unsubscribeCache(); unregister()
      window.clearInterval(timer)
      root.removeEventListener('click', click)
      root.removeEventListener('keydown', keydown)
    },
  }
  const unregister = coordinator.registerDevTools(controller)
  refreshCache()
  return controller
}
