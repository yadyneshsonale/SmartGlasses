import SwiftUI

/// Minimal floating glass status card
struct StatusCard: View {
    let status: PipelineStatus
    let isConnected: Bool
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0
    
    var body: some View {
        VStack(spacing: 20) {
            // Status Indicator
            ZStack {
                // Outer pulse ring (only when active)
                if status.isActive {
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 56, height: 56)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                }
                
                // Main indicator circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [statusColor, statusColor.opacity(0.6)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 20
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: statusColor.opacity(0.5), radius: 12, x: 0, y: 4)
                
                // Icon
                statusIcon
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 60, height: 60)
            
            // Status Text
            VStack(spacing: 6) {
                Text(statusTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text(statusSubtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .animation(.easeInOut(duration: 0.3), value: status)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        .onAppear {
            startPulseAnimation()
        }
        .onChange(of: status) { _ in
            startPulseAnimation()
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        switch status {
        case .idle:
            return Color(white: 0.5)
        case .connecting:
            return .orange
        case .connected:
            return .blue
        case .receiving:
            return .green
        case .translating:
            return .purple
        case .sending:
            return .cyan
        case .error:
            return .red
        }
    }
    
    private var statusIcon: Image {
        switch status {
        case .idle:
            return Image(systemName: "circle")
        case .connecting:
            return Image(systemName: "antenna.radiowaves.left.and.right")
        case .connected:
            return Image(systemName: "checkmark")
        case .receiving:
            return Image(systemName: "waveform")
        case .translating:
            return Image(systemName: "globe")
        case .sending:
            return Image(systemName: "arrow.up")
        case .error:
            return Image(systemName: "exclamationmark")
        }
    }
    
    private var statusTitle: String {
        switch status {
        case .idle:
            return "Ready"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .receiving:
            return "Receiving Audio"
        case .translating:
            return "Translating"
        case .sending:
            return "Sending Response"
        case .error(let message):
            return message.isEmpty ? "Error" : "Error"
        }
    }
    
    private var statusSubtitle: String {
        switch status {
        case .idle:
            return "Tap Start to begin translation"
        case .connecting:
            return "Establishing connection..."
        case .connected:
            return "Connected to Raspberry Pi"
        case .receiving:
            return "Processing incoming audio"
        case .translating:
            return "Converting speech to text"
        case .sending:
            return "Transmitting translated audio"
        case .error(let message):
            return message
        }
    }
    
    // MARK: - Animations
    
    private func startPulseAnimation() {
        guard status.isActive else {
            withAnimation(.easeOut(duration: 0.3)) {
                pulseScale = 1.0
                pulseOpacity = 0
            }
            return
        }
        
        pulseScale = 1.0
        pulseOpacity = 1.0
        
        withAnimation(
            .easeOut(duration: 1.5)
            .repeatForever(autoreverses: false)
        ) {
            pulseScale = 1.8
            pulseOpacity = 0
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        StatusCard(status: .receiving, isConnected: true)
            .padding()
    }
}
