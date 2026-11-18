const {test: base, expect} = require('@playwright/test');
const test = base.extend({
  peacefulGame: async ({request}, use) => {
    await expect(await request.post('/__browser/monster/disable')).toBeOK();
    try {
      await use();
    } finally {
      await expect(await request.post('/__browser/monster/enable')).toBeOK();
    }
  },
});
test.use({baseURL: 'http://127.0.0.1:47192', viewport: {width: 640, height: 800}});

async function openPlayableMap(page) {
  await page.addInitScript(() => {
    window.addEventListener('phx:frontier:player', ({detail}) => {
      window.frontierTestCanMove = !detail.clearing_cache && !detail.paused &&
        !detail.dead && detail.move_remaining_ms === 0;
    });
  });
  await page.goto('/multi/lat/0/lon/0');
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online');
  // The socket can be online while the fresh join still blocks tile clicks.
  await page.waitForFunction(() => window.frontierTestCanMove === true);
}

test('multiplayer streams preserve cached navigation, history, HUD and camera', async ({page}) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/multi/lat/0/lon/0');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await expect(page.locator('.terrain-tile')).toHaveCount(144);
  await expect(page.locator('#terrain-tiles')).toHaveAttribute('phx-update', 'stream');
  await expect(page.locator('#terrain-objects')).toHaveAttribute('phx-update', 'stream');
  await expect(page.locator('#multi-entities')).toHaveAttribute('phx-update', 'stream');
  await expect.poll(() => page.evaluate(async () =>
    (await window.fogOfWar.cache.inspect()).rows.filter(row => row.path.startsWith('/multi/')).length
  )).toBe(4);
  await expect(page.locator('.map-viewport')).toHaveClass(/pannable/);
  await page.locator('[data-connection="disconnect"]').click();
  await page.locator('a[href="/multi/lat/1/lon/1"]').click();
  await expect(page.locator('#player')).toHaveClass(/at-1-1/);
  await expect(page.locator('#frontier-bars')).toBeVisible();
  await expect(page.locator('#frontier-connection')).toHaveCount(1);
  await page.locator('a[href="/multi/lat/2/lon/2"]').click();
  await expect(page).toHaveURL(/\/multi\/lat\/1\/lon\/1$/);
  await page.goBack();
  await expect(page.locator('#player')).toHaveClass(/at-0-0/);
  await page.goForward();
  await expect(page.locator('#player')).toHaveClass(/at-1-1/);
  await page.locator('[data-connection="connect"]').click();
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  // The configured public preload is known to both the cache and the game.
  await expect(page).toHaveURL(/\/multi\/lat\/1\/lon\/1$/);
  expect(errors).toEqual([]);
});

