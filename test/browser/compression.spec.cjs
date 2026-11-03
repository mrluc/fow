const {test, expect} = require('@playwright/test');
test.use({baseURL:'http://127.0.0.1:47192'});
test('localStorage compresses real map HTML, reads legacy snapshots, and preserves offline navigation', async ({page}) => {
  await page.goto('/lat/0/lon/0');
  await expect.poll(()=>page.evaluate(()=>localStorage.getItem('frontier:seed:v2'))).toBe('complete');
  const stats=await page.evaluate(async()=>{
    const cache=window.fogOfWar.cache, url=new URL('/lat/1/lon/1',location.href);
    const plain=await cache.load(url), packed=localStorage.getItem('fog-of-war:page:'+url.pathname);
    const record=JSON.parse(packed);
    // Leave one real neighboring page in the old uncompressed format.
    const legacy=await cache.load(new URL('/lat/0/lon/1',location.href));
    localStorage.setItem('fog-of-war:page:/lat/0/lon/1',JSON.stringify(legacy));
    return {encoding:record.htmlEncoding,stored:packed.length,original:JSON.stringify(plain).length,
      htmlAbsent:!('html' in record),same:plain.html.includes('terrain-tile')};
  });
  expect(stats.encoding).toBe('gzip-base64');expect(stats.htmlAbsent).toBe(true);expect(stats.same).toBe(true);
  expect(stats.stored).toBeLessThan(stats.original*.4);
  console.log('Map localStorage characters:',stats.original,'→',stats.stored);
  const tools=page.locator('[data-fog-of-war-dev-tools]');
  await tools.locator('.launcher').click();
  await tools.getByRole('button',{name:'Pause connection',exact:true}).click();
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
    const fallback=JSON.parse(localStorage.getItem('fog-of-war:page:/test-fallback'));
    return {same:roundtrip.html===html+' newest',fallback:fallback.html===html};
  });
  expect(value).toEqual({same:true,fallback:true});
});
