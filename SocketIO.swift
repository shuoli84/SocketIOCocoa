//
//  EngineParser.swift
//  SocketIOCocoa
//
//  Created by LiShuo on 14/11/1.
//  Copyright (c) 2014年 LiShuo. All rights reserved.
//

import Foundation

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
}

/*
Engine parser used to encode and decode packet for engineio level. Since we are running on iOS, so we pretty sure we
can support binary, this parser only implemented the binary part. No base64 support.
*/

public enum PacketType : Int {
    case Open, Close, Ping, Pong, Message, Upgrade, Noop
    case Error = 255
}

public struct EnginePacket {
    public var type: PacketType
    public var data: NSData?
    
    public init(data: NSData?, type: PacketType){
        self.type = type
        self.data = data
    }
   
    public init(string: String, type: PacketType){
        var data = string.dataUsingEncoding(NSUTF8StringEncoding)
        self.init(data: data, type: type)
    }
    
    public init(decodeFromData data: NSData){
        let buf : [Byte] = Converter.nsdataToByteArray(data)
        if let packetType = PacketType(rawValue: Int(buf[0])){
            self.type = packetType
        }
        else{
            self.type = .Error
        }
        
        if data.length > 1 {
            self.data = Converter.bytearrayToNSData([Byte](buf[1..<buf.count]))
        }
        else{
            self.data = nil
        }
    }
    
    public func encode() -> NSData {
        var output = NSMutableData()
        var typeValue = self.type
        output.appendBytes(&typeValue, length: 1)
        if let data = self.data {
            output.appendData(self.data!)
        }
        return output
    }
}

let error_packet = EnginePacket(data: nil, type: .Error)

public class EngineParser {
    public class func encodePayload (packets: [EnginePacket]) -> NSData {
        var output = NSMutableData()
        for packet in packets{
            let encoded = packet.encode()
            var lengthBuf = [Byte]([1]) // 0 for string, 1 for binary, we only use 1 as we only support binary now
            let bufLengthStr = String(encoded.length)
            lengthBuf += Converter.nsstringToByteArray(bufLengthStr)
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
            
            var packetLength = 0
            for c in lengthBuf {
                packetLength = packetLength * 10 + (c - 48)
            }
            
            let encodedPacket = Converter.bytearrayToNSData([Byte](byteArray[offset..<offset+packetLength]))
            
            packets.append(EnginePacket(decodeFromData: encodedPacket))
            
            offset += packetLength
        }
        
        return packets
    }
}

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
    var writable: Bool = false
    
    //
    var sid: String?
    var secure: Bool = false
    var readyState : TransportReadyState = .Init
    
    var error_block: ((message: String, desciption: String)->Void)?
    var packet_block: ((packet: EnginePacket)->Void)?
    var close_block: (()->Void)?
    
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
        if let callback = self.packet_block {
            callback(packet: EnginePacket(decodeFromData: data))
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
    
    
    public func open(){
        
    }
    
    public func close(){
        
    }
    
    public func write(packets: [EnginePacket]){
        
    }
    
    public func onOpen(){
        
    }
}