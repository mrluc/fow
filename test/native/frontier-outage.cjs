// From FoW: source ../env.sh; node test/native/frontier-outage.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {once} = require('node:events');
const {setTimeout: delay} = require('node:timers/promises');

const root = path.resolve(__dirname, '../..');
const frontier = path.join(root, 'examples/frontier');
const origin = 'http://127.0.0.1:47192';
const target = process.env.CARGO_TARGET_DIR;
const children = new Set();

function start(command, args, cwd, env = process.env) {
  const child = spawn(command, args, {cwd, env, stdio: 'inherit'});
  children.add(child);
  child.once('exit', () => children.delete(child));
  return child;
}

async function run(command, args, cwd, env) {
  const [code] = await once(start(command, args, cwd, env), 'exit');
  assert.equal(code, 0, `${command} failed`);
}

async function reachable() {
  try {
    await (await fetch(origin, {signal: AbortSignal.timeout(500)})).arrayBuffer();
    return true;
  } catch {
    return false;
  }
}

async function phoenix() {
  const server = start('bash', ['test/browser/frontier-server.sh'], root);
  for (let attempt = 0; attempt < 200; attempt++) {
    assert.equal(server.exitCode, null, 'Phoenix exited before becoming ready');
    if (await reachable()) return server;
    await delay(100);
  }
  throw new Error('Phoenix did not become reachable');
}

async function main() {
  assert.equal(process.platform, 'darwin', 'Requires macOS WKWebView');
  assert(target, 'Source ../env.sh before running this test');
  assert(!await reachable(), 'Port 47192 already has a server');
  const scratch = fs.mkdtempSync(path.join(frontier, '.fow-outage-'));
  const manifestPath = path.join(frontier, path.basename(scratch) + '.json');
  const project = path.join(scratch, 'app');
  const bundle = path.join(scratch, 'bundle');
  const manifest = JSON.parse(fs.readFileSync(path.join(frontier, '.fow.json')));
  manifest.web.origin = origin;
  manifest.app.slug = 'frontier_outage';
  manifest.app.identifier = 'dev.fogofwar.outagetest' + Date.now();
  fs.writeFileSync(manifestPath, JSON.stringify(manifest));

  let acceptReport;
  const reporter = http.createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', origin);
    if (req.method !== 'POST' || req.url !== '/result' || req.headers.origin !== origin) {
      res.writeHead(404).end();
      return;
    }
    let body = '';
    for await (const chunk of req) body += chunk;
    res.end('ok');
    acceptReport?.(JSON.parse(body));
  });
  const next = (expected, app) => new Promise((resolve, reject) => {
    const finish = () => {
      clearTimeout(timer);
      app.off('exit', exited);
      acceptReport = undefined;
    };
    const exited = code => {
      finish();
      reject(new Error(`WebView exited while waiting for ${expected}: ${code}`));
    };
    const timer = setTimeout(() => {
      finish();
      reject(new Error(`Timed out waiting for ${expected}`));
    }, 40000);
    app.once('exit', exited);
    acceptReport = ({stage, detail}) => {
      finish();
      if (stage === expected) resolve(detail);
      else reject(new Error(`Expected ${expected}, got ${stage}: ${detail}`));
    };
  });

  try {
    await run('mix', ['assets.build'], frontier, {...process.env, MIX_ENV: 'test'});
    let server = await phoenix();
    const options = ['--manifest', manifestPath];
    await run('mix', ['fow.bundle.prepare', ...options, '--platform', 'apple', '--output', bundle], frontier);
    await run('mix', ['fow.gen.elixirkit', ...options, '--bundle-dir', bundle, '--output', project], frontier);

    reporter.listen(0, '127.0.0.1');
    await once(reporter, 'listening');
    const driver = fs.readFileSync(path.join(__dirname, 'frontier-outage-driver.js'), 'utf8')
      .replace('__REPORT_URL__', `http://127.0.0.1:${reporter.address().port}/result`);
    const rust = path.join(project, 'src-tauri/src/main.rs');
    const source = fs.readFileSync(rust, 'utf8');
    const init = '.initialization_script(FOW_NATIVE_READ_ASSET_INIT)';
    assert(source.includes(init), 'Missing WebKit host initialization');
    fs.writeFileSync(rust, source.replace(init, init + '\n            .initialization_script(include_str!("outage-driver.js"))'));
    fs.writeFileSync(path.join(path.dirname(rust), 'outage-driver.js'), driver);
    await run('cargo', ['build', '--release', '--features', 'custom-protocol'], path.join(project, 'src-tauri'));

    const app = start(path.join(target, 'release/frontier_outage_desktop'), [], project);
    assert.equal(await next('online', app), '/lat/0/lon/0');

    const offline = next('offline', app);
    const stopped = once(server, 'exit');
    server.kill('SIGTERM');
    await stopped;
    assert(!await reachable(), 'Phoenix still responds after stopping its process');
    assert.equal(await offline, '/lat/1/lon/1');
    assert(!await reachable(), 'Phoenix became reachable during offline navigation');

    const recovered = next('recovered', app);
    server = await phoenix();
    assert.equal(await recovered, '/lat/2/lon/2');
    console.log('PASS: native online → Phoenix stopped → cached navigation and history → Phoenix restarted → live navigation');
  } finally {
    for (const child of children) child.kill('SIGTERM');
    reporter.close();
    fs.rmSync(manifestPath, {force: true});
    fs.rmSync(scratch, {recursive: true, force: true});
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
