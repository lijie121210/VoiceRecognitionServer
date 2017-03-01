//
//  ServerApp.swift
//  VGServer
//
//  Created by jie on 2017/2/18.
//  Copyright © 2017年 HTIOT.Inc. All rights reserved.
//

import Cocoa
import CocoaAsyncSocket

public protocol AsyncSocketType {
    
    var socket: GCDAsyncSocket {get set}
    var date: Date {get set}
}

/// AsyncSocket
///
public struct AsyncSocket: Equatable {
    
    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func ==(lhs: AsyncSocket, rhs: AsyncSocket) -> Bool {
        return lhs.socket == rhs.socket && lhs.date == rhs.date
    }

    ///
    
    public var socket: GCDAsyncSocket
    public var date: Date
    
    public var isTimeout: Bool {
        return date.timeIntervalSinceNow > 300
    }
    
    public init(socket: GCDAsyncSocket, date: Date) {
        self.socket = socket
        self.date = date
    }
    
}

extension AsyncSocket: AsyncSocketType {
    
}

/// SerialArray
///
public class SerialArray <T> where T: Equatable {
    
    fileprivate var items: [T] = []
    
    fileprivate let queue: DispatchQueue = DispatchQueue(label: "com.vg.sockets.queue")
    
    public var isEmpty: Bool {
        var empty = false
        queue.sync {
            empty = items.isEmpty
        }
        return empty
    }
    
    public var itemsCount: Int {
        var count = 0
        queue.sync {
            count = items.count
        }
        return count
    }
    
    public subscript(index: Int) -> T {
        get {
            var res: T? = nil
            queue.sync {
                res = items[index]
            }
            return res!
        }
        set(newValue) {
            queue.async {
                self.items[index] = newValue
            }
        }
    }
    
    public func index(of element: T) -> Int? {
        var i: Int? = nil
        queue.sync {
            i = items.index(of: element)
        }
        return i
    }
    
    public func append(element: T) {
        queue.async {
            self.items.append(element)
        }
    }
    
    public func remove(element: T) {
        queue.async {
            guard let i = self.items.index(of: element) else {
                return
            }
            self.items.remove(at: i)
        }
        return
    }
    
    public func removeAll() {
        queue.async {
            self.items.removeAll()
            self.items = []
        }
    }
}


/// Work with SerialArray<AsyncSocket>
public extension SerialArray where T: AsyncSocketType {
    
    public func forEach(_ body: (T) throws -> ()) rethrows {
        try self.items.forEach { (t) in
            try body(t)
        }
    }
    
    public func append(socket: GCDAsyncSocket) {
        
        let workitem = DispatchWorkItem { 
            self.items.append( AsyncSocket(socket: socket, date: Date()) as! T )
        }
        queue.async(execute: workitem)
    }
    
