const {test,expect}=require('@playwright/test');
const {gzipSync}=require('node:zlib');
const {createHash}=require('node:crypto');
const snapshot=(path,html,savedAt='2020-01-01T00:00:00.000Z')=>({schema:1,build:'fog-of-war-2',path,regionId:'counter-site',savedAt,html});
const settled=page=>page.evaluate(async()=>{await window.fogOfWar.cache.flush();return (await window.fogOfWar.cache.inspect()).backend});
async function bundle(page,paths=['/bundled/one','/bundled/two','/bundled/three']){
  const pages={},files={};
  for(const [n,path] of paths.entries()){
    const html=`<main id="counter-site"><h1>Bundled ${n}</h1><a href="/">Home</a></main>`,payload=gzipSync(html),file=`pages/${n}.html.gz`;
    files[file]=payload;
    pages[path]={...snapshot(path,html),html:undefined,title:`Bundled ${n}`,file,encoding:'gzip',compressedBytes:payload.length,htmlBytes:Buffer.byteLength(html),sha256:createHash('sha256').update(payload).digest('hex')};
  }
  const index={schema:1,format:'fog-of-war-public-cache',scope:'public',origin:new URL(page.url()).origin,pages};
  const requests=[];
  await page.route('**/bundle/**',route=>{
    const file=new URL(route.request().url()).pathname.slice('/bundle/'.length);requests.push(file);
    return route.fulfill(file==='index.json'?{json:index}:{body:files[file],contentType:'application/octet-stream'});
  });
  return {index,files,requests};
}

test('migrates plain and compressed legacy records, preserving newer device data and corrupt originals',async({page})=>{
  const zipped={...snapshot('/legacy-gzip','<main>🌲 old compressed</main>'),html:undefined,htmlEncoding:'gzip-base64',htmlGzip:gzipSync('<main>🌲 old compressed</main>').toString('base64')};
  await page.addInitScript(({plain,zipped,corrupt})=>{
    if(sessionStorage.getItem('seeded'))return;
    sessionStorage.setItem('seeded','true');
    localStorage.setItem('fog-of-war:page:old-plain',JSON.stringify(plain));
    localStorage.setItem('fog-of-war:page:old-gzip',JSON.stringify(zipped));
    localStorage.setItem('fog-of-war:page:corrupt',JSON.stringify(corrupt));
  },{plain:snapshot('/legacy-plain','<main>old plain</main>'),zipped,corrupt:{...zipped,path:'/corrupt',htmlGzip:'broken'}});
  await page.goto('/');expect(await settled(page)).toBe('indexedDB');
  expect(await page.evaluate(async()=>{
    const cache=window.fogOfWar.cache;
    return [(await cache.load(new URL('/legacy-plain',location.href))).html,(await cache.load(new URL('/legacy-gzip',location.href))).html,Object.keys(localStorage).filter(key=>key.startsWith('fog-of-war:page:'))];
  })).toEqual(['<main>old plain</main>','<main>🌲 old compressed</main>',['fog-of-war:page:corrupt']]);
  await page.evaluate(async record=>{await window.fogOfWar.cache.save(record,{protectRoute:false});localStorage.setItem('fog-of-war:page:old-plain',JSON.stringify({...record,savedAt:'2000-01-01T00:00:00Z',html:'older'}));},snapshot('/legacy-plain','new device copy','2026-01-01T00:00:00Z'));
  await page.reload();await settled(page);
  expect(await page.evaluate(async()=>[(await window.fogOfWar.cache.load(new URL('/legacy-plain',location.href))).html,localStorage.getItem('fog-of-war:page:old-plain')])).toEqual(['new device copy',null]);
});

test('failed migration retains its legacy copy and later writes do not silently switch storage',async({page})=>{
  await page.addInitScript(record=>{
    localStorage.setItem('fog-of-war:page:/legacy',JSON.stringify(record));
    const put=IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put=function(value,...rest){if(this.name==='pages')throw new DOMException('Simulated full disk','QuotaExceededError');return put.call(this,value,...rest)};
  },snapshot('/legacy','<main>only copy</main>'));
  await page.goto('/');expect(await settled(page)).toBe('indexedDB');
  expect(await page.evaluate(async()=>{
    const cache=window.fogOfWar.cache;let failure;
    try{await cache.save({schema:1,build:'fog-of-war-2',path:'/failed',html:'new',savedAt:new Date().toISOString()},{protectRoute:false})}catch(error){failure=error.name}
    return {failure,backend:(await cache.inspect()).backend,legacy:!!localStorage.getItem('fog-of-war:page:/legacy'),html:(await cache.load(new URL('/legacy',location.href))).html};
  })).toEqual({failure:'QuotaExceededError',backend:'indexedDB',legacy:true,html:'<main>only copy</main>'});
});

test('unavailable IndexedDB falls back to localStorage and still supports offline navigation',async({page})=>{
  await page.addInitScript(()=>Object.defineProperty(window,'indexedDB',{get(){throw new DOMException('Blocked','SecurityError')}}));
  await page.goto('/');expect(await settled(page)).toBe('localStorage');
  await page.locator('a[href="/counters/one"]').click();await expect(page.locator('#increment-counter')).toBeVisible();
  const count=String(Number(await page.locator('#count').innerText())+1);
  await page.locator('#increment-counter').click();await expect(page.locator('#count')).toHaveText(count);await settled(page);
  const panel=page.locator('[data-fog-of-war-dev-tools]');await panel.locator('.launcher').click();await panel.getByRole('button',{name:'Disconnect socket',exact:true}).click();
  await page.getByRole('link',{name:'‹ Back',exact:true}).click();await expect(page.locator('#page-title')).toHaveText('Counters');
  await page.locator('a[href="/counters/one"]').click();await expect(page.locator('#count')).toHaveText(count);await expect(page.locator('#increment-counter')).toBeDisabled();
  expect(await page.evaluate(async()=>{try{await window.fogOfWar.cache.importBundle({})}catch(error){return error.message}})).toContain('requires IndexedDB');
});

