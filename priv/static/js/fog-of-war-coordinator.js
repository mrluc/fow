import {presentSavedPage} from './fog-of-war-presenter'
import {isExpired} from './fog-of-war-codec'
import {createFogOfWarCache} from './fog-of-war-cache'

export function installFogOfWarCoordinator(liveSocket, build, {transition = update => update(), accountKeyEndpoint} = {}) {
  const cache = createFogOfWarCache(build, {accountKeyEndpoint})
  const subscribers = new Set()
  const devTools = new Set()
  let lastStatus = null
  const navigationEvents = []
  const navigationSubscribers = new Set()
  let nextEvent = 0, liveAttempt = null, navigationTimer = null
  const redirect = liveSocket.redirect.bind(liveSocket)
  liveSocket.redirect = (to, ...args) => {
    if (snapshotMode && to === location.href) return
    return redirect(to, ...args)
  }
  const recordNavigation = (url, source) => {
    let cached = false
    try { cached = Boolean(cache.find(url)) } catch (_) { /* Logging must not break navigation. */ }
    const item = {id:`nav-${++nextEvent}`, path:url.pathname+url.search+url.hash,
      from:new URL(displayedURL).pathname, source, outcome:'attempt', time:Date.now(),
      cached}
    navigationEvents.unshift(item)
    if (navigationEvents.length > 200) navigationEvents.pop()
    navigationSubscribers.forEach(fn => fn())
    return item
  }
  const finishNavigation = (item, outcome, reason = '') => {
    Object.assign(item, {outcome, reason, time:Date.now()})
    navigationSubscribers.forEach(fn => fn())
  }
  cache.protect(location.pathname)
  window.addEventListener('phx:page-loading-start', event => {
    if (offline() || !event.detail?.to) return
    const url = new URL(event.detail.to, location.href)
    // LiveView can announce both redirect and root loading for one destination.
    if (liveAttempt?.path === url.pathname + url.search + url.hash) return
    if (liveAttempt) finishNavigation(liveAttempt, 'superseded')
    liveAttempt = recordNavigation(url, 'LiveView')
    const attempt = liveAttempt
    clearTimeout(navigationTimer)
    navigationTimer = setTimeout(async () => {
      if (liveAttempt !== attempt || offline() || !cache.find(url)) return
      unavailable = true
      finishNavigation(attempt, 'superseded', 'Navigation stalled; showing cached page.')
      liveAttempt = null
      await navigate(url)
      refresh()
    }, 1200)
  })
  const pruneExpired = () => { cache.pruneExpired().catch(() => {}) }
  window.addEventListener('phx:page-loading-stop', () => {
    pruneExpired()
    clearTimeout(navigationTimer)
    cache.protect(location.pathname)
    if (liveAttempt && !offline()) {
      liveAttempt.path = location.pathname + location.search + location.hash
      finishNavigation(liveAttempt, 'live')
      liveAttempt = null
    }
  })
  let paused = false
  let unavailable = Boolean(window.__fogOfWarNativeBundle)
  let everOpened = false
  const offline = () => paused || unavailable
  let snapshotMode = false
  let message = ''
  let outlet = null
  let displayedURL = location.href
  const initiallyRouted = Boolean(document.querySelector('[data-phx-main]'))
  const mainUnavailable = () => {
    const el = document.querySelector('[data-phx-main]')
    const view = liveSocket.main
    return !el || !view || view.el !== el || !el.isConnected || view.isDestroyed()
  }
  const mainReady = () => !mainUnavailable() && liveSocket.main.isConnected()
  const setText = (id, text) => {
    const el = document.getElementById(id)
    if (el && el.textContent !== text) el.textContent = text
  }
  // Idempotent writes: our class observer also sees these styling updates.
  const setClass = (el, name, enabled) => {
    if (el.classList.contains(name) !== enabled) el.classList.toggle(name, enabled)
  }
  const refreshNavigationStyles = () => {
    setClass(document.documentElement, 'fow-offline', offline())
    const destinations = new Map()
    const cached = href => {
      try {
        const url = new URL(href, location.href)
        if (!destinations.has(url.href)) destinations.set(url.href, Boolean(cache.find(url)))
        return destinations.get(url.href)
      } catch (_) { return false }
    }
    for (const container of document.querySelectorAll('.fow-nav')) {
      const links = container.matches('a[href]') ? [container] : [...container.querySelectorAll('a[href]')]
      const destination = container.dataset.fogOfWarTo
      const uncached = destination ? !cached(destination) : links.some(link => !cached(link.href))
      setClass(container, 'fow-nav-uncached', uncached)
    }
  }
  const refresh = () => {
    refreshNavigationStyles()
    const ready = liveSocket.isConnected() && mainReady()
    document.documentElement.dataset.connection = offline() ? 'paused' : ready ? 'live' : 'connecting'
    const counter = document.querySelector('#persistent-counter, #shell-press')
    if (counter) counter.disabled = offline() || !ready
    const faultButton = document.getElementById('server-outage')
    if (faultButton) faultButton.disabled = offline() || !ready
    const banner = document.getElementById('fog-of-war-debug-banner')
    if (banner) banner.hidden = !(offline() && document.body.dataset.fogOfWarDebug === 'loud')
    setText('connection-state', paused ? 'Paused · socket closed' : unavailable ? 'Server unavailable · retrying' : ready ? 'Live · view ready' : 'Connecting…')
    setText('connection-toggle', offline() ? 'Reconnect' : 'Pause connection')
    setText('fow-debug-message', message)
    const debugMessage = document.getElementById('fow-debug-message')
    if (debugMessage) debugMessage.hidden = !message
    setText('fog-of-war-debug-detail', paused ? 'DEBUG MODE · CONNECTION PAUSED' : 'DEBUG MODE · SERVER UNAVAILABLE')
    setText('connection-note', message || 'Browser-side control · closes this tab’s LiveView socket.')
    const status = {socketConnected: liveSocket.isConnected() && !paused, connection: offline() ? 'paused' : ready ? 'live' : 'connecting',
      text: paused ? 'Paused' : unavailable ? 'Server unavailable' : ready ? 'Live' : 'Connecting',
      message, snapshotMode, toggleLabel: offline() ? 'Reconnect' : 'Pause connection'}
    if (JSON.stringify(status) !== JSON.stringify(lastStatus)) {
      lastStatus = status
      subscribers.forEach(fn => fn(status))
    }
  }
  const lookup = async url => {
    try { return await cache.load(url) } catch (_) { return null }
  }
  const enterSnapshotMode = () => {
    const main = document.querySelector('[data-phx-main]')
    if (!main) throw new Error('No live region to retire')
    const preserved = [...devTools].map(controller => { controller.retain(); return controller.el })
    const shell = document.getElementById('persistent-shell')
    const page = document.createElement('main')
    page.className = 'lab'
    page.id = 'fog-of-war-offline-page'
    outlet = document.createElement('div')
    outlet.id = 'fog-of-war-offline-outlet'
    // Preserve only the toolbar markup/local listeners, not a hidden live page.
    // Internal adapter, pinned to LV 1.2.13: release owners/hooks/channels once.
    // Reconnect from this mode uses a full GET, never these retired owners.
    liveSocket.destroyAllViews()
    if (shell) page.append(shell)
    page.append(...preserved)
    page.append(outlet)
    main.replaceWith(page)
    snapshotMode = true
  }
  let navigation = 0
  const navigate = async (url, historyAction = 'push') => {
    const identityVersion = cache.identityVersion()
    const attempt = ++navigation
    const log = recordNavigation(url, historyAction === "pop" ? "History" : "Cached navigation")
    await cache.protect(url.pathname)
    const snapshot = await lookup(url)
    if (attempt !== navigation || identityVersion !== cache.identityVersion() || !offline()) { finishNavigation(log, 'superseded'); return true }
    if (!snapshot) {
      await cache.protect(new URL(displayedURL).pathname)
      message = 'This page is not available offline; it has not been saved.'
      finishNavigation(log, 'denied', 'No usable saved page for this destination.')
      refresh()
      return false
    }
    // Construct/validate the presentation before changing the URL.
    await transition(async () => {
      if (!await cache.canPresent(snapshot)) return
      if (identityVersion !== cache.identityVersion() || isExpired(snapshot)) return
      if (!snapshotMode) enterSnapshotMode()
      presentSavedPage(outlet, snapshot)
      // The route and its visible content commit together, including during a
      // delayed View Transition callback. A quick Back must not skip this stop.
      if (historyAction !== 'pop') {
        history[historyAction === 'replace' ? 'replaceState' : 'pushState']({fogOfWar: true}, '', url.href)
      }
      displayedURL = url.href
      finishNavigation(log, 'cached')
      pruneExpired()
      cache.protect(url.pathname)
      message = ''
      refresh()
    }, url)
    return true
  }
  const toggleConnection = intent => {
    navigation++
    const connect = intent === 'connect' || (intent !== 'disconnect' && (offline() || !mainReady()))
    if (connect && (snapshotMode || mainUnavailable() || (liveSocket.isConnected() && !mainReady()))) {
      // A socket may serve sticky LiveViews even after its routed page was retired.
      // Reconnecting that socket cannot resurrect the missing page owner.
      paused = false
      location.assign(location.href)
      return
    }
    message = ''
    if (connect) {
      paused = false
      if (unavailable) {
        unavailable = false
        liveSocket.disconnect(() => liveSocket.connect())
      } else liveSocket.connect()
    } else {
      paused = true
      liveSocket.disconnect(refresh)
    }
    refresh()
  }
  document.addEventListener('click', event => {
    const target = event.target instanceof Element ? event.target : null
    // Shadow DOM retargets developer-tool events to their host. Its hook owns them.
    if (target?.closest('[data-fog-of-war-dev-tools]')) return
    if (target?.closest('[data-connection-toggle]')) {
      event.preventDefault()
      event.stopImmediatePropagation()
      toggleConnection(target.closest('[data-connection-toggle]').dataset.connection)
      return
    }
    if (!offline()) return
    const link = target?.closest('a[href]')
    if (link?.target === '_blank' && new URL(link.href, location.href).origin !== location.origin) return
    if (link?.getAttribute('href').startsWith('#')) return
    if (link) {
      event.preventDefault()
      event.stopImmediatePropagation()
      navigate(new URL(link.href), link.dataset.phxLinkState === 'replace' ? 'replace' : 'push')
    } else if (target?.closest('[phx-click], [phx-click-away], button')) {
      event.preventDefault()
      event.stopImmediatePropagation()
      message = 'Read-only while offline; nothing queued.'
      refresh()
    }
  }, true)
  // Install before LiveView binds its own history listener; stop competing pop handlers.
  window.addEventListener('popstate', async event => {
    if (!offline()) return
    event.stopImmediatePropagation()
    if (!(await navigate(new URL(location.href), 'pop'))) history.replaceState({fogOfWar: true}, '', displayedURL)
  }, true)
  for (const name of ['submit', 'input', 'change', 'keydown', 'keyup', 'focusin', 'focusout']) {
    document.addEventListener(name, event => {
      if (!offline() || event.target.closest?.('#connection-controls, #persistent-shell, [data-fog-of-war-dev-tools]')) return
      event.stopImmediatePropagation()
      if (name === 'submit') event.preventDefault()
    }, true)
  }
  liveSocket.getSocket().onOpen(() => {
    everOpened = true
    if (!paused && (snapshotMode || (initiallyRouted && mainUnavailable()))) {
      location.assign(location.href)
      return
    }
    unavailable = false
    refresh()
  })
  const connectionLost = () => {
    if (everOpened && !paused) unavailable = true
    refresh()
  }
  liveSocket.getSocket().onClose(connectionLost)
  liveSocket.getSocket().onError(connectionLost)
  new MutationObserver(refresh).observe(document.body, {
    childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'data-phx-main', 'data-phx-session'],
  })
  cache.subscribe(refresh)
  pruneExpired()
  refresh()
  return {
    cache, toggleConnection,
    unlockAccount: cache.unlockAccount, lockAccount: cache.lockAccount,
    navigationEvents: () => navigationEvents.map(item => ({...item})),
    subscribeNavigations(fn) { navigationSubscribers.add(fn); return () => navigationSubscribers.delete(fn) },
    clearNavigations() { navigationEvents.length = 0; navigationSubscribers.forEach(fn => fn()) },
    canCapture: () => !offline() && !snapshotMode && liveSocket.isConnected(),
    subscribe(fn) { subscribers.add(fn); fn(lastStatus); return () => subscribers.delete(fn) },
    registerDevTools(controller) { devTools.add(controller); return () => devTools.delete(controller) },
  }
}
