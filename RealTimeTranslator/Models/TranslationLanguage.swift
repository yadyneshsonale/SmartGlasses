import Foundation

/// Supported translation languages.
/// Add new cases here and fill in displayName, bcp47Code, locale, and flag.
enum TranslationLanguage: String, CaseIterable, Identifiable {

    // Common
    case english    = "en"
    case spanish    = "es"
    case french     = "fr"
    case german     = "de"
    case italian    = "it"
    case portuguese = "pt"
    case dutch      = "nl"

    // Asian
    case japanese   = "ja"
    case korean     = "ko"
    case chinese    = "zh"

    // South Asian
    case hindi      = "hi"
    case tamil      = "ta"
    case telugu     = "te"
    case bengali    = "bn"

    // Middle Eastern / African
    case arabic     = "ar"
    case turkish    = "tr"
    case swahili    = "sw"

    // Eastern European
    case russian    = "ru"
    case polish     = "pl"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Spanish"
        case .french:     return "French"
        case .german:     return "German"
        case .italian:    return "Italian"
        case .portuguese: return "Portuguese"
        case .dutch:      return "Dutch"
        case .japanese:   return "Japanese"
        case .korean:     return "Korean"
        case .chinese:    return "Chinese"
        case .hindi:      return "Hindi"
        case .tamil:      return "Tamil"
        case .telugu:     return "Telugu"
        case .bengali:    return "Bengali"
        case .arabic:     return "Arabic"
        case .turkish:    return "Turkish"
        case .swahili:    return "Swahili"
        case .russian:    return "Russian"
        case .polish:     return "Polish"
        }
    }

    /// BCP-47 language tag used by AVSpeechSynthesisVoice and Apple Translation
    var bcp47Code: String {
        switch self {
        case .english:    return "en-US"
        case .spanish:    return "es-ES"
        case .french:     return "fr-FR"
        case .german:     return "de-DE"
        case .italian:    return "it-IT"
        case .portuguese: return "pt-BR"
        case .dutch:      return "nl-NL"
        case .japanese:   return "ja-JP"
        case .korean:     return "ko-KR"
        case .chinese:    return "zh-CN"
        case .hindi:      return "hi-IN"
        case .tamil:      return "ta-IN"
        case .telugu:     return "te-IN"
        case .bengali:    return "bn-IN"
        case .arabic:     return "ar-SA"
        case .turkish:    return "tr-TR"
        case .swahili:    return "sw-KE"
        case .russian:    return "ru-RU"
        case .polish:     return "pl-PL"
        }
    }

    /// Locale used for SFSpeechRecognizer
    var locale: Locale {
        Locale(identifier: bcp47Code)
    }

    var flag: String {
        switch self {
        case .english:    return "🇺🇸"
        case .spanish:    return "🇪🇸"
        case .french:     return "🇫🇷"
        case .german:     return "🇩🇪"
        case .italian:    return "🇮🇹"
        case .portuguese: return "🇧🇷"
        case .dutch:      return "🇳🇱"
        case .japanese:   return "🇯🇵"
        case .korean:     return "🇰🇷"
        case .chinese:    return "🇨🇳"
        case .hindi:      return "🇮🇳"
        case .tamil:      return "🇮🇳"
        case .telugu:     return "🇮🇳"
        case .bengali:    return "🇮🇳"
        case .arabic:     return "🇸🇦"
        case .turkish:    return "🇹🇷"
        case .swahili:    return "🇰🇪"
        case .russian:    return "🇷🇺"
        case .polish:     return "🇵🇱"
        }
    }
}
