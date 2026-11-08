// The root layout survives routed LiveView patches and cached navigation.
export function installDemoUI(fogOfWar) {
  const controls = document.getElementById('frontier-connection')
  if (!controls) return

  fogOfWar.subscribe(status => {
    const connected = status.socketConnected && status.connection === 'live'
    for (const button of controls.querySelectorAll('[data-connection]')) {
      const active = (button.dataset.connection === 'connect') === connected
      button.disabled = active
      button.classList.toggle('is-active', active)
      button.setAttribute('aria-pressed', String(active))
    }
    controls.querySelector('[data-label="connect"]').textContent = connected ? 'Connected' : 'Connect'
    controls.querySelector('[data-label="disconnect"]').textContent = connected ? 'Disconnect' : 'Disconnected'
    controls.querySelector('[data-connection-announcement]').textContent = connected ? 'Connected' : 'Disconnected'
  })
}
