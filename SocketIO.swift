/**************************************************************
       _____            __        __  ________
      / ___/____  _____/ /_____  / /_/  _/ __ \
      \__ \/ __ \/ ___/ //_/ _ \/ __// // / / /
     ___/ / /_/ / /__/ ,< /  __/ /__/ // /_/ /
    /____/\____/\___/_/|_|\___/\__/___/\____/

    SocketIO 1.0 Swift client.

Introduction
-------------
The official SocketIO 1.0 contains 2 layers:

1. EngineIO
The data transportation layer. Polling, websocket, wrapped in this layer and expose simple interfaces.

2. SocketIO
The SocketIO protocol layer, namespace, multiplexing etc.

We are doing the same here. We support xhr polling and websocket transports. Utilize alamofire and starscream to do the heavy lifting 
on underlying request and socket.

Installation
-------------
Due to the broken swift dependency management, I include all my dependencies by copy and paste. Until Cocoapod swift support become mature,
I suggest you do so. 

Following files are from external depot (Go and Search the name), they located under Vender folder:
alamofire.swift
Dollar.swfit
starscream.swift
SwifterSnippet.swift

The main swift file:
SocketIO.swift

Copy above to your project for now.

Concurrency model
-------------
The client has many state, which requires a consistent and elegant concurrency model. GCD here. All state involved 
operations should be dispatched on the dedicated queue, we also call callbacks in this queue, feel free to dispatch 
it in the callback.

Classes
-------------
Converter: Used to do conversion between NSString, [Byte], NSData, JSON

EnginePacket: The packet struct in EngineIO layer
EngineParser: The parser used to do payload encode and decode
Transport, BaseTransport, PollingTransport, WebsocketTransport: The transport class hierachy
EngineSocket: Represent as a socket, build upon transports, provides easy interface and manage connection lifecycle

SocketIOPacket: The packet struct in SocketIO layer
SocketIOParser: The parser used to serialize and deserialize packets containing binary etc
SocketIOSocket: The interface for client

All the classes are in the single file, it sucks, but easy to be copy and paste into your project. More than Happier 
to seperate them when Cocoapod swift matured.
***************************************************************/

import Foundation

// Converter is the helper utility to convert different types
public class Converter {
    // Convert from NSString -> NSData
    public class func nsstringToNSData(str : NSString) -> NSData {
        return str.dataUsingEncoding(NSUTF8StringEncoding)!
    }
    
    // Convert from NSData -> NSString
    public class func nsdataToNSString(data: NSData) -> NSString {
        return NSString(data: data, encoding: NSUTF8StringEncoding)!
    }
    
    // Convert from [Byte] -> NSData
    public class func bytearrayToNSData(arr: [Byte]) -> NSData {
        return NSData(bytes: arr, length: arr.count)
    }
    
    // Convert from NSData -> [Byte]
    public class func nsdataToByteArray(data: NSData) -> [Byte] {
        var array = [Byte](count:data.length, repeatedValue: 0)
        data.getBytes(&array, length: data.length)
        return array
    }
    
    // Convert from NSString to byte array
    public class func nsstringToByteArray(str: NSString) -> [Byte] {
        return nsdataToByteArray(nsstringToNSData(str))
    }
    
    // Convert form byte array to NSString 
    public class func bytearrayToNSString(bytes: [Byte]) -> NSString {
        return NSString(bytes: bytes, length: bytes.count, encoding: NSUTF8StringEncoding)!
    }
    
    // Convert from NSString to json object
    public class func nsstringToJSON(str: NSString) -> NSDictionary? {
        return self.nsdataToJSON(self.nsstringToNSData(str))
    }
    
    // Convert from NSData to json object
    public class func nsdataToJSON(data: NSData) -> NSDictionary? {
        return NSJSONSerialization.JSONObjectWithData(data, options: .MutableContainers, error: nil) as [String: AnyObject]
    }
    
    // Convert from JSON to nsdata
    public class func jsonToNSData(json: AnyObject) -> NSData?{
        return NSJSONSerialization.dataWithJSONObject(json, options: .allZeros, error: nil)
    }
    
    // Convert from JSON to nsstring
    public class func jsonToNSString(json: AnyObject) -> NSString?{
        if let data = self.jsonToNSData(json){
            return self.nsdataToNSString(data)
        }
        else{
            return nil
        }
    }
    
    // Convert from JSON to byte array
    public class func jsonToByteArray(json: AnyObject) -> [Byte] {
        if let data = self.jsonToNSData(json) {
            return self.nsdataToByteArray(data)
        }
        else {
            return []
        }
    }
    
    // Convert from byte array to json
    public class func bytearrayToJSON(bytes: [Byte]) -> NSDictionary? {
        return self.nsdataToJSON(self.bytearrayToNSData(bytes))
    }
}

// Mark Engine Packet & Parser

/*
Engine parser used to encode and decode packet for engineio level. Since we are running on iOS, so we pretty sure we
can support binary, this parser only implemented the binary part. No base64 support.
*/

// Ascii value enums
enum ASCII: Byte {
    case _0 = 48, _1, _2, _3, _4, _5, _6, _7, _8, _9
    case a = 97, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case A = 65, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z
    case COMMA = 44, DASH = 45, BACKSLASH=47
}

