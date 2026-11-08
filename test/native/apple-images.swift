// Native macOS characterization: HTTPS page -> app-owned image scheme.
// Run: swift test/native/apple-images.swift [--http]
import Cocoa
import WebKit
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let origin = CommandLine.arguments.contains("--http") ? "http://127.0.0.1:47180" : "https://fow-images.invalid"
final class Assets: NSObject, WKURLSchemeHandler {
    var requests: [String] = []
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let url = task.request.url!
        requests.append(url.absoluteString)
        let data = "<svg xmlns='http://www.w3.org/2000/svg' width='32' height='32'><rect width='32' height='32' fill='rgb(0,180,0)'/></svg>".data(using: .utf8)!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"image/svg+xml", "Access-Control-Allow-Origin":origin])!
        task.didReceive(response); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
final class Reporter: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        var result = message.body as! [String:Any]
        browser.takeSnapshot(with: nil) { image, error in
            var green = 0
            if let data = image?.tiffRepresentation, let pixels = NSBitmapImageRep(data:data) {
                for y in 0..<min(32,pixels.pixelsHigh) { for x in 0..<min(32,pixels.pixelsWide) {
                    if let color = pixels.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB), color.greenComponent > 0.5 && color.redComponent < 0.2 && color.blueComponent < 0.2 { green += 1 }
                }}
            }
            result["cssPaintedGreenPixels"] = green
            result["assetRequests"] = assets.requests
            if let error = error { result["snapshotError"] = error.localizedDescription }
            print(String(data:try! JSONSerialization.data(withJSONObject:result,options:.sortedKeys),encoding:.utf8)!);fflush(stdout)
            exit(0)
        }
    }
}
let assets = Assets(), reporter = Reporter(), config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
config.setURLSchemeHandler(assets,forURLScheme:"fog-of-war-assets")
config.userContentController.add(reporter,name:"result")
let browser = WKWebView(frame:NSRect(x:0,y:0,width:160,height:80),configuration:config)
let window = NSWindow(contentRect:NSRect(x:0,y:0,width:160,height:80),styleMask:[.titled],backing:.buffered,defer:false)
window.contentView = browser
let html = """
<!doctype html><html><head><style>body{margin:0;background:white}#css{position:absolute;left:0;top:0;width:32px;height:32px;background:url('fog-of-war-assets://bundle/green.svg?css')}img{position:absolute;top:0;width:32px;height:32px}#plain{left:48px}#cors{left:96px}</style></head><body><div id="css"></div><img id="plain" src="fog-of-war-assets://bundle/green.svg?plain"><img id="cors" crossorigin="anonymous" src="fog-of-war-assets://bundle/green.svg?cors"><script>
window.addEventListener('load',async()=>{
 const result={origin:location.origin,secure:isSecureContext};
 for(const id of ['plain','cors']){const image=document.getElementById(id);result[id+'Loaded']=image.complete&&image.naturalWidth>0;
  if(!result[id+'Loaded']){result[id+'CanvasReadable']=false;result[id+'CanvasError']='ImageNotLoaded';continue}
  try{const canvas=document.createElement('canvas');canvas.width=canvas.height=32;const ctx=canvas.getContext('2d');ctx.drawImage(image,0,0);ctx.getImageData(0,0,1,1);result[id+'CanvasReadable']=true}catch(error){result[id+'CanvasReadable']=false;result[id+'CanvasError']=error.name}
 }
 try{const response=await fetch('fog-of-war-assets://bundle/green.svg?fetch');result.fetchReadable=response.ok&&(await response.arrayBuffer()).byteLength>0}catch(error){result.fetchReadable=false;result.fetchError=error.name}
 window.webkit.messageHandlers.result.postMessage(result);
});
</script></body></html>
"""
browser.loadSimulatedRequest(URLRequest(url:URL(string:origin+"/start")!),responseHTML:html)
DispatchQueue.main.asyncAfter(deadline:.now()+20){print("Image probe timed out");exit(1)}
app.run()
