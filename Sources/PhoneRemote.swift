// PhoneRemote.swift — turn your phone into a remote, with no extra software to install.
// A small web server is built into the app (using Apple's Network framework). Turn it on from the
// menu bar; your phone opens a web page over Wi‑Fi and controls the Mac. The first time, a setup
// window shows the address and a QR code; after that it just starts quietly.
import AppKit
import SwiftUI
import Network
import CoreImage
import CoreImage.CIFilterBuiltins

final class PhoneServer {
    static let shared = PhoneServer()

    private(set) var running = false
    private(set) var lastError = ""
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "couchremote.phone", qos: .userInitiated)

    var port: UInt16 { UInt16(ConfigStore.shared.settings.phoneRemotePort) }
    var url: String { "http://\(Self.lanIP() ?? "your-mac’s-IP"):\(port)" }

    // MARK: start / stop

    @discardableResult
    func start() -> Bool {
        stop()
        lastError = ""
        let params = NWParameters.tcp
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options { tcp.noDelay = true }
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port), let l = try? NWListener(using: params, on: nwPort) else {
            lastError = "Couldn’t open port \(port). Try a different port in Settings."
            running = false
            return false
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.running = true
            case .failed(let e): self?.lastError = "\(e)"; self?.running = false
            case .cancelled: self?.running = false
            default: break
            }
        }
        listener = l
        l.start(queue: queue)
        running = true
        return true
    }

    func stop() {
        listener?.cancel(); listener = nil
        running = false
    }

    @discardableResult
    func toggle() -> Bool {
        if running { stop(); ConfigStore.shared.config.settings.phoneRemoteEnabled = false }
        else { _ = start(); ConfigStore.shared.config.settings.phoneRemoteEnabled = true }
        return running
    }

    // MARK: a connection

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isDone, err in
            guard let self = self else { return }
            var buf = buffer
            if let d = data { buf.append(d) }
            // Handle every complete request sitting in the buffer (keep-alive sends many)
            while let (method, path, body, consumed) = Self.parse(buf) {
                buf = Data(buf.dropFirst(consumed))     // re-base so indices stay zero-based
                self.respond(conn, method: method, path: path, body: body)
            }
            if isDone || err != nil { conn.cancel(); return }
            self.receive(conn, buffer: buf)
        }
    }

    /// Pulls one whole HTTP request out of the buffer. Returns nil if more bytes are still needed.
    private static func parse(_ data: Data) -> (method: String, path: String, body: String, consumed: Int)? {
        guard let headerEnd = range(of: [13, 10, 13, 10], in: data) else { return nil }   // \r\n\r\n
        let headerData = data.subdata(in: 0..<headerEnd)
        guard let header = String(data: headerData, encoding: .utf8) else { return ("GET", "/", "", headerEnd + 4) }
        let lines = header.components(separatedBy: "\r\n")
        let first = lines.first?.components(separatedBy: " ") ?? []
        let method = first.count > 0 ? first[0] : "GET"
        let path = first.count > 1 ? first[1] : "/"
        var contentLength = 0
        for l in lines where l.lowercased().hasPrefix("content-length:") {
            contentLength = Int(l.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let bodyStart = headerEnd + 4
        guard data.count >= bodyStart + contentLength else { return nil }   // wait for the whole body
        let body = contentLength > 0 ? (String(data: data.subdata(in: bodyStart..<(bodyStart + contentLength)), encoding: .utf8) ?? "") : ""
        return (method, path, body, bodyStart + contentLength)
    }

    private static func range(of pattern: [UInt8], in data: Data) -> Int? {
        guard data.count >= pattern.count else { return nil }
        let bytes = [UInt8](data)
        var i = 0
        while i <= bytes.count - pattern.count {
            var match = true
            for j in 0..<pattern.count where bytes[i + j] != pattern[j] { match = false; break }
            if match { return i }
            i += 1
        }
        return nil
    }

    private func respond(_ conn: NWConnection, method: String, path: String, body: String) {
        let route = path.components(separatedBy: "?").first ?? path
        if route == "/" {
            send(conn, status: "200 OK", type: "text/html; charset=utf-8", body: Self.page)
        } else if route == "/c" {
            for line in body.split(separator: "\n") { dispatch(String(line)) }
            send(conn, status: "200 OK", type: "text/plain", body: "ok")
        } else if route == "/ping" {
            send(conn, status: "200 OK", type: "text/plain", body: "ok")
        } else {
            send(conn, status: "404 Not Found", type: "text/plain", body: "no")
        }
    }

    private func send(_ conn: NWConnection, status: String, type: String, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(bodyData.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: keep-alive\r\n\r\n"
        var out = head.data(using: .utf8) ?? Data()
        out.append(bodyData)
        conn.send(content: out, completion: .contentProcessed { _ in })
    }

    // MARK: commands from the phone (run on the main thread)

    private func dispatch(_ line: String) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard let cmd = parts.first.map(String.init) else { return }
        func num(_ i: Int) -> CGFloat { i < parts.count ? CGFloat(Double(parts[i]) ?? 0) : 0 }
        DispatchQueue.main.async {
            switch cmd {
            case "m": Input.move(dx: num(1), dy: num(2))
            case "s": Input.scroll(dx: Int32(num(1)), dy: Int32(num(2)))
            case "click": Input.click()
            case "rclick": Input.rightClick()
            case "down": Input.mouseDown()
            case "up": Input.mouseUp()
            case "key": if parts.count > 1 { self.pressKey(String(parts[1])) }
            case "text": if line.count > 5 { Input.type(String(line.dropFirst(5))) }
            case "menu": Engine.shared.fire(.menuTap)
            case "home", "tv": BigScreen.shared.toggle()
            case "play": Runner.globalPlayPause()
            case "next": Input.media(.next)
            case "prev": Input.media(.previous)
            case "volup": _ = Runner.volumeStep(up: true)
            case "voldown": _ = Runner.volumeStep(up: false)
            case "mute": Input.media(.mute)
            case "mode": _ = Engine.shared.cycleMode()
            case "couch": CouchMenu.shared.toggle()
            default: break
            }
        }
    }

    private func pressKey(_ name: String) {
        let map: [String: Int] = ["left": KeyCode.left, "right": KeyCode.right, "up": KeyCode.up, "down": KeyCode.down,
                                  "return": KeyCode.ret, "space": KeyCode.space, "esc": KeyCode.escape,
                                  "tab": KeyCode.tab, "delete": KeyCode.delete]
        if let code = map[name] { Input.key(code) }
    }

    // MARK: this Mac's address on the local network

    static func lanIP() -> String? {
        var best: String?
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return nil }
        defer { freeifaddrs(first) }
        var p: UnsafeMutablePointer<ifaddrs>? = start
        while let cur = p {
            let a = cur.pointee
            let name = String(cString: a.ifa_name)
            if let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), name.hasPrefix("en") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if !ip.hasPrefix("169.254") { best = best ?? ip; if name == "en0" { return ip } }
                }
            }
            p = a.ifa_next
        }
        return best
    }

    static func qrImage(_ string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    // MARK: the phone page (served at /)

    static let page = """
    <!doctype html><html><head><meta charset=utf-8>
    <meta name=viewport content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
    <meta name=apple-mobile-web-app-capable content=yes>
    <title>Couch Remote</title>
    <style>
    *{box-sizing:border-box;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent;touch-action:none}
    html,body{margin:0;height:100%;background:#0a0a0f;color:#fff;font:16px -apple-system,system-ui,sans-serif;overscroll-behavior:none}
    .wrap{display:flex;flex-direction:column;height:100%;padding:14px;gap:12px}
    .pad{flex:1;border-radius:24px;background:linear-gradient(160deg,#1b1b26,#101019);border:1px solid #ffffff1a;
         display:flex;align-items:center;justify-content:center;color:#ffffff44;font-weight:600;letter-spacing:.4px}
    .row{display:flex;gap:10px}
    button{flex:1;border:0;border-radius:16px;padding:16px 0;font-size:16px;font-weight:600;color:#fff;
           background:#ffffff14;border:1px solid #ffffff14;-webkit-appearance:none}
    button:active{background:#ffffff2e;transform:scale(.97)}
    .accent{background:linear-gradient(160deg,#f0457c,#7a3cf0);border:0}
    .tall{padding:20px 0;font-size:20px}
    .grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
    .ico{font-size:20px}
    input{width:100%;padding:14px;border-radius:16px;border:1px solid #ffffff22;background:#ffffff10;color:#fff;font-size:16px}
    </style></head><body>
    <div class=wrap>
      <div class=pad id=pad>Trackpad — drag to move, tap to click, two fingers to scroll</div>
      <div class=row>
        <button id=menu>‹ Menu</button>
        <button id=home>TV</button>
        <button id=couch>Menu •••</button>
      </div>
      <div class=grid>
        <button data-k=up class=ico>▲</button>
        <button id=play class=ico accent>⏯</button>
        <button data-k=down class=ico>▼</button>
        <button data-k=left class=ico>◀</button>
        <button id=ok class="ico accent">OK</button>
        <button data-k=right class=ico>▶</button>
      </div>
      <div class=row>
        <button id=prev>⏮ Prev</button>
        <button id=voldown>Vol −</button>
        <button id=volup>Vol +</button>
        <button id=next>Next ⏭</button>
      </div>
      <input id=kb placeholder="Tap here to type on your Mac" autocapitalize=off autocorrect=off>
    </div>
    <script>
    var q=[];
    function go(c){q.push(c);flush()}
    var sending=false;
    function flush(){ if(sending||!q.length)return; sending=true; var b=q.join("\\n"); q=[];
      fetch('/c',{method:'POST',body:b,keepalive:true}).catch(function(){}).finally(function(){sending=false; if(q.length)flush();}); }
    var pad=document.getElementById('pad'), last=null, moved=false, startT=0, two=false;
    function pt(e){return e.touches?e.touches[0]:e}
    pad.addEventListener('touchstart',function(e){e.preventDefault(); last=pt(e); moved=false; startT=Date.now(); two=e.touches.length>1;},{passive:false});
    pad.addEventListener('touchmove',function(e){e.preventDefault(); var p=pt(e); if(!last){last=p;return;}
      var dx=p.clientX-last.clientX, dy=p.clientY-last.clientY; last=p;
      if(Math.abs(dx)+Math.abs(dy)>1)moved=true;
      if(e.touches.length>1){ go('s '+Math.round(dx*2)+' '+Math.round(-dy*2)); }
      else { go('m '+(dx*1.7).toFixed(1)+' '+(dy*1.7).toFixed(1)); } },{passive:false});
    pad.addEventListener('touchend',function(e){e.preventDefault(); if(!moved && !two && Date.now()-startT<250) go('click'); last=null;},{passive:false});
    function tap(id,c){var el=document.getElementById(id); if(el)el.addEventListener('click',function(){go(c)});}
    tap('menu','menu');tap('home','home');tap('couch','couch');tap('play','play');tap('ok','click');
    tap('prev','prev');tap('next','next');tap('volup','volup');tap('voldown','voldown');
    document.querySelectorAll('[data-k]').forEach(function(b){b.addEventListener('click',function(){go('key '+b.getAttribute('data-k'))})});
    var kb=document.getElementById('kb');
    kb.addEventListener('input',function(){ if(kb.value){ go('text '+kb.value); kb.value=''; } });
    kb.addEventListener('keydown',function(e){ if(e.key==='Enter'){go('key return')} if(e.key==='Backspace'&&!kb.value){go('key delete')} });
    </script></body></html>
    """
}

