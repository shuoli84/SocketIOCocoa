//
//  UtilsTests.swift
//  SocketIOCocoa
//
//  Created by LiShuo on 14/11/28.
//  Copyright (c) 2014年 LiShuo. All rights reserved.
//

import Cocoa
import XCTest
import SocketIOCocoa

class UtilsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testContainsBinary() {
        // This is an example of a functional test case.
        XCTAssertFalse(containsBinary("string"))
        XCTAssertFalse(containsBinary(["string", "what"]))
        XCTAssertFalse(containsBinary(["string": "what"]))
        XCTAssertFalse(containsBinary(["string": [1,2,3]]))
        XCTAssertTrue(containsBinary(Converter.nsstringToNSData("what")))
        XCTAssertTrue(containsBinary(["string", Converter.nsstringToNSData("what")]))
        XCTAssertTrue(containsBinary(["string": Converter.nsstringToNSData("what")]))
    }
}
