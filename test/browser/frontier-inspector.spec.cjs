const {test, expect} = require('@playwright/test');
test.use({baseURL: 'http://127.0.0.1:47192'});

test.afterEach(async ({page}) => {
  if (await page.locator('#pause-game').getAttribute('aria-pressed') === 'true')
    await page.locator('#pause-game').click({timeout: 3000});
});

test('inspector freezes ticks and animation, renders clickable entities, and single steps', async ({page, context}) => {
  await page.goto('/dev/game');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  // Earlier tests leave offline players around; select our connected scout explicitly.
  const player = await context.newPage();
  await player.goto('/multi/lat/0/lon/0');
  await expect(player.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  await page.goto('/dev/game');
  await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
  try {
    await page.locator('#pause-game').click();
    await expect(page.locator('.game-debug')).toHaveAttribute('data-paused', 'true');
    await expect.poll(() => player.evaluate(() => document.documentElement.classList.contains('frontier-paused'))).toBe(true);
    const tick = await page.locator('#game-tick').innerText();
    await page.waitForTimeout(350);
    await expect(page.locator('#game-tick')).toHaveText(tick);
    const connectedId = await page.locator('.debug-entities .entity-player').evaluateAll(nodes => {
      const visible = nodes.find(el => {
        const r = el.getBoundingClientRect();
        return document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2) === el;
      });
      return visible?.getAttribute('phx-value-id');
    });
    const entity = page.locator(`.debug-entities .entity-player[phx-value-id="${connectedId}"]`);
    await expect(entity).toBeVisible();
    await entity.click();
    await expect(page.locator('pre.selected[data-player-detail]')).toHaveCount(1);
    await page.locator('.debug-entities .entity-monster').click();
    await expect(page.locator('.debug-monster-detail pre')).toBeVisible();
    expect(await page.locator('.debug-entities .entity-monster').evaluate(el => getComputedStyle(el).animationPlayState)).toBe('paused');
    await page.locator('#step-game').click();
    await expect(page.locator('#game-tick')).toHaveText(String(Number(tick) + 1));
  } finally {
    if (await page.locator('#pause-game').getAttribute('aria-pressed') === 'true') await page.locator('#pause-game').click();
    await player.close();
  }
});
