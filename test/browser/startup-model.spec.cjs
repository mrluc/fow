const {test, expect} = require('@playwright/test');
const origin = 'http://127.0.0.1:47183';
test.use({baseURL: origin});
const cached = page => page.frameLocator('#cached');
const candidate = page => page.frameLocator('#candidate');

async function networkGate(page) {
  let http = false, joins = false;
  const delayed = [];
  const attempts = [];
  await page.route(origin + '/**', route => {
    const url = new URL(route.request().url());
    if (route.request().isNavigationRequest() && (url.pathname === '/' || url.pathname.startsWith('/counters/'))) {
      attempts.push(url.pathname);
      if (!http) return route.abort('internetdisconnected');
    }
    return route.continue();
  });
  await page.routeWebSocket('**/live/websocket**', socket => {
    const server = socket.connectToServer();
    server.onMessage(message => {
      let data;
      try { data = JSON.parse(String(message)); } catch (_) {}
      // Forward the real handshake, but hold real LiveView replies until explicitly released.
      if (!joins && data?.[3] === 'phx_reply' && data?.[2]?.startsWith('lv:')) delayed.push({socket, message});
      else socket.send(message);
    });
  });
  return {
    attempts,
    allowHTTP: () => {http = true},
    waiting: () => delayed.length,
    allowJoins: () => {joins = true; for (const entry of delayed.splice(0)) {try {entry.socket.send(entry.message)} catch (_) { /* Cancelled candidates have no recipient. */ }}},
  };
}

test('browser model: failed loads keep cached navigation, and automatic recovery waits for the real mount', async ({page}) => {
  const gate = await networkGate(page);
  await page.goto('/__fog_of_war_test__/startup');
  await expect(cached(page).locator('#page-title')).toHaveText('Counters');
  await expect.poll(() => gate.attempts.length).toBeGreaterThan(0);
  await cached(page).locator('a[href="/counters/one"]').click();
  await expect(cached(page).locator('#counter-title')).toHaveText('Counter one');
  await expect(cached(page).locator('#increment-counter')).toBeDisabled();
  await expect(cached(page).locator('[data-phx-main],[data-phx-session]')).toHaveCount(0);
  await cached(page).getByRole('link', {name:'‹ Back', exact:true}).click();
  await expect(cached(page).locator('#page-title')).toHaveText('Counters');
  await expect(page.locator('body')).toHaveAttribute('data-presentation', 'cached');

  gate.allowHTTP();
  await page.evaluate(() => window.dispatchEvent(new Event('online')));
  await expect.poll(() => gate.waiting()).toBeGreaterThan(0);
  await expect(candidate(page).locator('[data-phx-main]')).toHaveCount(1);
  // Real HTTP and transport success are insufficient: the real join reply is still held.
  await expect.poll(() => page.locator('#candidate').evaluate(el => el.contentWindow.liveSocket?.isConnected())).toBe(true);
  await expect(page.locator('body')).toHaveAttribute('data-presentation', 'cached');
  await expect(page.locator('#cached')).toBeVisible();

  gate.allowJoins();
  await expect(page.locator('body')).toHaveAttribute('data-presentation', 'live');
  await expect(page.locator('#cached')).toBeHidden();
  await expect(candidate(page).locator('#page-title')).toHaveText('Counters');
  await candidate(page).locator('a[href="/counters/one"]').click();
  await expect(candidate(page).locator('#counter-title')).toHaveText('Counter one');
  const before = Number(await candidate(page).locator('#count').innerText());
  await candidate(page).locator('#increment-counter').click();
  await expect(candidate(page).locator('#count')).toHaveText(String(before + 1));
});

test('browser model: navigation invalidates an old attempt and a late readiness callback cannot take over', async ({page}) => {
  const gate = await networkGate(page);
  await page.goto('/__fog_of_war_test__/startup');
  gate.allowHTTP();
  await page.evaluate(() => window.dispatchEvent(new Event('online')));
  await expect.poll(() => gate.waiting()).toBeGreaterThan(0);
  await page.evaluate(() => {
    window.oldCandidate = document.querySelector('#candidate').contentWindow;
    window.oldAttempt = String(window.startupModel.inspect().generation);
  });
  await cached(page).locator('a[href="/counters/two"]').click();
  await expect(cached(page).locator('#counter-title')).toHaveText('Counter two');
  await page.evaluate(() => window.dispatchEvent(new MessageEvent('message', {
    origin:location.origin, source:window.oldCandidate,
    data:{kind:'fog-of-war-test-root-mounted', attempt:window.oldAttempt, path:'/'},
  })));
  await expect(page.locator('body')).toHaveAttribute('data-presentation', 'cached');
  expect(await page.evaluate(() => window.startupModel.inspect().events.some(event => event.kind === 'committed'))).toBe(false);
  await expect.poll(() => page.locator('#candidate').evaluate(el => !!el.contentWindow.liveSocket?.isConnected())).toBe(true);
  gate.allowJoins();
  await expect(page.locator('body')).toHaveAttribute('data-presentation', 'live');
  await expect(candidate(page).locator('#counter-title')).toHaveText('Counter two');
  const commits = await page.evaluate(() => window.startupModel.inspect().events.filter(event => event.kind === 'committed'));
  expect(commits.map(event => event.path)).toEqual(['/counters/two']);
});
