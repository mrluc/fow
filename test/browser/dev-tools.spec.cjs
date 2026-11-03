const {test, expect} = require('@playwright/test');
const host = page => page.locator('[data-fog-of-war-dev-tools]');
const ready = page => expect.poll(() => page.evaluate(() => window.liveSocket.isConnected())).toBe(true);
const paths = page => page.evaluate(() => Object.entries(localStorage)
  .filter(([key]) => key.startsWith('fog-of-war:page:')).map(([,raw]) => JSON.parse(raw).path).sort());

test('package dev tools survive routing and offline handoff, with isolated compact styling', async ({page}) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/'); await ready(page);
  const panel = host(page);
  await expect(panel.locator('.launcher')).toBeVisible();
  expect(await panel.evaluate(el => getComputedStyle(el).position)).toBe('fixed');
  const original = await panel.elementHandle();
  await panel.getByRole('button', {name: /Fog of War/}).click();
  await page.getByRole('link', {name: 'Counter one 0', exact: true}).click();
  await ready(page);
  await expect.poll(() => original.evaluate(el => el.isConnected)).toBe(true);
  await expect(panel.locator('.panel')).toBeVisible();
  await expect(panel.getByRole('button', {name: /Persistent/})).toHaveCount(0);
  await page.locator('#increment-counter').click();
  await expect(page.locator('#count')).toHaveText('1');
  const count = await page.locator('#count').innerText();
  await expect.poll(() => paths(page)).toEqual(['/', '/counters/one']);
  await panel.getByRole('button', {name: 'Disconnect socket', exact: true}).click();
  await expect.poll(() => page.evaluate(() => window.liveSocket.isConnected())).toBe(false);
  const requests = [];
  page.on('request', request => requests.push(request.url()));
  await page.getByRole('link', {name: '‹ Back', exact: true}).click();
  await expect(page.locator('#page-title')).toHaveText('Counters');
  await page.getByRole('link', {name: /Counter one/}).click();
  await expect(page.locator('#count')).toHaveText(count);
  await expect(page.locator('#increment-counter')).toBeDisabled();
  await expect(page.locator('[data-phx-main]')).toHaveCount(0);
  await expect.poll(() => original.evaluate(el => el.isConnected)).toBe(true);
  await panel.getByRole('button', {name: 'Collapse developer tools'}).click();
  await expect(panel.locator('.launcher')).toBeVisible();
  await panel.locator('.launcher').click();
  await panel.getByRole('tab', {name: /Cache/}).click();
  await expect(panel.locator('tbody tr[data-kind="cache"]')).toHaveCount(2);
  await panel.locator('tbody tr[data-kind="cache"]').filter({hasText: '/counters/one'}).click();
  await expect(panel.locator('[data-detail]')).toContainText('"storageBytes"');
  await expect(panel.locator('[data-detail]')).toContainText('Counter one');
  const dimensions = await panel.locator('.panel').boundingBox();
  expect(dimensions.width).toBeGreaterThan(600);
  expect(dimensions.height).toBeLessThan(260);
  await page.screenshot({path: require('node:path').resolve(__dirname, '../../results/dev-tools-cache.png')});
  // A host site's aggressive button stylesheet must not reach the tool's shadow tree.
  await page.addStyleTag({content: 'button {font-size: 80px !important; padding: 80px !important}'});
  expect(await panel.locator('[data-action="clear"]').evaluate(el => getComputedStyle(el).fontSize)).toBe('11px');
  await panel.getByRole('tab', {name: 'Help', exact: true}).click();
  await expect(panel.getByRole('heading', {name:'A website that remembers what you saw'})).toBeVisible();
  expect(requests).toEqual([]);
  await panel.getByRole('button', {name: 'Reconnect', exact: true}).click();
  await ready(page);
  await expect(page.locator('#count')).toHaveText(count);
  await page.locator('#increment-counter').click();
  await expect(page.locator('#count')).toHaveText(String(Number(count) + 1));
  expect(errors).toEqual([]);
});

