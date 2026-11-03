const {test, expect} = require('@playwright/test');
const origin = 'http://127.0.0.1:47183';
const path = '/counters/three';
// These tests deliberately characterize stock behavior, including its destructive fallback.
// They do NOT assert that losing cached content is acceptable Fog of War behavior.
test.use({baseURL: origin});

async function fixture(page, variant, failRefresh = false) {
  const staleReplies = [];
  page.on('websocket', socket => socket.on('framereceived', ({payload}) => {
    try {
      const message = JSON.parse(String(payload));
      if (message[3] === 'phx_reply' && message[4]?.response?.reason === 'stale') staleReplies.push(message[4]);
    } catch (_) {}
  }));
  let documents = 0;
  await page.route(origin + path, route => {
    if (!route.request().isNavigationRequest()) return route.continue();
    documents++;
    if (documents === 1) return route.continue({headers: {...route.request().headers(), 'x-fog-of-war-test-session': variant}});
    if (failRefresh) return route.abort('internetdisconnected');
    return route.continue();
  });
  const response = await page.goto(path);
  if (variant === 'expired') expect(response.headers()['x-fog-of-war-token-verdict']).toBe('expired');
  return {staleReplies, documents: () => documents};
}

for (const variant of ['expired', 'missing-cookie', 'mismatched-csrf']) {
  test(`stock LiveView automatically refreshes ${variant} session state and becomes interactive`, async ({page}) => {
    const observed = await fixture(page, variant);
    await expect.poll(() => observed.documents()).toBe(2);
    await expect.poll(() => observed.staleReplies.length).toBeGreaterThan(0);
    // A second document request does not mean its navigation has committed yet.
    // Locator assertions survive that commit; evaluating in the old document does not.
    await expect(page.locator('[data-phx-main]')).toHaveClass(/\bphx-connected\b/);
    const before = Number(await page.locator('#count').innerText());
    await page.locator('#increment-counter').click();
    await expect(page.locator('#count')).toHaveText(String(before + 1));
    expect(observed.documents()).toBe(2);
  });
}

test('characterization: expired session plus a failed HTTP refresh loses the supplied page', async ({page}, testInfo) => {
  const observed = await fixture(page, 'expired', true);
  await expect.poll(() => observed.documents()).toBeGreaterThan(1);
  await expect.poll(() => observed.staleReplies.length).toBeGreaterThan(0);
  await expect(page.locator('#counter-site')).toHaveCount(0);
  await testInfo.attach('stock-recovery-failure', {body: Buffer.from(JSON.stringify({
    expectedCharacterization: 'stock fallback discards supplied content; Fog of War must prevent this',
    documentRequests: observed.documents(), staleReplies: observed.staleReplies.length,
  }, null, 2)), contentType: 'application/json'});
});
