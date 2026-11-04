const {test, expect} = require('@playwright/test');

test('app styling follows offline state and cached destinations across routing and cache changes', async ({page}) => {
  await page.goto('/');
  const one = page.locator('a.counter-link[href="/counters/one"]');
  const two = page.locator('a.counter-link[href="/counters/two"]');
  await expect(one).toHaveClass(/fow-nav-uncached/);
  await one.click();
  await expect(page.locator('#increment-counter')).toBeVisible();
  await page.getByRole('link', {name: '‹ Back', exact: true}).click();
  await expect(one).not.toHaveClass(/fow-nav-uncached/);
  await expect(two).toHaveClass(/fow-nav-uncached/);
  await expect(page.locator('html')).not.toHaveClass(/fow-offline/);
  const panel = page.locator('[data-fog-of-war-dev-tools]');
  await panel.getByRole('button', {name: /Fog of War/}).click();
  await panel.getByRole('button', {name: 'Disconnect socket', exact: true}).click();
  await expect(page.locator('html')).toHaveClass(/fow-offline/);
  expect(await two.evaluate(el => getComputedStyle(el).opacity)).toBe('0.4');
  await two.click();
  await expect(page).toHaveURL(/\/$/);
  await one.click();
  await expect(page.locator('#count')).toBeVisible();
  expect(await page.locator('#increment-counter').evaluate(el => getComputedStyle(el).opacity)).toBe('0.4');
  await expect(page.locator('#increment-counter')).toBeDisabled();
  await page.getByRole('link', {name: '‹ Back', exact: true}).click();
  // Cross-tab removals must update styling without a DOM patch or reload.
  const sibling = await page.context().newPage();
  await sibling.goto('/counters/three');
  await sibling.evaluate(() => window.fogOfWar.cache.remove('/counters/one'));
  await expect(one).toHaveClass(/fow-nav-uncached/);
  await sibling.close();
  await panel.getByRole('button', {name: 'Reconnect', exact: true}).click();
  await expect(page.locator('html')).not.toHaveClass(/fow-offline/);
  await expect(two).toHaveClass(/fow-nav-uncached/);
});
