const {test,expect}=require('@playwright/test');
test.use({baseURL:'http://127.0.0.1:47192',viewport:{width:640,height:800}});

for(const width of [640,375]) test(`zoomed movement preserves fog and logo layers at ${width}px`,async({page})=>{
  await page.setViewportSize({width,height:800});
  await page.goto('/lat/0/lon/0');
  await expect.poll(()=>page.evaluate(async()=> (await window.fogOfWar.cache.inspect()).rows.length)).toBe(4);
  // Make the real logo's layer measurable where terrain passes beneath it.
  await page.addStyleTag({content:'.game-logo {left:25vw !important;top:320px !important;background:rgb(255,0,255) !important}'});
  await page.locator('a[href="/lat/0/lon/1"]').click();
  await page.waitForFunction(()=>document.getAnimations().some(a=>a.effect?.getComputedTiming().duration===650));
  await page.evaluate(()=>{for(const a of document.getAnimations()){a.pause();if(a.effect?.getComputedTiming().duration===650)a.currentTime=300}});
  await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  const rememberedFloor = page.locator('.sector.at-1-1 .floor');
  const rememberedTree = page.locator('.object.at-1-1 .tree').first();
  const currentFloor = page.locator('.sector.at-0-1 .floor');
  const unexploredFloor = page.locator('.sector.at-2-2 .floor');
  await expect(rememberedFloor).toHaveCSS('filter', 'saturate(0.45) brightness(0.55)');
  await expect(rememberedTree).toHaveCSS('filter', /brightness\(0.55\)/);
  await expect(currentFloor).toHaveCSS('filter', 'none');
  await expect(unexploredFloor).toHaveCSS('filter', 'brightness(0)');
  const screenshot=await page.screenshot();
  const sample=await page.evaluate(async base64=>{
    const image=new Image();image.src='data:image/png;base64,'+base64;await image.decode();
    const copy=document.createElement('canvas');copy.width=innerWidth;copy.height=innerHeight;
    const ctx=copy.getContext('2d');ctx.drawImage(image,0,0);
    const frame=ctx.getImageData(0,0,innerWidth,innerHeight).data;
    const logo=document.querySelector('.game-logo').getBoundingClientRect();
    const center=(Math.floor(logo.top+logo.height/2)*innerWidth+Math.floor(logo.left+logo.width/2))*4;
    return [...frame.slice(center,center+3)];
  },screenshot.toString('base64'));
  expect(sample).toEqual([255,0,255]);
  if(width===375){
    const state=()=>rememberedFloor.evaluate(el=>({
      x:el.getBoundingClientRect().x, filter:getComputedStyle(el).filter,
    }));
    const before=await state();
    await page.evaluate(()=>{for(const a of document.getAnimations())if(a.effect?.getComputedTiming().duration===650)a.currentTime=500});
    await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
    const after=await state();
    expect(after.x).not.toBe(before.x);
    expect(after.filter).toBe(before.filter);
  }
  await page.evaluate(()=>document.getAnimations().forEach(a=>a.play()));
  await page.evaluate(()=>window.fogOfWar.toggleConnection());
  await expect(currentFloor).toHaveCSS('filter', 'saturate(0.45) brightness(0.55)');
});
