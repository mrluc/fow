// Characterization of pinned upstream LiveView behavior, not Fog of War acceptance tests.
// Start test/browser/server.sh; use Node with the installed Playwright in NODE_PATH.
const {chromium, expect} = require('@playwright/test');
const fs = require('node:fs');
const origin = process.env.BASE_URL || 'http://127.0.0.1:47182';
(async () => {
  const browser = await chromium.launch({channel: 'chrome', headless: true});
  const results = [];
  try {
    for (const scenario of ['fresh-cookie-and-html', 'missing-cookie', 'invalid-token', 'refresh-http-fails']) {
      const context = await browser.newContext();
      const response = await context.request.get(origin + '/counters/three');
      if (!response.ok()) throw new Error('Start test/browser/server.sh first');
      let html = await response.text();

      if (['invalid-token', 'refresh-http-fails'].includes(scenario)) {
        html = html.replace(/data-phx-session="[^"]+"/g, 'data-phx-session="invalid-for-characterization"');
      }
      const page = await context.newPage();
      page.on("pageerror", error => console.error(scenario + " pageerror: " + error.message));
      console.log("Characterizing " + scenario);
      page.on("requestfailed", req => console.error(scenario + " request failed: " + req.resourceType() + " " + req.failure()?.errorText));
      let documents = 0, refreshes = 0;
      const events = [];
      page.on('websocket', socket => socket.on('framereceived', ({payload}) => {
        try {
          const message = JSON.parse(String(payload));
          if (message[3] === 'phx_reply') events.push({status: message[4]?.status, reason: message[4]?.response?.reason});
        } catch (_) {}
      }));
      await page.route(origin + '/counters/three', route => {
        if (!route.request().isNavigationRequest()) return route.continue();
        documents++;
        refreshes++;
        if (scenario === 'refresh-http-fails') return route.abort('internetdisconnected');
        return route.continue();
      });
      // Establish a real-origin document, then supply HTML without another page GET.
      // This probe does not depend on synthetic top-level navigation behavior.
      await page.goto(origin + '/robots.txt');
      await page.evaluate(() => history.replaceState({}, '', '/counters/three'));
      if (scenario === 'missing-cookie') await context.clearCookies();
      await page.setContent(html, {waitUntil:'domcontentloaded'});
      if (scenario === 'refresh-http-fails') {
        await expect.poll(() => refreshes).toBeGreaterThan(0);
        await expect.poll(() => page.locator('#counter-site').count()).toBe(0);
        results.push({scenario, refreshes, cachedContentSurvived:false, events});
      } else {
        // A working server action proves a joined view, not just a connected transport.
        await expect(page.locator('#increment-counter')).toBeVisible();
        await expect.poll(() => page.evaluate(() => !!window.liveSocket?.main?.isConnected()), {timeout: 5000}).toBe(true).catch(async error => {
          console.error(await page.evaluate(() => ({url:location.href,socket:!!window.liveSocket,connected:window.liveSocket?.isConnected(),main:!!window.liveSocket?.main,scripts:[...document.scripts].map(s=>s.src),root:!!document.querySelector('[data-phx-main]')})));
          console.error({scenario,documents,refreshes,events}); throw error;
        });
        const before = Number(await page.locator('#count').innerText());
        await page.locator('#increment-counter').click();
        await expect(page.locator('#count')).toHaveText(String(before + 1));
        if (scenario !== 'fresh-cookie-and-html') expect(refreshes).toBeGreaterThan(0);
        else expect(refreshes).toBe(0);
        results.push({scenario, refreshes, serverActionPassed:true, events});
      }
      await context.close();
    }
    const report = {liveView:'1.2.13', origin, results};
    if (process.env.REPORT) fs.writeFileSync(process.env.REPORT, JSON.stringify(report,null,2)+'\n');
    console.log(JSON.stringify(report,null,2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
