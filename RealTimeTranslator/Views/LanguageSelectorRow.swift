import SwiftUI

/// Minimal language selector row with dropdown menus and swap button
struct LanguageSelectorRow: View {
    @Binding var sourceLanguage: TranslationLanguage
    @Binding var targetLanguage: TranslationLanguage
    let onSwap: () -> Void
    
    @State private var swapRotation: Double = 0
    
    var body: some View {
        HStack(spacing: 8) {
            // Source Language Picker
            MinimalLanguagePicker(
                selection: $sourceLanguage,
                label: "From"
            )
            
            // Swap Button
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    swapRotation += 180
                }
                onSwap()
            }) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .rotationEffect(.degrees(swapRotation))
                }
            }
            .buttonStyle(MinimalScaleButtonStyle())
            .fixedSize()
            
            // Target Language Picker
            MinimalLanguagePicker(
                selection: $targetLanguage,
                label: "To"
            )
        }
    }
}

// MARK: - Minimal Language Picker
private struct MinimalLanguagePicker: View {
    @Binding var selection: TranslationLanguage
    let label: String
    
    var body: some View {
        Menu {
            ForEach(TranslationLanguage.allCases) { language in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = language
                    }
                }) {
                    HStack {
                        Text(language.flag)
                        Text(language.displayName)
                        if selection == language {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.5)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(selection.flag)
                        .font(.system(size: 16))
                    
                    Text(selection.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    Spacer(minLength: 2)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Minimal Scale Button Style
private struct MinimalScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        LanguageSelectorRow(
            sourceLanguage: .constant(.english),
            targetLanguage: .constant(.spanish),
            onSwap: {}
        )
        .padding()
    }
}
