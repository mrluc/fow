// macOS: test the actual generated Frontier app, then rebuild without the test driver.
// source ../env.sh; node test/native/frontier-smoke.cjs [generated-project]
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),{spawn}=require('node:child_process');
const root=path.resolve(__dirname,'../..'),project=path.resolve(process.argv[2]||path.join(root,'examples/frontier/.fow/apps/elixirkit/dev'));
const rust=path.join(project,'src-tauri/src/main.rs'),original=fs.readFileSync(rust,'utf8');
const manifest=JSON.parse(fs.readFileSync(path.join(project,'.fow.json'))),origin=manifest.web.origin,start=manifest.web.start_path;
const executable=path.join(process.env.CARGO_TARGET_DIR,'release/bundle/macos/Frontier.app/Contents/MacOS/frontier_desktop');
const log=fs.openSync(path.join(project,'native-smoke.log'),'w');
const check=(ok,message)=>{if(!ok)throw new Error(message)};
const build=()=>new Promise((resolve,reject)=>{
  const child=spawn('bash',['build.sh'],{cwd:project,stdio:['ignore',log,log]});
  child.on('error',reject);child.on('exit',code=>code===0?resolve():reject(new Error('Build failed; inspect native-smoke.log')));
});
async function main(){
  let app,result;
  const server=http.createServer(async(req,res)=>{
    res.setHeader('Access-Control-Allow-Origin',origin);
    if(req.method!=='POST'||req.url!=='/result'){res.writeHead(404);res.end();return}
    let body='';for await(const chunk of req)body+=chunk;
    result=JSON.parse(body);res.end('ok');
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const callback=`http://127.0.0.1:${server.address().port}/result`;
  const script=`(() => {
    if(location.origin!==${JSON.stringify(origin)})return;
    const errors=[];window.addEventListener('error',event=>errors.push(event.message));
    const wait=async predicate=>{const end=Date.now()+20000;while(!await predicate()){if(Date.now()>end)throw new Error('Native Frontier readiness timeout');await new Promise(resolve=>setTimeout(resolve,25))}};
    const check=(ok,message)=>{if(!ok)throw new Error(message)};
    const report=value=>fetch(${JSON.stringify(callback)},{method:'POST',body:JSON.stringify(value)});
    window.addEventListener('load',async()=>{try{
      await wait(()=>window.fogOfWar&&window.liveSocket?.main?.isConnected());
      const cache=window.fogOfWar.cache;await cache.ready;await window.frontierPreload;await cache.flush();
      check((await cache.inspect()).backend==='indexedDB','Expected IndexedDB');
      check(document.querySelectorAll('.terrain-tile').length===144,'Terrain did not render');
      const logoURL=getComputedStyle(document.querySelector('.game-logo')).backgroundImage.match(/url\\(["']?(.*?)["']?\\)/)[1];
      await new Promise((resolve,reject)=>{const image=new Image();image.onload=resolve;image.onerror=()=>reject(new Error('Logo failed to load'));image.src=logoURL});
      const count=(await cache.inspect()).rows.filter(row=>row.valid).length;check(count>=4,'Neighbors were not cached');
      window.fogOfWar.toggleConnection();
      document.querySelector('.tile-target[href="/lat/1/lon/1"]').click();
      await wait(()=>location.pathname==='/lat/1/lon/1'&&document.querySelector('#player')?.classList.contains('at-1-1'));
      document.querySelector('.tile-target[href="/lat/2/lon/2"]').click();
      await wait(()=>window.fogOfWar.navigationEvents().some(event=>event.path==='/lat/2/lon/2'&&event.outcome==='denied'));
      check(location.pathname==='/lat/1/lon/1','Uncached route should be denied');
      history.back();await wait(()=>location.pathname===${JSON.stringify(start)}&&document.querySelector('#player')?.classList.contains('at-0-0'));
      check(document.querySelector('canvas.pixel-fog')?.width>0,'Pixel fog did not initialize');check(errors.length===0,errors.join('; '));
      await report({ok:true,backend:'indexedDB',cached:count,terrainTiles:144,logo:logoURL,offlineMove:true,uncachedDenied:true,history:true});
    }catch(error){await report({ok:false,error:error.stack||error.message,errors})}});
  })();`;
  try{
    check(original.includes('.initialization_script(include_str!("../../priv/fog_of_war_seed.js"))'),'Unexpected host template');
    fs.writeFileSync(path.join(project,'priv/frontier_smoke.js'),script);
    fs.writeFileSync(rust,original.replace('.initialization_script(include_str!("../../priv/fog_of_war_seed.js"))','.initialization_script(include_str!("../../priv/fog_of_war_seed.js"))\n                    .initialization_script(include_str!("../../priv/frontier_smoke.js"))'));
    console.log('Building and launching Frontier in its native WebView.');await build();
    app=spawn(executable,[],{detached:true,stdio:['ignore',log,log]});
    const until=Date.now()+45000;
    while(!result){check(Date.now()<until,'Frontier timed out; inspect native-smoke.log');await new Promise(resolve=>setTimeout(resolve,100))}
    check(result.ok,JSON.stringify(result));console.log('Frontier native smoke passed:',JSON.stringify(result));
  }finally{
    if(app?.pid){try{process.kill(-app.pid,'SIGTERM')}catch(_){}}
    server.close();fs.writeFileSync(rust,original);fs.rmSync(path.join(project,'priv/frontier_smoke.js'),{force:true});
    // The app eventually installed for the user must contain no test-only driver.
    console.log('Rebuilding normal Frontier.app without test instrumentation.');await build();fs.closeSync(log);
  }
}
main().catch(error=>{console.error(error);process.exitCode=1});
