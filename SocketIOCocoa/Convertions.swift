//
//  Convertions.swift
//  SocketIOCocoa
//
//  Created by LiShuo on 14/11/1.
//  Copyright (c) 2014年 LiShuo. All rights reserved.
//

import Foundation

class Converter {
    // Convert from NSString -> NSData
    class func nsstringToNSData(str : NSString) -> NSData {
        return str.dataUsingEncoding(NSUTF8StringEncoding)!
    }

    // Convert from NSData -> NSString
    class func nsdataToNSString(data: NSData) -> NSString {
        return NSString(data: data, encoding: NSUTF8StringEncoding)!
    }

    // Convert from [Byte] -> NSData
    class func bytearrayToNSData(arr: [Byte]) -> NSData {
        return NSData(bytes: arr, length: arr.count)
    }

    // Convert from NSData -> [Byte]
    class func nsdataToByteArray(data: NSData) -> [Byte] {
        var array = [Byte](count:data.length, repeatedValue: 0)
        data.getBytes(&array, length: data.length)
        return array
    }

    // Convert from NSString to byte array
    class func nsstringToByteArray(str: NSString) -> [Byte] {
        return nsdataToByteArray(nsstringToNSData(str))
    }
}