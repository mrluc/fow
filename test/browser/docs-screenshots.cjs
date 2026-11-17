const {chromium, expect} = require('@playwright/test');
const path = require('node:path');

async function main() {
  const browser = await chromium.launch({channel: process.env.DOCS_BROWSER_CHANNEL || undefined});
  try {
    const page = await browser.newPage({viewport: {width: 960, height: 760}, reducedMotion: 'reduce'});
    const output = path.resolve(__dirname, '../../docs/screenshots');
    const save = name => page.screenshot({path: path.join(output, name + '.jpg'), quality: 83, animations: 'disabled'});
    const ready = () => expect.poll(() => page.evaluate(() => window.liveSocket?.main?.isConnected())).toBe(true);
    await page.goto(process.env.COUNTERS_URL || 'http://127.0.0.1:47180/');
    await ready();
    await save('counters');
    const panel = page.locator('[data-fog-of-war-dev-tools]');
    await page.getByRole('link', {name: /Counter one/}).click();
    await page.locator('#increment-counter').click();
    await expect(page.locator('#count')).toHaveText('1');
    await panel.locator(".launcher").click();
    await expect(panel.locator('tbody tr[data-kind="cache"]').filter({hasText: '/counters/one'})).toBeVisible();
    await panel.getByRole('button', {name: 'Disconnect socket', exact: true}).click();
    await page.getByRole('link', {name: /Back/}).click();
    await page.getByRole('link', {name: /Counter one/}).click();
    await expect(page.locator('#increment-counter')).toBeDisabled();
    await panel.locator('tbody tr[data-kind="cache"]').filter({hasText: '/counters/one'}).click();
    await expect(panel.locator('[data-detail]')).toContainText('storageBytes');
    await save('counters-offline');
    await page.evaluate(() => sessionStorage.setItem('fog-of-war:dev-tools-layout',
      JSON.stringify({dock: 'bottom-right', width: 680, height: 300, split: 53})));
    await page.reload();
    await ready();
    if (await panel.locator('.launcher').isVisible()) await panel.locator('.launcher').click();
    const corner = panel.locator('.tools[data-dock="bottom-right"] .panel');
    await expect(corner).toBeVisible();
    await expect(panel.locator('tbody tr[data-kind="cache"]').filter({hasText: '/counters/one'})).toBeVisible();
    const bounds = await corner.boundingBox();
    await page.screenshot({
      path: path.join(output, 'counters-dev-tools.jpg'), quality: 88, animations: 'disabled',
      clip: {x: bounds.x - 20, y: bounds.y - 28, width: bounds.width + 26, height: bounds.height + 34}
    });
    if (process.argv.includes('--counters-only')) return;
    await page.goto(process.env.FRONTIER_URL || 'http://127.0.0.1:47190/multi/lat/0/lon/0');
    await ready();
    await page.locator('#player').waitFor();
    await save('frontier');
  } finally {
    await browser.close();
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
