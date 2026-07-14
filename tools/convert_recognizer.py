#!/usr/bin/env python3
"""Convert a PyTorch CTC text-recognition model to Core ML for YomiKit.

The script takes a TorchScript module (or a regular PyTorch module exported
with ``torch.jit.trace`` / ``torch.jit.script``) that maps a line image to
per-timestep class logits, and produces:

* ``<output>.mlpackage`` — a Core ML model whose image input is named
  ``image`` and whose logits output is named ``logits``, matching the
  defaults of ``CoreMLTextRecognizer.Configuration`` in YomiKit.
* ``<output>-vocab.json`` — the class-index → character vocabulary that
  ``CoreMLTextRecognizer`` needs for CTC decoding (blank at index 0 by
  convention; use ``--blank-index`` when your model differs).

The script never downloads anything: you bring your own checkpoint and
vocabulary. See ``tools/README.md`` for where to obtain upstream models
and for licensing notes.

Example:

    python3 tools/convert_recognizer.py \
        --checkpoint recognizer_traced.pt \
        --vocab vocab.txt \
        --width 320 --height 48 \
        --output JapaneseRecognizer

Requirements: ``pip install -r tools/requirements.txt`` (torch and
coremltools are intentionally not vendored with YomiKit).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert a PyTorch CTC recognizer to Core ML for YomiKit."
    )
    parser.add_argument(
        "--checkpoint",
        required=True,
        type=Path,
        help="TorchScript file (.pt) of the recognition model. The module "
        "must accept a float image tensor [1, C, H, W] in 0...1 and return "
        "logits shaped [T, num_classes] or [1, T, num_classes].",
    )
    parser.add_argument(
        "--vocab",
        required=True,
        type=Path,
        help="Vocabulary file: either a JSON array of strings, or a UTF-8 "
        "text file with one character per line. Index order must match the "
        "model's class indices.",
    )
    parser.add_argument("--width", type=int, default=320, help="Model input width in pixels.")
    parser.add_argument("--height", type=int, default=48, help="Model input height in pixels.")
    parser.add_argument(
        "--channels",
        type=int,
        default=3,
        choices=(1, 3),
        help="Number of input channels the model expects (1=grayscale, 3=RGB).",
    )
    parser.add_argument(
        "--blank-index",
        type=int,
        default=0,
        help="CTC blank class index; recorded in the vocab JSON metadata.",
    )
    parser.add_argument(
        "--scale",
        type=float,
        default=1.0 / 255.0,
        help="Pixel scale applied by Core ML before inference (default maps "
        "0...255 to 0...1).",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Output basename; produces <output>.mlpackage and <output>-vocab.json.",
    )
    parser.add_argument(
        "--compute-units",
        choices=("all", "cpu_only", "cpu_and_gpu", "cpu_and_ne"),
        default="all",
        help="Core ML compute units the converted model targets.",
    )
    parser.add_argument(
        "--min-deployment-target",
        choices=("iOS16", "iOS17", "iOS18"),
        default="iOS16",
        help="Minimum deployment target for the converted model.",
    )
    return parser.parse_args(argv)


def load_vocabulary(path: Path) -> list[str]:
    """Loads the vocabulary as a list of strings, one per class index."""
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        vocab = json.loads(text)
        if not isinstance(vocab, list) or not all(isinstance(v, str) for v in vocab):
            raise ValueError(f"{path}: JSON vocabulary must be an array of strings")
        return vocab
    # Plain text: one character (or multi-scalar token) per line. Empty
    # lines are kept as empty tokens so line numbers equal class indices.
    return text.split("\n")[:-1] if text.endswith("\n") else text.split("\n")


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    try:
        import coremltools as ct
        import torch
    except ImportError as error:
        print(
            f"missing dependency: {error.name}. "
            "Run: pip install -r tools/requirements.txt",
            file=sys.stderr,
        )
        return 1

    if not args.checkpoint.exists():
        print(f"checkpoint not found: {args.checkpoint}", file=sys.stderr)
        return 1

    vocab = load_vocabulary(args.vocab)
    print(f"vocabulary: {len(vocab)} classes (blank at {args.blank_index})")

    print(f"loading TorchScript module from {args.checkpoint} ...")
    module = torch.jit.load(str(args.checkpoint), map_location="cpu")
    module.eval()

    example = torch.rand(1, args.channels, args.height, args.width)
    with torch.no_grad():
        logits = module(example)
    # Sanity-check the output contract before converting.
    shape = list(logits.shape)
    squeezed = [d for d in shape if d != 1] if len(shape) > 2 else shape
    if len(squeezed) != 2:
        print(
            f"unexpected model output shape {shape}; expected [T, C] or [1, T, C]",
            file=sys.stderr,
        )
        return 1
    num_classes = squeezed[-1]
    if num_classes != len(vocab):
        print(
            f"vocabulary size {len(vocab)} does not match model classes {num_classes}",
            file=sys.stderr,
        )
        return 1
    print(f"model output verified: {shape} ({squeezed[0]} timesteps, {num_classes} classes)")

    traced = torch.jit.trace(module, example)

    color_layout = ct.colorlayout.RGB if args.channels == 3 else ct.colorlayout.GRAYSCALE
    compute_units = {
        "all": ct.ComputeUnit.ALL,
        "cpu_only": ct.ComputeUnit.CPU_ONLY,
        "cpu_and_gpu": ct.ComputeUnit.CPU_AND_GPU,
        "cpu_and_ne": ct.ComputeUnit.CPU_AND_NE,
    }[args.compute_units]

    print("converting to Core ML ...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=example.shape,
                scale=args.scale,
                color_layout=color_layout,
            )
        ],
        minimum_deployment_target=getattr(ct.target, args.min_deployment_target),
        compute_units=compute_units,
        convert_to="mlprogram",
    )

    # Normalize the output feature name to "logits" so the Swift side works
    # with its default configuration.
    spec = mlmodel.get_spec()
    output_name = spec.description.output[0].name
    if output_name != "logits":
        ct.utils.rename_feature(spec, output_name, "logits")
        mlmodel = ct.models.MLModel(spec, weights_dir=mlmodel.weights_dir)

    mlmodel.short_description = "YomiKit CTC text recognizer"
    mlmodel.user_defined_metadata["yomikit.vocab_size"] = str(len(vocab))
    mlmodel.user_defined_metadata["yomikit.blank_index"] = str(args.blank_index)

    package_path = args.output.with_suffix(".mlpackage")
    mlmodel.save(str(package_path))
    print(f"saved {package_path}")

    vocab_path = args.output.parent / f"{args.output.name}-vocab.json"
    vocab_path.write_text(
        json.dumps(
            {"blankIndex": args.blank_index, "vocabulary": vocab},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"saved {vocab_path}")
    print(
        "next: in Swift, load the vocab JSON with RecognizerVocabulary(contentsOf:) "
        "and the model with CoreMLTextRecognizer(modelAt:configuration:)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
