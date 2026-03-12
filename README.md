# RealTimeTranslator

<p align="center">
  <img src="https://img.shields.io/badge/iOS-16.0+-blue.svg" alt="iOS 16.0+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange.svg" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/SwiftUI-5.0-purple.svg" alt="SwiftUI 5.0">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT License">
</p>

A **real-time speech translator** iOS app with **sub-1-second latency** and **offline support**. Designed for live conversations, this app captures speech, transcribes it, translates it to a target language, and speaks the translation aloud — all in near real-time.

Supports integration with a **Raspberry Pi** for remote audio streaming and IoT translation scenarios.

---

## Features

- **Real-Time Translation** — Continuous speech-to-speech translation with ~650ms total latency
- **19 Languages Supported** — Including English, Spanish, French, German, Japanese, Chinese, Hindi, Arabic, and more
- **Offline Capable** — Uses on-device speech recognition and Apple Translation (iOS 26+)
- **Raspberry Pi Integration** — Receive audio streams via WebSocket from remote devices
- **Auto-Reconnect** — Persistent network connection with automatic reconnection
- **Device Discovery** — Bonjour/mDNS discovery of translator devices on local network
- **Modern UI** — Dark-mode SwiftUI interface with real-time status indicators
- **Connection Statistics** — Live monitoring of packets, bytes, latency, and buffer status

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           iOS Device                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────┐    ┌───────────────────┐    ┌──────────────────────┐     │
│   │ AVAudioEngine│ →  │ SFSpeechRecognizer│ →  │  TranslationService  │     │
│   │  (mic input) │    │  (speech-to-text) │    │ (Apple/API/CoreML)   │     │
│   └──────────────┘    └───────────────────┘    └──────────────────────┘     │
│          │                                               │                   │
│          │              ┌──────────────────────┐         │                   │
│          │              │  AVSpeechSynthesizer │ ← ──────┘                   │
│          │              │   (text-to-speech)   │                             │
│          │              └──────────────────────┘                             │
│          │                                                                   │
│          │         ────── OR (Raspberry Pi Mode) ──────                      │
│          │                                                                   │
│   ┌──────────────┐    ┌───────────────────┐    ┌──────────────────────┐     │
│   │  WebSocket   │ →  │  IncomingAudioBuf │ →  │  TranslationWorker   │     │
│   │  Receiver    │    │   (ring buffer)   │    │  (STT + Translate)   │     │
│   └──────────────┘    └───────────────────┘    └──────────────────────┘     │
│                                                          │                   │
│                       ┌───────────────────┐              │                   │
│                       │  OutgoingAudioBuf │ ← ───────────┘                   │
│                       │   (TTS output)    │                                  │
│                       └───────────────────┘                                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Latency Breakdown

| Stage | Target Latency |
|-------|----------------|
| Speech Recognition | ~300ms |
| Translation | ~150ms |
| TTS Playback Start | ~200ms |
| **Total** | **~650ms** |

---

## Supported Languages

| Language | Code | Flag | Language | Code | Flag |
|----------|------|------|----------|------|------|
| English | en-US | 🇺🇸 | Hindi | hi-IN | 🇮🇳 |
| Spanish | es-ES | 🇪🇸 | Tamil | ta-IN | 🇮🇳 |
| French | fr-FR | 🇫🇷 | Telugu | te-IN | 🇮🇳 |
| German | de-DE | 🇩🇪 | Bengali | bn-IN | 🇮🇳 |
| Italian | it-IT | 🇮🇹 | Arabic | ar-SA | 🇸🇦 |
| Portuguese | pt-BR | 🇧🇷 | Turkish | tr-TR | 🇹🇷 |
| Dutch | nl-NL | 🇳🇱 | Swahili | sw-KE | 🇰🇪 |
| Japanese | ja-JP | 🇯🇵 | Russian | ru-RU | 🇷🇺 |
| Korean | ko-KR | 🇰🇷 | Polish | pl-PL | 🇵🇱 |
| Chinese | zh-CN | 🇨🇳 | | | |

---

## Requirements

- **Xcode 15+** (or later)
- **iOS 16.0+** deployment target
- **Physical iPhone** — Microphone not available in Simulator
- **Apple Developer Account** — Free tier works for device testing
- **Raspberry Pi** *(optional)* — For remote audio streaming

