#!/usr/bin/env bash
# Smoke test for YomiKit.
#
# Runs entirely offline and finishes in well under five minutes:
#   1. Structural checks: required files exist, Package.swift is sane and
#      the Python tools parse.
#   2. If a Swift toolchain is available (natively, or via an already
#      pulled swift:6.0.3 Docker image), runs the core test subset that
#      exercises the end-to-end mock pipeline and the model-tool contract.
# Prints "SMOKE OK" and exits 0 only when every check passed AND the Swift
# tests actually ran. When no offline toolchain exists, only structural
# checks run and the final line is the distinct token
# "SMOKE OK (structural only)" so a degraded run can never be mistaken for
# a full one.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "SMOKE FAIL: $1" >&2
    exit 1
}

# --- 1. Required files ------------------------------------------------------
required_files=(
    Package.swift
    LICENSE
    README.md
    README.zh.md
    README.ja.md
    CHANGELOG.md
    CONTRIBUTING.md
    Sources/YomiKitCore/Backend/OCRBackend.swift
    Sources/YomiKitCore/Backend/MockOCRBackend.swift
    Sources/YomiKitCore/Backend/DocumentPipeline.swift
    Sources/YomiKitCore/Decoding/RecognizerVocabulary.swift
    Sources/YomiKitCore/Layout/LayoutAnalyzer.swift
    Sources/YomiKitCore/Table/TableReconstructor.swift
    Sources/YomiKitCore/Receipt/ReceiptFieldExtractor.swift
    Sources/YomiKit/VisionTextRecognizer.swift
    Sources/YomiKit/CoreMLTextRecognizer.swift
    Tests/YomiKitCoreTests/PipelineTests.swift
    Tests/YomiKitCoreTests/RecognizerContractTests.swift
    Tests/YomiKitCoreTests/Resources/tiny-recognizer-vocab.json
    Tests/YomiKitCoreTests/Resources/tiny-recognizer-roundtrip.json
    Tests/YomiKitTests/YomiKitModuleTests.swift
    tools/convert_recognizer.py
    tools/distill_recognizer.py
)
for file in "${required_files[@]}"; do
    [ -f "$file" ] || fail "missing required file: $file"
done
echo "[smoke] all ${#required_files[@]} required files present"

# --- 2. Package.swift structure ---------------------------------------------
python3 - <<'PYEOF' || fail "Package.swift structure check"
src = open("Package.swift", encoding="utf-8").read()
assert src.count("(") == src.count(")"), "unbalanced parentheses"
assert src.count("[") == src.count("]"), "unbalanced brackets"
for needle in (
    "swift-tools-version: 6.0",
    'name: "yomikit"',
    '"YomiKitCore"',
    '"YomiKit"',
    '"YomiKitCoreTests"',
    '"YomiKitTests"',
):
    assert needle in src, f"missing {needle!r} in Package.swift"
print("[smoke] Package.swift declares both libraries and both test targets")
PYEOF

# --- 3. Python tools parse ---------------------------------------------------
python3 - <<'PYEOF' || fail "Python tools syntax check"
import ast
for path in ("tools/convert_recognizer.py", "tools/distill_recognizer.py"):
    ast.parse(open(path, encoding="utf-8").read(), filename=path)
print("[smoke] Python tools parse cleanly")
PYEOF

# --- 4. Core test subset (when a toolchain is reachable offline) -------------
test_filter='PipelineTests|READMEExampleTests|ReceiptExtractionTests|RecognizerContractTests'
tests_ran=1
if command -v swift >/dev/null 2>&1; then
    echo "[smoke] native Swift toolchain found; running core test subset"
    swift test --filter "$test_filter" || fail "swift test subset"
elif command -v docker >/dev/null 2>&1 \
    && docker info >/dev/null 2>&1 \
    && docker image inspect swift:6.0.3 >/dev/null 2>&1; then
    echo "[smoke] running core test subset in the local swift:6.0.3 image"
    # Copy the sources without any stale host .build/ (tar instead of cp so
    # the exclusion happens before anything lands in the container).
    docker run --rm -v "$PWD":/src:ro swift:6.0.3 bash -c \
        "set -o pipefail && mkdir -p /tmp/yomikit && tar -C /src --exclude=.build -cf - . | tar -C /tmp/yomikit -xf - && cd /tmp/yomikit && swift test --filter '$test_filter'" \
        || fail "swift test subset (docker)"
else
    tests_ran=0
    echo "[smoke] no offline Swift toolchain available; structural checks only" >&2
    echo "[smoke] to run the tests: docker run --rm -v \"\$PWD:/src\" -w /src swift:6.0.3 swift test" >&2
fi

if [ "$tests_ran" -eq 1 ]; then
    echo "SMOKE OK"
else
    # Distinct token: structural checks passed but no test was executed.
    echo "SMOKE OK (structural only)"
fi
