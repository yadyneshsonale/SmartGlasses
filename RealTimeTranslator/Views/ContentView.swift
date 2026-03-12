import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = TranslatorViewModel()
    @State private var showSettings = false
    @State private var showConnectionStats = false
    
    var body: some View {
        ZStack {
            
            // Background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.04, green: 0.04, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                
                VStack(spacing: 0) {
                    
                    // Top Bar
                    topBar
                    
                    // Connection Banner
                    connectionBanner
                        .padding(.top, 12)
                    
                    Spacer(minLength: 40)
                    
                    // Main Content
                    mainContent
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .frame(
                    maxWidth: .infinity,
                    minHeight: UIScreen.main.bounds.height
                )
            }
        }
        .preferredColorScheme(.dark)
        
        .sheet(isPresented: $showSettings) {
            SettingsView(
                selectedHost: $viewModel.raspberryPiHost,
                selectedPort: $viewModel.raspberryPiPort,
                onConnect: {}
            )
        }
        
        .sheet(isPresented: $showConnectionStats) {
            ConnectionStatsPanel(
                stats: viewModel.stats,
                status: viewModel.status,
                host: viewModel.raspberryPiHost,
                port: viewModel.raspberryPiPort
            )
        }
        
        .alert("Permission Required", isPresented: $viewModel.showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable speech recognition permissions in Settings.")
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            
            // Stats Button
            Button {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                showConnectionStats = true
            } label: {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                    )
            }
            
            Spacer()
            
            Text("Translator")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Settings Button
            Button {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.8))
                    )
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Connection Banner
    
    private var connectionBanner: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 10) {
                // Status Dot with pulse animation when receiving
                ZStack {
                    if viewModel.isRunning && viewModel.stats.receivedPackets > 0 {
                        Circle()
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 20, height: 20)
                            .scaleEffect(pulseAnimation ? 1.5 : 1.0)
                            .opacity(pulseAnimation ? 0 : 0.5)
                            .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: pulseAnimation)
                    }
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionStatusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    HStack(spacing: 8) {
                        Text("\(viewModel.raspberryPiHost):\(viewModel.raspberryPiPort)")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        
                        if viewModel.isRunning && viewModel.stats.receivedPackets > 0 {
                            Text("•")
                                .foregroundColor(.white.opacity(0.3))
                            Text("\\(viewModel.stats.bytesReceivedFormatted)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.green.opacity(0.8))
                        }
                    }
                }
                
                Spacer()
                
                if viewModel.isRunning {
                    // Live indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.2))
                    )
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.isRunning ? Color.green.opacity(0.08) : Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.isRunning ? Color.green.opacity(0.2) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear { pulseAnimation = true }
    }
    
    @State private var pulseAnimation = false
    
    private var statusColor: Color {
        switch viewModel.status {
        case .idle: return .orange
        case .connecting: return .yellow
        case .connected, .receiving, .translating, .sending: return .green
        case .error: return .red
        }
    }
    
    private var connectionStatusText: String {
        if !viewModel.isRunning {
            return "Tap to configure"
        }
        switch viewModel.status {
        case .idle: return "Ready"
        case .connecting: return "Connecting..."
        case .connected: return "Connected - Waiting for data"
        case .receiving: return "Receiving (\\(viewModel.stats.receivedPackets) packets)"
        case .translating: return "Translating..."
        case .sending: return "Sending response..."
        case .error(let msg): return "Error: \\(msg)"
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(spacing: 28) {
            
            LanguageSelectorRow(
                sourceLanguage: $viewModel.sourceLanguage,
                targetLanguage: $viewModel.targetLanguage,
                onSwap: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        viewModel.swapLanguages()
                    }
                }
            )
            
            StatusCard(
                status: viewModel.status,
                isConnected: viewModel.isRunning
            )
            
            PrimaryControlButton(isActive: viewModel.isRunning) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    
                    if viewModel.isRunning {
                        viewModel.stopPipeline()
                    } else {
                        viewModel.startPipeline()
                    }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    
    func makeBody(configuration: Configuration) -> some View {
        
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}