    public func remove(socket: GCDAsyncSocket) {
        
        let workitem = DispatchWorkItem {
            guard
                let s = self.items.first(where: { $0.socket == socket }),
                let i = self.items.index(of: s) else {
                    print(#function, "fail to fetch socket: <socket>")
                    return
            }
            
            self.items.remove(at: i)
        }
        queue.async(execute: workitem)
    }
    
    public func removeAndDisconnect(socket: T) {
        
        let workitem = DispatchWorkItem {
            guard let i = self.items.index(of: socket) else {
                print(#function, "fail to fetch socket: <socket>")
                return
            }
            socket.socket.disconnect()
            self.items.remove(at: i)
        }
        queue.async(execute: workitem)
    }
    
    public func update(socket: GCDAsyncSocket, to date: Date) {
        let workitem = DispatchWorkItem {
            guard
                let s = self.items.first(where: { $0.socket == socket }),
                let i = self.items.index(of: s) else {
                    print(#function, "fail to fetch socket: <socket>")
                    return
            }
            
            self.items[i] = (AsyncSocket(socket: socket, date: date) as! T)
        }
        queue.async(execute: workitem)
    }
    
    public func asyncSocket(of socket: GCDAsyncSocket) -> T? {
        var res: T? = nil
        self.queue.sync {
            res = self.items.first(where: { $0.socket == socket })
        }
        return res
    }

}



public struct SerializedData: Equatable {
    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func ==(lhs: SerializedData, rhs: SerializedData) -> Bool {
        return lhs.json == rhs.json && lhs.type == rhs.type && lhs.size == rhs.size && lhs.data == rhs.data
    }
    
    
    public enum DType: String, Equatable {
        case heartbeat = "heartbeat"
        case image = "image"
        case text = "text"
        case audio = "wav"
    }
    
    public struct DKey {
        
        static let type = "type"
        static let size = "size"
    }
    
    let data: Data
    let json: [String : String]
    let type: DType
    let size: Int
    
    init?(unpack data: Data) {
        guard
            let res = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
            let d = res as? [String:String],
            let t = d[DKey.type],
            let s = d[DKey.size],
            let type = DType(rawValue: t),
            let size = Int(s)
            else {
                return nil
        }
        
        self.json = d
        self.type = type
        self.size = size
        self.data = data
    }
    
    init(pack data: Data = Data(), type: DType = .heartbeat) {
        
        var package = [String:String]()
        package[DKey.type] = type.rawValue
        package[DKey.size] = type == DType.heartbeat ? String(0) : String(data.count)
        
        /// Create the header data from dictionary and append end mark.
        var packagedata = try! JSONSerialization.data(withJSONObject: package, options: .prettyPrinted)
        packagedata.append(GCDAsyncSocket.crlfData())
        
        /// Append real data. So heartbeat data should be Data().
        packagedata.append(data)
        
        self.json = package
        self.type = type
        self.size = data.count
        self.data = packagedata
    }
    
}


/// Server
///
public class Server: NSObject, GCDAsyncSocketDelegate {
    
    public struct Tag {
        static let header = 1
        static let payload = 2
    }
    
    private var acceptedSockets: SerialArray<AsyncSocket>!
    private var socket: GCDAsyncSocket!
    
    /// Heartbeat header will not by stored here, or anywhere.
    private var currentHeader: SerializedData?
    
    /// Check timeout
    private var monitorTimer: DispatchSourceTimer?
    
    deinit {
        print(Date(), self, #function)
        
        socket.delegate = nil
        socket = nil
        
        acceptedSockets.removeAll()
    }
    
    override init() {
        
        socket = GCDAsyncSocket()
        acceptedSockets = SerialArray<AsyncSocket>()
        
        super.init()
        
        socket.setDelegate(self, delegateQueue: DispatchQueue(label: "com.vg.server"))
        
        startMonitor()
    }
    
    
    /// Monitor
    
    public func eventHandler() {
        print(#function, "checking ... ")
        
        guard acceptedSockets.isEmpty == false else {
            return
        }
        
        var needdelete = [AsyncSocket]()
        acceptedSockets.forEach({ (t) in
            if t.isTimeout {
                needdelete.append(t)
            }
        })
        
        for sock in needdelete {
            acceptedSockets.removeAndDisconnect(socket: sock)
        }
    }
    
    public func startMonitor() {
        
        let event = DispatchWorkItem { [weak self] in if let s = self { s.eventHandler() } }
        
        let queue = DispatchQueue(label: "com.vg.mointor", attributes: .concurrent)
        
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.scheduleRepeating(deadline: .now(), interval: .seconds(30), leeway: .seconds(5))
        timer.setEventHandler(handler: event)
        timer.resume()
        
        monitorTimer?.cancel()
        monitorTimer = timer
    }
    
    public func stopMonitor() {
        
        monitorTimer?.cancel()
        monitorTimer = nil
    }
    
    
    /// Socket stack
    
    @discardableResult
    public func listen(on port: Int = 9632) -> Bool {
        do {
            try socket.accept(onPort: UInt16(port))
            print(#function, "socket listening on ", socket.localHost ?? "unknown host:", port )
            return true
        } catch {
            print(#function, "socket listen failed.")
            return false
        }
    }
    
    public func disconnect() {
        socket.disconnect()
        
        socket.delegate = nil
        socket = nil
        
        acceptedSockets.removeAll()
    }

    
    /// GCDAsyncSocketDelegate
    
    public func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        print(self, #function, " new client.")
        
        acceptedSockets.append(socket: newSocket)
        
        newSocket.readData(to: GCDAsyncSocket.crlfData(), withTimeout: -1, tag: Tag.header)
    }
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        print(self, #function, host, port)
    }
    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        print(self, #function, err?.localizedDescription ?? "unknown error.")
        
        acceptedSockets.remove(socket: sock)
    }
    
    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        
        /// update latest online activity time
        acceptedSockets.update(socket: sock, to: Date())
        
        /// parse received data
        
        switch tag {
        case Tag.header:
            
            guard let serializedData = SerializedData(unpack: data) else {
                print(self, #function, "fail to unpack data<\(data)>")
                return
            }
            
            if serializedData.type == .heartbeat {
                print(self, #function, "heartbeat!")
                sock.readData(to: GCDAsyncSocket.crlfData(), withTimeout: -1, tag: Tag.header)
            } else {
                currentHeader = serializedData
                sock.readData(toLength: UInt(serializedData.size), withTimeout: -1, tag: Tag.payload)
            }
        case Tag.payload:
            guard
                let type = currentHeader?.type,
                let size = currentHeader?.size,
                size == data.count else {
                    return print(self, #function, "data size error")
            }
            
            switch type {
            case .audio:
                print("audio!")
                break
            default:
                print("Done!")
                break
            }
            
            currentHeader = nil
            
            sock.readData(to: GCDAsyncSocket.crlfData(), withTimeout: -1, tag: Tag.header)
            
        default:
            break
        }
        
        
    }
}
