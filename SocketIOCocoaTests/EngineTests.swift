//
//  Engine.swift
//  SocketIOCocoa
//
//  Created by LiShuo on 14/11/8.
//  Copyright (c) 2014年 LiShuo. All rights reserved.
//

import Foundation
import XCTest
import SocketIOCocoa

class EnginePacketTest: XCTestCase{
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
    
    func testPollingTransportURI() {
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
    
    func testWebsocketTransportURI() {
        let transport = WebsocketTransport(
            host: "localhost", path: "/socket.io/", port: "8001", secure: false)
        
        let uri = transport.uri()
        var url = NSURL(string: uri)!
        XCTAssertEqual("localhost", url.host!)
        XCTAssertEqual(8001, url.port!)
        XCTAssertEqual("/socket.io", url.path!)
        XCTAssertEqual("ws", url.scheme!)
        
        let query : String = url.query!
        let params : [String: String] = query.parametersFromQueryString()
        XCTAssertEqual("3", params["EIO"]!)
        XCTAssertEqual("websocket", params["transport"]!)
        
        println(uri)
    }
    
    func testPollingTransportOpen() {
        var expectation = self.expectationWithDescription("async request")
        let transport = PollingTransport(
            host: "localhost", path: "/socket.io/", port: "8001", secure: false)
        
        class TestTransportDelegate: EngineTransportDelegate{
            var packet: EnginePacket?
            var expectation: XCTestExpectation
            var dispatchQueue: dispatch_queue_t = {
                return dispatch_queue_create("test queue", DISPATCH_QUEUE_SERIAL)
                }()
            
            init(expectation: XCTestExpectation){
                self.expectation = expectation
            }
            
            private func transportOnClose(transport: Transport) {
            }
            private func transportOnError(transport: Transport, error: String, withDescription description: String) {
                NSException(name: error, reason: description, userInfo: nil)
            }
            private func transportOnOpen(transport: Transport) {
                
            }
            private func transportOnPacket(transport: Transport, packet: EnginePacket) {
                println(packet)
                self.packet = packet
                XCTAssert(packet.type == .Open)
                self.expectation.fulfill()
            }
            private func transportDispatchQueue(transport: Transport) -> dispatch_queue_t {
                return self.dispatchQueue
            }
        }
        
        var delegate = TestTransportDelegate(expectation: expectation)
        transport.delegate = delegate
        transport.open()
        self.waitForExpectationsWithTimeout(30, handler: nil)
        
        transport.write([
            EnginePacket(string: "hello world 1", type: .Message),
            EnginePacket(nsdata: Converter.nsstringToNSData("hello world 1"), type: .Message),
            ])
        sleep(1)
    }
    
    func testWebsocketTransport(){
        var expectation = self.expectationWithDescription("async request")
        let transport = WebsocketTransport(
            host: "localhost", path: "/socket.io/", port: "8001", secure: false)
        
        class TestTransportDelegate: EngineTransportDelegate{
            var packet: EnginePacket?
            var expectation: XCTestExpectation
            var dispatchQueue: dispatch_queue_t = {
                return dispatch_queue_create("test queue", DISPATCH_QUEUE_SERIAL)
                }()
            
            init(expectation: XCTestExpectation){
                self.expectation = expectation
            }
            
            private func transportOnClose(transport: Transport) {
            }
            private func transportOnError(transport: Transport, error: String, withDescription description: String) {
                NSException(name: error, reason: description, userInfo: nil)
            }
            private func transportOnOpen(transport: Transport) {
                self.expectation.fulfill()
            }
            private func transportOnPacket(transport: Transport, packet: EnginePacket) {
                println(packet)
            }
            private func transportDispatchQueue(transport: Transport) -> dispatch_queue_t {
                return self.dispatchQueue
            }
        }
        
        var delegate = TestTransportDelegate(expectation: expectation)
        transport.delegate = delegate
        transport.open()
        self.waitForExpectationsWithTimeout(30, handler: nil)
        
        transport.write([
            EnginePacket(string: "hello world 1", type: .Message),
            EnginePacket(nsdata: Converter.nsstringToNSData("hello world 1"), type: .Message),
            ])
        sleep(1)
    }
    
    func testEngineSocket(){
        var expectation = self.expectationWithDescription("async request")
        var socket = EngineSocket(host: "localhost", port: "8001", path: "/socket.io/", secure: false, transports: ["polling", "websocket"], upgrade: true, config: [:])
        XCTAssertNotNil(socket)
        
        class TestSocketDelegate: EngineSocketDelegate{
            var expectation: XCTestExpectation
            
            init(expectation: XCTestExpectation){
                self.expectation = expectation
            }
            
            private func socketOnPacket(socket: EngineSocket, packet: EnginePacket) {
                println("Recieved packet")
            }
            
            private func socketOnData(socket: EngineSocket, data: [Byte], isBinary: Bool) {
                println(data)
                expectation.fulfill()
            }
            
            private func socketOnOpen(socket: EngineSocket) { }
            private func socketOnClose(socket: EngineSocket) { }
            private func socketOnError(socket: EngineSocket, error: String, description: String) {
            }
        }
        
        var delegate = TestSocketDelegate(expectation: expectation)
        socket.delegate = delegate
        socket.open()
        
        self.waitForExpectationsWithTimeout(30, handler: nil)
    }
}