import SwiftUI

/// Premium large capsule control button with gradient and animations
struct PrimaryControlButton: View {
    let isActive: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var glowOpacity: Double = 0
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPressed = false
                }
            }
            
            action()
        }) {
            ZStack {
                // Glow effect
                Capsule()
                    .fill(buttonGradient)
                    .blur(radius: 20)
                    .opacity(glowOpacity)
                    .scaleEffect(1.1)
                
                // Main button background
                Capsule()
                    .fill(buttonGradient)
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: buttonShadowColor, radius: 15, x: 0, y: 8)
                
                // Button content
                HStack(spacing: 12) {
                    Image(systemName: isActive ? "stop.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                    
                    Text(isActive ? "Stop Translation" : "Start Translation")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(.white)
                .animation(.easeInOut(duration: 0.3), value: isActive)
            }
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .onAppear {
            startGlowAnimation()
        }
        .onChange(of: isActive) { _ in
            startGlowAnimation()
        }
    }
    
    // MARK: - Computed Properties
    
    private var buttonGradient: LinearGradient {
        if isActive {
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.3, blue: 0.35),
                    Color(red: 0.85, green: 0.2, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.35, green: 0.55, blue: 1.0),
                    Color(red: 0.5, green: 0.35, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var buttonShadowColor: Color {
        isActive
            ? Color(red: 0.9, green: 0.25, blue: 0.3).opacity(0.4)
            : Color(red: 0.4, green: 0.45, blue: 1.0).opacity(0.4)
    }
    
    // MARK: - Animations
    
    private func startGlowAnimation() {
        if isActive {
            withAnimation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true)
            ) {
                glowOpacity = 0.5
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                glowOpacity = 0
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 24) {
            PrimaryControlButton(isActive: false) {}
            PrimaryControlButton(isActive: true) {}
        }
        .padding()
    }
}
