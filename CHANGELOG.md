# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-08

### Added

- `YomiKitCore` (platform-independent, Linux-testable):
  - Layout analysis: orientation detection (vertical/horizontal), line clustering, block clustering, and reading-order sorting via recursive XY-cut — tategaki columns right-to-left, stacked sections top-to-bottom.
  - Table reconstruction from bounding boxes: row/column band inference, spanning-cell detection, dense grid output.
  - Japanese receipt field extraction: store name, date (wareki era conversion), time, line items with quantity and discounts, subtotal/total, per-rate tax lines with reduced-rate detection, tendered amount, change, item count.
  - Japanese text post-processing: full-width/half-width normalization (ASCII and katakana with dakuten composition), kanji numeral parsing, era date parsing, yen amount parsing.
  - CTC greedy decoder for custom recognition models, plus `RecognizerVocabulary` — a validated loader for the `<output>-vocab.json` sidecar written by the conversion script.
  - `OCRBackend` protocol, `MockOCRBackend`, `AnyOCRBackend`, and `DocumentPipeline` end-to-end orchestration.
  - `OrientationClassifier.classifyRegion(width:height:)` — single-region orientation used to decide vertical-column rotation in recognition backends.
  - Markdown and JSON exporters.
- `YomiKit` (Apple platform layer, compiled behind `#if canImport(...)`):
  - `VisionTextRecognizer` — Apple Vision configured for Japanese, with coordinate conversion.
  - `CoreMLTextRecognizer` and `CoreMLModelLoader` — custom Core ML recognition models with Vision region proposals and CTC decoding; tall tategaki column crops are rotated a quarter turn before recognition (`Configuration.verticalRegionHandling`).
  - `YomiScanner` — one-line `CGImage` entry point.
- `tools/` — Python scripts to convert a TorchScript CTC recognizer to Core ML and to distill a large recognizer into a compact mobile student (no weights bundled or downloaded). Both scripts are exercised end-to-end against a tiny randomly-initialized model; the student's forward pass uses a trace-friendly `flatten` so the traced graph converts to Core ML.
- Test suite (89 tests) covering geometry, layout, tables, receipts, text processing, mock-driven end-to-end pipeline orchestration, and Python↔Swift contract fixtures generated from a real run of the model tools; runs on Linux.
