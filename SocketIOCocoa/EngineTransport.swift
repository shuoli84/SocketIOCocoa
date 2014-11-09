import Foundation


public enum TransportReadyState: Printable, DebugPrintable{
    case Init, Open, Opening, Closing, Closed, Pausing, Paused
    
    public var description: String {
        switch self{
        case Init: return "Init"
        case Open: return "Open"
        case Opening: return "Opening"
        case Closing: return "Closing"
        case Closed: return "Closed"
        case Pausing: return "Pausing"
        case Paused: return "Paused"
        }
    }
    
    public var debugDescription: String {
        return self.description
    }
}

/*
Concurrency model for transport. Due to the shared state between operations, all state changing method should be called
in Socket's queue, including EngineIO level and SocketIO level.
*/
public protocol EngineTransportDelegate: class {
    // Called when error occured
    func transportOnError(transport: Transport, error: String, withDescription description: String)
    
    // Called when transport opened
    func transportOnOpen(transport: Transport)
    
    // Called when a packet received
    func transportOnPacket(transport: Transport, packet: EnginePacket)
    
    // Called when the transport closed
    func transportOnClose(transport: Transport)
    
    // Called when the dispatch queue needed
    func transportDispatchQueue(transport: Transport) -> dispatch_queue_t
    
    // Called when the transport paused
    func transportOnPause(transport: Transport)
}

// Base class for transport
public protocol Transport: class {
    /**
    Whether the transport is writable. The client should always check the writable flag.
    Transport class don't have a write queue. So each write goes straight into send method.
    NOTE: There could be race condition
    */
    var writable: Bool { get set }
    
    // The sid
    var sid : String? { get set }
    
    // Whether the transport supports pausible
    var pausible : Bool { get }
    
    // The name of the transport
    var name: String { get }
    
    // Headers for request
    var headers: [String: String] { get set }
    
    // Delegate
    weak var delegate: EngineTransportDelegate? { get set }
    func setDelegate(delegate: EngineTransportDelegate?)
    
    func open()
    
    func close()
    
    func write(packets: [EnginePacket])
    
    func pause()
    
}

public class BaseTransport: Logger, Transport {
    // Engine protocol version
    let protocolVersion: Int = 3
    
    // Path where socketio endpoint locates, default "/socket.io/"
    var path: String
    
    // Host of uri
    var host: String
    
    // Port
    var port: String
    
    // Headers
    public var headers: [String: String] = [:]
    
    // Flag indicates whether current transport is writable
    public var writable: Bool = false
    
    // Sid, generated from server and received from the handshake request
    public var sid: String?
    
    // Whether this runs on a secure protocol
    var secure: Bool = false
    
    // The state of transport
    var readyState : TransportReadyState = .Init
    
    // The delegate
    public weak var delegate: EngineTransportDelegate?
    
    public func setDelegate(delegate: EngineTransportDelegate?){
        self.delegate = delegate
    }
    
    public var pausible : Bool { get { return false } }
    
    // The name of transport
    public var name : String {
        get {
            return "_base_transport"
        }
    }
    
    public init(host: String, path : String, port: String,
        secure : Bool, query : String = ""){
            self.path = path
            self.host = host
            self.port = port
            self.secure = secure
    }
    
    public func onError(message: String, description: String){
        if let delegate = self.delegate {
            delegate.transportOnError(self, error: message, withDescription: description)
        }
        else{
            debug("onError block not set, ignore error")
        }
    }
    
    public func onData(data: NSData){
        if let delegate = self.delegate {
            for packet in EngineParser.decodePayload(data){
                delegate.transportOnPacket(self, packet: packet)
            }
        }
        else{
            debug("onData block not set, ignore packet")
        }
    }
    
    public func onOpen(){
        self.readyState = .Open
        self.writable = true
        
        if let delegate = self.delegate {
            delegate.transportOnOpen(self)
        }
    }
    
    public func onClose(){
        self.readyState = .Closed
        if let delegate = self.delegate {
            delegate.transportOnClose(self)
        }
    }
    
    func dispatchQueue() -> dispatch_queue_t {
        if let delegate = self.delegate{
            return delegate.transportDispatchQueue(self)
        }
        else{
            // Default we run on main queue
            return dispatch_get_main_queue()
        }
    }
    
    public func open() {}
    public func close() {}
    public func pause() {}
    public func write(packets: [EnginePacket]) {}
}

