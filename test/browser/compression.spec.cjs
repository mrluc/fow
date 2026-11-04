const {test, expect} = require('@playwright/test');
test.use({baseURL:'http://127.0.0.1:47192'});
test('IndexedDB compresses real map HTML as binary and preserves offline navigation', async ({page}) => {
  await page.goto('/lat/0/lon/0');
  await expect.poll(()=>page.evaluate(()=>localStorage.getItem('frontier:seed:v2'))).toBe('complete');
  const stats=await page.evaluate(async()=>{
    const cache=window.fogOfWar.cache, url=new URL('/lat/1/lon/1',location.href);
    const plain=await cache.load(url), record=await cache.getRecord(url.pathname);
    const row=(await cache.inspect()).rows.find(row=>row.path===url.pathname);
    return {encoding:record.htmlEncoding,stored:row.bytes,original:new TextEncoder().encode(plain.html).length,
      binary:record.htmlGzip instanceof Uint8Array,htmlAbsent:!('html' in record),same:plain.html.includes('terrain-tile')};
  });
  expect(stats.encoding).toBe('gzip');expect(stats.binary).toBe(true);expect(stats.htmlAbsent).toBe(true);expect(stats.same).toBe(true);
  expect(stats.stored).toBeLessThan(stats.original*.4);
  console.log('Map cache bytes:',stats.original,'→',stats.stored);
  const tools=page.locator('[data-fog-of-war-dev-tools]');
  await tools.locator('.launcher').click();
  await tools.getByRole('button',{name:'Disconnect socket',exact:true}).click();
  const requests=[];page.on('request',r=>requests.push(r.url()));
  await page.locator('.tile-target[href="/lat/0/lon/1"]').click();
  await expect(page.locator('#player')).toHaveClass(/at-0-1/);
  await page.locator('.tile-target[href="/lat/1/lon/1"]').click();
  await expect(page.locator('#player')).toHaveClass(/at-1-1/);
  await page.goBack();await expect(page.locator('#player')).toHaveClass(/at-0-1/);
  expect(requests).toEqual([]);
});

test('compression preserves Unicode and capture order; unavailable browser codec falls back to plain HTML',async({page})=>{
  await page.goto('/lat/0/lon/0');
  await expect.poll(()=>page.evaluate(()=>localStorage.getItem('frontier:seed:v2'))).toBe('complete');
  const value=await page.evaluate(async()=>{
    const cache=window.fogOfWar.cache;
    const source=await cache.load(new URL(location.href));
    const html='<section>🌲 café 日本語</section>'.repeat(100);
    await Promise.all([cache.save({...source,path:'/test-order',html},{protectRoute:false}),cache.save({...source,path:'/test-order',html:html+' newest'},{protectRoute:false})]);
    const roundtrip=await cache.load(new URL('/test-order',location.href));
    window.CompressionStream=undefined;
    await cache.save({...source,path:'/test-fallback',html},{protectRoute:false});
    const fallback=await cache.getRecord('/test-fallback');
    return {same:roundtrip.html===html+' newest',fallback:fallback.html===html};
  });
  expect(value).toEqual({same:true,fallback:true});
});
