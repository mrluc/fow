const {test, expect} = require('@playwright/test');
test.use({baseURL: 'http://127.0.0.1:47192'});

test('negative lives show spent scouts plus red debt, and death desaturates the scout', async ({page}) => {
  await page.goto('/multi/lat/0/lon/0');
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online');
  await expect(page.locator('[data-lives-count]')).toHaveText('3');
  await page.evaluate(() => window.dispatchEvent(new CustomEvent('phx:frontier:player', {detail: {
    health: 0, dead: true, lives: -2, life: 5, respawn_remaining_ms: 5000, move_remaining_ms: 0,
  }})));
  await expect(page.locator('[data-lives-count]')).toHaveText('-2');
  await expect(page.locator('.life-spent')).toHaveCount(3);
  await expect(page.locator('.life-debt')).toHaveCount(2);
  await expect(page.locator('#frontier-death')).toContainText('You died');
  await expect(page.locator('#frontier-death')).toContainText('Respawning in 5');
  await expect(page.locator('#player')).toHaveCSS('opacity', '0.4');
  await expect(page.locator('#player')).toHaveCSS('filter', /grayscale\(1\)/);
  await page.locator('a[href="/multi/lat/0/lon/1"]').evaluate(el => el.click());
  await expect(page).toHaveURL(/\/multi\/lat\/0\/lon\/0$/);
});

test('the occupied monster plays its cycle without losing camera geometry on health ticks', async ({page}) => {
  await page.setViewportSize({width: 1200, height: 900});
  await page.goto('/dev/game');
  await expect.poll(async () => Number(await page.locator('#game-tick').innerText()) % 30, {intervals: [100], timeout: 7000}).toBeLessThan(10);
  const position = await page.locator('.debug-monster').evaluate(el =>
    el.closest('.debug-map-label').className.match(/at-(\d)-(\d)/).slice(1));
  await page.goto(`/multi/lat/${position[0]}/lon/${position[1]}`);
  await page.evaluate(() => {
    const scene = document.querySelector('#map-scene');
    window.cameraStyleLosses = 0;
    new MutationObserver(() => {
      if (!scene.style.getPropertyValue('--map-scale')) window.cameraStyleLosses++;
    }).observe(scene, {attributes: true, attributeFilter: ['style']});
  });
  const monster = page.locator('.entity-monster');
  await expect(monster).toHaveClass(/monster-exploding/, {timeout: 5000});
  await expect(monster).toHaveCSS('animation-name', 'monster-explode');
  await expect(monster).toHaveCSS('animation-duration', '3s');
  await expect.poll(() => page.locator('[data-bar="health"]').evaluate(el => el.value)).toBeLessThan(100);
  const health = await page.locator('[data-bar="health"]').evaluate(el => el.value);
  await page.waitForTimeout(900);
  expect(await page.locator('[data-bar="health"]').evaluate(el => el.value)).toBeGreaterThan(health);
  expect(await page.evaluate(() => window.cameraStyleLosses)).toBe(0);

});

test('clicking the beast plays a server-confirmed elixir strike', async ({page, request}) => {
  await expect(await request.post('/__browser/monster/disable')).toBeOK();
  try {
    await page.goto('/dev/game');
    const [lat, lon] = await page.locator('.debug-monster').evaluate(el =>
      el.closest('.debug-map-label').className.match(/at-(\d)-(\d)/).slice(1));
    await page.addInitScript(() => {
      window.addEventListener('phx:frontier:player', ({detail}) => {
        window.frontierJoinReady = !detail.clearing_cache;
      });
    });
    await page.goto(`/multi/lat/${lat}/lon/${lon}`);
    await page.waitForFunction(() => window.frontierJoinReady === true);
    const monster = page.locator('button.entity-monster');
    await expect(monster).toHaveAttribute('title', /200 HP/);
    await monster.hover();
    await expect(monster).toHaveCSS('scale', '1.07');
    await monster.click({timeout: 5000});
    await expect(monster).toHaveAttribute('title', /100 HP/);
    await expect(page.locator('.elixir-shard')).toHaveCount(12);
    await expect.poll(() => monster.evaluate(el => getComputedStyle(el).backgroundImage),
      {intervals: [30]}).toMatch(/monster-recompose/);
    await expect(page.locator('.elixir-shard')).toHaveCount(0);
    await expect(page.locator('[data-bar="move"]')).toHaveJSProperty('value', 100);
    await monster.click({timeout: 5000});
    await expect(monster).toBeDisabled();
    await expect.poll(() => monster.evaluate(el => getComputedStyle(el).backgroundImage),
      {intervals: [30]}).toMatch(/monster-spread-starfish/);
    await expect(monster).toHaveCSS('opacity', '0');
    await expect(page.locator('#frontier-slay-notice')).toHaveText('You slayed the Pitch Beast');
  } finally {
    await expect(await request.post('/__browser/monster/enable')).toBeOK();
  }
});