public class PollingTransport : BaseTransport{
    // The name of the transport
    override public var name : String{
        get { return "polling" }
    }
    
    // Polling state
    var polling = false
    
    // Polling request
    var pollingRequest: Request?
    
    // Posting request
    var postingRequest: Request?
    
    public override func logPrefix() -> String {
        return "[PollingTransport][\(self.readyState)]"
    }
    
    public override var pausible : Bool {
        get { return true }
    }
    
    public override func open(){
        dispatch_async(self.dispatchQueue(), { () -> Void in
            if self.readyState == .Closed || self.readyState == .Init{
                self.readyState = .Opening
                // First poll sends a handshake request
                self.poll()
            }
        })
    }
    
    // Poll
    func poll(){
        let uri = self.uri()
        
        debug("polling \(uri)")
        
        self.polling = true
        Manager.sharedInstance.session.configuration.HTTPAdditionalHeaders = self.headers
        self.pollingRequest = request(.GET, uri)
            .response { (request, response, data, error) -> Void in
                dispatch_async(self.dispatchQueue()){ ()-> Void in
                    if response?.statusCode >= 200 && response?.statusCode < 300 {
                        self.debug("Request succeeded")
                        
                        if let nsdata = data as? NSData {
                            self.onData(nsdata)
                        }
                    }
                    else{
                        if let e = error {
                            self.onError("error: Poll request failed \(e)", description: e.description)
                        }
                    }
                    
                    if self.readyState == .Open {
                        self.debug("polling")
                        dispatch_async(self.dispatchQueue()){
                            if self.readyState == .Open{
                                self.poll()
                            }
                        }
                    }
                }
        }
    }
    
    func onPollingComplete(){
        self.polling = false
        if self.readyState == .Pausing {
            self.tryPause()
        }
    }
    
    public override func onData(data: NSData) {
        debug("polling got data \(Converter.nsdataToByteArray(data).description)")
        
        for packet in EngineParser.decodePayload(data){
            if self.readyState == .Opening {
                debug("Polling got data back, set state to Open")
                self.readyState = .Open
                self.writable = true
            }
            
            if packet.type == .Close {
                debug("Got close packet from server")
                self.onClose()
                return
            }
            
            if let delegate = self.delegate {
                for packet in EngineParser.decodePayload(data){
                    delegate.transportOnPacket(self, packet: packet)
                }
            }
            else{
                debug("Delegate not set, ignore packet \(packet)")
            }
            
        }
        
        if self.readyState == .Open && self.sid == nil{
            debug("Sid is none after connection openned")
            return
        }
    
        if self.readyState != .Closed {
            self.polling = false
            self.onPollingComplete()
        }
    }
    
    public override func close(){
        if self.readyState == .Opening || self.readyState == .Open {
            self.pollingRequest?.cancel()
            self.postingRequest?.cancel()
            self.onClose()
        }
    }
    
    public override func write(packets: [EnginePacket]){
        if self.readyState == .Open{
            debug("Send \(packets.count) packets out")
            self.writable = false
            let encoded = EngineParser.encodePayload(packets)
            
            Manager.sharedInstance.session.configuration.HTTPAdditionalHeaders = self.headers
            self.postingRequest = request(.POST, self.uri(), parameters: ["data": encoded], encoding: .Custom({
                (URLRequest: URLRequestConvertible, parameters: [String: AnyObject]?) -> (NSURLRequest, NSError?) in
                var mutableURLRequest: NSMutableURLRequest! = URLRequest.URLRequest.mutableCopy() as NSMutableURLRequest
                mutableURLRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                mutableURLRequest.HTTPBody = parameters!["data"] as? NSData!
                return (mutableURLRequest, nil)
            }))
                .response({ [unowned self](request, response, data, err) -> Void in
                    dispatch_async(self.dispatchQueue()){
                        self.writable = true
                        if self.readyState == .Pausing {
                            self.tryPause()
                        }
                        else {
                            if err != nil{
                                self.onError("error", description: "Failed sending data to server")
                            }
                            else{
                                self.debug("Request send to server succeeded")
                            }
                        }
                    }
                })
        }
        else{
            self.debug("Transport not open")
        }
    }
    
    public override func pause(){
        debug("Pausing")
        self.readyState = .Pausing
        
        if self.polling || !self.writable {
            // If sending or reading data, then try to stop it in the poll and write method
            debug("The transport still polling or writing, postpone the pause action")
            return
        }
        else {
            self.tryPause()
        }
    }

