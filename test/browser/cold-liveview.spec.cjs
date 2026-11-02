const {test, expect} = require('@playwright/test');
const origin = 'http://127.0.0.1:47183';
test.use({baseURL:origin});
test.afterEach(async ({request})=>{await request.get(origin+'/__fog_of_war_test__/backend?down=false')});

// Native-loader model: complete build-time HTML/assets, no cookie transfer,
// fake socket, pause button, forced reconnect, sanitized markup or second view.
async function installBundle(context, request, startPath, browserOffline = true) {
  expect(await context.cookies()).toEqual([]);
  const response = await request.get(origin + '/__fog_of_war_test__/live-bundle');
  expect(response.ok()).toBe(true);
  const bundle = await response.json();
  expect(bundle.signed_age_days).toBe(30);
  expect(bundle.token_verdict).toBe('expired');
  expect(bundle.response_cookies_included).toBe(false);
  expect(bundle.pages[startPath]).toContain('data-phx-session=');
  expect(bundle.pages[startPath]).toContain('name="csrf-token"');
  expect(bundle.pages[startPath]).toContain('/assets/js/app.js');
  await request.get(origin + '/__fog_of_war_test__/backend?down=true');
  let online = false;
  const served = [], freshDocuments = [], stale = [], attempts = [], errors = [];
  await context.route(origin + '/**', async route => {
    const req=route.request(), path=new URL(req.url()).pathname;
    if (!online) {
      if (req.isNavigationRequest() && bundle.pages[path]) {
        served.push(path);
        return route.continue({headers:{...req.headers(),'x-fog-of-war-test-bundle':bundle.bundle_id}});
      }
      const asset=bundle.assets[path];
      if (asset && path.endsWith('/app.js') && browserOffline) await context.setOffline(true);
      if (asset) return route.fulfill({status:200,contentType:asset.content_type,body:Buffer.from(asset.body,'base64')});
      return route.abort('internetdisconnected');
    }
    if(req.isNavigationRequest()) freshDocuments.push(path);
    return route.continue();
  });
  const page=await context.newPage();
  page.on('console',message=>{if(message.type()==='error') errors.push(message.text())});
  page.on('websocket',socket=>{
    attempts.push(socket.url().split('?')[0]);
    socket.on('framereceived',({payload})=>{
      try {const data=JSON.parse(String(payload));if(data[3]==='phx_reply' && data[4]?.response?.reason==='stale') stale.push(true)}catch(_){}
    });
  });
  // The native-loader stand-in serves cached bytes at the intended URL, without
  // calling Phoenix or issuing cookies. Offline mode begins before app.js executes.
  const loaded = await page.goto(startPath);
  expect(loaded.headers()['x-fog-of-war-render-source']).toBe('bundle');
  expect(await context.cookies()).toEqual([]);
  return {page,served,freshDocuments,stale,attempts,errors,
    reconnect:async()=>{online=true;await request.get(origin + '/__fog_of_war_test__/backend?down=false');await context.setOffline(false)}};
}
async function assertColdPage(probe,title) {
  await expect(probe.page.locator('#counter-title')).toHaveText(title);
  expect(await probe.page.evaluate(()=>window.liveSocket.isConnected())).toBe(false);
  expect(await probe.page.evaluate(()=>localStorage.length)).toBe(0);
  await expect.poll(()=>probe.attempts.length,{timeout:15000}).toBeGreaterThan(1);
  await expect(probe.page.locator('#counter-title')).toHaveText(title);
  await expect(probe.page.locator('#counter-site')).toBeVisible();
  expect(probe.stale).toHaveLength(0);
  expect(probe.freshDocuments).toEqual([]);
}
async function assertAutomaticRecovery(probe,path,title) {
  await probe.reconnect();
  await expect.poll(()=>probe.stale.length,{timeout:15000}).toBeGreaterThan(0);
  await expect.poll(()=>probe.freshDocuments,{timeout:15000}).toEqual([path]);
  await expect(probe.page).toHaveURL(origin+path);
  await expect(probe.page.locator('#counter-title')).toHaveText(title);
  await expect.poll(()=>probe.page.evaluate(()=>!!window.liveSocket?.main?.isConnected())).toBe(true);
  const before=Number(await probe.page.locator('#count').innerText());
  await probe.page.locator('#increment-counter').click();
  await expect(probe.page.locator('#count')).toHaveText(String(before+1));
}
test('full baked LiveView stays visible offline, retries, and automatically refreshes its expired session',async({context,request},testInfo)=>{
  const probe=await installBundle(context,request,'/counters/three');
  await assertColdPage(probe,'Counter three');
  await assertAutomaticRecovery(probe,'/counters/three','Counter three');
  await testInfo.attach('cold-liveview-observation',{body:Buffer.from(JSON.stringify({
    bundlePagesServed:probe.served,socketAttempts:probe.attempts.length,staleReplies:probe.stale.length,
    automaticFreshDocuments:probe.freshDocuments,browserConsoleErrors:probe.errors,
  },null,2)),contentType:'application/json'});
});
test('with backend unavailable, baked pages navigate before reconnecting and automatically refresh the current route',async({context,request})=>{
  const probe=await installBundle(context,request,'/counters/one',false);
  await assertColdPage(probe,'Counter one');
  await probe.page.getByRole('link',{name:'‹ Back',exact:true}).click();
  await expect(probe.page).toHaveURL(origin+'/');
  await expect(probe.page.locator('#page-title')).toHaveText('Counters');
  await probe.page.locator('a[href="/counters/two"]').click();
  await expect(probe.page).toHaveURL(origin+'/counters/two');
  await expect(probe.page.locator('#counter-title')).toHaveText('Counter two');
  expect(probe.served).toEqual(['/counters/one','/','/counters/two']);
  expect(probe.freshDocuments).toEqual([]);
  await assertAutomaticRecovery(probe,'/counters/two','Counter two');
});
