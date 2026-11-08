// Native connected death/respawn check. Requires Frontier on port 47190.
// Run: swift test/native/frontier-respawn.swift
import Cocoa
import WebKit
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var browser: WKWebView!
var window: NSWindow!
final class Reporter: NSObject, WKScriptMessageHandler {
  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    print(message.body)
    let result = message.body as? [String: Any]
    if result?["stage"] as? String == "done" || result?["stage"] as? String == "failed" {
      browser.takeSnapshot(with: nil) { image, _ in
        if let tiff = image?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
          try? png.write(to: URL(fileURLWithPath: "/tmp/frontier-respawn-webkit.png"))
        }
        exit(result?["stage"] as? String == "done" ? 0 : 1)
      }
    }
  }
}
let script = #"""
(async () => {
 const report = data => window.webkit.messageHandlers.probe.postMessage(data);
 const wait = async (name, predicate, timeout = 20000) => {
  const until = Date.now() + timeout;
  while (!predicate()) {
   if (Date.now() > until) throw Error('Timeout: ' + name);
   await new Promise(resolve => setTimeout(resolve, 100));
  }
 };
 try {
  if (location.pathname === '/dev/game') {
   await wait('decision boundary', () => Number(document.querySelector('#game-tick')?.textContent) % 30 < 10);
   const pos = document.querySelector('.debug-monster').closest('.debug-map-label').className.match(/at-(\d)-(\d)/);
   location.href = `/multi/lat/${pos[1]}/lon/${pos[2]}`;
   return;
  }
  await wait('connected', () => window.liveSocket?.main?.isConnected());
  await wait('death', () => document.documentElement.classList.contains('frontier-dead'));
  report({stage: 'dead', classes: document.documentElement.className});
  await wait('respawn', () => Number(document.querySelector('[data-bar="health"]').value) > 0 &&
    Number(document.querySelector('[data-lives-count]').textContent) < 3);
  await new Promise(resolve => setTimeout(resolve, 1200));
  const scout = getComputedStyle(document.querySelector('#player'));
  const ground = getComputedStyle(document.querySelector('.sector.current .floor'));
  const result = {stage: 'done', filter: scout.filter, opacity: scout.opacity, ground: ground.filter,
    classes: document.documentElement.className, path: location.pathname};
  if (scout.filter.includes('grayscale(1)') || scout.opacity !== '1' || ground.filter !== 'none') result.stage = 'failed';
  report(result);
 } catch (error) { report({stage: 'failed', error: String(error), classes: document.documentElement.className}); }
})();
"""#
let config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
let reporter = Reporter()
config.userContentController.add(reporter, name: "probe")
config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
browser = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: config)
window = NSWindow(contentRect: browser.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = browser
window.orderBack(nil)
browser.load(URLRequest(url: URL(string: "http://127.0.0.1:47190/dev/game")!))
DispatchQueue.main.asyncAfter(deadline: .now() + 50) { print("Native respawn probe timed out"); exit(2) }
app.run()
