import Cocoa
import WebKit
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
final class Probe: NSObject, WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    webView.evaluateJavaScript("""
    JSON.stringify((() => {let storage;try {localStorage.setItem('fog-origin-probe','ok'); storage=localStorage.getItem('fog-origin-probe')}catch(e){storage=e.name};return {url:location.href,origin:location.origin,documentURL:document.URL,baseURI:document.baseURI,secure:isSecureContext,storage}})())
    """) { result, error in
      print("WEBKIT_ORIGIN_PROBE " + String(describing: result ?? error as Any)); fflush(stdout)
      guard let text=result as? String, let data=text.data(using:.utf8),
        let state=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
        state["origin"] as? String == "https://counter.example",
        state["secure"] as? Bool == true,
        state["storage"] as? String == "ok" else {exit(1)}
      exit(0)
    }
  }
}
let probe = Probe()
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = .nonPersistent()
let webView = WKWebView(frame: NSRect(x:0,y:0,width:640,height:480), configuration:configuration)
webView.navigationDelegate = probe
webView.loadHTMLString("<!doctype html><html><body>Bundled origin probe</body></html>", baseURL: URL(string:"https://counter.example/counters/one")!)
DispatchQueue.main.asyncAfter(deadline:.now()+15) {print("WEBKIT_ORIGIN_PROBE timeout"); fflush(stdout); exit(1)}
app.run()
