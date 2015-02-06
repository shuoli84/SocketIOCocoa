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
    
    func testBinaryParser() {
        var socketPacket = SocketIOPacket(type: .Event, data: [
            "what": "the",
            "data": Converter.nsstringToNSData("hell"),
            "array": [1,2, Converter.nsstringToNSData("great")]
            ] as NSDictionary)
        
        var result = BinaryParser.deconstructPacket(socketPacket)
        println(Converter.jsonToNSString(result.packet.data!))
        XCTAssert(result.buffers.count == 2)
        
        let packet = BinaryParser.reconstructPacket(result.packet, buffers: result.buffers)
        println(packet)
        XCTAssert(packet.attachments == 0)
        let data = packet.data as NSDictionary
        XCTAssert(Converter.nsdataToNSString(data.objectForKey("data") as NSData) == "hell")
    }
    
    func testMeasureSocketIOEncode(){
        self.measureBlock(){
            for _ in 0...200{
                self.testSocketIOPacket()
            }
        }
    }
    
    func testSocketIOPacket(){
        var socketPacket = SocketIOPacket(type: .Event, data: [
            "what": "the"
            ] as NSDictionary, id: 0, nsp: "chat")
        var encodedString = socketPacket.encodeAsString()
        XCTAssert(Converter.bytearrayToNSString(encodedString) == "2/chat,0{\"what\":\"the\"}")
        
        var decodedPacket = SocketIOPacket(decodedFromString: encodedString)
        
        XCTAssert(decodedPacket.type == .Event)
        XCTAssert(decodedPacket.id == 0)
        XCTAssert(decodedPacket.nsp == "/chat")
        let data = decodedPacket.data as NSDictionary
        XCTAssert(data.objectForKey("what") as NSString == "the")
        
        socketPacket = SocketIOPacket(type: .BinaryEvent, data: [
            "what": "the",
            "data": Converter.nsstringToNSData("hell"),
            "array": [1,2, Converter.nsstringToNSData("great")]
            ] as NSDictionary, id: 0, nsp: "chat")
        
        let (encoded, buffers) = socketPacket.encode()
        XCTAssert(2 == buffers.count)
        
        var decoder = SocketIOPacketDecoder()
        
        let binaryPacket = SocketIOPacket(decodedFromString: encoded)
        decoder.packetToBeReConstructed = binaryPacket
        var flag = false
        var decodedBinaryPacket: SocketIOPacket?
        for data in buffers{
            decodedBinaryPacket = decoder.addBuffer(data)
            if decodedBinaryPacket != nil{
                break;
            }
        }
        
        if let p = decodedBinaryPacket{
            XCTAssert(p.type == .BinaryEvent)
            let (encoded, buffers) = p.encode()
            XCTAssert(buffers.count == 2)
        }
        else{
            XCTAssert(false, "packet not reconstructed")
        }
        
        socketPacket = SocketIOPacket(type: .Event, data: ["message", "Hello world"] as NSArray, id: 12312, nsp: "chat")
        let (encoded2, _) = socketPacket.encode()
        let encodedStr = Converter.bytearrayToNSString(encoded2)
        XCTAssert("2/chat,12312[\"message\",\"Hello world\"]" == encodedStr)
    }
    
    func testSocketIOClient(){
        let uri = "http://localhost:8001/socket.io/"
        var client = SocketIOClient(uri: uri, query: ["test": "hello"], reconnect: true, timeout: 3, transports: ["polling"])
        XCTAssert(client.uri == uri)
        
        class ClientDelegate: SocketIOClientDelegate {
            var expectation: XCTestExpectation?
            var reconnectExpectation: XCTestExpectation?
            var closeExpectation: XCTestExpectation?
            
            init(expectation: XCTestExpectation){
                self.expectation = expectation
            }
            
            private func clientOnClose(client: SocketIOClient) {
                NSLog("Client on Close")
                self.closeExpectation?.fulfill()
            }
            
            private func clientOnConnectionTimeout(client: SocketIOClient) {
                NSLog("Client on connect timeout")
            }
            
            private func clientOnError(client: SocketIOClient, error: String, description: String?) {
                NSLog("Client on Erorr \(error) [\(description)]")
            }
            private func clientOnOpen(client: SocketIOClient) {
                NSLog("Client on Open")
                self.expectation?.fulfill()
                self.expectation = nil // prevent refulfill
            }
            private func clientOnPacket(client: SocketIOClient, packet: SocketIOPacket) {}
            private func clientReconnectionError(client: SocketIOClient, error: String, description: String?) {
                NSLog("Client reconnection Error \(error) [\(description)]")
            }
            private func clientReconnectionFailed(client: SocketIOClient) {
                NSLog("Client reconnection failed")
            }
            private func clientReconnected(client: SocketIOClient) {
                NSLog("Client reconnected!!")
                self.reconnectExpectation?.fulfill()
            }
        }
        
        var expectation = self.expectationWithDescription("Client open expectation")
        var delegate = ClientDelegate(expectation: expectation)
        client.delegate = delegate
        client.open()
        self.waitForExpectationsWithTimeout(10, handler: nil)
        
        // Test the reconnection
        // Close the underlying engine socket
        client.engineSocket?.close()
        
        expectation = self.expectationWithDescription("Wait for reconnect")
        delegate.reconnectExpectation = expectation
        self.waitForExpectationsWithTimeout(10, handler: nil)
        
        expectation = self.expectationWithDescription("Wait for close")
        delegate.closeExpectation = expectation
        client.close()
        self.waitForExpectationsWithTimeout(10, handler: nil)
    }
    
    func testSocketIOClientReceive(){
        let uri = "http://localhost:8001/socket.io/"
        var client = SocketIOClient(uri: uri, reconnect: true, timeout: 3)
        XCTAssert(client.uri == uri)
        
        class ClientDelegate: SocketIOClientDelegate {
            var expectation: XCTestExpectation?
            
            init(expectation: XCTestExpectation){
                self.expectation = expectation
            }
            
            private func clientOnClose(client: SocketIOClient) {
                NSLog("Client on Close")
            }
            
            private func clientOnConnectionTimeout(client: SocketIOClient) {
                NSLog("Client on connect timeout")
            }
            
            private func clientOnError(client: SocketIOClient, error: String, description: String?) {
                NSLog("Client on Erorr \(error) [\(description)]")
            }
            private func clientOnOpen(client: SocketIOClient) {
                NSLog("Client on Open")
            }
            private func clientOnPacket(client: SocketIOClient, packet: SocketIOPacket) {
                NSLog("Client got data")
                self.expectation?.fulfill()
                self.expectation = nil
            }
            private func clientReconnectionError(client: SocketIOClient, error: String, description: String?) {
                NSLog("Client reconnection Error \(error) \(description)")
            }
            private func clientReconnectionFailed(client: SocketIOClient) {
                NSLog("Client reconnection failed")
            }
            private func clientReconnected(client: SocketIOClient) {
            }
        }
        
        var expectation = self.expectationWithDescription("Client open expectation")
        var delegate = ClientDelegate(expectation: expectation)
        client.delegate = delegate
        client.open()
        
        self.waitForExpectationsWithTimeout(10, handler: nil)
    }
    
    func testSocketIOSocketWrongNameSpace(){
        class SocketIODelegate: SocketIOSocketDelegate {
            var expectation: XCTestExpectation?
            var errorexpectation: XCTestExpectation?
            
            init(){}
            
            private func socketOnEvent(socket: SocketIOSocket, event: String, data: AnyObject?) {
                NSLog("Socket on Event \(event), data \(data)")
            }
            
            private func socketOnPacket(socket: SocketIOSocket, packet: SocketIOPacket) {
                NSLog("Socket on Packet \(packet)")
            }
            
            private func socketOnOpen(socket: SocketIOSocket) {
                NSLog("Socket on open")
            }
            
            private func socketOnError(socket: SocketIOSocket, error: String, description: String?) {
                NSLog("Socket on error: \(error)")
                self.errorexpectation?.fulfill()
                self.errorexpectation = nil
            }
        }
        
        let uri = "http://localhost:8001/socket.io/"
        // Open socket and client together
        var client = SocketIOClient(uri: uri, reconnect: true, timeout: 30)
        
        var socket = client.socket("wrongnamespace")
        var delegate = SocketIODelegate()
        var expectation = self.expectationWithDescription("Socket fail on wrong namespace")
        delegate.errorexpectation = expectation
        socket.delegate = delegate
        socket.open()
        // Open client first, then open the socket
        self.waitForExpectationsWithTimeout(30, handler: nil)
    }
    
    func testSocketIOSocketConnect(){
        class SocketIODelegate: SocketIOSocketDelegate {
            var expectation: XCTestExpectation?
            
            init(){}
            
            private func socketOnEvent(socket: SocketIOSocket, event: String, data: AnyObject?) {
                NSLog("Socket on Event \(event), data \(data)")
            }
            
            private func socketOnPacket(socket: SocketIOSocket, packet: SocketIOPacket) {
                NSLog("Socket on Packet \(packet)")
            }
            
            private func socketOnOpen(socket: SocketIOSocket) {
                NSLog("Socket on open")
                self.expectation?.fulfill()
                self.expectation = nil
            }
            
            private func socketOnError(socket: SocketIOSocket, error: String, description: String?) {
                NSLog("Socket on error")
            }
        }
        
        let uri = "http://localhost:8001/socket.io/"
        // Open socket and client together
        var client = SocketIOClient(uri: uri, reconnect: true, timeout: 30)
        
        // The echo namespace is defined in socketio server
        var expectation = self.expectationWithDescription("Socket open")
        var socket = client.socket("echo")
        socket.event("test evet", data: ["haha": "hehe"])
        var delegate = SocketIODelegate()
        socket.delegate = delegate
        delegate.expectation = expectation
        socket.open()
        self.waitForExpectationsWithTimeout(30, handler: nil)
    }
    
    func testSocketIOSocketReceive(){
        class SocketIODelegate: SocketIOSocketDelegate {
            var expectation: XCTestExpectation?
            
            init(){}
            
            private func socketOnEvent(socket: SocketIOSocket, event: String, data: AnyObject?) {
                NSLog("Socket on Event \(event), data \(data)")
                self.expectation?.fulfill()
                self.expectation = nil
            }
            
            private func socketOnPacket(socket: SocketIOSocket, packet: SocketIOPacket) {
                NSLog("Socket on Packet \(packet)")
            }
            
            private func socketOnOpen(socket: SocketIOSocket) {
                NSLog("Socket on open")
                self.expectation?.fulfill()
            }
            
            private func socketOnError(socket: SocketIOSocket, error: String, description: String?) {
                NSLog("Socket on error: \(error)")
            }
        }
        
        let uri = "http://localhost:8001/socket.io/"
        // Open socket and client together
        var client = SocketIOClient(uri: uri, reconnect: true, timeout: 30)
        client.headers = ["Test-Header": "Hello"]
        
        // The echo namespace is defined in socketio server
        var expectation = self.expectationWithDescription("Socket open")
        var socket = client.socket("echo")
        var delegate = SocketIODelegate()
        socket.delegate = delegate
        delegate.expectation = expectation
        socket.open()
        self.waitForExpectationsWithTimeout(30, handler: nil)
    }
    
    func testSocketIOSocketAck(){
        class SocketIODelegate: SocketIOSocketDelegate {
            init(){}
            
            private func socketOnEvent(socket: SocketIOSocket, event: String, data: AnyObject?) {
                NSLog("Socket on Event \(event), data \(data)")
            }
            
            private func socketOnPacket(socket: SocketIOSocket, packet: SocketIOPacket) {
                NSLog("Socket on Packet \(packet)")
            }
            
            private func socketOnOpen(socket: SocketIOSocket) {
                NSLog("Socket on open")
            }
            
            private func socketOnError(socket: SocketIOSocket, error: String, description: String?) {
                NSLog("Socket on error: \(error)")
            }
        }
        
        let uri = "http://localhost:8001/socket.io/"
        // Open socket and client together
        var client = SocketIOClient(uri: uri, reconnect: true, timeout: 30, transports:["polling", "websocket"])
        client.headers = ["Test-Header": "Hello"]
        
        // The echo namespace is defined in socketio server
        var expectation = self.expectationWithDescription("Socket open")
        var socket = client.socket("echo")
        var delegate = SocketIODelegate()
        socket.delegate = delegate
        socket.open()
        
        socket.event("message", data: [1,2,3]) { (packet) -> Void in
            expectation.fulfill()
        }
        self.waitForExpectationsWithTimeout(300, handler: nil)
        
        expectation = self.expectationWithDescription("Binary message")
        socket.event("message", data: ["what": Converter.nsstringToNSData("hell")]) { (packet) -> Void in
            expectation.fulfill()
        }
        self.waitForExpectationsWithTimeout(300, handler: nil)
    }
    
    func testSocketIOSocketStartStopStartStop(){
        class TestSocketIOClientDelegate: SocketIOClientDelegate {
            var openExpection: XCTestExpectation?
            var onPacketExpectation: XCTestExpectation?
            var closeExpectation: XCTestExpectation?
            
            init(){}
            
            private func clientOnClose(client: SocketIOClient) {
                self.closeExpectation?.fulfill()
            }
            
            private func clientOnOpen(client: SocketIOClient) {
                self.openExpection?.fulfill()
            }
            
            private func clientOnPacket(client: SocketIOClient, packet: SocketIOPacket) {
                self.onPacketExpectation?.fulfill()
                self.onPacketExpectation = nil
            }
            
            private func clientReconnected(client: SocketIOClient) {
            }
            
            private func clientReconnectionError(client: SocketIOClient, error: String, description: String?) {
            }
            
            private func clientReconnectionFailed(client: SocketIOClient) {
            }
            
            private func clientOnConnectionTimeout(client: SocketIOClient) {
            }
            
            private func clientOnError(client: SocketIOClient, error: String, description: String?) {
            }
        }
        
        let uri = "http://localhost:8001/socket.io/"
        // Open socket and client together
        var client = SocketIOClient(uri: uri, reconnect: true, timeout: 30, transports:["polling", "websocket"])
        var delegate = TestSocketIOClientDelegate()
        client.delegate = delegate
        
        for i in 0...100 {
            var openExpectation = self.expectationWithDescription("Client open")
            delegate.openExpection = openExpectation
            client.open()
            self.waitForExpectationsWithTimeout(30, handler: nil)
            var closeExpectation = self.expectationWithDescription("Client closed")
            delegate.closeExpectation = closeExpectation
            client.close()
            self.waitForExpectationsWithTimeout(30, handler: nil)
        }
        
        // Now we should also able to process as a normal client
        client.delegate = nil
        client.open()
        var socket = client.socket("echo")
        
        class TestSocketDelegate : SocketIOSocketDelegate {
            var eventExpectation: XCTestExpectation?
            
            init(){}
            
            private func socketOnError(socket: SocketIOSocket, error: String, description: String?) {
                
            }
            private func socketOnEvent(socket: SocketIOSocket, event: String, data: AnyObject?) {
                NSLog("Got event \(event)")
                self.eventExpectation?.fulfill()
                self.eventExpectation = nil
            }
            private func socketOnOpen(socket: SocketIOSocket) {
                
            }
            private func socketOnPacket(socket: SocketIOSocket, packet: SocketIOPacket) {
                
            }
        }
        var socketDelegate = TestSocketDelegate()
        socketDelegate.eventExpectation = self.expectationWithDescription("For event")
        socket.delegate = socketDelegate
        socket.event("message", data: "~~~~~~~~~", ack: nil)
        self.waitForExpectationsWithTimeout(30, handler: nil)
    }
}