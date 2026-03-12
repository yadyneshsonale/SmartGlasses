import SwiftUI

/// Expandable panel showing connection statistics and network details
struct ConnectionStatsPanel: View {
    let stats: PipelineStats
    let status: PipelineStatus
    let host: String
    let port: Int
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Connection Status Section
                        StatsSection(title: "Connection") {
                            StatsRow(
                                icon: "wifi",
                                label: "Status",
                                value: status.label,
                                valueColor: status.color
                            )
                            
                            StatsRow(
                                icon: "server.rack",
                                label: "Device",
                                value: "\(host):\(port)"
                            )
                        }
                        
                        // Network Statistics Section
                        StatsSection(title: "Network Statistics") {
                            StatsRow(
                                icon: "arrow.down.circle",
                                label: "Packets Received",
                                value: "\(stats.receivedPackets)"
                            )
                            
                            StatsRow(
                                icon: "arrow.down.doc",
                                label: "Data Received",
                                value: stats.bytesReceivedFormatted,
                                valueColor: .green
                            )
                            
                            StatsRow(
                                icon: "arrow.up.circle",
                                label: "Packets Sent",
                                value: "\(stats.sentPackets)"
                            )
                            
                            StatsRow(
                                icon: "clock",
                                label: "Average Latency",
                                value: "\(stats.latencyMs) ms",
                                valueColor: latencyColor
                            )
                        }
                        
                        // Buffer Statistics Section
                        StatsSection(title: "Buffer Status") {
                            BufferBar(
                                label: "Incoming Buffer",
                                current: stats.incomingBufferSize,
                                max: 10
                            )
                            
                            BufferBar(
                                label: "Outgoing Buffer",
                                current: stats.outgoingBufferSize,
                                max: 20
                            )
                        }
                        
                        // Processing Statistics Section
                        StatsSection(title: "Processing") {
                            StatsRow(
                                icon: "checkmark.circle",
                                label: "Processed Frames",
                                value: "\(stats.processedFrames)"
                            )
                            
                            StatsRow(
                                icon: "xmark.circle",
                                label: "Dropped Frames",
                                value: "\(stats.droppedFrames)",
                                valueColor: stats.droppedFrames > 0 ? .orange : .white.opacity(0.7)
                            )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Connection Details")
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
    }
    
    private var latencyColor: Color {
        if stats.latencyMs < 100 {
            return .green
        } else if stats.latencyMs < 300 {
            return .yellow
        } else {
            return .orange
        }
    }
}

// MARK: - Stats Section
private struct StatsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1)
            
            VStack(spacing: 12) {
                content
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
        }
    }
}

// MARK: - Stats Row
private struct StatsRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .white.opacity(0.7)
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - Buffer Bar
private struct BufferBar: View {
    let label: String
    let current: Int
    let max: Int
    
    private var fillPercentage: Double {
        guard max > 0 else { return 0 }
        return min(Double(current) / Double(max), 1.0)
    }
    
    private var fillColor: Color {
        if fillPercentage < 0.5 {
            return .green
        } else if fillPercentage < 0.8 {
            return .yellow
        } else {
            return .orange
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                
                Spacer()
                
                Text("\(current) / \(max) frames")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.1))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fillColor)
                        .frame(width: geo.size.width * fillPercentage)
                }
            }
            .frame(height: 8)
        }
    }
}

#Preview {
    ConnectionStatsPanel(
        stats: PipelineStats(
            incomingBufferSize: 4,
            outgoingBufferSize: 2,
            receivedPackets: 1234,
            sentPackets: 1200,
            processedFrames: 1180,
            droppedFrames: 20,
            latencyMs: 420
        ),
        status: .connected,
        host: "192.168.137.252",
        port: 8080
    )
}