test('IndexedDB stores a seven-megabyte region without consuming localStorage',async({page})=>{
  await page.goto('/');await settled(page);
  expect(await page.evaluate(async()=>{
    window.CompressionStream=undefined;
    const cache=window.fogOfWar.cache,html='x'.repeat(7*1024*1024);
    await cache.save({schema:1,build:'fog-of-war-2',path:'/large',html,savedAt:new Date().toISOString()},{protectRoute:false});
    return {length:(await cache.load(new URL('/large',location.href))).html.length,backend:(await cache.inspect()).backend,keys:Object.keys(localStorage).filter(key=>key.startsWith('fog-of-war:page:')).length};
  })).toEqual({length:7*1024*1024,backend:'indexedDB',keys:0});
});

test('bundle import commits bounded batches, resumes after reload, and preserves device captures',async({page})=>{
  await page.goto('/');await settled(page);
  const fixture=await bundle(page,['/bundled/one','/bundled/two','/bundled/three','/device']);
  await page.evaluate(record=>window.fogOfWar.cache.save(record,{protectRoute:false}),snapshot('/device','device wins','2010-01-01T00:00:00Z'));
  expect(await page.evaluate(async()=>{
    const controller=new AbortController();window.progress=[];
    try{await window.fogOfWar.cache.importBundle('/bundle/index.json',{batchSize:1,signal:controller.signal,onProgress:state=>{window.progress.push(state);controller.abort()}})}catch(error){return {name:error.name,completed:window.progress[0].completed}}
  })).toEqual({name:'AbortError',completed:1});
  await page.reload();await settled(page);
  const result=await page.evaluate(()=>window.fogOfWar.cache.importBundle('/bundle/index.json',{batchSize:1}));
  expect(result).toMatchObject({completed:4,complete:true,stored:2,skipped:1});
  expect(fixture.requests.filter(file=>file==='pages/0.html.gz')).toHaveLength(1);
  expect(fixture.requests).not.toContain('pages/3.html.gz');
  expect(await page.evaluate(async()=>{
    const cache=window.fogOfWar.cache;return [(await cache.load(new URL('/device',location.href))).html,(await cache.getRecord('/bundled/two')).htmlGzip instanceof Uint8Array];
  })).toEqual(['device wins',true]);
  // A cached route imported from the server-produced format is a real offline destination.
  const panel=page.locator('[data-fog-of-war-dev-tools]');await panel.locator('.launcher').click();await panel.getByRole('button',{name:'Disconnect socket',exact:true}).click();
  await page.evaluate(()=>{const link=document.createElement('a');link.href='/bundled/two';link.id='imported-link';link.textContent='Imported';document.querySelector('#counter-site').append(link)});
  await page.locator('#imported-link').click();await expect(page.locator('#counter-site h1')).toHaveText('Bundled 1');
});

test('bundle checksum failures do not commit or discard device data, and a later bundle can update an earlier bundle',async({page})=>{
  await page.goto('/');await settled(page);const fixture=await bundle(page,['/bundled/one']);
  fixture.index.pages['/bundled/one'].sha256='0'.repeat(64);
  expect(await page.evaluate(async()=>{try{await window.fogOfWar.cache.importBundle('/bundle/index.json')}catch(error){return error.message}})).toContain('checksum mismatch');
  expect(await page.evaluate(()=>window.fogOfWar.cache.find(new URL('/bundled/one',location.href)))).toBe(null);
  fixture.index.pages['/bundled/one'].sha256=createHash('sha256').update(fixture.files['pages/0.html.gz']).digest('hex');
  await page.evaluate(()=>window.fogOfWar.cache.importBundle('/bundle/index.json'));
  const updated='<main id="counter-site">New bundle</main>',bytes=gzipSync(updated),record=fixture.index.pages['/bundled/one'];
  Object.assign(record,{savedAt:'2025-01-01T00:00:00Z',compressedBytes:bytes.length,htmlBytes:Buffer.byteLength(updated),sha256:createHash('sha256').update(bytes).digest('hex')});fixture.files['pages/0.html.gz']=bytes;
  await page.evaluate(()=>window.fogOfWar.cache.importBundle('/bundle/index.json'));
  expect(await page.evaluate(async()=>(await window.fogOfWar.cache.load(new URL('/bundled/one',location.href))).html)).toBe(updated);
  fixture.index.origin='https://other.example';
  expect(await page.evaluate(async()=>{try{await window.fogOfWar.cache.importBundle('/bundle/index.json')}catch(error){return error.message}})).toContain('origin');
});


test('failed IndexedDB availability write chooses fallback without an unhandled transaction rejection',async({page})=>{
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
    const put=IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put=function(value,...rest){if(this.name==='imports')throw new DOMException('Storage denied','QuotaExceededError');return put.call(this,value,...rest)};
  });
  await page.goto('/');expect(await settled(page)).toBe('localStorage');
  await expect.poll(()=>page.evaluate(async()=>(await window.fogOfWar.cache.inspect()).rows.map(row=>row.path))).toEqual(['/']);
  expect(errors).toEqual([]);
});
