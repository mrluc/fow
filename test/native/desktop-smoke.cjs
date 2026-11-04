// Runs the generated ElixirKit app, not a browser emulation of its WebView.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),{spawn}=require('node:child_process');
const root=path.resolve(__dirname,'../..'),work=path.join(root,'.fow/native-test'),project=path.join(work,'desktop');
const origin='http://127.0.0.1:47182',port=47184;
const assert=(value,message)=>{if(!value)throw new Error(message)};
let app;
async function main(){
  const results=[];
  const server=http.createServer(async(req,res)=>{
    res.setHeader('Access-Control-Allow-Origin',origin);
    if(req.url==='/result'){
      let body='';for await(const chunk of req)body+=chunk;
      results.push(JSON.parse(body));res.end('ok');return;
    }
    const relative=req.url.slice('/bundle/'.length);
    if(!req.url.startsWith('/bundle/')||relative.includes('..')){res.writeHead(404);res.end();return}
    try{res.setHeader('Content-Type',relative.endsWith('.json')?'application/json':'application/octet-stream');res.end(fs.readFileSync(path.join(work,'cache',relative)))}catch(error){res.writeHead(404);res.end()}
  });
  await new Promise(resolve=>server.listen(port,'127.0.0.1',resolve));
  const script=`(() => {
    if(location.origin!==${JSON.stringify(origin)})return;
    const wait=async predicate=>{const end=Date.now()+20000;while(!await predicate()){if(Date.now()>end)throw new Error('Native readiness timeout');await new Promise(resolve=>setTimeout(resolve,25))}};
    const assert=(ok,message)=>{if(!ok)throw new Error(message)};
    const report=result=>fetch('http://127.0.0.1:${port}/result',{method:'POST',body:JSON.stringify(result)});
    window.addEventListener('load',async()=>{try{
      await wait(()=>window.fogOfWar&&window.liveSocket?.main?.isConnected());
      const cache=window.fogOfWar.cache;assert(await cache.ready==='indexedDB','IndexedDB unavailable in WKWebView');
      const phase=sessionStorage.getItem('native-cache-phase');
      if(!phase){
        const controller=new AbortController();let committed=0;
        try{await cache.importBundle('http://127.0.0.1:${port}/bundle/index.json',{batchSize:1,signal:controller.signal,onProgress:state=>{committed=state.completed;controller.abort()}})}catch(error){assert(error.name==='AbortError','Unexpected import failure: '+error.message)}
        assert(committed===1,'First batch did not commit');sessionStorage.setItem('native-cache-phase','resume');location.reload();return;
      }
      const state=await cache.importBundle('http://127.0.0.1:${port}/bundle/index.json',{batchSize:1});
      assert(state.complete&&state.completed===4,'Resume did not finish all exported routes');
      const record=await cache.getRecord('/counters/two');assert(record.htmlGzip instanceof Uint8Array,'Gzip payload was not stored as binary');
      const saved=await cache.load(new URL('/counters/two',location.href));assert(saved.html.includes('Counter two'),'Exported region failed gzip decode');
      window.fogOfWar.toggleConnection();
      const link=document.querySelector('a[href="/counters/two"]');assert(link,'Counter navigation not found');link.click();
      await wait(()=>location.pathname==='/counters/two'&&document.querySelector('#increment-counter')?.disabled);
      sessionStorage.removeItem('native-cache-phase');
      await report({ok:true,backend:(await cache.inspect()).backend,completed:state.completed,path:location.pathname,binary:true,offline:true,resumed:true});
    }catch(error){await report({ok:false,error:error.stack||error.message})}});
  })();`;
  fs.writeFileSync(path.join(project,'priv/indexeddb_smoke.js'),script);
  const rust=path.join(project,'src-tauri/src/main.rs');
  fs.writeFileSync(rust,fs.readFileSync(rust,'utf8').replace('External(local)','External(live)').replace('http://127.0.0.1:47180/',origin+'/').replace('.initialization_script(include_str!("../../priv/fog_of_war_seed.js"))','.initialization_script(include_str!("../../priv/indexeddb_smoke.js"))'));
  const log=fs.openSync(path.join(work,'build.log'),'w');
  try{
    console.log('Building the cached ElixirKit desktop app; log: '+path.join(work,'build.log'));
    await new Promise((resolve,reject)=>{
      const build=spawn('bash',['build.sh'],{cwd:project,stdio:['ignore',log,log]});
      build.on('error',reject);build.on('exit',code=>code===0?resolve():reject(new Error('Native build failed: '+code)));
    });
    const executable=path.join(process.env.CARGO_TARGET_DIR,'release/bundle/macos/Counters.app/Contents/MacOS/counters_desktop');
    console.log('Launching actual desktop WebView for batch import, reload, and offline navigation.');
    app=spawn(executable,[],{detached:true,stdio:['ignore',log,log]});
    const until=Date.now()+45000;
    while(!results.length){assert(Date.now()<until,'Native result timed out; inspect build.log');await new Promise(resolve=>setTimeout(resolve,100))}
    assert(results[0].ok,JSON.stringify(results[0]));console.log('Native IndexedDB check passed:',JSON.stringify(results[0]));
  }finally{if(app?.pid){try{process.kill(-app.pid,'SIGTERM')}catch(_){}}server.close();fs.closeSync(log)}
}
main().catch(error=>{console.error(error);process.exitCode=1});