/*
       __            _             _____  ___
      /__\ __   __ _(_)_ __   ___  \_   \/___\
     /_\| '_ \ / _` | | '_ \ / _ \  / /\//  //
    //__| | | | (_| | | | | |  __/\/ /_/ \_//
    \__/|_| |_|\__, |_|_| |_|\___\____/\___/
               |___/
*/

// The packet type for engine, the lower level of socketio
public enum PacketType: Byte {
    case Open, Close, Ping, Pong, Message, Upgrade, Noop, Error = 20, Max
    
    var description: String {
        switch self{
        case .Open: return "Open"
        case .Close: return "Close"
        case .Ping: return "Ping"
        case .Pong: return "Pong"
        case .Message: return "Message"
        case .Upgrade: return "Upgrade"
        case .Noop: return "Noop"
        case .Error: return "Error"
        case .Max: return "Max"
        }
    }
}

// The packet on engine layer
public struct EnginePacket : Printable, DebugPrintable{
    public var type: PacketType
    public var data: [Byte]?
    public var isBinary: Bool = false
    
    public var description: String{
        if let data = self.data {
            if self.isBinary{
                return "[\(type.description)][Binary: \(isBinary)]: \(data)"
            }
            else{
                let string = Converter.bytearrayToNSString(data)
                return "[\(type.description)][Binary: \(isBinary)]: \(string)"
            }
        }
        else {
            return "[\(type.description)][Binary: \(isBinary)]: \(self.data)"
        }
    }
    
    public var debugDescription: String {
        return self.description
    }
    
    public var json: NSDictionary {
        let json = NSJSONSerialization.JSONObjectWithData(Converter.bytearrayToNSData(self.data!), options: .MutableContainers, error: nil) as Dictionary<String, AnyObject!>
        return json
    }
    
    public init(data: [Byte]?, type: PacketType, isBinary: Bool){
        self.type = type
        self.data = data
        self.isBinary = isBinary
    }
   
    public init(string: String, type: PacketType){
        var data = Converter.nsstringToByteArray(string)
        self.init(data: data, type: type, isBinary: false)
    }
    
    public init(nsdata: NSData, type: PacketType){
        self.init(data:Converter.nsdataToByteArray(nsdata), type: type, isBinary: true)
    }
    
    public init(decodeFromData data: NSData){
        let buf : [Byte] = Converter.nsdataToByteArray(data)
        let typeByte = buf[0]
        
        if typeByte >= ASCII._0.rawValue && typeByte <= ASCII._9.rawValue {
            // This is a string
            self.init(decodeFromString: buf)
        }
        else if typeByte < PacketType.Max.rawValue {
            // This is a binary
            let isBinary = true
            var type : PacketType = .Error
            var data : [Byte]?
            
            if let packetType = PacketType(rawValue: buf[0]){
                type = packetType
            }
            
            if buf.count > 1 {
                data = [Byte](buf[1..<buf.count])
            }
            
            self.init(data: data, type: type, isBinary: isBinary)
        }
        else{
            self.init(data: nil, type: .Error, isBinary: false)
        }
    }
    
    // Decode from string
    init(decodeFromString bytes: [Byte]){
        var type : PacketType = .Error
        var data : [Byte]?
        var isBinary = false
        
        // 98 value for 'b'
        if bytes[0] == 98 {
            // We are not support base64 encode
            type = .Error
            data = Converter.nsstringToByteArray("Base 64 is not supported yet")
        }
        
        let packetType = bytes[0] - 48 // value for '0'
        
        if let ptype = PacketType(rawValue: packetType) {
            type = ptype
        }
        else{
            type = .Error
        }
        
        if bytes.count > 1 {
            data = [Byte](bytes[1..<bytes.count])
        }
        
        self.init(data: data, type: type, isBinary: isBinary)
    }
    
    public func encode() -> NSData {
        var output = NSMutableData()
        var typeValue = self.type
        
        if isBinary {
            output.appendBytes(&typeValue, length: 1)
        }
        else {
            var typeByte : Byte = typeValue.rawValue + ASCII._0.rawValue
            output.appendBytes(&typeByte, length: 1)
        }
        
        if let data = self.data {
            output.appendData(Converter.bytearrayToNSData(data))
        }
        
        return output
    }
}

let error_packet = EnginePacket(data: nil, type: .Error, isBinary: false)

public class EngineParser {
    public class func encodePayload (packets: [EnginePacket]) -> NSData {
        var output = NSMutableData()
        for packet in packets{
            let encoded = packet.encode()
            var lengthBuf = [Byte]([packet.isBinary ? 1 : 0])
            let bufLengthStr = String(encoded.length)
            
            for c in Converter.nsstringToByteArray(bufLengthStr) {
                lengthBuf.append(c - 48)
            }
            
            lengthBuf.append(255)
            output.appendBytes(lengthBuf, length: lengthBuf.count)
            output.appendData(encoded)
        }
        return output
    }
    
    public class func decodePayload(data : NSData) -> [EnginePacket] {
        let byteArray = Converter.nsdataToByteArray(data)
        var packets : [EnginePacket] = []
        var offset = 0
        
