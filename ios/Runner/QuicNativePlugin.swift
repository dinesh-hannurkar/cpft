import Flutter
import Network

class QuicNativePlugin: NSObject, FlutterPlugin {
    private let channel: FlutterMethodChannel
    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.cpft.quic.queue")

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        channel.setMethodCallHandler(self.handle)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            if let args = call.arguments as? [String: Any],
               let port = args["port"] as? Int {
                startListener(port: port)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Port required", details: nil))
            }
            
        case "sendStreamData":
            guard let args = call.arguments as? [String: Any],
                  let ip = args["ip"] as? String,
                  let port = args["port"] as? Int,
                  let streamId = args["streamId"] as? Int,
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            
            sendData(ip: ip, port: port, streamId: streamId, data: data.data)
            result(nil)
            
        case "stop":
            stopListener()
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startListener(port: Int) {
        do {
            let parameters = NWParameters.quic(alpn: ["cpft"])
            // Allow P2P
            parameters.includePeerToPeer = true
            
            if let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) {
                listener = try NWListener(using: parameters, on: nwPort)
                
                listener?.newConnectionHandler = { [weak self] connection in
                    self?.handleNewConnection(connection)
                }
                
                listener?.start(queue: queue)
                NSLog("[QuicNative] Listener started on port \(port)")
            }
        } catch {
            NSLog("[QuicNative] Failed to start listener: \(error)")
        }
    }
    
    private func stopListener() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection)
    }
    
    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] (content, context, isComplete, error) in
            if let data = content, !data.isEmpty {
                // Parse CPFT header? Or assumes raw stream.
                // Pass back to Flutter
                // For simplicity, we assume generic stream 0 for now or parse header
                
                // TODO: Parse StreamID from data if manual framing, 
                // or use QUIC streams if using NWProtocolQUIC
            }
            if error == nil {
                self?.receive(on: connection)
            }
        }
    }
    
    private func sendData(ip: String, port: Int, streamId: Int, data: Data) {
        let key = "\(ip):\(port)"
        let connection: NWConnection
        
        if let existing = connections[key] {
            connection = existing
        } else {
            let host = NWEndpoint.Host(ip)
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port))!
            let params = NWParameters.quic(alpn: ["cpft"])
            params.includePeerToPeer = true
            
            connection = NWConnection(host: host, port: nwPort, using: params)
            connection.start(queue: queue)
            connections[key] = connection
        }
        
        // Send
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                NSLog("[QuicNative] Send error: \(error)")
            }
        }))
    }
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.cpft.quic", binaryMessenger: registrar.messenger())
        let instance = QuicNativePlugin(channel: channel)
        registrar.addMethodCallDelegate(instance as! FlutterPlugin, channel: channel)
        // Note: We need to hold reference to instance
        objc_setAssociatedObject(registrar, "QuicNativePlugin", instance, .OBJC_ASSOCIATION_RETAIN)
    }
}
