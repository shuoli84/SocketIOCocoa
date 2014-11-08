import Foundation

// Converter is the helper utility to convert different types
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
    
    // Convert form byte array to NSString
    public class func bytearrayToNSString(bytes: [Byte]) -> NSString {
        return NSString(bytes: bytes, length: bytes.count, encoding: NSUTF8StringEncoding)!
    }
    
    // Convert from NSString to json object
    public class func nsstringToJSON(str: NSString) -> AnyObject? {
        return self.nsdataToJSON(self.nsstringToNSData(str))
    }
    
    // Convert from NSData to json object
    public class func nsdataToJSON(data: NSData) -> AnyObject? {
        return NSJSONSerialization.JSONObjectWithData(data, options: .MutableContainers, error: nil)
    }
    
    // Convert from JSON to nsdata
    public class func jsonToNSData(json: AnyObject) -> NSData?{
        return NSJSONSerialization.dataWithJSONObject(json, options: .allZeros, error: nil)
    }
    
    // Convert from JSON to nsstring
    public class func jsonToNSString(json: AnyObject) -> NSString?{
        if let data = self.jsonToNSData(json){
            return self.nsdataToNSString(data)
        }
        else{
            return nil
        }
    }
    
    // Convert from JSON to byte array
    public class func jsonToByteArray(json: AnyObject) -> [Byte] {
        if let data = self.jsonToNSData(json) {
            return self.nsdataToByteArray(data)
        }
        else {
            return []
        }
    }
    
    // Convert from byte array to json
    public class func bytearrayToJSON(bytes: [Byte]) -> AnyObject? {
        return self.nsdataToJSON(self.bytearrayToNSData(bytes))
    }
}

// Ascii value enums
enum ASCII: Byte {
    case _0 = 48, _1, _2, _3, _4, _5, _6, _7, _8, _9
    case a = 97, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case A = 65, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z
    case COMMA = 44, DASH = 45, BACKSLASH = 47
}

// Logger
public protocol LoggerProtocol {
    func logPrefix() -> String
}

public class Logger: LoggerProtocol {
    public func logPrefix() -> String {
        return "[Prefix Undefined]"
    }
    
    public func debug(message: String) {
        NSLog("[D]\(self.logPrefix()) \(message)")
    }
    
    public func info(message: String) {
        NSLog("[I]\(self.logPrefix()) \(message)")
    }
}