//
//  SocketIOCocoaTests.swift
//  SocketIOCocoaTests
//
//  Created by LiShuo on 14/11/1.
//  Copyright (c) 2014年 LiShuo. All rights reserved.
//

import Cocoa
import XCTest
import SocketIOCocoa

class SocketIOCocoaTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testPacket() {
        // Test packet without data
        var packet = EnginePacket(data: nil, type: .Open, isBinary: false)
        XCTAssert(packet.encode().length == 1, "The length should be 1")
        
        // Test packet with string dat
        var testString = "what the hell"
        packet = EnginePacket(string: testString, type: .Open)
        XCTAssert(!packet.isBinary, "Packet should be string")
        
        var encoded = packet.encode()
        XCTAssert(encoded.length == 14, "Mismatch length")
        
        let decodedPacket = EnginePacket(decodeFromData: encoded)
        XCTAssert(decodedPacket.type == PacketType.Open, "Mismatch type")
        XCTAssert(decodedPacket.isBinary == false)
        
        // Test packet with binary data
        var binaryData = Converter.nsstringToNSData(testString)
        packet = EnginePacket(nsdata: binaryData, type: .Open)
        XCTAssert(packet.isBinary == true)
        
        encoded = packet.encode()
        XCTAssert(encoded.length == 14)
        
        packet = EnginePacket(decodeFromData: encoded)
        XCTAssert(packet.isBinary == true)
    }
    
    func testPayload(){
        let packets = [
            EnginePacket(string: "The first packet", type: .Open),
            EnginePacket(nsdata: Converter.nsstringToNSData("The second packet"), type: .Open),
            EnginePacket(string: "The third packet", type: .Open),
        ]
        
        var d = EngineParser.encodePayload(packets)
        var decoded_packets = EngineParser.decodePayload(d)
        
        XCTAssert(Converter.bytearrayToNSString(decoded_packets[0].data!) == "The first packet", "not matching")
        XCTAssert(Converter.bytearrayToNSString(decoded_packets[1].data!) == "The second packet")
        XCTAssert(Converter.bytearrayToNSString(decoded_packets[2].data!) == "The third packet")
    }
    
    func testPerformancePayload() {
        self.measureBlock(){
            for _ in 0...1000 {
                self.testPayload()
            }
        }
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock() {
            let longstring = "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            "This is a very long string"
            
            for i in 0...1000 {
                let packet = EnginePacket(string: "long string", type:.Open)
                let encoded = packet.encode()
                let decoded = EnginePacket(decodeFromData: encoded)
            }
        }
    }

    func testBaseTransportURI() {
        let transport = PollingTransport(
            host: "localhost", path: "/socket.io/", port: "8001", secure: false)
        
        let uri = transport.uri()
        var url = NSURL(string: uri)!
        XCTAssertEqual("localhost", url.host!)
        XCTAssertEqual(8001, url.port!)
        XCTAssertEqual("/socket.io", url.path!)
        XCTAssertEqual("http", url.scheme!)
        
        let query : String = url.query!
        let params : [String: String] = query.parametersFromQueryString()
        XCTAssertEqual("3", params["EIO"]!)
        XCTAssertEqual("polling", params["transport"]!)
        
        println(uri)
    }
    
    
    func testBaseTransportOpen() {
        var expectation = self.expectationWithDescription("async request")
        let transport = PollingTransport(
            host: "localhost", path: "/socket.io/", port: "8001", secure: false)
        
        var packet : EnginePacket?
        transport.onPacket { (p: EnginePacket) -> Void in
            packet = p
            XCTAssert(p.type == .Open)
            expectation.fulfill()
        }
        transport.open()
        self.waitForExpectationsWithTimeout(30, handler: nil)
        println(packet)
        
        expectation = self.expectationWithDescription("send data")
        transport.write([
            EnginePacket(string: "Hello world", type: .Message),
            EnginePacket(nsdata: Converter.nsstringToNSData("Hello world"), type: .Message),
            ])
        self.waitForExpectationsWithTimeout(5, handler:nil)
    }
    
    func testEngineSocket(){
        var expectation = self.expectationWithDescription("async request")
        var socket = EngineSocket(host: "localhost", port: "8001", path: "/socket.io/", secure: false, transports: ["polling", "websocket"], upgrade: true, config: [:])
        XCTAssertNotNil(socket)
        
        socket.messageBlock = {
            (bytes: [Byte], isBinary: Bool) -> Void in
            println(bytes)
            expectation.fulfill()
        }
        
        socket.open()
        
        self.waitForExpectationsWithTimeout(30, handler: nil)
    }
}
