// Run against a generated PublicShell and the source example, not a mocked offline renderer.
const {chromium} = require('@playwright/test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
(async () => {
  const shell = process.env.PUBLIC_SHELL_URL;
  assert(shell, 'Set PUBLIC_SHELL_URL to the generated host readiness URL');
  const generated = path.resolve(__dirname, '../../examples/wrappers/elixirkit');
  const manifest = JSON.parse(fs.readFileSync(path.join(generated, '.fow.json')));
  const seed = fs.readFileSync(path.join(generated, 'priv/fog_of_war_seed.js'), 'utf8');
  const browser = await chromium.launch({channel: 'chrome', headless: true});
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    const remote = [];
    await page.route('**/*', route => {
      if (new URL(route.request().url()).origin !== new URL(shell).origin) {
        remote.push(route.request().url()); return route.abort();
      }
      return route.continue();
    });
    await page.goto(shell);
    await page.locator('a.counter-link[href="/counters/one"]').click();
    await page.waitForURL('**/counters/one');
    await page.getByRole('button', {name: 'Increment', exact: true}).waitFor();
    assert(await page.getByRole('button', {name: 'Increment', exact: true}).isDisabled());
    assert.equal(await page.locator('[data-phx-session],[data-phx-static],meta[name=csrf-token]').count(), 0);
    await page.getByRole('link', {name: '‹ Back', exact: true}).click();
    await page.waitForURL(shell);
    assert.equal(await page.locator('html').getAttribute('data-fog-of-war-public-shell'), 'true');
    assert.deepEqual(remote, [], 'The bundled public shell made an external network request');
    await page.screenshot({path: path.resolve(__dirname, '../../results/wrapper-public-shell.png'), fullPage: true});
    await context.close();

    // Observe cache at first inline application script: preload must have already happened.
    const live = await browser.newContext();
    await live.addInitScript({content: seed});
    const remotePage = await live.newPage();
    await remotePage.route('**/*', route => route.fulfill({contentType: 'text/html', body:
      `<html><script>window.initialCache = JSON.parse(localStorage.getItem('fog-of-war:page:/'));</script><body>Probe</body></html>`}));
    await remotePage.goto(manifest.web.origin + '/');
    assert.equal(await remotePage.evaluate(() => window.initialCache?.path), '/');
    await remotePage.evaluate(() => localStorage.setItem('fog-of-war:page:/', JSON.stringify({path: '/', html: 'newer-online-value'})));
    await remotePage.reload();
    assert.equal(await remotePage.evaluate(() => window.initialCache.html), 'newer-online-value');
    await remotePage.goto('http://127.0.0.1:47189/');
    assert.equal(await remotePage.evaluate(() => localStorage.length), 0, 'Seed escaped configured origin');
    await live.close();
    console.log('PASS bundled offline navigation/back, disabled actions, no session/remote requests, document-start seed, no overwrite, exact origin');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
