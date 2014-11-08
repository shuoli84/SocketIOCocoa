//
//  EngineIO.swift
//  SocketIOCocoa
//
//  Created by LiShuo on 14/11/8.
//  Copyright (c) 2014年 LiShuo. All rights reserved.
//

import Foundation

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