    func tryPause(){
        if !self.polling && self.writable {
            debug("Paused")
            self.readyState = .Paused
            
            self.delegate?.transportOnPause(self)
        }
    }
    
    // Construct the uri used for request
    public func uri() -> String{
        let schema = self.secure ? "https" : "http"
        var query : [String: AnyObject] = [
            "EIO": self.protocolVersion,
            "transport": self.name,
            "t": Int(NSDate().timeIntervalSince1970)
        ]
        
        if let sid : String = self.sid {
            query["sid"] = sid
        }
        
        var port = ""
        if self.port != "" && (self.port != "80" && schema == "http") || (self.port != "443" && schema == "https") {
            port = ":\(self.port)"
        }
        
        let queryString = query.urlEncodedQueryStringWithEncoding(NSUTF8StringEncoding)
        let uri = "\(schema)://\(self.host)\(port)\(self.path)?\(queryString)"
        return uri
    }
}

public class WebsocketTransport : BaseTransport, WebsocketDelegate{
    // The name of the transport
    override public var name : String{ get { return "websocket" }}
    
    // The websocket instance
    var websocket : Websocket?
    
    public override func logPrefix() -> String{
        return "[WebsocketTransport][\(self.readyState.description)]"
    }
    
    override public func open(){
        dispatch_async(self.dispatchQueue(), { () -> Void in
            if self.readyState == .Closed || self.readyState == .Init{
                self.readyState = .Opening
                
                let uri = self.uri()
                
                if let nsurl = NSURL(string: uri) {
                    self.debug("Connecting \(uri)")
                    var socket = Websocket(url: nsurl)
                    socket.headers = self.headers
                    socket.delegate = self
                    socket.connect()
                    self.websocket = socket
                }
                else{
                    self.debug("Invalid url \(uri)")
                }
            }
        })
    }
    
    override public func close(){
        self.readyState = .Closing
        self.websocket?.disconnect()
        // Following logic located in websocketdelegate method diddisconnect
    }
    
    override public func write(packets: [EnginePacket]){
        dispatch_async(self.dispatchQueue()){
            for packet in packets{
                if packet.isBinary{
                    self.websocket?.writeData(packet.encode())
                }
                else {
                    // TODO Check whether we should avoid the extra data->string encode and stream it out
                    self.websocket?.writeString(Converter.nsdataToNSString(packet.encode()))
                }
            }
        }
    }
    
    public func uri() -> String {
        let schema = self.secure ? "wss" : "ws"
        var query : [String: AnyObject] = [
            "EIO": self.protocolVersion,
            "transport": self.name,
            "t": Int(NSDate().timeIntervalSince1970)
        ]
        
        if let sid : String = self.sid {
            query["sid"] = sid
        }
        
        var port = ""
        if self.port != "" && (self.port != "80" && schema == "ws") || (self.port != "443" && schema == "wss") {
            port = ":\(self.port)"
        }
        
        let queryString = query.urlEncodedQueryStringWithEncoding(NSUTF8StringEncoding)
        let uri = "\(schema)://\(self.host)\(port)\(self.path)?\(queryString)"
        return uri
    }
    
    // MARK Websocket delegate
    public func websocketDidConnect() {
        dispatch_async(self.dispatchQueue()){
            self.debug("Websocket transport connected")
            self.onOpen()
        }
    }
    
    public func websocketDidDisconnect(error: NSError?) {
        debug("Websocket disconnected")
        dispatch_async(self.dispatchQueue()){
            self.readyState = .Closed
            self.websocket = nil
            if let delegate = self.delegate {
                delegate.transportOnClose(self)
            }
        }
    }
    
    public func websocketDidReceiveData(data: NSData) {
        dispatch_async(self.dispatchQueue()){
            self.debug("Received binary message \(data)")
            self.onData(data)
        }
    }
    
    public func websocketDidReceiveMessage(text: String) {
        dispatch_async(self.dispatchQueue()){
            self.debug("Received text message \(text)")
            self.onData(Converter.nsstringToNSData(text))
        }
    }
    
    public func websocketDidWriteError(error: NSError?) {
        debug("Websocket write error")
    }
    // END Websocket delegate
   
    // The method is running on the queue
    public override func onData(data: NSData){
        let packet = EnginePacket(decodeFromData: data)
        
        if let delegate = self.delegate {
            delegate.transportOnPacket(self, packet: packet)
        }
    }
}