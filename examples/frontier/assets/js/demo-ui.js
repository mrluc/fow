// The root layout survives routed LiveView patches and cached navigation.
export function installDemoUI(fogOfWar) {
  const controls = document.getElementById('frontier-connection')
  if (!controls) return
  const button = controls.querySelector('[data-connection-toggle]')
  fogOfWar.subscribe(status => {
    const online = status.socketConnected && status.connection === 'live'
    const action = online ? 'Go offline' : 'Go online'
    controls.dataset.online = String(online)
    button.dataset.connection = online ? 'disconnect' : 'connect'
    button.setAttribute('aria-label', action)
    controls.querySelector('[data-connection-action]').textContent = action
    controls.querySelector('[data-connection-announcement]').textContent = online ? 'Online' : 'Offline'
  })
}
