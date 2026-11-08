const {test, expect} = require('@playwright/test');
test.use({baseURL: 'http://127.0.0.1:47192'});
const snapshotPaths = page => page.evaluate(async () => (await window.fogOfWar.cache.inspect()).rows.filter(row=>row.valid).map(row=>row.path).sort());
test('procedural 4×4 world seeds three real neighbors, animates the scout, and navigates cached coordinates offline', async ({page}) => {
  await page.setViewportSize({width:900,height:800});
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
  await page.goto('/lat/0/lon/0');
  await expect(page).toHaveURL(/\/lat\/0\/lon\/0$/);
  await expect.poll(() => snapshotPaths(page)).toEqual(['/lat/0/lon/0','/lat/0/lon/1','/lat/1/lon/0','/lat/1/lon/1']);
  expect(await page.evaluate(async () => (await window.fogOfWar.cache.inspect()).rows.filter(r => r.open).map(r => r.path))).toEqual(['/lat/0/lon/0']);
  await expect(page.locator('.terrain-tile')).toHaveCount(144);
  await expect(page.locator('.ground-layer .sector')).toHaveCount(16);
  await expect(page.locator('.tile-target')).toHaveCount(3);
  await expect(page.locator('.ground-layer .at-1-1')).not.toHaveClass(/fow-nav-uncached/);
  await expect(page.locator('.ground-layer .at-3-3')).toHaveClass(/fow-nav-uncached/);
  await expect(page.locator('.sector.at-1-1 .floor')).toHaveCSS('filter', 'saturate(0.45) brightness(0.55)');
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
  await expect(panel.getByRole('button',{name:'Semi-transparent developer tools',exact:true})).toHaveAttribute('aria-pressed','true');
  // expect(await panel.evaluate(el=>el.style.getPropertyValue('--fog-of-war-dev-tools-scale'))).toBe('1.1');
  await panel.getByRole('button',{name:'Disconnect socket',exact:true}).click();
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


test('map grows and stays centered while CSS fog stays on remembered terrain and trees', async ({page}) => {
  await page.setViewportSize({width:900,height:800});
  await page.goto('/lat/0/lon/0');
  await expect.poll(() => snapshotPaths(page)).toHaveLength(4);
  const bounds = () => page.locator('.floor').evaluateAll(els => {
    const r=els.map(el=>el.getBoundingClientRect());
    const left=Math.min(...r.map(x=>x.left)),right=Math.max(...r.map(x=>x.right));
    return {width:right-left,center:(left+right)/2};
  });
  const configuredLogoWidth=()=>page.locator('.game-logo').evaluate(el=>{
    const style=getComputedStyle(el),share=parseFloat(style.getPropertyValue('--game-logo-width'))/100;
    return Math.min(innerWidth*share,parseFloat(style.getPropertyValue('--game-logo-max-width')));
  });
  const smallLogo=await page.locator('.game-logo').boundingBox();
  expect(smallLogo.width).toBeCloseTo(await configuredLogoWidth(),0);
  const small=await bounds();
  expect(Math.abs(small.center-450)).toBeLessThan(2);
  await page.setViewportSize({width:1600,height:1000});
  await expect.poll(async () => (await bounds()).width).toBeGreaterThan(small.width*1.4);
  expect(Math.abs((await bounds()).center-800)).toBeLessThan(2);
  const largeLogo=await page.locator('.game-logo').boundingBox();
  expect(largeLogo.width).toBeCloseTo(await configuredLogoWidth(),0);
  const aspect=await page.locator('.game-logo').evaluate(el=>{const [w,h]=getComputedStyle(el).aspectRatio.split('/').map(Number);return w/h});
  expect(largeLogo.width/largeLogo.height).toBeCloseTo(aspect,1);
  await expect(page.locator('.sector.at-1-1 .floor')).toHaveCSS('filter', 'saturate(0.45) brightness(0.55)');
  await expect(page.locator('.object.at-1-1 .tree').first()).toHaveCSS('filter', /brightness\(0.55\)/);
  await expect(page.locator('.sector.at-0-0 .floor')).toHaveCSS('filter', 'none');
  await page.screenshot({path:require('node:path').resolve(__dirname,'../../results/frontier-responsive.png')});
  await page.setViewportSize({width:375,height:740});
  expect((await page.locator('.game-logo').boundingBox()).width).toBeCloseTo(await configuredLogoWidth(),0);
  await expect(page.locator('.map-viewport')).toHaveClass(/pannable/);
  await expect.poll(async()=> (await bounds()).width).toBeGreaterThan(375);
});

test.describe('narrow camera', () => {
  test.use({viewport:{width:375,height:740},hasTouch:true});
  test('dragging pans without navigation; taps still travel online and offline', async ({page}) => {
    await page.goto('/lat/0/lon/0');
    await expect.poll(() => snapshotPaths(page)).toHaveLength(4);
    await expect(page.locator('.map-viewport')).toHaveClass(/pannable/);
    const scene = page.locator('#map-scene');
    const offset = () => scene.evaluate(el => parseFloat(el.style.getPropertyValue('--camera-x')));
    const initial = await offset();
    const logo = await page.locator('.game-logo').boundingBox();
    const tile = page.locator('a[href="/lat/1/lon/1"]');
    const box = await tile.boundingBox();
    await page.mouse.move(box.x+box.width/2,box.y+box.height/2);
    await page.mouse.down();
    await page.mouse.move(box.x+box.width/2+85,box.y+box.height/2-25,{steps:8});
    await page.mouse.up();
    await expect.poll(offset).toBeGreaterThan(initial+70);
    await expect(page).toHaveURL(/\/lat\/0\/lon\/0$/);
    expect(await page.locator('.game-logo').boundingBox()).toEqual(logo);
    await page.locator('a[href="/lat/1/lon/0"]').tap();
    await expect(page).toHaveURL(/\/lat\/1\/lon\/0$/);
    await page.evaluate(()=>Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))));
    // Opening the DevTools isn't needed to prove the camera is independent of connection state.
    await page.evaluate(()=>window.fogOfWar.toggleConnection());
    await expect(page.locator('html')).toHaveClass(/fow-offline/);
    await page.locator('a[href="/lat/1/lon/1"]').tap();
    await expect(page).toHaveURL(/\/lat\/1\/lon\/1$/);
    await expect(page.locator('.map-viewport')).toHaveClass(/pannable/);
    await page.evaluate(()=>Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{}))));
    await expect(page.locator('#player')).toBeInViewport();
    expect(await page.locator('body').evaluate(el => el.scrollHeight <= innerHeight)).toBe(true);
    await page.screenshot({path:require('node:path').resolve(__dirname,'../../results/frontier-mobile-camera.png')});
  });
});
