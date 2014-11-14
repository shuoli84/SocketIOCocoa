SocketIOCocoa
=============

The socket 1.0 client in Swift. It includes xhr polling and websocket transports.

This is a port from socketio.client, which means the code structure are quite similar.

Motivation
=============

For our startup project, We running socketio1.0 in our server, and needs a socketio 1.0 iOS client, I tried my best to find the 
iOS client, but with no luck. 

Installation
=============

Untill CocoaPod's swift library support story completes, it is much easier just copy all files and put them in your project. The
framework way is troublesome and I won't bother to mark them down here.

Files needs to copied:

All swift files under Vender

All swift files under SocketIOCocoa

Usage
=============

ObjC
---------

Create a client

    self.client = [[SocketIOClient alloc] initWithUri: @"http://<server ip>/socket.io/" transports:@[@"polling", @"websocket"] autoConnect:YES reconnect:YES reconnectAttempts:0 reconnectDelay:5 reconnectDelayMax:30 timeout:30];
    [self.client open];

Create a socket

    self.apiSocket = [self.client socket:@"namespace"];
    self.apiSocket.delegate = self;
    
The SocketIOProtocol delegate

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

LINBANG

北京邻邦科技
