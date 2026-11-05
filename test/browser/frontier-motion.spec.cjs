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
  const screenshot=await page.screenshot();
  const sample=await page.evaluate(async base64=>{
    const image=new Image();image.src='data:image/png;base64,'+base64;await image.decode();
    const copy=document.createElement('canvas');copy.width=innerWidth;copy.height=innerHeight;
    const ctx=copy.getContext('2d');ctx.drawImage(image,0,0);
    const frame=ctx.getImageData(0,0,innerWidth,innerHeight).data;
    const mask=document.querySelector('canvas.pixel-fog').getContext('2d').getImageData(0,0,innerWidth,innerHeight).data;
    const logo=document.querySelector('.game-logo').getBoundingClientRect();
    let fogPixels=0,uncovered=0;
    for(let y=0;y<innerHeight;y++)for(let x=0;x<innerWidth;x++){
      const i=(y*innerWidth+x)*4;
      if(mask[i+3]!==190 || x>=logo.left&&x<logo.right&&y>=logo.top&&y<logo.bottom)continue;
      fogPixels++;
      // The actual gray fog (alpha 190) bounds even white terrain to these values.
      if(frame[i]>119||frame[i+1]>123||frame[i+2]>119)uncovered++;
    }
    const center=(Math.floor(logo.top+logo.height/2)*innerWidth+Math.floor(logo.left+logo.width/2))*4;
    return {fogPixels,uncovered,logoPixel:[...frame.slice(center,center+3)]};
  },screenshot.toString('base64'));
  expect(sample.fogPixels).toBeGreaterThan(1000);
  expect(sample.uncovered).toBe(0);
  expect(sample.logoPixel).toEqual([255,0,255]);
  if(width===375){
    const state=()=>page.evaluate(()=>{
      const canvas=document.querySelector('canvas.pixel-fog');
      const bytes=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
      let signature=0;for(let i=3;i<bytes.length;i+=4)signature=(signature*31+bytes[i])>>>0;
      return {transform:getComputedStyle(document.querySelector('#map-scene')).transform,signature};
    });
    const before=await state();
    await page.evaluate(()=>{for(const a of document.getAnimations())if(a.effect?.getComputedTiming().duration===650)a.currentTime=500});
    await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
    const after=await state();
    expect(after.transform).not.toBe(before.transform);
    expect(after.signature).not.toBe(before.signature);
  }
  await page.evaluate(()=>document.getAnimations().forEach(a=>a.play()));
});