test('clear unused preserves every open Fog of War route and unrelated localStorage', async ({page, context}) => {
  await page.goto('/counters/three'); await ready(page);
  await page.getByRole('link', {name: 'All counters'}).click();
  await page.getByRole('link', {name: /Counter one/}).click();
  await ready(page);
  const other = await context.newPage();
  await other.goto('/counters/two'); await ready(other);
  await page.evaluate(() => localStorage.setItem('example:unrelated', 'keep me'));
  const panel = host(page);
  await panel.locator('.launcher').click();
  await panel.getByRole('tab', {name: /Cache/}).click();
  await expect(panel.locator('tbody tr[data-kind="cache"]')).toHaveCount(4);
  const times=await panel.locator('tbody tr[data-kind="cache"]').evaluateAll(rows=>rows.map(row=>Number(row.dataset.time)));
  expect(times).toEqual([...times].sort((a,b)=>b-a));
  await panel.getByRole('button',{name:'Path',exact:true}).click();
  const renderedPaths = await panel.locator('tbody tr[data-kind="cache"] td:first-child').allTextContents();
  expect(renderedPaths).toEqual([...renderedPaths].sort());
  await expect(panel.locator('tbody tr[data-kind="cache"]').filter({hasText: '/counters/one'}).locator('td').last()).toHaveText('●');
  await expect(panel.locator('tbody tr[data-kind="cache"]').filter({hasText: '/counters/two'}).locator('td').last()).toHaveText('●');
  await panel.getByRole('button', {name: 'Clear unused', exact: true}).click();
  await expect.poll(() => paths(page)).toEqual(['/counters/one', '/counters/two']);
  expect(await other.evaluate(() => localStorage.getItem('example:unrelated'))).toBe('keep me');
  await expect(panel.locator('[data-cache-message]')).toContainText('kept 2 open');
  await expect(panel.getByRole('button', {name: 'Clear unused', exact: true})).toBeDisabled();
  await other.close();
  await panel.getByRole('button', {name: 'Refresh', exact: true}).click();
  await expect(panel.getByRole('button', {name: 'Clear unused', exact: true})).toBeEnabled();
  await panel.getByRole('button', {name: 'Clear unused', exact: true}).click();
  await expect.poll(() => paths(page)).toEqual(['/counters/one']);
  await page.reload(); await ready(page);
  await expect.poll(() => paths(page)).toEqual(['/counters/one']);
});


test('without cross-tab locks inspection works and destructive clearing stays disabled', async ({page}) => {
  await page.addInitScript(() => Object.defineProperty(navigator, 'locks', {value: undefined}));
  await page.goto('/counters/three'); await ready(page);
  await page.getByRole('link', {name: 'All counters'}).click();
  const panel = host(page);
  await panel.locator('.launcher').click();
  await panel.getByRole('tab', {name: /Cache/}).click();
  await expect(panel.locator('tbody tr[data-kind="cache"]')).toHaveCount(2);
  await expect(panel.getByRole('button', {name: 'Clear unused', exact: true})).toBeDisabled();
  await expect(panel.getByRole('button', {name: 'Clear unused', exact: true})).toHaveAttribute('title', /Web Locks/);
});


test('online capture replaces legacy element/build keys with one record per route', async ({page}) => {
  await page.addInitScript(() => {
    const old = {schema: 1, build: 'fog-of-war-1', path: '/', savedAt: '2000-01-01T00:00:00.000Z', html: '<main>Old</main>'};
    localStorage.setItem('fog-of-war:page:/:counter-content', JSON.stringify(old));
    localStorage.setItem('fog-of-war:page:/:counter-site', JSON.stringify(old));
  });
  await page.goto('/'); await ready(page);
  await expect.poll(() => page.evaluate(() => Object.keys(localStorage).filter(key => key.startsWith('fog-of-war:page:')).sort())).toEqual(['fog-of-war:page:/']);
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('fog-of-war:page:/')).regionId)).toBe('counter-site');
});