test('offline death reconnects, clears remembered routes and respawns automatically', async ({page}) => {
  test.setTimeout(45000);
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/multi/lat/0/lon/0');
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online');
  await expect.poll(() => page.evaluate(async () => (await window.fogOfWar.cache.inspect()).rows.length)).toBe(4);
  await page.locator('[data-connection="disconnect"]').click();
  await expect(page.locator('[data-bar="health"]')).toHaveJSProperty('value', 1, {timeout: 23000});
  await expect(page.locator('[data-connection-label]')).toHaveText('Reconnect 0s');
  await expect(page.locator('#frontier-death')).toBeHidden();
  await expect(page.locator('[data-lives-count]')).toHaveText('3');
  await page.locator('[data-connection="connect"]').click();
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online', {timeout: 10000});
  await expect(page.locator('#frontier-death')).toContainText('Respawned', {timeout: 10000});
  await expect(page.locator('[data-bar="health"]')).toHaveJSProperty('value', 100);
  await expect(page.locator('[data-lives-count]')).toHaveText('2');
  await expect.poll(() => page.evaluate(async () => (await window.fogOfWar.cache.inspect()).rows.length)).toBe(1);
  await expect(page.locator('#frontier-death')).toBeHidden();
  await expect(page.locator('html')).not.toHaveClass(/frontier-dead/);
  await expect(page.locator('#player')).toHaveCSS('opacity', '1');
  await expect(page.locator('#player')).toHaveCSS('filter', /grayscale\(0\)/);
  await expect(page.locator('.sector.current .floor')).toHaveCSS('filter', 'none');
  if (await page.locator('.object.current .tree').count()) {
    await expect(page.locator('.object.current .tree').first()).not.toHaveCSS('filter', /saturate/);
  }

  expect(errors).toEqual([]);
});

test('connected death at desktop width restores scout color after respawn', async ({page}) => {
  test.setTimeout(30000);
  await page.setViewportSize({width: 1200, height: 900});
  await page.goto('/dev/game');
  await expect.poll(async () => Number(await page.locator('#game-tick').innerText()) % 30,
    {intervals: [100], timeout: 7000}).toBeLessThan(10);
  const position = await page.locator('.debug-monster').evaluate(el =>
    el.closest('.debug-map-label').className.match(/at-(\d)-(\d)/).slice(1));
  await page.goto(`/multi/lat/${position[0]}/lon/${position[1]}`);
  await expect(page.locator('#frontier-death')).toContainText('You died', {timeout: 16000});
  await expect(page.locator('#player')).toHaveCSS('opacity', '0.4');
  await expect(page.locator('#frontier-death')).toContainText('Respawned', {timeout: 10000});
  await expect(page.locator('html')).not.toHaveClass(/frontier-dead/);
  await expect(page.locator('#player')).toHaveCSS('opacity', '1');
  await expect(page.locator('#player')).toHaveCSS('filter', /grayscale\(0\)/);
  await expect(page.locator('.sector.current .floor')).toHaveCSS('filter', 'none');
  await expect(page.locator('#frontier-death')).toBeHidden();
});

test('respawn teleports without reusing the dead scout walking snapshot', async ({page}) => {
  await page.setViewportSize({width: 1200, height: 900});
  await page.addInitScript(() => {
    window.addEventListener('phx:frontier:player', ({detail}) => {
      window.frontierJoinReady = !detail.clearing_cache;
    });
  });
  await page.goto('/multi/lat/0/lon/0');
  await page.waitForFunction(() => window.frontierJoinReady === true);
  await expect(page.locator('[data-connection-announcement]')).toHaveText('Online');
  await page.evaluate(() => {
    window.frontierMoves = 0;
    window.addEventListener('frontier:moved', () => window.frontierMoves++);
    window.dispatchEvent(new Event('frontier:respawning'));
  });
  await page.locator('a[href="/multi/lat/0/lon/1"]').click();
  await expect(page).toHaveURL(/\/multi\/lat\/0\/lon\/1$/);
  await expect(page.locator('#player')).toHaveClass(/at-0-1/);
  expect(await page.evaluate(() => window.frontierMoves)).toBe(0);
});
