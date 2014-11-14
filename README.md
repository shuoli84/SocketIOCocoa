SocketIOCocoa
=============

The socket 1.0 client in Swift. It includes xhr polling and websocket transports.

This is a port from socketio.client, which means the code structure are quite similar.

Motivation & Contribute
=============

For our startup project, we running socketio1.0 in our server, and needs an iOS client. I tried my best to find the 
iOS client, but with no luck.

I am still dogfooding it, any issue report, pull request are welcomed.

Installation
=============

Untill CocoaPod's swift library support story completes, it is much easier just copy all files and put them in your project. The
framework way is troublesome and I won't bother to mark them down here.

Files needs to copied:

All swift files under Vender

All swift files under SocketIOCocoa

Usage
=============

Swift
---------

Create a client

```swift 
var client = SocketIOClient(uri: uri, reconnect: true, timeout: 30)
client.open()
```    
    
Create a socket

```swift    
var socket = client.socket("namespace")
// Set a delegate on socket
```

The SocketIOSocketDelegate

```swift
@objc public protocol SocketIOSocketDelegate {
    // Called when the socket received a low level packet
    optional func socketOnPacket(socket: SocketIOSocket, packet: SocketIOPacket)
    
    // Called when the socket received an event
    func socketOnEvent(socket: SocketIOSocket, event: String, data: AnyObject?)
    
    // Called when the socket is open
    func socketOnOpen(socket: SocketIOSocket)
    
    // Called when the socket is on error
    func socketOnError(socket: SocketIOSocket, error: String, description: String?)
}
```

ObjC
---------

Create a client
```objc
self.client = [[SocketIOClient alloc] initWithUri: @"http://<server ip>/socket.io/" transports:@[@"polling", @"websocket"] autoConnect:YES reconnect:YES reconnectAttempts:0 reconnectDelay:5 reconnectDelayMax:30 timeout:30];
[self.client open];
```

Create a socket

```objc
self.apiSocket = [self.client socket:@"namespace"];
self.apiSocket.delegate = self;
```

The SocketIOSocketDelegate

Socket received event with data
   
    - (void)socketOnEvent:(SocketIOSocket *)socket event:(NSString *)event data:(id)data

Socket on open
   
    - (void)socketOnOpen:(SocketIOSocket *)socket{

Socket on error, description is a detailed message for the error
   
    - (void)socketOnError:(SocketIOSocket *)socket error:(NSString *)error description:(NSString *)description
    
Socket on packet, lower level packet, used to tracking socket activity.
   
    - (void)socketOnPacket:(SocketIOSocket *)socket packet:(SocketIOPacket *)packet;
    
Under the hood
=============

Alamofire for xhr polling, starscream for websocket. GCD for async tasks.

TODO
=============

Test and fix ACK

Performance enhaucement

LICENSE
=============
MIT

CREDIT
=============

Linbang 北京邻邦科技
* **Twitter:** [@shuoli84](https://twitter.com/shuoli84)
* **Tip me:** [Tip](https://gratipay.com/shuoli84/)
