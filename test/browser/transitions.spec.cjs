const {test, expect} = require('@playwright/test');
test('counter navigation slides in both directions online and from cache; counter events do not animate', async ({page}) => {
  await page.addInitScript(() => {
    const start = document.startViewTransition.bind(document);
    window.transitions = [];
    document.startViewTransition = update => {
      window.transitions.push(document.documentElement.dataset.fogOfWarDirection);
      return start(update);
    };
  });
  await page.goto('/');
  await page.locator('a[href="/counters/one"]').click();
  await expect(page.locator('#counter-title')).toHaveText('Counter one');
  await expect.poll(() => page.evaluate(() => window.transitions)).toEqual(['forward']);
  await page.locator('#increment-counter').click();
  await expect.poll(() => page.evaluate(() => window.transitions)).toEqual(['forward']);
  await page.goBack();
  await expect(page.locator('#page-title')).toHaveText('Counters');
  await expect.poll(() => page.evaluate(() => window.transitions)).toEqual(['forward', 'back']);
  const panel = page.locator('[data-fog-of-war-dev-tools]');
  await panel.getByRole('button', {name: /Fog of War/}).click();
  await panel.getByRole('button', {name: 'Pause connection', exact: true}).click();
  await page.locator('a[href="/counters/one"]').click();
  await expect(page.locator('#increment-counter')).toBeDisabled();
  await page.goBack();
  await expect(page.locator('#page-title')).toHaveText('Counters');
  await expect.poll(() => page.evaluate(() => window.transitions)).toEqual(['forward', 'back', 'forward', 'back']);
  await page.emulateMedia({reducedMotion:'reduce'});
  await page.locator('a[href="/counters/one"]').click();
  await expect(page.locator('#count')).toBeVisible();
  expect(await page.evaluate(() => window.transitions)).toEqual(['forward', 'back', 'forward', 'back']);
});
