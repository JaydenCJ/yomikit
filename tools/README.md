# YomiKit model tools

Python scripts for bringing your own recognition model to YomiKit's
`CoreMLTextRecognizer`. YomiKit ships **no model weights** — on Apple
platforms it uses Apple Vision out of the box, and these scripts exist for
users who want a custom Japanese recognition model instead.

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r tools/requirements.txt
```

## Scripts

### `convert_recognizer.py`

Converts a TorchScript CTC recognition model (line image in, per-timestep
class logits out) to a Core ML `.mlpackage` plus a `-vocab.json` file. The
input feature is named `image` and the output `logits`, matching the Swift
side's `CoreMLTextRecognizer.Configuration` defaults.

```bash
python3 tools/convert_recognizer.py \
  --checkpoint recognizer_traced.pt \
  --vocab vocab.txt \
  --width 320 --height 48 \
  --output JapaneseRecognizer
```

### `distill_recognizer.py`

Distills a heavy server-side recognizer into a compact CRNN student
(response-based distillation: timestep-wise KL on soft targets plus CTC on
the teacher's greedy transcription) using a directory of unlabeled
text-line images. The output is a TorchScript checkpoint that
`convert_recognizer.py` can convert.

```bash
python3 tools/distill_recognizer.py \
  --teacher recognizer_traced.pt \
  --images ./line_crops \
  --num-classes 7000 \
  --epochs 10 \
  --output student.pt
```

## Where the weights come from

**These scripts do not download models, and this repository does not
contain any.** You must obtain an upstream checkpoint yourself — for
example a recognition model you trained, or an open-source Japanese OCR
recognizer exported to TorchScript. Before converting or distilling a
third-party model, check that its license permits redistribution in your
app; the license of the converted model follows the upstream weights, not
YomiKit's MIT license.

## Model contract

Both scripts (and the Swift `CoreMLTextRecognizer`) assume the standard
CTC recognizer shape:

| | Value |
|---|---|
| Input | float image tensor `[1, C, H, W]`, values `0...1` (Core ML input feature `image`) |
| Output | logits `[T, num_classes]` or `[1, T, num_classes]` (Core ML output feature `logits`) |
| Decoding | greedy CTC (blank collapse) — `CTCGreedyDecoder` in Swift |
| Vocabulary sidecar | JSON object `{"blankIndex": N, "vocabulary": ["<blank>", ...]}`, array index = class id — written as `<output>-vocab.json` |

On the Swift side, load the sidecar with `RecognizerVocabulary` (YomiKitCore)
instead of parsing it by hand:

```swift
import YomiKit

let vocab = try RecognizerVocabulary(contentsOf: vocabJSONURL)
let recognizer = try await CoreMLTextRecognizer(
    modelAt: mlpackageURL,
    configuration: .init(vocabulary: vocab)
)
let scanner = YomiScanner(recognizer: recognizer)
```

## What has been verified (and what has not)

To keep the repository weight-free, the scripts are exercised against a
**tiny randomly-initialized teacher model created on the fly** — the same
code paths a real checkpoint takes, with throwaway weights:

```bash
# 1. distillation: 8 synthetic line images, 2 epochs, loss decreases,
#    TorchScript student saved
python3 tools/distill_recognizer.py --teacher teacher_tiny.pt \
  --images ./lines --num-classes 25 --epochs 2 --batch-size 4 \
  --hidden 48 --output student_tiny.pt

# 2. conversion: student -> TinyRecognizer.mlpackage + TinyRecognizer-vocab.json,
#    input feature "image", output feature "logits" confirmed in the spec
python3 tools/convert_recognizer.py --checkpoint student_tiny.pt \
  --vocab vocab.txt --width 320 --height 48 --output TinyRecognizer
```

The student's real logits and the converter's real vocab sidecar are
committed as test fixtures (`Tests/YomiKitCoreTests/Resources/`), and a
Swift test asserts that `CTCGreedyDecoder` reproduces the Python greedy
decode on them exactly — so the Python↔Swift contract cannot silently
drift.

Not verified: **Core ML prediction of the converted package** (coremltools
can only run predictions on macOS; the conversion above was run on Linux),
and **distillation quality on real data** (convergence and accuracy depend
on your teacher and corpus). Treat recognition accuracy as unproven until
you evaluate your own converted model on device.