// MARK: - Turning it on, and the setup window

extension PhoneServer {
    /// Turn the phone remote on and, the first time, show the setup window. If it's been set up
    /// before, it just starts the server quietly.
    func enable() {
        _ = start()
        ConfigStore.shared.config.settings.phoneRemoteEnabled = true
        if !ConfigStore.shared.settings.phoneSetupSeen { PhoneSetup.shared.show() }
        else { HUD.shared.show("Phone remote on · \(url)", symbol: "iphone", kind: .connection) }
    }

    func disable() {
        stop()
        ConfigStore.shared.config.settings.phoneRemoteEnabled = false
        HUD.shared.show("Phone remote off", symbol: "iphone.slash", kind: .connection)
    }
}

final class PhoneSetup {
    static let shared = PhoneSetup()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Phone Remote"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: PhoneSetupView(close: { [weak w] in w?.orderOut(nil) }))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PhoneSetupView: View {
    var close: () -> Void
    @ObservedObject var store = ConfigStore.shared
    private var urlString: String { PhoneServer.shared.url }

    var body: some View {
        VStack(spacing: 18) {
            Text("Use your phone as a remote")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
            Text("No app to install. Make sure your phone is on the same Wi‑Fi as this Mac, then open this address in its web browser — or scan the code.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let img = PhoneServer.qrImage(urlString) {
                Image(nsImage: img).interpolation(.none).resizable().frame(width: 200, height: 200)
                    .background(Color.white).cornerRadius(12)
            }
            Text(urlString).font(.system(size: 20, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
            if !PhoneServer.shared.running {
                Label(PhoneServer.shared.lastError.isEmpty ? "Starting…" : PhoneServer.shared.lastError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.caption)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("First time: macOS may ask to allow Couch Remote to find devices on your local network — tap Allow. If nothing connects, check the macOS firewall isn’t blocking it.")
            }
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Toggle("Don’t show this setup again — just turn the server on next time", isOn: $store.config.settings.phoneSetupSeen)
            HStack {
                Button("Copy address") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(urlString, forType: .string) }
                Spacer()
                Button("Done") { store.config.settings.phoneSetupSeen = true; close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520, height: 620)
    }
}
