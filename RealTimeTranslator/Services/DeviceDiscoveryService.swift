import Foundation
import Network
import Combine

/// Discovered device on local network
struct DiscoveredDevice: Identifiable, Equatable {
    let id: String
    var name: String
    let host: String
    let port: Int
    var latencyMs: Int?
    var isReachable: Bool = false
    
    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Service for discovering Raspberry Pi devices on local network using Bonjour/mDNS
@MainActor
class DeviceDiscoveryService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning: Bool = false
    @Published var scanError: String?
    
    // MARK: - Private Properties
    
    private var browser: NWBrowser?
    private var connections: [String: NWConnection] = [:]
    private var pingTasks: [String: Task<Void, Never>] = [:]
    
    /// Service type for Raspberry Pi translator service
    /// The Raspberry Pi should advertise: _translator._tcp
    private let serviceType = "_translator._tcp"
    
    // MARK: - Scanning
    
    /// Start scanning for devices on local network
    func startScanning() {
        guard !isScanning else { return }
        
        isScanning = true
        scanError = nil
        discoveredDevices = []
        
        // Create NWBrowser for Bonjour discovery
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleBrowserState(state)
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results, changes: changes)
            }
        }
        
        browser?.start(queue: .main)
        
        // Also try UDP broadcast scan as fallback
        performUDPScan()
    }
    
    /// Stop scanning
    func stopScanning() {
        browser?.cancel()
        browser = nil
        isScanning = false
        
        // Cancel ping tasks
        pingTasks.values.forEach { $0.cancel() }
        pingTasks.removeAll()
        
        // Cancel connections
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }
    
    // MARK: - Manual Connection
    
    /// Add a manual device entry
    func addManualDevice(host: String, port: Int) {
        let device = DiscoveredDevice(
            id: "\(host):\(port)",
            name: "Manual Device",
            host: host,
            port: port,
            latencyMs: nil,
            isReachable: false
        )
        
        // Check if already exists
        if !discoveredDevices.contains(where: { $0.id == device.id }) {
            discoveredDevices.append(device)
            checkDeviceReachability(device)
        }
    }
    
    // MARK: - Private Methods
    
    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            scanError = nil
        case .failed(let error):
            scanError = "Discovery failed: \(error.localizedDescription)"
            isScanning = false
        case .cancelled:
            isScanning = false
        default:
            break
        }
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                resolveEndpoint(result)
            case .removed(let result):
                removeDevice(for: result)
            default:
                break
            }
        }
    }
    
    private func resolveEndpoint(_ result: NWBrowser.Result) {
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    if let endpoint = connection.currentPath?.remoteEndpoint,
                       case .hostPort(let host, let port) = endpoint {
                        let hostString = "\(host)"
                        let portInt = Int(port.rawValue)
                        
                        let device = DiscoveredDevice(
                            id: "\(hostString):\(portInt)",
                            name: self?.extractName(from: result) ?? "Raspberry Pi",
                            host: hostString,
                            port: portInt,
                            latencyMs: nil,
                            isReachable: true
                        )
                        
                        if !(self?.discoveredDevices.contains(where: { $0.id == device.id }) ?? true) {
                            self?.discoveredDevices.append(device)
                            self?.measureLatency(for: device)
                        }
                    }
                    connection.cancel()
                case .failed:
                    connection.cancel()
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func extractName(from result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint {
            return name
        }
        return "Raspberry Pi"
    }
    
    private func removeDevice(for result: NWBrowser.Result) {
        if case .service(let name, _, _, _) = result.endpoint {
            discoveredDevices.removeAll { $0.name == name }
        }
    }
    
    // MARK: - UDP Broadcast Scan
    
    private func performUDPScan() {
        // Scan common IP ranges for translator service
        let baseIPs = getLocalNetworkBase()
        
        for baseIP in baseIPs {
            for i in 1...254 {
                let host = "\(baseIP).\(i)"
                let device = DiscoveredDevice(
                    id: "\(host):8080",
                    name: "Scanning...",
                    host: host,
                    port: 8080
                )
                checkDeviceReachability(device)
            }
        }
    }
    
    private func getLocalNetworkBase() -> [String] {
        var bases: [String] = []
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return ["192.168.1", "192.168.0", "10.0.0"]
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    
                    if getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if let lastDot = ip.lastIndex(of: ".") {
                            let base = String(ip[..<lastDot])
                            if !bases.contains(base) {
                                bases.append(base)
                            }
                        }
                    }
                }
            }
            
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        
        return bases.isEmpty ? ["192.168.1"] : bases
    }
    
    private func checkDeviceReachability(_ device: DiscoveredDevice) {
        let connection = NWConnection(
            host: NWEndpoint.Host(device.host),
            port: NWEndpoint.Port(integerLiteral: UInt16(device.port)),
            using: .tcp
        )
        
        let deviceId = device.id
        connections[deviceId] = connection
        
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms timeout
            connection.cancel()
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                timeout.cancel()
                
                switch state {
                case .ready:
                    // Device is reachable - add if not already present
                    if !(self?.discoveredDevices.contains(where: { $0.id == deviceId }) ?? true) {
                        var reachableDevice = device
                        reachableDevice.name = "Raspberry Pi"
                        reachableDevice.isReachable = true
                        self?.discoveredDevices.append(reachableDevice)
                        self?.measureLatency(for: reachableDevice)
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    self?.connections.removeValue(forKey: deviceId)
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .main)
    }
    
    // MARK: - Latency Measurement
    
    private func measureLatency(for device: DiscoveredDevice) {
        pingTasks[device.id] = Task {
            let start = CFAbsoluteTimeGetCurrent()
            
            let connection = NWConnection(
                host: NWEndpoint.Host(device.host),
                port: NWEndpoint.Port(integerLiteral: UInt16(device.port)),
                using: .tcp
            )
            
            // Use a class to track if continuation was already resumed
            final class ContinuationState: @unchecked Sendable {
                var hasResumed = false
                let lock = NSLock()
                
                func tryResume(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if hasResumed { return false }
                    hasResumed = true
                    continuation.resume()
                    return true
                }
            }
            
            let state = ContinuationState()
            
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                connection.stateUpdateHandler = { [weak self] connState in
                    switch connState {
                    case .ready:
                        let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                        Task { @MainActor in
                            if let index = self?.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                                self?.discoveredDevices[index].latencyMs = latency
                            }
                        }
                        connection.cancel()
                        _ = state.tryResume(continuation)
                    case .failed, .cancelled:
                        _ = state.tryResume(continuation)
                    default:
                        break
                    }
                }
                connection.start(queue: .main)
                
                // Timeout after 2 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if state.tryResume(continuation) {
                        connection.cancel()
                    }
                }
            }
        }
    }
}
