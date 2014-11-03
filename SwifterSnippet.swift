//
//  SwifterSnippet.swift
//  SocketIOCocoa
//
//  Created by LiShuo on 14/11/3.
//  Copyright (c) 2014年 LiShuo. All rights reserved.
//

import Foundation

public extension String {
    public func urlEncodedStringWithEncoding(encoding: NSStringEncoding) -> String {
        let charactersToBeEscaped = ":/?&=;+!@#$()',*" as CFStringRef
        let charactersToLeaveUnescaped = "[]." as CFStringRef
        
        let str = self as NSString
        
        let result = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, str as CFString, charactersToLeaveUnescaped, charactersToBeEscaped, CFStringConvertNSStringEncodingToEncoding(encoding)) as NSString
        
        return result as String
    }
    
    public func parametersFromQueryString() -> Dictionary<String, String> {
        var parameters = Dictionary<String, String>()
        
        let scanner = NSScanner(string: self)
        
        var key: NSString?
        var value: NSString?
        
        while !scanner.atEnd {
            key = nil
            scanner.scanUpToString("=", intoString: &key)
            scanner.scanString("=", intoString: nil)
            
            value = nil
            scanner.scanUpToString("&", intoString: &value)
            scanner.scanString("&", intoString: nil)
            
            if key != nil && value != nil {
                parameters.updateValue(value!, forKey: key!)
            }
        }
        
        return parameters
    }
}

extension Dictionary {
    func queryStringWithEncoding() -> String {
        var parts = [String]()
        
        for (key, value) in self {
            let keyString: String = "\(key)"
            let valueString: String = "\(value)"
            let query: String = "\(keyString)=\(valueString)"
            parts.append(query)
        }
        
        return join("&", parts)
    }
    
    func urlEncodedQueryStringWithEncoding(encoding: NSStringEncoding) -> String {
        var parts = [String]()
        
        for (key, value) in self {
            let keyString: String = "\(key)".urlEncodedStringWithEncoding(encoding)
            let valueString: String = "\(value)".urlEncodedStringWithEncoding(encoding)
            let query: String = "\(keyString)=\(valueString)"
            parts.append(query)
        }
        
        return join("&", parts)
    }
}