---

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/RealTimeTranslator.git
cd RealTimeTranslator
```

### 2. Open in Xcode

```bash
open RealTimeTranslator.xcodeproj
```

### 3. Configure Signing

1. Select the project in Xcode Navigator
2. Go to **Signing & Capabilities**
3. Select your **Team** (Personal Team works for testing)
4. Ensure automatic signing is enabled

### 4. Build and Run

1. Connect your iPhone via USB
2. Select your device as the build target
3. Press **Cmd + R** to build and run

---

## Usage

### Basic Translation (Microphone Mode)

1. **Launch the app** on your iPhone
2. **Select source language** (the language you'll speak)
3. **Select target language** (the language for translation)
4. **Tap the microphone button** to start
5. **Speak** — the app will transcribe, translate, and speak the translation
6. **Tap again** to stop

### Raspberry Pi Mode

1. **Configure connection** — Tap the settings icon (⚙️)
2. **Enter Raspberry Pi IP** and port (default: 8080)
3. **Tap Connect** — The app will establish a WebSocket connection
4. **Stream audio** from your Raspberry Pi — The app processes incoming audio

### Connection Statistics

Tap the chart icon (📊) to view:
- Incoming/outgoing buffer sizes
- Received packets and bytes
- Current latency
- Connection status

---

## Raspberry Pi Setup

For Raspberry Pi integration, your Pi should run a WebSocket server that streams audio:

### Audio Format Requirements

- **Format**: PCM 16-bit signed integer
- **Sample Rate**: 16,000 Hz
- **Channels**: Mono (1 channel)
- **Encoding**: Little-endian

### WebSocket Endpoints

| Endpoint | Port | Purpose |
|----------|------|---------|
| `/audio` | 8080 | Receive audio from Pi |
| `/audio` | 8081 | Send translated audio to Pi |

### Bonjour/mDNS Discovery

For automatic device discovery, advertise your service as:
```
Service Type: _translator._tcp
```

---

## Project Structure

```
RealTimeTranslator/
├── RealTimeTranslatorApp.swift        # App entry point
│
├── Views/
│   ├── ContentView.swift              # Main SwiftUI interface
│   ├── SettingsView.swift             # Connection settings
│   ├── ConnectionStatsPanel.swift     # Stats overlay
│   ├── StatusCard.swift               # Status display component
│   ├── LanguageSelectorRow.swift      # Language picker row
│   ├── PrimaryControlButton.swift     # Main action button
│   └── GrainientBackground.swift      # Custom background
│
├── ViewModels/
│   └── TranslatorViewModel.swift      # Main app state & orchestration
│
├── Services/
│   ├── SpeechRecognitionService.swift # AVAudioEngine + Speech framework
│   ├── TranslationService.swift       # Apple Translation / API fallback
│   ├── TTSService.swift               # AVSpeechSynthesizer wrapper
│   ├── NetworkReceiver.swift          # WebSocket client (incoming)
│   ├── NetworkSender.swift            # WebSocket client (outgoing)
│   ├── TranslationWorker.swift        # Background processing pipeline
│   ├── IncomingAudioBuffer.swift      # Ring buffer for received audio
│   ├── OutgoingAudioBuffer.swift      # Ring buffer for TTS output
│   └── DeviceDiscoveryService.swift   # Bonjour/mDNS device discovery
│
├── Models/
│   └── TranslationLanguage.swift      # 19 supported languages enum
│
└── Resources/
    ├── Info.plist                     # Permissions & app metadata
    └── CoreMLConversionGuide.md       # Guide for offline models
```

---

## Translation Backends

The app uses a tiered translation approach:

### 1. Apple Translation Framework (iOS 26+)
- **Primary** method when available
- Fully on-device, no network required
- Best quality and lowest latency

### 2. MyMemory API (Fallback)
- Free translation API (5,000 chars/day)
- No API key required
- Network connection needed

### 3. Demo Simulation (Last Resort)
- Basic hardcoded translations for common phrases
- Works completely offline
- Limited vocabulary

---

## Permissions

The app requires the following permissions (configured in `Info.plist`):

| Permission | Purpose |
|------------|---------|
| **Microphone** | Capture speech for translation |
| **Speech Recognition** | Convert speech to text |

Users will be prompted to grant these permissions on first launch.

---

## Configuration

### Network Settings

Edit in Settings view or modify defaults in `TranslatorViewModel.swift`:

```swift
@Published var raspberryPiHost: String = "192.168.137.252"
@Published var raspberryPiPort: Int = 8080
```

### Translation Service

To use a custom CoreML model, see `Resources/CoreMLConversionGuide.md`.

---

## Technical Details

### Audio Processing

- **Input Format**: 16-bit PCM, 16kHz, mono
- **Buffer Size**: 1024 samples per frame
- **Ring Buffer**: Holds 10-20 frames for smooth processing

### Network Protocol

- **Transport**: WebSocket (ws://)
- **Reconnect**: Auto-reconnect with exponential backoff
- **Max Attempts**: 10 reconnection attempts
- **Ping Interval**: Keepalive for connection stability

### Speech Recognition

- Uses `SFSpeechRecognizer` with streaming recognition
- Supports partial results for real-time feedback
- Silence detection (1.5s threshold) for utterance boundaries

---

## Troubleshooting

### "Microphone not available"

- Simulator doesn't support microphone — use a physical device
- Check microphone permissions in Settings → RealTimeTranslator

### "Speech recognizer unavailable"

- Ensure speech recognition permission is granted
- Some languages may not be available on-device
- Check internet connection for cloud recognition

### Connection Issues

- Verify Raspberry Pi IP address is correct
- Ensure both devices are on the same network
- Check firewall settings on Pi (ports 8080-8081)
- Try manual IP entry if Bonjour discovery fails

### Translation Not Working

- Apple Translation requires iOS 26+ for on-device
- MyMemory API has daily limits (5,000 chars)
- Check network connectivity for API fallback

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Apple Speech Framework for on-device recognition
- Apple Translation Framework for neural translation
- AVFoundation for audio processing and TTS
- MyMemory API for translation fallback



---

<p align="center">
Made with ❤️ for real-time communication across language barriers
</p>
