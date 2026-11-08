// Predict while disconnected; multiplayer server snapshots reconcile the HUD online.
export function installGameBars(fogOfWar) {
  const panel = document.getElementById('frontier-bars')
  if (!panel) return
  const rules = JSON.parse(panel.dataset.gameRules)
  const move = panel.querySelector('[data-bar="move"]')
  const health = panel.querySelector('[data-bar="health"]')
  const connection = panel.querySelector('[data-bar="connection"]')
  const label = panel.querySelector('[data-connection-label]')
  const key = 'frontier:bar-prediction:v1'
  const lifetime = hp => 1000 * (
    Math.ceil(Math.max(0, hp - rules.offline_threshold) / rules.offline_fast_damage) +
    Math.ceil(Math.min(hp, rules.offline_threshold) / rules.offline_slow_damage)
  )
  const connectionMax = lifetime(rules.health_max)
  let state = {
    health: rules.health_max, connected: false, updated: Date.now(),
    elapsed: 0, damageHits: 0, connectionRemaining: connectionMax, moved: false,
  }
  try {
    const saved = JSON.parse(sessionStorage.getItem(key))
    if ([1, 2].includes(saved?.version)) {
      state = saved.state
      state.connectionRemaining ??= state.connected ? connectionMax : Math.max(0, state.budget - state.elapsed)
    }
  } catch (_) {}
  state.lives ??= rules.initial_lives
  const death = document.getElementById('frontier-death')
  const lives = panel.querySelector('[data-lives-count]')
  const icons = panel.querySelector('[data-lives-icons]')
  let renderedLives
  let noticeUntil = 0
  let paused = false
  let pausedAt = 0
  let authoritative = false
  let animation

  function update(now = Date.now()) {
    const previousHealth = state.health
    const ticks = paused ? 0 : Math.max(0, Math.floor((now - state.updated) / rules.tick_ms))
    const elapsed = ticks * rules.tick_ms
    state.updated = paused ? now : state.updated + elapsed
    if (state.connected) {
      state.connectionRemaining = Math.min(connectionMax, state.connectionRemaining + elapsed * rules.connection_recovery_multiplier)
      if (!authoritative && state.health > 0 && ticks) {
        const rate = rules.healing_per_second * ticks -
          (state.moved ? rules.healing_per_second - rules.moving_healing_per_second : 0)
        state.health = Math.min(rules.health_max, state.health + rate * rules.tick_ms / 1000)
        state.moved = false
      }
    } else {
      state.connectionRemaining = Math.max(0, state.connectionRemaining - elapsed)
      state.elapsed += elapsed
      const hits = Math.floor(state.elapsed / 1000) - state.damageHits
      if (hits > 0) {
        const fast = Math.min(hits, Math.max(0,
          Math.ceil((state.health - rules.offline_threshold) / rules.offline_fast_damage)))
        if (fast) state.health = Math.max(rules.offline_threshold,
          state.health - fast * rules.offline_fast_damage)
        state.health = Math.max(0, state.health - (hits - fast) * rules.offline_slow_damage)
        state.damageHits += hits
      }
    }
    if (state.health <= 0 && previousHealth > 0) {
      state.lives--
      state.deathAt = now - Math.max(0, state.elapsed - lifetime(state.offlineHealth ?? rules.health_max))
    }
    document.documentElement.classList.toggle('frontier-dead', state.health <= 0)
    if (death) {
      const dead = state.health <= 0
      death.hidden = !dead && now >= noticeUntil
      death.querySelector('[data-death-title]').textContent = dead ? 'You died' : 'Respawned'
      const seconds = Math.max(0, Math.ceil((rules.respawn_delay_ms - ((paused ? pausedAt : now) - (state.deathAt ?? now))) / 1000))
      death.querySelector('[data-death-detail]').textContent = dead ?
        (seconds ? `Respawning in ${seconds}…` : state.connected ? 'Respawning…' : 'Reconnect to respawn') : ''
    }
    if (lives && renderedLives !== state.lives) {
      renderedLives = state.lives
      lives.textContent = state.lives
      icons.replaceChildren()
      const add = className => {
        const icon = document.createElement('i')
        icon.className = 'life-scout ' + className
        icons.append(icon)
      }
      for (let i = 0; i < Math.max(rules.initial_lives, state.lives); i++) add(i < state.lives ? '' : 'life-spent')
      for (let i = 0; i < -state.lives; i++) add('life-debt')
    }
    health.value = state.health
    health.textContent = Math.round(state.health) + ' health'
    const remaining = state.connectionRemaining
    const recovery = Math.ceil((connectionMax - remaining) / rules.connection_recovery_multiplier / 1000)
    connection.value = remaining / connectionMax * connection.max
    connection.textContent = state.connected ? recovery + 's to recover' : Math.ceil(remaining / 1000) + 's'
    label.textContent = state.connected ? (recovery ? 'Recover ' + recovery + 's' : 'Connected') :
      'Reconnect ' + Math.ceil(remaining / 1000) + 's'
    try {
      sessionStorage.setItem(key, JSON.stringify({version: 2, rules: panel.dataset.gameRules, state}))
    } catch (_) {}
  }

  window.addEventListener('frontier:moved', () => {
    update()
    state.moved = true
    cancelAnimationFrame(animation)
    const started = performance.now()
    move.value = 0
    const draw = now => {
      move.value = Math.min(move.max, (now - started) / rules.move_recharge_ms * move.max)
      if (move.value < move.max) animation = requestAnimationFrame(draw)
    }
    animation = requestAnimationFrame(draw)
  })

  window.addEventListener('phx:frontier:player', ({detail}) => {
    update()
    authoritative = true
    paused = !!detail.paused
    pausedAt = Date.now()
    document.documentElement.classList.toggle('frontier-paused', paused)
    state.health = detail.health
    state.lives = detail.lives ?? state.lives
    if (detail.dead) state.deathAt = Date.now() - (rules.respawn_delay_ms - detail.respawn_remaining_ms)
    else state.deathAt = null
    state.updated = Date.now()
    // Server ticks own the move charge online, including corrections from another tab.
    cancelAnimationFrame(animation)
    move.value = Math.max(0, 1 - detail.move_remaining_ms / rules.move_recharge_ms) * move.max
    update()
  })

  fogOfWar.subscribe(status => {
    update()
    const connected = status.socketConnected && status.connection === 'live'
    if (connected !== state.connected) {
      state.offlineHealth = state.health
      state.connected = connected
      state.updated = Date.now()
      state.elapsed = 0
      state.damageHits = 0
      state.moved = false
    }
    update()
  })
  window.addEventListener('phx:frontier:respawned', () => {
    noticeUntil = Date.now() + 2000
    update()
  })
  window.addEventListener('click', event => {
    if ((paused || state.health <= 0) && event.target.closest?.('.tile-target')) {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }, true)
  setInterval(update, rules.tick_ms)
}

// Ask for a fresh record after a backgrounded tab resumes, even if nothing changed.
export const FrontierPlayer = {
  mounted() {
    this.handleEvent('frontier:respawn', async ({life, player_id}) => {
      window.dispatchEvent(new Event('frontier:respawning'))
      const marker = `frontier:respawn:${player_id}`
      try {
        const notify = sessionStorage.getItem(marker) !== String(life)
        if (notify) {
          const cache = window.fogOfWar.cache
          await cache.flush()
          const {rows} = await cache.inspect()
          for (const row of rows) if (row.path.startsWith('/multi/')) await cache.remove(row.path)
          sessionStorage.setItem(marker, String(life))
        }
        this.pushEvent('respawn_ready', {life, notify})
      } catch (error) {
        console.error('[Frontier] Could not clear remembered routes for respawn', error)
      }
    })
    this.syncPlayer = () => {
      if (document.visibilityState === 'visible') this.pushEvent('sync_player', {})
    }
    document.addEventListener('visibilitychange', this.syncPlayer)
  },
  reconnected() { this.pushEvent('sync_player', {}) },
  destroyed() { document.removeEventListener('visibilitychange', this.syncPlayer) },
}
