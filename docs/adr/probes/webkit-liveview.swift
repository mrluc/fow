import Cocoa
import WebKit
import Foundation
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = .nonPersistent()
let webView = WKWebView(frame:NSRect(x:0,y:0,width:640,height:480),configuration:configuration)
let url = URL(string:CommandLine.arguments.dropFirst().first ?? "http://127.0.0.1:47182/counters/three")!
var originalCount:Int?
var finished = false
func finish(_ result:String) { if !finished {finished=true;print(result);fflush(stdout);exit(result.contains("server_action_passed") ? 0 : 1)} }
func poll(_ remaining:Int) {
  webView.evaluateJavaScript("JSON.stringify({origin:location.origin,live:!!window.liveSocket?.main?.isConnected(),count:document.querySelector('#count')?.textContent})") { value,error in
    if let value=value as? String,
      let bytes=value.data(using:.utf8),
      let state=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any],
      state["live"] as? Bool == true,
      let countText=state["count"] as? String,
      let count=Int(countText) {
        if let before=originalCount {
          if count==before+1 {finish("WEBKIT_LIVEVIEW_PROBE server_action_passed " + value);return}
        } else {
          originalCount=count
          webView.evaluateJavaScript("document.querySelector('#increment-counter').click()",completionHandler:nil)
        }
    }
    if remaining==0 {finish("WEBKIT_LIVEVIEW_PROBE failed: " + String(describing:value ?? error as Any))}
    else {DispatchQueue.main.asyncAfter(deadline:.now()+0.2){poll(remaining-1)}}
  }
}
URLSession(configuration:.ephemeral).dataTask(with:url) {data,response,error in
  guard let data=data,let response=response as? HTTPURLResponse,let html=String(data:data,encoding:.utf8) else {DispatchQueue.main.async{finish("FETCH_FAILED " + String(describing:error))};return}
  let headers=Dictionary(uniqueKeysWithValues:response.allHeaderFields.map{(String(describing:$0.key),String(describing:$0.value))})
  let cookies=HTTPCookie.cookies(withResponseHeaderFields:headers,for:url)
  DispatchQueue.main.async {
    let group=DispatchGroup()
    for cookie in cookies {group.enter();webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie){group.leave()}}
    group.notify(queue:.main) {
      webView.loadHTMLString(html,baseURL:url)
      DispatchQueue.main.asyncAfter(deadline:.now()+0.3){poll(60)}
    }
  }
}.resume()
DispatchQueue.main.asyncAfter(deadline:.now()+20){finish("WEBKIT_LIVEVIEW_PROBE timeout")}
app.run()