test('offline movement at desktop width keeps the map scale during the walk', async ({page, peacefulGame}) => {
  await page.setViewportSize({width: 1280, height: 900});
  await page.goto('/multi/lat/0/lon/0');
  await expect.poll(() => page.evaluate(async () => (await window.fogOfWar.cache.inspect()).rows.length)).toBe(4);
  await expect(page.locator('#map-scene')).toHaveCSS('transform', /^matrix\(2\./);
  await page.evaluate(() => {
    const animate = Element.prototype.animate;
    Element.prototype.animate = function (frames, options) {
      if (this.id === 'map-scene') window.walkTransforms = frames.map(frame => frame.transform);
      return animate.call(this, frames, options);
    };
  });
  await page.locator('[data-connection="disconnect"]').click();
  await page.locator('a[href="/multi/lat/0/lon/1"]').click();
  await expect(page.locator('#player')).toHaveClass(/walking/);
  const [start, end] = await page.evaluate(() => window.walkTransforms);
  expect(end).toBe(start);
  await expect(page.locator('#player')).not.toHaveClass(/walking/);
});

test('other entities use client CSS slots with stable server order', async ({browser}) => {
  const contexts = await Promise.all([0, 1, 2].map(() => browser.newContext()));
  try {
    const pages = await Promise.all(contexts.map(context => context.newPage()));
    for (const page of pages) {
      await page.goto('http://127.0.0.1:47192/multi/lat/0/lon/0');
      await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    }
    await expect.poll(() => pages[0].locator('#multi-entities .entity-player').count()).toBeGreaterThanOrEqual(2);
    const slots = await pages[0].locator('#multi-entities > .entity-slot').evaluateAll(nodes =>
      nodes.map(node => ({id: node.id, transform: getComputedStyle(node).transform, style: node.getAttribute('style')})));
    expect(slots.map(slot => slot.id)).toEqual(slots.map(slot => slot.id).sort());
    expect(slots[0].transform).not.toEqual(slots[1].transform);
    expect(slots.every(slot => slot.style === null)).toBe(true);
    await expect(pages[0].locator('#player')).toHaveClass(/at-0-0/);
  } finally {
    await Promise.all(contexts.map(context => context.close()));
  }
});

test('server health repairs an old zero-HP prediction and shared tabs follow accepted moves', async ({page, context}) => {
  await page.goto('/multi/lat/0/lon/0');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.evaluate(() => {
    const key = 'frontier:bar-prediction:v1';
    const saved = JSON.parse(sessionStorage.getItem(key));
    saved.state.health = 0;
    saved.state.updated = Date.now() - 60000;
    sessionStorage.setItem(key, JSON.stringify(saved));
  });
  await page.reload();
  await expect(page.locator('[data-bar="health"]')).toHaveJSProperty('value', 100);
  const other = await context.newPage();
  await other.goto('/multi/lat/0/lon/0');
  await expect(other.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  const originalId = await page.locator('[data-phx-main]').getAttribute('id');
  await page.locator('a[href="/multi/lat/0/lon/1"]').click();
  for (const tab of [page, other]) {
    await expect(tab).toHaveURL(/\/multi\/lat\/0\/lon\/1$/);
    await expect(tab.locator('#player')).toHaveClass(/at-0-1/);
    await expect(tab.locator('[data-bar="health"]')).toHaveJSProperty('value', 100);
  }
  await expect(page.locator('[data-phx-main]')).toHaveAttribute('id', originalId);
  await other.close();
});

test('reconnect keeps an explored destination with another tab connected and explicitly paced offline moves', async ({page, context, peacefulGame}) => {
  test.setTimeout(45000);
  await openPlayableMap(page);
  const visit = async path => {
    await page.locator(`a[href="${path}"]`).click();
    await expect(page).toHaveURL(new RegExp(path + '$'));
    await expect(page.locator('[data-bar="move"]')).toHaveJSProperty('value', 100);
  };
  await visit('/multi/lat/0/lon/1');
  await visit('/multi/lat/0/lon/2');
  await visit('/multi/lat/0/lon/1');
  await visit('/multi/lat/0/lon/0');
  await page.evaluate(() => window.fogOfWar.cache.flush());
  const other = await context.newPage();
  await other.goto('/multi/lat/0/lon/0');
  await expect(other.locator('[data-connection-announcement]')).toHaveText('Online');
  await page.locator('[data-connection="disconnect"]').click();
  const departure = Date.now();
  await visit('/multi/lat/0/lon/1');
  await page.waitForTimeout(1100);
  await visit('/multi/lat/0/lon/2');
  await page.waitForTimeout(1100);
  expect(Date.now() - departure).toBeGreaterThanOrEqual(2200);
  await page.locator('[data-connection="connect"]').click();
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online', {timeout: 15000});
  await expect(page).toHaveURL(/\/multi\/lat\/0\/lon\/2$/);
  await expect(page.locator('#player')).toHaveClass(/at-0-2/);
  await expect(other).toHaveURL(/\/multi\/lat\/0\/lon\/2$/);
  await other.close();
});

test('inspector reset respawns a connected player and clears old cached exploration', async ({page, context}) => {
  await page.goto('/multi/lat/0/lon/0');
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online');
  await expect.poll(() => page.evaluate(async () => (await window.fogOfWar.cache.inspect()).rows.length)).toBe(4);
  const inspector = await context.newPage();
  await inspector.goto('/dev/game');
  await expect(inspector.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await inspector.getByRole('button', {name: 'Reset game', exact: true}).click();
  await expect(page.locator('#frontier-death')).toContainText('Respawned');
  await expect(page.locator('[data-bar="health"]')).toHaveJSProperty('value', 100);
  await expect(page.locator('[data-lives-count]')).toHaveText('3');
  await expect.poll(() => page.evaluate(async () => (await window.fogOfWar.cache.inspect()).rows.map(row=>row.path))).toEqual([new URL(page.url()).pathname]);
  await inspector.close();
});


test('reported journey: reconnect from 0,2 at preloaded 1,0 after 3.8 seconds offline', async ({page, peacefulGame}) => {
  await openPlayableMap(page);
  await page.locator('a[href="/multi/lat/0/lon/1"]').click();
  await expect(page).toHaveURL(/\/multi\/lat\/0\/lon\/1$/);
  await page.waitForTimeout(1100);
  await page.locator('a[href="/multi/lat/0/lon/2"]').click();
  await expect(page).toHaveURL(/\/multi\/lat\/0\/lon\/2$/);
  await page.waitForTimeout(1100);
  await page.locator('[data-connection="disconnect"]').click();
  const departed = Date.now();
  await page.locator('a[href="/multi/lat/0/lon/1"]').click();
  await expect(page).toHaveURL(/\/multi\/lat\/0\/lon\/1$/);
  await page.waitForTimeout(1100);
  await page.locator('a[href="/multi/lat/1/lon/0"]').click();
  await expect(page).toHaveURL(/\/multi\/lat\/1\/lon\/0$/);
  await page.waitForTimeout(Math.max(0, 3800 - (Date.now() - departed)));
  await page.locator('[data-connection="connect"]').click();
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online', {timeout: 15000});
  await expect(page).toHaveURL(/\/multi\/lat\/1\/lon\/0$/);
  await expect(page.locator('#player')).toHaveClass(/at-1-0/);
});

test('an open DevTools socket cannot masquerade as a connected player; Connect restores the page', async ({page}) => {
  await page.goto('/multi/lat/0/lon/0');
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online');
  const original = await page.locator('[data-phx-main]').getAttribute('id');
  await page.evaluate(() => {
    window.liveSocket.main.destroy();
    // Reproduce a retired main with the independent sticky DevTools root still present.
    document.querySelector('[data-phx-main]').removeAttribute('data-phx-main');
    document.querySelector('#player').classList.add('retired-player');
  });
  expect(await page.evaluate(() => window.liveSocket.isConnected())).toBe(true);
  const tools = page.locator('[data-fog-of-war-dev-tools]');
  await expect(tools.locator('[data-state]')).toHaveText('Disconnected');
  await expect(tools.locator('.dot').first()).toHaveCSS('animation-name', 'none');
  await expect(page.locator('[data-connection="connect"]')).toBeEnabled();
  await page.locator('[data-connection="connect"]').click();
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online');
  await expect(page.locator('[data-phx-main]')).not.toHaveAttribute('id', original);
  await expect(page.locator('[data-bar="health"]')).toHaveJSProperty('value', 100);
  await expect(tools.locator('[data-state]')).toHaveText('Live');
});


test('socket reopening automatically recovers a retired main page', async ({page}) => {
  await page.goto('/multi/lat/0/lon/0');
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online');
  const original = await page.locator('[data-phx-main]').getAttribute('id');
  await page.evaluate(() => {
    window.liveSocket.main.destroy();
    document.querySelector('[data-phx-main]').removeAttribute('data-phx-main');
    window.liveSocket.disconnect(() => window.liveSocket.connect());
  });
  await expect(page.locator('[data-phx-main]')).not.toHaveAttribute('id', original);
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online');
});
