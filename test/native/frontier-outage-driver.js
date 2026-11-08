// Injected only into the generated test host, including after the recovery GET.
(async () => {
  if (location.origin !== 'http://127.0.0.1:47192') return;
  const route = '/lat/1/lon/1';
  const phase = 'frontier-native-outage';
  const report = (stage, detail) => fetch('__REPORT_URL__', {
    method: 'POST', body: JSON.stringify({stage, detail}),
  });
  const wait = async (description, predicate) => {
    const end = Date.now() + 25000;
    while (!await predicate()) {
      if (Date.now() > end) throw new Error('Timed out: ' + description);
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  };
  const live = () => window.liveSocket?.main?.isConnected() &&
    !document.documentElement.classList.contains('fow-offline');
  const at = (path, tile) => location.pathname === path &&
    document.querySelector('#player')?.classList.contains(tile);
  const click = path => document.querySelector(`.tile-target[href="${path}"]`).click();

  try {
    await wait('connected LiveView', live);
    if (sessionStorage.getItem(phase) === 'recovering') {
      if (!at(route, 'at-1-1')) throw new Error('Recovered at the wrong route: ' + location.pathname);
      click('/lat/2/lon/2');
      await wait('fresh live navigation to an unbundled tile', () => live() && at('/lat/2/lon/2', 'at-2-2'));
      await report('recovered', location.pathname);
      return;
    }

    await window.fogOfWarStartup;
    await window.frontierPreload;
    await window.fogOfWar.cache.flush();
    await report('online', location.pathname);
    await wait('real transport outage', () => !window.liveSocket.isConnected() &&
      document.documentElement.classList.contains('fow-offline'));
    click(route);
    await wait('cached navigation', () => at(route, 'at-1-1'));
    click('/lat/2/lon/2');
    await wait('uncached navigation denied', () => window.fogOfWar.navigationEvents().some(
      event => event.path === '/lat/2/lon/2' && event.outcome === 'denied'));
    if (!at(route, 'at-1-1')) throw new Error('Uncached navigation replaced the map');
    history.back();
    await wait('cached back navigation', () => at('/lat/0/lon/0', 'at-0-0'));
    history.forward();
    await wait('cached forward navigation', () => at(route, 'at-1-1'));
    sessionStorage.setItem(phase, 'recovering');
    await report('offline', location.pathname);
  } catch (error) {
    await report('failed', error.stack || String(error));
  }
})();
