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

***************************************************************/

import Foundation

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

@objc public class SocketIOPacket: Printable{
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
    
    public convenience init(decodedFromString string: [Byte]){
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
            if let json: AnyObject = Converter.bytearrayToJSON(bodyBuffer) {
                data = json
            }
            else{
                data = Converter.bytearrayToNSString(bodyBuffer)
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
    func clientReconnectionError(client: SocketIOClient, error: String, description: String?)
    
    // Called when the client reconnected
    func clientReconnected(client: SocketIOClient)
    
    func clientOnError(client: SocketIOClient, error: String, description: String?)
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

public class SocketIOClient: NSObject, EngineSocketDelegate {
    public var uri: String
    var host: String
    var path: String
    var port: String
    var secure: Bool
    
    var transports: [String]
    var upgrade: Bool
    var readyState: SocketIOClientReadyState = .Closed
    var autoConnect: Bool
    var autoReconnect: Bool
    var namespaces: [String: SocketIOSocket] = [:]
    var connectedSockets: [SocketIOSocket] = []
    
    // Custom http headers
    public var headers: [String: String] = [:]
    
    
    // How many attempts to reconnect. nil for infinite
    var reconnectAttempts: Int
    
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
    
    @objc public init(uri: String, transports: [String] = ["polling", "websocket"], autoConnect: Bool = true,
        reconnect: Bool = true, reconnectAttempts: Int = 0, reconnectDelay: Int = 1, reconnectDelayMax: Int = 5,
        timeout: Int = 30){
            self.uri = uri
            var url = NSURL(string: uri)
            self.host = url!.host!
            self.path = url!.path!
            if url!.port != nil {
                self.port = String(Int(url!.port!))
            }
            else{
                self.port = ""
            }
            self.secure = url!.scheme == "wss" || url!.scheme == "https"
            self.transports = transports
            self.upgrade = transports.count > 1
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
        
        self.engineSocket = EngineSocket(host: self.host, port: self.port, path: self.path, secure: self.secure, transports: self.transports, upgrade: self.upgrade, config: [:])
        
        self.engineSocket!.headers = self.headers
        
        self.engineSocket!.delegate = self
        self.readyState = .Opening
        self.engineSocket!.open()
        
        if self.timeout != 0 {
            NSLog("connect attempt will timeout after \(self.timeout) seconds")
            
            self.delay(Double(self.timeout)){
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
        
        if self.reconnectAttempts != 0 && self.attempts > self.reconnectAttempts {
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
    
    // TODO Check whether we need to add the callback
    public func packet(packet: SocketIOPacket){
        NSLog("[SocketIOClient][\(self.readyState.description)] Sending packet \(packet.description)")
        
        let (encoded, buffers) = packet.encode()
        
        self.engineSocket?.send(encoded, callback: nil)
        for buffer in buffers{
            self.engineSocket?.send(buffer, callback: nil)
        }
    }
    
    // Create socket object attached to a namespace
    public func socket(namespace: String) -> SocketIOSocket{
        var nsp = startsWith(namespace, "/") ? namespace : "/\(namespace)"
        
        if let socket = self.namespaces[nsp] {
            return socket
        }
        
        var socket = SocketIOSocket(client: self, namespace: nsp, autoConnect: self.autoConnect)
        self.namespaces[nsp] = socket
        
        return socket
    }
    
    // EngineSocketDelegate
    public func socketOnOpen(socket: EngineSocket) {
        dispatch_async(self.dispatchQueue){
            [unowned self] () -> Void in
            
            self.readyState = .Open
            
            if self.reconnecting {
                NSLog("[SocketIOClient] Reconnection succeeded")
                self.reconnecting = false
                self.attempts = 0
                self.delegate?.clientReconnected(self)
            }
            else {
                NSLog("[SocketIOClient][\(self.readyState.description) Underlying engine socket connected")
                self.delegate?.clientOnOpen(self)
            }
            
            // Go through all namespaces and send out Connect message
            for (namespace, socket) in self.namespaces{
                socket.connect()
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
    
    public func socketOnData(socket: EngineSocket, data: [Byte], isBinary: Bool) {
        NSLog("[SocketIOClient][\(self.readyState.description)] got packet from underlying socket")
        
        var socketIOPacket: SocketIOPacket?
        
        if isBinary{
            socketIOPacket = self.decoder.addBuffer(Converter.bytearrayToNSData(data))
        }
        else{
            socketIOPacket = self.decoder.addString(data)
        }
        
        if socketIOPacket != nil {
            self.delegate?.clientOnPacket(self, packet: socketIOPacket!)
            
            if let namespace = socketIOPacket?.nsp {
                if self.namespaces[namespace] != nil{
                    var socket = self.socket(namespace)
                    socket.receivePacket(socketIOPacket!)
                }
                else{
                    NSLog("[SocketIOClient][\(self.readyState.description)] Unknown namespace \(namespace)")
                }
            }
        }
    }
    
    public func socketOnPacket(socket: EngineSocket, packet: EnginePacket){
        // We have no interest in packet
    }
    
    public func socketOnError(socket: EngineSocket, error: String, description: String?) {
        dispatch_async(self.dispatchQueue){
            [unowned self] () -> Void in
            if self.reconnecting {
                NSLog("Reconnect failed with error: \(error) [\(description)]")
                
                self.delegate?.clientReconnectionError(self, error: error, description: description)
                self.reconnecting = false
                self.reconnect()
            }
            else{
                NSLog("[SocketIOClient][\(self.readyState.description)] Underlying engine socket raised error \(error) [\(description)]")
                self.delegate?.clientOnError(self, error: error, description: description)
            }
        }
    }
    
    public func socketDidUpgraded(socket: EngineSocket) {
        NSLog("Underlying socket upgraded")
    }
    
    // End of EngineSocketDelegate
}

@objc public protocol SocketIOSocketDelegate {
    // Called when the socket received a low level packet
    optional func socketOnPacket(socket: SocketIOSocket, packet: SocketIOPacket)
    
    // Called when the socket received an event
    func socketOnEvent(socket: SocketIOSocket, event: String, data: AnyObject?)
    
    // Called when the socket is open
    func socketOnOpen(socket: SocketIOSocket)
    
    // Called when the socket is on error
    func socketOnError(socket: SocketIOSocket, error: String, description: String?)
}

public class SocketIOSocket: NSObject {
    unowned var client: SocketIOClient
    var namespace: String
    var messageIdCounter: Int = 0
    var acknowledgeCallbacks: [Int: (()->Void)] = [:]
    var receiveBuffer: [SocketIOPacket] = []
    var sendBuffer: [SocketIOPacket] = []
    var connected = false
    var autoConnect: Bool
    
    public var delegate: SocketIOSocketDelegate?
    
    public init(client: SocketIOClient, namespace: String, autoConnect: Bool = false){
        self.client = client
        self.namespace = startsWith(namespace, "/") ? namespace : "/\(namespace)"
        self.autoConnect = autoConnect
    }
    
    public func open(){
        if self.connected {
            return
        }
        
        if self.client.readyState == .Open {
            self.connect()
        }
        else{
            self.client.open()
        }
    }
    
    // This function will be called by the client
    public func onOpen(){
        self.delegate?.socketOnOpen(self)
    }
    
    public func connect(){
        NSLog("[SocketIOSocket][\(self.namespace)][\(self.connected)] connect to namespace")
        self.packet(.Connect)
    }
    
    public func packet(type: SocketIOPacketType, data: AnyObject? = nil){
        let socketPacket = SocketIOPacket(type: type, data: data, nsp: self.namespace)
        self.client.packet(socketPacket)
    }
    
    public func event(event: String, data: AnyObject?){
        var packetData: NSMutableArray = []
        packetData.insertObject(event, atIndex: 0)
        if data != nil {
            packetData.insertObject(data!, atIndex: 1)
        }
        
        self.packet(.Event, data: packetData)
    }
    
    public func receivePacket(packet: SocketIOPacket){
        self.delegate?.socketOnPacket?(self, packet: packet)
        
        switch packet.type {
        case .Connect:
            self.connected = true
            self.delegate?.socketOnOpen(self)
        case .Error:
            self.delegate?.socketOnError(self, error: packet.data as String, description: nil)
        case .Event, .BinaryEvent:
            if let data: AnyObject = packet.data {
                if let dataArray = data as? NSArray {
                    if dataArray.count > 0 {
                        let event: NSString = dataArray[0] as NSString
                        if dataArray.count > 1{
                            self.delegate?.socketOnEvent(self, event: event, data: dataArray[1])
                        }
                        else{
                            self.delegate?.socketOnEvent(self, event: event, data: nil)
                        }
                    }
                }
                else{
                    NSLog("The data is not a array, not able to get the event name, ignore")
                }
            }
        case .Ack, .BinaryAck:
            break
        default:
            break
        }
    }
}