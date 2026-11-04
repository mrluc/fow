const {test, expect} = require('@playwright/test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const project = path.resolve(__dirname, '../../examples/frontier');
const origin = 'http://127.0.0.1:47192';

test('native public bundle starts offline, imports gzip routes and automatically recovers the selected route', async ({browser}) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'fog-native-browser-'));
  const manifest = JSON.parse(fs.readFileSync(path.join(project, '.fow.json')));
  // Keep this fixture's static files rooted in the real example, but isolate every output.
  manifest.web.origin = origin;
  manifest.public.static_root = 'priv/static';
  const manifestFile = path.join(project, `.fow-test-${process.pid}.json`);
  fs.writeFileSync(manifestFile, JSON.stringify(manifest));
  const output = path.join(root, 'bundle');
  let context;
  try {
    execFileSync('mix', ['fow.bundle.prepare', '--manifest', manifestFile, '--output', output, '--platform', 'android'], {cwd: project, env: {...process.env, MIX_ENV:'test'}, stdio:'pipe'});
    const native = JSON.parse(fs.readFileSync(path.join(output, 'native.json')));
    // A fulfilled document has no local IP response metadata. Allow the local test server
    // explicitly; this is a Chrome test-harness permission, not a production setting.
    context = await browser.newContext({permissions:['local-network-access']});
    let initial = true, online = false;
    await context.routeWebSocket('**/*', socket => { if (online) socket.connectToServer(); else socket.close(); });
    await context.route('**/*', route => {
      const url = new URL(route.request().url()); url.search = ''; url.hash = '';
      const resource = native.files[url.href];
      if (initial && route.request().isNavigationRequest() && url.href === native.url) {
        initial = false;
        return route.fulfill({status:200, contentType:'text/html', body:fs.readFileSync(path.join(output,native.startup))});
      }
      if (resource) return route.fulfill({status:200, contentType:resource.mime, body:fs.readFileSync(path.join(output,resource.file))});
      return online ? route.continue() : route.abort('internetdisconnected');
    });
    const page = await context.newPage();
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.goto(native.url);
    await expect.poll(() => page.evaluate(() => Boolean(window.fogOfWarStartup))).toBe(true);
    expect(await page.evaluate(() => window.fogOfWarStartup)).toMatchObject({complete:true,stored:4});
    await expect(page.locator('html')).toHaveClass(/fow-offline/);
    const art = await page.evaluate(async () => Promise.all(['/images/fog-of-war-logo.png','/images/terrain.png','/images/pine.png','/images/scout-idle.png','/images/scout-walk.png'].map(src => new Promise((resolve,reject) => {
      const image = new Image(); image.crossOrigin = 'anonymous';
      image.onload = () => { try {
        const canvas = document.createElement('canvas'); canvas.width = canvas.height = 4;
        const ctx = canvas.getContext('2d'); ctx.drawImage(image,0,0,4,4); ctx.getImageData(0,0,4,4); resolve(true);
      } catch(error) {reject(error)} };
      image.onerror = () => reject(new Error(src)); image.src = src;
    }))));
    expect(art).toEqual([true,true,true,true,true]);
    await page.locator('a[href="/lat/0/lon/1"]').first().click();
    await expect(page).toHaveURL(origin + '/lat/0/lon/1');
    online = true; // No UI toggle or forced reload: the real socket retries.
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/, {timeout:15000});
    await expect(page).toHaveURL(origin + '/lat/0/lon/1');
    await page.locator('a[href="/lat/0/lon/2"]').first().click();
    await expect(page).toHaveURL(origin + '/lat/0/lon/2');
    await expect(page.locator('[data-phx-main]')).toHaveClass(/phx-connected/);
    expect(errors).toEqual([]);
  } finally {
    await context?.close(); fs.rmSync(manifestFile,{force:true}); fs.rmSync(root,{recursive:true,force:true});
  }
});
