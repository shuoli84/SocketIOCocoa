//
//  EngineParser.swift
//  SocketIOCocoa
//
//  Created by LiShuo on 14/11/1.
//  Copyright (c) 2014年 LiShuo. All rights reserved.
//

import Foundation

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
    public func encodePacket(packet : EnginePacket) -> NSData?{
        return packet.encode()
    }
}