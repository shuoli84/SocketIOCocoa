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
        var packet = EnginePacket(data: nil, type: .Open)
        XCTAssert(packet.encode().length == 1, "The length should be 1")
        
        var testString = "what the hell"
        packet = EnginePacket(string: testString, type: .Open)
        let encoded = packet.encode()
        XCTAssert(encoded.length == 14, "Mismatch length")
        
        let decodedPacket = EnginePacket(decodeFromData: encoded)
        XCTAssert(decodedPacket.type == PacketType.Open, "Mismatch type")
    }
    
    func testPayload(){
        let packets = [
            EnginePacket(string: "The first packet", type: .Open),
            EnginePacket(string: "The second packet", type: .Open),
            EnginePacket(string: "The third packet", type: .Open),
        ]
        
        var d = EngineParser.encodePayload(packets)
        Converter.nsdataToByteArray(d)
        var decoded_packets = EngineParser.decodePayload(d)
        
        XCTAssert(Converter.nsdataToNSString(decoded_packets[0].data!) == "The first packet", "not matching")
        XCTAssert(Converter.nsdataToNSString(decoded_packets[1].data!) == "The second packet")
        XCTAssert(Converter.nsdataToNSString(decoded_packets[2].data!) == "The third packet")
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

    func testBaseTransport() {
        let transport = BaseTransport(
            host: "localhost", path: "/socket.io/", port: "8001", secure: false)
        XCTAssertNotNil(transport, "Should no nil")
    }
    
    func testAlamofire() {
        var expectation = self.expectationWithDescription("asynchronous request")

        request(.GET, "http://www.baidu.com/").response { (request, response, data, error) in
            expectation.fulfill()
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                println(response)
            })
        }
        
        self.waitForExpectationsWithTimeout(10.0, handler: nil)
    }
}
