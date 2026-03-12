# CoreML Conversion Guide
## Adding Offline Translation to RealTimeTranslator

This guide shows how to convert a HuggingFace translation model to CoreML
so the app can translate fully offline on-device.

---

## 1. Choose Your Model

| Model | Size | Languages | Best For |
|-------|------|-----------|----------|
| Helsinki-NLP/opus-mt-en-es | ~300 MB | EN→ES | Fast, single pair |
| Helsinki-NLP/opus-mt-ROMANCE | ~300 MB | EN→FR/ES/PT/IT | Multi-Romance |
| facebook/nllb-200-distilled-600M | ~2.4 GB | 200 languages | Maximum coverage |
| facebook/m2m100_418M | ~1.6 GB | 100 languages | Good balance |

For <1s latency on iPhone, MarianMT (Helsinki-NLP) models are recommended.

---

## 2. Install Conversion Tools

```bash
pip install coremltools transformers torch sentencepiece
```

---

## 3. Convert MarianMT to CoreML

```python
# convert_marian.py
import coremltools as ct
import torch
from transformers import MarianMTModel, MarianTokenizer

MODEL_NAME = "Helsinki-NLP/opus-mt-en-es"
OUTPUT_PATH = "TranslationModel_en_es.mlpackage"

# Load model
tokenizer = MarianTokenizer.from_pretrained(MODEL_NAME)
model = MarianMTModel.from_pretrained(MODEL_NAME)
model.eval()

# Trace with example input
text = "Hello, how are you?"
inputs = tokenizer([text], return_tensors="pt", padding=True)

with torch.no_grad():
    traced = torch.jit.trace(
        model,
        (inputs["input_ids"], inputs["attention_mask"]),
        strict=False
    )

# Convert to CoreML
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="input_ids", shape=inputs["input_ids"].shape, dtype=int),
        ct.TensorType(name="attention_mask", shape=inputs["attention_mask"].shape, dtype=int),
    ],
    compute_units=ct.ComputeUnit.ALL,  # Use Neural Engine
    minimum_deployment_target=ct.target.iOS16,
)

mlmodel.save(OUTPUT_PATH)
print(f"Saved to {OUTPUT_PATH}")
```

Run it:
```bash
python convert_marian.py
```

---

## 4. Add Model to Xcode

1. Drag `TranslationModel_en_es.mlpackage` into your Xcode project
2. Check "Copy items if needed"
3. Add to target: RealTimeTranslator ✓

Xcode auto-generates Swift bindings. You'll get classes like:
- `TranslationModel_en_es`
- `TranslationModel_en_esInput`
- `TranslationModel_en_esOutput`

---

## 5. Update TranslationService.swift

Replace the `translateWithCoreML` method body:

```swift
private func translateWithCoreML(
    text: String,
    from source: TranslationLanguage,
    to target: TranslationLanguage
) async -> String {
    guard let model = try? TranslationModel_en_es() else { return text }

    // Tokenize (implement or use a Swift tokenizer library)
    let inputIds = tokenize(text: text, tokenizer: marianTokenizer)
    let attentionMask = Array(repeating: 1, inputIds.count)

    let input = TranslationModel_en_esInput(
        input_ids: inputIds,
        attention_mask: attentionMask
    )

    guard let output = try? model.prediction(input: input) else { return text }
    return detokenize(output.logits)
}
```

**Note**: You'll also need a Swift tokenizer for MarianMT.
Options:
- [swift-transformers](https://github.com/huggingface/swift-transformers) by HuggingFace
- Bundle the SentencePiece vocabulary file and call it via a thin wrapper

---

## 6. Using Apple's Translation Framework (Easiest, iOS 17.4+)

For most use cases, Apple's built-in Translation framework is simpler
and requires no model conversion:

```swift
import Translation

// In TranslationService.swift
@available(iOS 17.4, *)
func translateWithAppleTranslation(text: String, from: TranslationLanguage, to: TranslationLanguage) async -> String? {
    let config = TranslationSession.Configuration(
        source: Locale.Language(identifier: from.bcp47Code),
        target: Locale.Language(identifier: to.bcp47Code)
    )
    let session = TranslationSession(configuration: config)
    guard let response = try? await session.translate(text) else { return nil }
    return response.targetText
}
```

Models download once (~50–200MB per language pair), then run fully offline.
This is already wired up in TranslationService.swift — just uncomment the block.

---

## 7. Expected Performance

| Approach | Latency | Offline | Languages |
|----------|---------|---------|-----------|
| Apple Translation (iOS 17.4+) | 80–200ms | ✓ (after download) | ~20 |
| MarianMT CoreML | 100–300ms | ✓ | 1000+ pairs |
| NLLB-200 CoreML | 200–500ms | ✓ | 200 |

Total pipeline (speech + translation + TTS) ≈ **600–900ms** — under 1 second.