        while offset < byteArray.count {
            var lengthBuf = [Byte]()
            let isBinary = byteArray[offset++] == 1
            
            for index in 0..<byteArray.count - offset{
                let byte = byteArray[offset+index]
                if byte != 255{
                    lengthBuf.append(byte)
                }
                else{
                    break
                }
            }
            
            offset += lengthBuf.count + 1 // extra 1 for 255
            
            var packetLength: Int = 0
            for c in lengthBuf {
                packetLength = packetLength * 10 + Int(c)
            }
            
            let restBuffer = [Byte](byteArray[offset..<offset+packetLength])
            if isBinary {
                let encodedPacket = Converter.bytearrayToNSData(restBuffer)
                packets.append(EnginePacket(decodeFromData: encodedPacket))
            }
            else {
                packets.append(EnginePacket(decodeFromString: restBuffer))
            }
            
            offset += packetLength
        }
        
        return packets
    }
}

// Mark Engine Transport

public enum TransportReadyState: Printable, DebugPrintable{
    case Init, Open, Opening, Closing, Closed
    
    public var description: String {
        switch self{
        case Init: return "Init"
        case Open: return "Open"
        case Opening: return "Opening"
        case Closing: return "Closing"
        case Closed: return "Closed"
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
}

// Base class for transport
public protocol Transport {
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
    
    // Delegate
    weak var delegate: EngineTransportDelegate? { get set }
    
    func open()
    
    func close()
    
    func write(packets: [EnginePacket])
   
    func pause()
   
}

public class BaseTransport: Transport {
    // Engine protocol version
    let protocolVersion: Int = 3
    
    // Path where socketio endpoint locates, default "/socket.io/"
    var path: String
    
    // Host of uri
    var host: String
    
    // Port
    var port: String
    
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
    
    public var pausible : Bool { get { return false } }
    
    // The name of transport
    var name : String {
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
            NSLog("onError block not set, ignore error")
        }
    }
    
    public func onData(data: NSData){
        if let delegate = self.delegate {
            for packet in EngineParser.decodePayload(data){
                delegate.transportOnPacket(self, packet: packet)
            }
        }
        else{
            NSLog("onData block not set, ignore packet")
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
    override var name : String{
        get { return "polling" }
    }
    
    // Polling state
    var polling = false
    
    // Polling request
    var pollingRequest: Request?
    
    // Posting request
    var postingRequest: Request?
    
    // Polling complete callback
    var pollingCompleteBlock: (()->Void)?
    
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
        
        NSLog("polling \(uri)")
        
        self.polling = true
        self.pollingRequest = request(.GET, uri)
        .response { (request, response, data, error) -> Void in
            // Consider dispatch to the same queue
            dispatch_async(self.dispatchQueue()){ ()-> Void in
                NSLog("Response get")
                
                if response?.statusCode >= 200 && response?.statusCode < 300 {
                    NSLog("Request succeeded")
                    
                    if let nsdata = data as? NSData {
                        self.onData(nsdata)
                    }
                }
                else{
                    if let e = error {
                        self.onError("error: Poll request failed \(e)", description: e.description)
                    }
                }
                
                if self.readyState == .Open{
                    NSLog("The state is Open, keep polling")
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
        if let callback = self.pollingCompleteBlock {
            callback()
        }
    }
    
    public override func onData(data: NSData) {
        NSLog("polling got data \(Converter.nsdataToByteArray(data).description)")
        
        let packets = EngineParser.decodePayload(data)
        
        for packet in packets{
            if self.readyState == .Opening {
                NSLog("Polling got data back, set state to Open")
                self.readyState = .Open
            }
            
            if packet.type == .Close {
                NSLog("Got close packet from server")
                self.onClose()
                return
            }
            
            if let delegate = self.delegate {
                for packet in EngineParser.decodePayload(data){
                    delegate.transportOnPacket(self, packet: packet)
                }
            }
            else{
                NSLog("Delegate not set, ignore packet")
            }
            
            if self.readyState == .Open && self.sid == nil{
                NSLog("Sid is none after connection openned")
                return
            }
            
            if self.readyState != .Closed {
                self.polling = false
                self.onPollingComplete()
            }
        }
    }
    
    override public func close(){
        if self.readyState == .Opening || self.readyState == .Open {
            self.pollingRequest?.cancel()
            self.postingRequest?.cancel()
            self.onClose()
        }
    }
    
    override public func write(packets: [EnginePacket]){
        if self.readyState == .Open{
            NSLog("Send \(packets.count) packets out")
            self.writable = false
            let encoded = EngineParser.encodePayload(packets)
            
            self.postingRequest = request(.POST, self.uri(), parameters: ["data": encoded], encoding: .Custom({
                (URLRequest: URLRequestConvertible, parameters: [String: AnyObject]?) -> (NSURLRequest, NSError?) in
                    var mutableURLRequest: NSMutableURLRequest! = URLRequest.URLRequest.mutableCopy() as NSMutableURLRequest
                    mutableURLRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                    mutableURLRequest.HTTPBody = parameters!["data"] as? NSData!
                    return (mutableURLRequest, nil)
                }))
            .response({ [unowned self](request, response, data, err) -> Void in
                self.writable = true
                if err != nil{
                    self.onError("error", description: "Failed sending data to server")
                }
                else{
                    NSLog("Request send to server succeeded")
                }
            })
        }
        else{
            NSLog("Transport not open")
        }
    }
    
    public override func pause(){}
    
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
    override var name : String{ get { return "websocket" }}
    
    // The websocket instance
    var websocket : Websocket?
    
    override public func open(){
        dispatch_async(self.dispatchQueue(), { () -> Void in
            if self.readyState == .Closed || self.readyState == .Init{
                self.readyState = .Opening
                
                let uri = self.uri()
                
                if let nsurl = NSURL(string: uri) {
                    var socket = Websocket(url: nsurl)
                    socket.delegate = self
                    socket.connect()
                    self.websocket = socket
                }
                else{
                    NSLog("Invalid url \(uri)")
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
            NSLog("Websocket transport connected")
            self.onOpen()
        }
    }
    
    public func websocketDidDisconnect(error: NSError?) {
        NSLog("Websocket disconnected")
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
            NSLog("Received binary message \(data)")
            self.onData(data)
        }
    }
    
    public func websocketDidReceiveMessage(text: String) {
        dispatch_async(self.dispatchQueue()){
            NSLog("Received test message \(text)")
            self.onData(Converter.nsstringToNSData(text))
        }
    }
    
    public func websocketDidWriteError(error: NSError?) {
        NSLog("Websocket write error")
    }
    // END Websocket delegate
    
    public override func onOpen(){
        self.readyState = .Open
        if let delegate = self.delegate {
            delegate.transportOnOpen(self)
        }
    }
    
    // The method is running on the queue
    public override func onData(data: NSData){
        let packet = EnginePacket(decodeFromData: data)
        
        if let delegate = self.delegate {
            delegate.transportOnPacket(self, packet: packet)
        }
    }
}


// Mark Engine Socket

// The delegate for EngineSocket
public protocol EngineSocketDelegate: class{
    // Called when the socket state is Open
    func socketOnOpen(socket: EngineSocket)
    
    // Called when the socket state is Closed
    func socketOnClose(socket: EngineSocket)
    
    // Called when a new packet received
    func socketOnPacket(socket: EngineSocket, packet: EnginePacket)
   
    // Called when there is a message decoded
    func socketOnData(socket: EngineSocket, data: [Byte], isBinary: Bool)
    
    // Called when there is an error occured
    func socketOnError(socket: EngineSocket, error: String, description: String)
}

enum EngineSocketReadyState : Int, Printable{
    case Init, Open, Opening, Closing, Closed, Upgrading
    
    var description: String {
        switch self{
        case .Init: return "Init"
        case .Open: return "Open"
        case .Opening: return "Opening"
        case .Closing: return "Closing"
        case .Closed: return "Closed"
        case .Upgrading: return "Upgrading"
        }
    }
}

// A counter which counts how many EngineSocket created
var socketCount: Int = 0

public class EngineSocket: EngineTransportDelegate{
    // Whether the protocol is secure
    var secure: Bool = false
    
    // Host
    var host: String
    
    // Port
    var port: String
    
    // Path
    var path: String
    
    // Sid generated by server, unique identifier for one socket client
    var id: String?
    
    // The running queue, create it when create a new instance
    var queue: dispatch_queue_t = {
        ++socketCount
        return dispatch_queue_create("com.menic.EngineIO-queue\(socketCount)", DISPATCH_QUEUE_SERIAL)
    }()
    
    // Available transports
    var transports: [String]
    
    // Whether the socket should upgrade
    var upgrade: Bool
    
    // Hold for available upgrades
    var upgrades: [String] = ["websocket"]
    
    // Flag indicating whether we are in the upgrading phase
    var upgrading: Bool = false
    
    // The state of socket
    var readyState: EngineSocketReadyState = .Init
    
    // Transport instance
    var transport: Transport?
    
    // Ping interval
    var pingInterval: Int = 30000
    
    // Ping timeout
    var pingTimeout: Int = 30000
    
    // The write queue
    var writeQueue: [EnginePacket] = []
    
    // The write calllback queue
    var writeCallbackQueue: [(()->Void)?] = []
    
    // The delegate
    public weak var delegate: EngineSocketDelegate?
    
    public init(host: String, port: String, path: String = "/socket.io/", secure: Bool = false,
        transports: [String] = ["polling", "websocket"], upgrade: Bool = true, config: [String:AnyObject] = [:]) {
            self.host = host
            self.port = port
            self.path = path
            self.transports = transports
            self.upgrade = upgrade
    }
    
    func createTransport(transportName: String) -> Transport? {
        var transport : Transport? = nil
        if $.contains(self.transports, value: transportName){
            if transportName == "polling" {
                transport = PollingTransport(host: self.host, path: self.path, port: self.port, secure: self.secure)
            }
            else if transportName == "websocket" {
                transport = WebsocketTransport(host: self.host, path: self.path, port: self.port, secure: self.secure)
            }
        }
        
        if transport != nil && self.id != nil{
            transport!.sid = self.id
        }
        
        return transport
    }
    
    func setTransport(inout transport: Transport){
        transport.delegate = self
        self.transport = transport
    }
    
    public func open(){
        assert(transports.count != 0)
        dispatch_async(self.queue){
            [unowned self] () -> Void in
            self.readyState = .Opening
            
            let transportName = $.first(self.transports)!
            if var transport = self.createTransport(transportName){
                self.setTransport(&transport)
                transport.open()
            }
            else{
                NSLog("Not able to create transport")
            }
        }
    }
    
    public func close(){
        // Trigger the close the underlying transport
        dispatch_async(self.queue){
            [unowned self] () -> Void in
            self.readyState = .Closing
            self.transport?.close()
        }
    }
    
    // EngineTransportDelegate
    public func transportOnPacket(transport: Transport, packet: EnginePacket) {
        NSLog("[EngineSocket] Received one packet")
        if self.readyState == .Open || self.readyState == .Opening{
            NSLog("[EngineSocket] Receive: [\(packet.type.description)")
            
            if let delegate = self.delegate {
                delegate.socketOnPacket(self, packet: packet)
            }
            
            switch packet.type{
            case .Open:
                if let data = packet.data{
                    if let json = Converter.bytearrayToJSON(data){
                        self.onHandshake(json)
                    }
                    else{
                        NSLog("Failed to parse json")
                        return
                    }
                }
                else{
                    NSLog("[EngineSocket] There is no data on Open packet")
                    return
                }
            case .Message:
                if let data = packet.data{
                    if let delegate = self.delegate {
                        delegate.socketOnData(self, data: data, isBinary: packet.isBinary)
                    }
                }
                else{
                    NSLog("No data on Message packet, ignore")
                }
            case .Pong:
                break
            case .Error:
                if let data = packet.data {
                    self.onError("error", reason: Converter.bytearrayToNSString(data))
                }
                else{
                    self.onError("error")
                }
            default:
                NSLog("HITTING DEFAULT CLAUSE, CAREFUL")
                break
            }
        }
        else{
            NSLog("packet received with socket readyState [\(self.readyState.description)]")
        }
    }
    
    public func transportOnError(transport: Transport, error: String, withDescription description: String) { }
    
    public func transportOnClose(transport: Transport) {
        if self.readyState == .Closing {
            NSLog("[EngineSocket][\(self.readyState.description)] The transport closed as expected")
            
            self.readyState = .Closed
            self.delegate?.socketOnClose(self)
        }
        else{
            NSLog("[EngineSocket][\(self.readyState.description)] The transport closed unexpected")
            self.delegate?.socketOnClose(self)
        }
    }
    
    public func transportOnOpen(transport: Transport) { }
    
    public func transportDispatchQueue(transport: Transport) -> dispatch_queue_t {
        // All transport related task should run on socket's queue
        return self.queue
    }
    
    // End of EngineTransport Delegate
    
    func onHandshake(data: NSDictionary){
        if let sid = data["sid"] as? String{
            self.id = sid
            self.transport!.sid = sid
        }
        else{
            NSLog("Not able to parse sid")
        }
        
        if let upgrades = data["upgrades"] as? [String]{
            self.upgrades = upgrades
        }
        
        if let pingInterval = data["pingInterval"]?.integerValue {
            self.pingInterval = pingInterval
        }
        
        if let pingTimeout = data["pingTimeout"]?.integerValue {
            self.pingTimeout = pingTimeout
        }
        
        self.onOpen()
        
        if self.readyState == .Closed{
            self.setPing()
        }
    }
    
    func onOpen(){
        NSLog("Socket Open")
        
        self.readyState = .Open
        
        if let delegate = self.delegate {
            delegate.socketOnOpen(self)
        }
        
        self.flush() // Flush out cached packets
        
        if self.readyState == .Open && self.upgrade && self.transport!.pausible {
            NSLog("Start upgrading")
            for upgrade in upgrades {
               self.probe(upgrade)
            }
        }
    }
    
    func onError(message: String, reason: String? = nil){
        
    }
    
    func setPing(){
        
    }
    
    /**
    send data
    */
    func send(data: NSData, callback: (()->Void)? = nil){
        self.send(.Message, data: Converter.nsdataToByteArray(data), isBinary: false, callback: callback)
    }
    
    // send packet and data with a callback
    func send(packetType: PacketType, data: [Byte]? = nil, isBinary: Bool, callback: (()->Void)? = nil){
        let packet = EnginePacket(data: data, type:packetType, isBinary: isBinary)
        self.packet(packet, callback: callback)
    }
    
    func flush(){
        if self.readyState != .Closed && !self.upgrading && self.transport!.writable {
            if self.writeQueue.count == 0{
                return
            }
            
            NSLog("Flushing \(self.writeQueue.count) packets")
            
            // LOCK HERE
            let packets = self.writeQueue
            self.writeQueue = []
            // UNLOCK HERE
            self.transport!.write(packets)
        }
    }
    
    func probe(upgrade: String){
        
    }
    
    func packet(packet: EnginePacket, callback: (()->Void)?){
        dispatch_async(self.queue){
            [unowned self] () -> Void in
            self.writeQueue.append(packet)
            self.writeCallbackQueue.append(callback)
            self.flush()
        }
    }
}

/*
       _____            __        __  ________
      / ___/____  _____/ /_____  / /_/  _/ __ \
      \__ \/ __ \/ ___/ //_/ _ \/ __// // / / /
     ___/ / /_/ / /__/ ,< /  __/ /__/ // /_/ /
    /____/\____/\___/_/|_|\___/\__/___/\____/
*/

public enum SocketIOPacketType: Byte, Printable{
    case Connect = 0, Disconnect, Event, Ack, Error, BinaryEvent, BinaryAck
    
    public var description: String {
        switch self{
        case Connect: return "Connect"
        case Disconnect: return "Disconnect"
        case Event: return "Event"
        case Ack: return "Ack"
        case Error: return "Error"
        case BinaryEvent: return "BinaryEvent"
        case BinaryAck: return "BinaryAck"
        }
    }
}


func deconstructData(data: AnyObject, inout buffers: [NSData]) -> AnyObject{
    if data is NSDictionary {
        var returnDict : NSMutableDictionary = [:]
        
        let keys = (data as NSDictionary).allKeys
        for key in keys {
            if let strkey = key as? NSString {
                let value: AnyObject = data.objectForKey(key)!
                returnDict.setObject(deconstructData(value, &buffers), forKey: strkey)
            }
            else{
                NSLog("Dict has a non string key")
            }
        }
        
        return returnDict as AnyObject
    }
    else if data is NSArray {
        var returnArray: [AnyObject] = []
        for item in data as NSArray {
            returnArray.append(deconstructData(item, &buffers))
        }
        
        return returnArray as AnyObject
    }
    else if data is NSData {
        var placeHolder: NSDictionary = [
            "_placeholder": true,
            "num": buffers.count
        ]
        
        buffers.append(data as NSData)
        return placeHolder
    }
    
    return data
}

func reconstructData(data: AnyObject, buffers: [NSData]) -> AnyObject {
    if data is NSDictionary {
        let dict = data as NSDictionary
        if dict.valueForKey("_placeholder") != nil {
            let bufferIndex: Int? = dict.objectForKey("num")?.integerValue
            if bufferIndex != nil{
                return buffers[bufferIndex!]
            }
        }
        else{
            var returnDict : NSMutableDictionary = [:]
            
            let keys = dict.allKeys
            for key in keys {
                if let strkey = key as? NSString {
                    let value: AnyObject = data.objectForKey(key)!
                    returnDict.setObject(reconstructData(value, buffers), forKey: strkey)
                }
                else{
                    NSLog("Dict has a non string key")
                }
            }
            
            return returnDict as AnyObject
        }
    }
    else if data is NSArray {
        var returnArray: [AnyObject] = []
        for item in data as NSArray{
            returnArray.append(reconstructData(item, buffers))
        }
        return returnArray
    }
    
    return data
}

// Binary parser doing binary packet deconstruct and contruct
public class BinaryParser {
    public class func deconstructPacket(packet: SocketIOPacket) -> (packet: SocketIOPacket, buffers: [NSData]){
        var buffers: [NSData] = []
        if let data: AnyObject = packet.data {
            let deconstructedData: AnyObject = deconstructData(data, &buffers)
            return (SocketIOPacket(type: packet.type, data: deconstructedData, nsp: packet.nsp, id: packet.id, attachments: buffers.count), buffers)
        }
        else {
            return (packet, buffers)
        }
    }
    
    public class func reconstructPacket(packet: SocketIOPacket, buffers: [NSData]) -> SocketIOPacket{
        if let data: AnyObject = packet.data {
            let constructedData: AnyObject = reconstructData(data, buffers)
            return SocketIOPacket(type: packet.type, data: constructedData, nsp: packet.nsp, id: packet.id, attachments: 0)
        }
        else{
            return packet
        }
    }
}

public struct SocketIOPacket: Printable{
    public var type: SocketIOPacketType
    public var data: AnyObject?
    public var nsp: String?
    public var id: String?
    public var attachments: Int
    
    public init(type: SocketIOPacketType, data: AnyObject? = nil, nsp: String? = nil, id: String? = nil, attachments: Int = 0){
        self.type = type
        self.data = data
        self.nsp = nsp
        self.id = id
        self.attachments = attachments
    }
    
    public init(decodedFromString string: [Byte]){
        var packetType = SocketIOPacketType(rawValue: string[0] - ASCII._0.rawValue)
        var attachment: Int = 0
        var nsp: String? = nil
        var id: String? = nil
        var data: AnyObject? = nil
        
        var offset = 1 // 1 byte for type
        
        if packetType == nil {
            packetType = .Error
        }
        
        // Parse the attachement count
        if packetType == .BinaryEvent || packetType == .BinaryAck {
            var attachmentBuf = [Byte]()
            while offset < string.count && string[offset] != ASCII.DASH.rawValue {
                attachmentBuf.append(string[offset++])
            }
            
            // Even if string not able to parse, it will return 0
            attachment = Converter.bytearrayToNSString(attachmentBuf).integerValue
            
            offset++ // Skip the '-'
        }
        
        
        // Parse the namespace
        if offset < string.count && string[offset] == ASCII.BACKSLASH.rawValue {
            // WE have a namespace
            var nspBuffer = [Byte]()
            
            while offset < string.count && string[offset] != ASCII.COMMA.rawValue {
                nspBuffer.append(string[offset++])
            }
            
            nsp = Converter.bytearrayToNSString(nspBuffer)
            
            offset++ // Skip the ','
        }
        
        
        // Parse the id
        if offset < string.count && string[offset] >= ASCII._0.rawValue && string[offset] <= ASCII._9.rawValue {
            var idBuffer = [Byte]()
            
            while offset < string.count && string[offset] >= ASCII._0.rawValue && string[offset] <= ASCII._9.rawValue {
                idBuffer.append(string[offset++])
            }
            
            id = Converter.bytearrayToNSString(idBuffer)
        }
        
        // Parse the body
        if offset < string.count {
            let bodyBuffer = [Byte](string[offset..<string.count])
            if let json = Converter.bytearrayToJSON(bodyBuffer) {
                data = json
            }
        }
       
        self.init(type: packetType!, data: data, nsp: nsp, id: id, attachments: attachment)
    }
    
    public var description: String {
        return "[\(type.description)][NS:\(nsp)][DATA<\(data)>]"
    }
    
    public func encodeAsString() -> [Byte]{
        var encodeBuf = [Byte]()
        encodeBuf.append(self.type.rawValue + ASCII._0.rawValue)
        
        if self.type == .BinaryEvent || self.type == .BinaryAck {
            if self.attachments > 0{
                encodeBuf += Converter.nsstringToByteArray(String(self.attachments) + "-")
            }
        }
        
        // If we have a namespace other than '/', append it followed by a ','
        if let nsp = self.nsp {
            if nsp != "/" {
                encodeBuf += Converter.nsstringToByteArray((startsWith(nsp, "/") ? "" : "/") + nsp + ",")
            }
        }
        
        // Followed by id
        if let id = self.id {
            encodeBuf += Converter.nsstringToByteArray(id)
        }
        
        if let data: AnyObject = self.data {
            encodeBuf += Converter.jsonToByteArray(data)
        }
        
        return encodeBuf
    }
    
    // TODO Check how to void several layer of bytearray -> data
    public func encode() -> ([Byte], [NSData]){
        var (packet, buffers) = BinaryParser.deconstructPacket(self)
        var encodedPacket = packet.encodeAsString()
        return (encodedPacket, buffers)
    }
}

public class SocketIOPacketDecoder {
    // The buffers for the packet needs reconstructed
    public var buffers: [NSData] = []
    
    // The packet which needs to be reconstructed
    public var packetToBeReConstructed: SocketIOPacket? = nil
    
    public init(){}
    
    public func addString(data: [Byte]) -> SocketIOPacket? {
        let decoded = SocketIOPacket(decodedFromString: data)
        if decoded.type == .BinaryEvent || decoded.type == .BinaryAck {
            if decoded.attachments > 0{
                self.packetToBeReConstructed = decoded
                return nil
            }
        }
        return decoded
    }
    
    public func addBuffer(data: NSData) -> SocketIOPacket? {
        self.buffers.append(data)
        
        if let packet = self.packetToBeReConstructed {
            if self.buffers.count == packet.attachments {
                self.packetToBeReConstructed = nil
                let buffers = self.buffers
                self.buffers = []
                return BinaryParser.reconstructPacket(packet, buffers: buffers)
            }
        }
        return nil
    }
}

public protocol SocketIOClientDelegate {
    func clientOnOpen(client: SocketIOClient)
    func clientOnClose(client: SocketIOClient)
    func clientOnConnectionTimeout(client: SocketIOClient)
    
    // Called when reconnect failed. E.g exceed the max attempts
    func clientReconnectionFailed(client: SocketIOClient)
    
    // Called when any error happened in reconnection
    func clientReconnectionError(client: SocketIOClient, error: String, description: String)
    
    // Called when the client reconnected
    func clientReconnected(client: SocketIOClient)
    
    func clientOnError(client: SocketIOClient, error: String, description: String)
    func clientOnPacket(client: SocketIOClient, packet: SocketIOPacket)
}

public enum SocketIOClientReadyState: Int, Printable {
    case Open, Opening, Closed
    
    public var description: String {
        switch self{
        case .Open: return "Open"
        case .Opening: return "Opening"
        case .Closed: return "Closed"
        }
    }
}

public class SocketIOClient: EngineSocketDelegate {
    public var uri: String
    var transports: [String] = []
    var readyState: SocketIOClientReadyState = .Closed
    var autoConnect: Bool
    var autoReconnect: Bool
    var namespaces: [String: SocketIOSocket] = [:]
    var connectedSockets: [SocketIOSocket] = []
    
    
    // How many attempts to reconnect. nil for infinite
    var reconnectAttempts: Int?
    
    var reconnectDelay: Int
    var reconnectDelayMax: Int
    var timeout: Int
    
    public var reconnecting = false
    public var attempts: Int = 0
    public var engineSocket: EngineSocket?
    var decoder: SocketIOPacketDecoder
    var skipReconnect = false
    
    // Flag indicate whether we already did reconnect on open
    var openReconnectPerformed: Bool = true
    
    public var delegate: SocketIOClientDelegate?
    
    var dispatchQueue: dispatch_queue_t = {
        return dispatch_queue_create("com.menic.SocketIOClient-queue", DISPATCH_QUEUE_SERIAL)
    }()
    
    public init(uri: String, transports: [String] = ["polling", "websocket"], autoConnect: Bool = true,
        reconnect: Bool = true, reconnectAttempts: Int? = nil, reconnectDelay: Int = 1, reconnectDelayMax: Int = 5,
        timeout: Int = 30){
            self.uri = uri
            self.transports = transports
            self.autoConnect = autoConnect
            self.autoReconnect = reconnect
            self.reconnectAttempts = reconnectAttempts
            self.reconnectDelay = reconnectDelay
            self.reconnectDelayMax = reconnectDelayMax
            self.timeout = timeout
            self.decoder = SocketIOPacketDecoder()
    }
    
    
    func delay(delay:Double, closure:()->()) {
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                Int64(delay * Double(NSEC_PER_SEC))
            ),
            self.dispatchQueue, closure)
    }
    
    public func sendAll(event: String, data: AnyObject?){
        
    }
    
    func maybeReconnectOnOpen(){
        if !self.openReconnectPerformed && !self.reconnecting && self.autoReconnect && self.attempts == 0{
            self.openReconnectPerformed = true
            self.reconnect()
        }
    }
    
    public func open(){
        NSLog("[SocketIOClient] ready state: \(self.readyState.description)")
        if self.readyState == .Open || self.readyState == .Opening {
            return
        }
        
        NSLog("[SocketIOClient] Opening")
        
        self.engineSocket = EngineSocket(host: "localhost", port: "8001", path: "/socket.io/", secure: false, transports: self.transports, upgrade: true, config: [:])
        
        self.engineSocket!.delegate = self
        self.readyState = .Opening
        self.engineSocket!.open()
        
        if self.timeout != 0 {
            NSLog("connect attempt will timeout after \(self.timeout) seconds")
            
            self.delay(Double(self.timeout)){
                [unowned self]() -> Void in
                if self.readyState != .Open {
                    NSLog("[SocketIOClient] connect timeout")
                    self.engineSocket?.delegate = nil
                    self.engineSocket?.close()
                    
                    self.delegate?.clientOnConnectionTimeout(self)
                }
            }
        }
    }
    
    func reconnect(){
        if self.reconnecting || self.skipReconnect {
            return
        }
        
        self.attempts++
        
        if self.reconnectAttempts != nil && self.attempts > self.reconnectAttempts {
            NSLog("reconnect failed")
            self.delegate?.clientReconnectionFailed(self)
            self.reconnecting = false
        }
        else{
            let delay = min(self.attempts * self.reconnectDelay, self.reconnectDelayMax)
            NSLog("Will wait \(delay) seconds before reconnect")
            
            self.delay(Double(delay)){
                [unowned self] ()->Void in
                if self.skipReconnect {
                    return
                }
                
                self.reconnecting = true
                NSLog("[SocketIOClient] attempting to reconnect")
                self.open()
            }
        }
    }
    
    // EngineSocketDelegate
    public func socketOnOpen(socket: EngineSocket) {
        //
        // Here locate a bug. The dispatch async not called!!! Could because that the queue is not empty or the queue
        // blocked, CHeck this!!
        //
        NSLog("Socket opened")
        dispatch_async(self.dispatchQueue){
            [unowned self] () -> Void in
            if self.reconnecting {
                NSLog("[SocketIOClient] Reconnection succeeded")
                self.reconnecting = false
                self.attempts = 0
                self.delegate?.clientReconnected(self)
            }
            else {
                NSLog("[SocketIOClient][\(self.readyState.description) Underlying engine socket connected")
                self.readyState = .Open
                self.delegate?.clientOnOpen(self)
            }
        }
    }
    
    public func socketOnClose(socket: EngineSocket) {
        NSLog("[SocketIOClient] Underlying socket closed")
        
        self.readyState = .Closed
        self.delegate?.clientOnClose(self)
        
        if self.autoReconnect {
            self.reconnect()
        }
    }
    
    public func socketOnPacket(socket: EngineSocket, packet: EnginePacket) {
    }
    
    public func socketOnData(socket: EngineSocket, data: [Byte], isBinary: Bool) {
        var packet: SocketIOPacket?
        if isBinary {
            packet = self.decoder.addBuffer(Converter.bytearrayToNSData(data))
        }
        else {
            packet = self.decoder.addString(data)
        }
        
        if let p = packet {
            self.delegate?.clientOnPacket(self, packet: p)
        }
    }
    
    public func socketOnError(socket: EngineSocket, error: String, description: String) {
        dispatch_async(self.dispatchQueue){
            [unowned self] () -> Void in
            if self.reconnecting {
                NSLog("Reconnect failed with error: \(error) [\(description)]")
                
                self.delegate?.clientReconnectionError(self, error: error, description: description)
                self.reconnecting = false
                self.reconnect()
            }
            else{
                
            }
        }
    }
    
    // End of EngineSocketDelegate
    
}

public class SocketIOSocket{
}