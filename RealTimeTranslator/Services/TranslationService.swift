import Foundation
import NaturalLanguage
import Translation

/// TranslationService handles translation using Apple's Translation framework (iOS 17.4+)
/// with a fallback to a pluggable CoreML model.
///
/// To swap in a CoreML model:
///   1. Drag your .mlpackage into the Xcode project
///   2. Replace the `translateWithCoreML` method body
///   3. Remove or disable the `translateWithAppleAPI` method
class TranslationService {

    // MARK: - Main Entry Point
    func translate(text: String, from source: TranslationLanguage, to target: TranslationLanguage) async -> String {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }

        // Attempt Apple Translation framework first (iOS 26+)
        if #available(iOS 26.0, *) {
            if let result = await translateWithAppleTranslation(text: text, from: source, to: target) {
                return result
            }
        }

        // Fallback: Use LibreTranslate API or demo
        return await translateWithFallback(text: text, from: source, to: target)
    }

    // MARK: - Apple Translation Framework (iOS 26+)
    @available(iOS 26.0, *)
    private func translateWithAppleTranslation(
        text: String,
        from source: TranslationLanguage,
        to target: TranslationLanguage
    ) async -> String? {
        do {
            let sourceLanguage = Locale.Language(identifier: source.bcp47Code)
            let targetLanguage = Locale.Language(identifier: target.bcp47Code)
            
            let session = try TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
            let response = try await session.translate(text)
            
            return response.targetText
        } catch {
            print("Apple Translation error:", error)
            return nil
        }
    }

    // MARK: - Fallback Translation (Free API)
    /// Uses MyMemory free translation API as fallback
    /// Free tier: 5000 chars/day, no API key needed
    private func translateWithFallback(
        text: String,
        from source: TranslationLanguage,
        to target: TranslationLanguage
    ) async -> String {
        // Try MyMemory API (free, no key required)
        let langPair = "\(source.bcp47Code)|\(target.bcp47Code)"
        
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: langPair)
        ]
        
        guard let url = components?.url else {
            return simulateTranslation(text: text, from: source, to: target)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return simulateTranslation(text: text, from: source, to: target)
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseData = json["responseData"] as? [String: Any],
               let translatedText = responseData["translatedText"] as? String {
                // Check for error responses
                if translatedText.uppercased().contains("PLEASE USE POST METHOD") ||
                   translatedText.uppercased().contains("QUERY LENGTH LIMIT") {
                    return simulateTranslation(text: text, from: source, to: target)
                }
                return translatedText
            }
        } catch {
            print("Translation API error:", error)
        }
        
        // Final fallback to simulation
        return simulateTranslation(text: text, from: source, to: target)
    }

    // MARK: - Demo Simulation
    /// Stub translation used when API fails
    private func simulateTranslation(text: String, from source: TranslationLanguage, to target: TranslationLanguage) -> String {
        let prefix = "[\(target.displayName)] "

        // Very small hardcoded demo glossary
        let demos: [String: [String: String]] = [
            "hello": ["es": "hola", "fr": "bonjour", "de": "hallo", "hi": "नमस्ते", "ta": "வணக்கம்", "ja": "こんにちは", "zh": "你好", "ar": "مرحبا"],
            "goodbye": ["es": "adiós", "fr": "au revoir", "de": "auf Wiedersehen", "hi": "अलविदा", "ta": "விடைபெறுகிறேன்", "ja": "さようなら", "zh": "再见", "ar": "وداعا"],
            "thank you": ["es": "gracias", "fr": "merci", "de": "danke", "hi": "धन्यवाद", "ta": "நன்றி", "ja": "ありがとう", "zh": "谢谢", "ar": "شكرا"],
            "how are you": ["es": "¿cómo estás?", "fr": "comment allez-vous?", "de": "wie geht es dir?", "hi": "आप कैसे हैं?", "ta": "நீங்கள் எப்படி இருக்கிறீர்கள்?"],
        ]

        let lower = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if let entry = demos[lower], let translated = entry[target.bcp47Code] {
            return translated
        }

        return prefix + text
    }
}
