const {test, expect} = require('@playwright/test');
test.use({baseURL: 'http://127.0.0.1:47192'});
const snapshotPaths = page => page.evaluate(() => Object.entries(localStorage).filter(([k]) => k.startsWith('fog-of-war:page:')).map(([,v]) => JSON.parse(v).path).sort());
test('procedural 4×4 world seeds three real neighbors, animates the scout, and navigates cached coordinates offline', async ({page}) => {
  const errors=[]; page.on('pageerror', e => errors.push(e.message));
  await page.addInitScript(() => {
    const start=document.startViewTransition.bind(document);
    window.mapTransitions=0; window.scoutMoves=[];
    document.startViewTransition=update=>{
      const from=document.getElementById('player')?.getBoundingClientRect();
      window.mapTransitions++;
      const transition=start(update);
      transition.ready.then(()=>{
        const scout=document.getElementById('player'),to=scout?.getBoundingClientRect();
        if(from&&to)window.scoutMoves.push({from:[from.x,from.y],to:[to.x,to.y],pose:getComputedStyle(scout).backgroundImage});
      }).catch(error=>window.scoutMoves.push({error:error.message}));
      return transition;
    };
  });
  await page.goto('/');
  await expect(page).toHaveURL(/\/lat\/0\/lon\/0$/);
  await expect.poll(() => snapshotPaths(page)).toEqual(['/lat/0/lon/0','/lat/0/lon/1','/lat/1/lon/0','/lat/1/lon/1']);
  expect(await page.evaluate(async () => (await window.fogOfWar.cache.inspect()).rows.filter(r => r.open).map(r => r.path))).toEqual(['/lat/0/lon/0']);
  await expect(page.locator('.terrain-tile')).toHaveCount(144);
  await expect(page.locator('.ground-layer .sector')).toHaveCount(16);
  await expect(page.locator('.tile-target')).toHaveCount(3);
  await expect(page.locator('.ground-layer .at-1-1')).not.toHaveClass(/fow-nav-uncached/);
  await expect(page.locator('.ground-layer .at-3-3')).toHaveClass(/fow-nav-uncached/);
  expect(await page.locator('.ground-layer .at-1-1 .screen-fog').evaluate(el=>getComputedStyle(el).backgroundImage)).toContain('conic-gradient');
  expect(await page.locator('.screen-fog').first().evaluate(el=>getComputedStyle(el).transform)).toBe('none');
  // Transparent diamond hit areas sit over the whole terrain, with no visible labels or page chrome.
  await expect(page.locator('#frontier-map')).toHaveText('');
  expect(await page.locator('.tile-target').first().evaluate(el => getComputedStyle(el).clipPath)).toContain('polygon');
  expect(await page.locator('body').evaluate(el => el.scrollHeight <= innerHeight)).toBe(true);
  await page.locator('.tile-target[href="/lat/1/lon/1"]').click();
  await expect(page.locator('#player')).toHaveClass(/at-1-1/);
  await expect.poll(()=>page.evaluate(()=>window.mapTransitions)).toBeGreaterThan(0);
  await expect.poll(()=>page.evaluate(()=>window.scoutMoves.length)).toBeGreaterThan(0);
  expect(await page.evaluate(()=>window.scoutMoves.some(m=>m.from&&JSON.stringify(m.from)!==JSON.stringify(m.to)&&m.pose.includes('scout-walk.png')))).toBe(true);
  await expect(page.locator('.tile-target')).toHaveCount(8);
  await page.locator('.tile-target[href="/lat/0/lon/0"]').click();
  await expect(page.locator('#player')).toHaveClass(/at-0-0/);
  const panel=page.locator('[data-fog-of-war-dev-tools]');
  await panel.getByRole('button',{name:/Fog of War/}).click();
  await panel.getByRole('button',{name:'Pause connection',exact:true}).click();
  const requests=[];page.on('request',r=>requests.push(r.url()));
  await page.locator('.tile-target[href="/lat/1/lon/1"]').click();
  await expect(page.locator('#player')).toHaveClass(/at-1-1/);
  await page.locator('.tile-target[href="/lat/2/lon/2"]').click();
  await expect(page).toHaveURL(/\/lat\/1\/lon\/1$/);
  await page.locator('.tile-target[href="/lat/0/lon/1"]').click();
  await expect(page.locator('#player')).toHaveClass(/at-0-1/);
  await page.goBack();await expect(page.locator('#player')).toHaveClass(/at-1-1/);
  await page.evaluate(()=>Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))));
  await expect(page.locator('#player')).not.toHaveClass(/walking/);
  expect(requests).toEqual([]);expect(errors).toEqual([]);
  await page.screenshot({path:require('node:path').resolve(__dirname,'../../results/frontier-offline.png'),fullPage:true});
});
