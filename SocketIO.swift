//
//  EngineParser.swift
//  SocketIOCocoa
//
//  Created by LiShuo on 14/11/1.
//  Copyright (c) 2014年 LiShuo. All rights reserved.
//

import Foundation

// Mark Converter

/**
Converter is the helper utility to convert different types
*/
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
        return self.nsdataToNSString(self.bytearrayToNSData(bytes))
    }
    
    // Convert from NSString to json object
    public class func nsstringToJSON(str: NSString) -> NSDictionary? {
        let data = self.nsstringToNSData(str)
        return self.nsdataToJSON(data)
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

enum ASCII: Byte, DebugPrintable, Printable{
    case _0 = 48, _1, _2, _3, _4, _5, _6, _7, _8, _9
    case a = 97, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case A = 65, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z
    
    var description: String {
        return "\(self.rawValue)"
    }
    
    var debugDescription: String {
        return self.description
    }
}

public enum PacketType: Byte {
    case Open, Close, Ping, Pong, Message, Upgrade, Noop
    case Error = 20, Max
    
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

public struct EnginePacket : Printable, DebugPrintable{
    public var type: PacketType
    public var data: [Byte]?
    public var isBinary: Bool = false
    
    public var description: String{
        if let data = self.data {
            return "[\(type.description)][\(isBinary)]: \(data)"
        }
        else {
            return "[\(type.description)][\(isBinary)]: \(self.data)"
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
        if data != nil{
            self.data = data
        }
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
            var lengthBuf = [Byte]([1]) // 0 for string, 1 for binary, we only use 1 as we only support binary now
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
    
    class func decodePayloadAsString(string: String) -> [EnginePacket] {
        return []
    }
}

// Mark Engine Transport

public enum TransportReadyState{
    case Init, Open, Opening, Closing, Closed
}

public protocol Transport {
    func open()
    func close()
    func write(packets: [EnginePacket])
    func onOpen()
    func onData(data: NSData)
    func onClose()
    func onError(message: String, description: String)
    
    // Whether the transport supports pausible
    var pausible : Bool { get }
    
    // The pause method
    func pause()
    
    // The sid
    var sid : String? { get set }
    
    /**
    Whether the transport is writable. The client should always check the writable flag. 
    Transport class don't have a write queue. So each write goes straight into send method.
    NOTE: There could be race condition
    */
    var writable : Bool { get set }
    
    mutating func onPacket(callback : (packet: EnginePacket)->Void)
}


public class BaseTransport {
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
    
    public var sid: String?
    
    var secure: Bool = false
    var readyState : TransportReadyState = .Init
    
    public var error_block: ((message: String, desciption: String)->Void)?
    
    public var packetBlock: ((packet: EnginePacket)->Void)?
    
    public var close_block: (()->Void)?
    
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
        if let callback = self.error_block {
            callback(message: message, desciption: description)
        }
        else{
            NSLog("onError block not set, ignore error")
        }
    }
    
    public func onData(data: NSData){
        if let callback = self.packetBlock {
            for packet in EngineParser.decodePayload(data){
                callback(packet: packet)
            }
        }
        else{
            NSLog("onData block not set, ignore packet")
        }
    }
    
    public func onClose(){
        self.readyState = .Closed
        if let callback = self.close_block {
            callback()
        }
    }
    
    public func onPacket(callback: (packet: EnginePacket)->Void){
        self.packetBlock = callback
    }
}

public class PollingTransport : BaseTransport, Transport {
    
    // The name of the transport
    override var name : String{
        get {
            return "polling"
        }
    }
    
    // Polling state
    var polling = false
    
    public var pausible : Bool {
        get { return true }
    }
    
    
    public func open(){
        if self.readyState == .Closed || self.readyState == .Init{
            self.readyState = .Opening
            
            self.poll()
            
            while self.readyState == .Open{
                self.poll()
            }
        }
    }
    
    func poll(){
        NSLog("polling")
        self.polling = true
        
        request(.GET, self.uri())
        .response { (request, response, data, error) -> Void in
            // Consider dispatch to the same queue
            NSLog("Response get")
            
            if response?.statusCode >= 200 && response?.statusCode < 300 {
                NSLog("Request succeeded")
                
                if let nsdata = data as? NSData {
                    self.onData(nsdata)
                }
            }
        }
    }
    
    public func close(){
        
    }
    
    public func write(packets: [EnginePacket]){
        
    }
    
    public func onOpen(){
        
    }
    
    public func pause(){
        
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

public class WebsocketTransport : BaseTransport, Transport {
    // The name of the transport
    override var name : String{
        get { return "websocket" }
    }
    
    public var pausible : Bool {
        get { return false }
    }
    
    public func open(){
        
    }
    
    public func close(){
        
    }
    
    public func write(packets: [EnginePacket]){
        
    }
    
    public func onOpen(){
        
    }
    
    public func pause(){
        
    }
}


// Mark Engine Socket

enum EngineSocketReadyState : Int{
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

public class EngineSocket{
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
    
    // The callback block when a packet received
    var packetBlock: ((EnginePacket)->Void)?
    var openBlock: (()->Void)?
    var messageBlock: ((NSData)->Void)?
    
    
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
        
        if transport != nil{
            if self.id != nil{
                transport!.sid = self.id
            }
        }
        
        return transport
    }
    
    func setTransport(inout transport: Transport){
        transport.onPacket({
            [unowned self](packet: EnginePacket) -> Void in
            self.onPacket(packet)
        })
        
        self.transport = transport
    }
    
    public func open(){
        assert(transports.count != 0)
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
    
    func onPacket(packet: EnginePacket){
        NSLog("[EngineSocket] Received one packet")
        if self.readyState == .Open || self.readyState == .Opening{
            NSLog("[EngineSocket] Receive: [%s]", packet.type.description)
            
            if let callback = self.packetBlock {
                callback(packet)
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
                    self.onMessage(Converter.bytearrayToNSData(data))
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
            NSLog("packet received with socket readyState [%s]", self.readyState.description)
        }
    }
    
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
    
    func onMessage(data: NSData){
        if let callback = self.messageBlock {
            callback(data)
        }
    }
    
    func onOpen(){
        NSLog("Socket Open")
        
        self.readyState = .Open
        if let callback = self.openBlock {
            callback()
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
        let packet = EnginePacket(data: data, type:packetType, isBinary: false) // TODO FIX ME
        self.packet(packet, callback: callback)
    }
    
    func flush(){
        if self.readyState != .Closed && !self.upgrading && self.transport!.writable {
            if self.writeQueue.count == 0{
                return
            }
            
            NSLog("Flushing %d packets", self.writeQueue.count)
            
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
        self.writeQueue.append(packet)
        self.writeCallbackQueue.append(callback)
        self.flush()
    }
}