import SwiftUI

/// Settings view with device discovery and manual connection
struct SettingsView: View {
    @Binding var selectedHost: String
    @Binding var selectedPort: Int
    let onConnect: () -> Void
    
    @StateObject private var discoveryService = DeviceDiscoveryService()
    @Environment(\.dismiss) private var dismiss
    
    @State private var manualHost: String = ""
    @State private var manualPort: String = "8080"
    @State private var showManualEntry: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Current Connection
                        if !selectedHost.isEmpty {
                            CurrentConnectionCard(
                                host: selectedHost,
                                port: selectedPort
                            )
                        }
                        
                        // Device Discovery Section
                        DeviceDiscoverySection(
                            discoveryService: discoveryService,
                            onSelectDevice: { device in
                                selectedHost = device.host
                                selectedPort = device.port
                                onConnect()
                                dismiss()
                            }
                        )
                        
                        // Manual Connection Section
                        ManualConnectionSection(
                            host: $manualHost,
                            port: $manualPort,
                            isExpanded: $showManualEntry,
                            onConnect: {
                                if let portInt = Int(manualPort), !manualHost.isEmpty {
                                    selectedHost = manualHost
                                    selectedPort = portInt
                                    onConnect()
                                    dismiss()
                                }
                            }
                        )
                        
                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            manualHost = selectedHost
            manualPort = "\(selectedPort)"
            discoveryService.startScanning()
        }
        .onDisappear {
            discoveryService.stopScanning()
        }
    }
}

// MARK: - Current Connection Card
private struct CurrentConnectionCard: View {
    let host: String
    let port: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current Connection", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(host)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    
                    Text("Port \(port)")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                Spacer()
                
                Image(systemName: "wifi")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Device Discovery Section
private struct DeviceDiscoverySection: View {
    @ObservedObject var discoveryService: DeviceDiscoveryService
    let onSelectDevice: (DiscoveredDevice) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("AVAILABLE DEVICES")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1)
                
                Spacer()
                
                if discoveryService.isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white.opacity(0.5))
                } else {
                    Button(action: {
                        discoveryService.startScanning()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            // Device List or Empty State
            VStack(spacing: 0) {
                if discoveryService.discoveredDevices.isEmpty {
                    EmptyDeviceState(isScanning: discoveryService.isScanning)
                } else {
                    ForEach(discoveryService.discoveredDevices) { device in
                        DeviceRow(device: device) {
                            onSelectDevice(device)
                        }
                        
                        if device.id != discoveryService.discoveredDevices.last?.id {
                            Divider()
                                .background(.white.opacity(0.1))
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
            
            // Error message
            if let error = discoveryService.scanError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
    }
}

// MARK: - Empty Device State
private struct EmptyDeviceState: View {
    let isScanning: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isScanning ? "antenna.radiowaves.left.and.right" : "wifi.slash")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.3))
            
            Text(isScanning ? "Scanning..." : "No devices found")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            
            if !isScanning {
                Text("Make sure your Raspberry Pi is on the same network")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Device Row
private struct DeviceRow: View {
    let device: DiscoveredDevice
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Device Icon
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "server.rack")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                }
                
                // Device Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    Text(device.host)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                Spacer()
                
                // Latency
                if let latency = device.latencyMs {
                    Text("\(latency)ms")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(latencyColor(latency))
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }
    
    private func latencyColor(_ ms: Int) -> Color {
        if ms < 100 { return .green }
        if ms < 300 { return .yellow }
        return .orange
    }
}

// MARK: - Manual Connection Section
private struct ManualConnectionSection: View {
    @Binding var host: String
    @Binding var port: String
    @Binding var isExpanded: Bool
    let onConnect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text("MANUAL CONNECTION")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            
            // Expandable Content
            if isExpanded {
                VStack(spacing: 16) {
                    // IP Address Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IP Address")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        TextField("192.168.137.252", text: $host)
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }
                    
                    // Port Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Port")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        TextField("8080", text: $port)
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                            .keyboardType(.numberPad)
                    }
                    
                    // Connect Button
                    Button(action: onConnect) {
                        Text("Connect")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .blue.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(host.isEmpty)
                    .opacity(host.isEmpty ? 0.5 : 1.0)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    SettingsView(
        selectedHost: .constant("192.168.137.252"),
        selectedPort: .constant(8080),
        onConnect: {}
    )
}
