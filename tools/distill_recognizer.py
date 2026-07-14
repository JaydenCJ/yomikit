#!/usr/bin/env python3
"""Distill a large CTC text-recognition model into a small mobile student.

Server-side Japanese OCR models are usually too heavy for phones. This
script trains a compact CRNN student against a frozen TorchScript teacher
using response-based knowledge distillation on unlabeled line images:

* soft targets — KL divergence between temperature-scaled teacher and
  student distributions at each timestep (student timesteps are aligned to
  the teacher's by linear interpolation when the lengths differ);
* hard targets — CTC loss on the teacher's greedy-decoded label sequence,
  which keeps the student's blank alignment sane.

The result is a TorchScript checkpoint that ``convert_recognizer.py`` can
turn into a Core ML model. The script never downloads anything — you
provide the teacher checkpoint and a directory of text-line images (crops
of receipts, scans, rendered text, etc.).

Example:

    python3 tools/distill_recognizer.py \
        --teacher recognizer_traced.pt \
        --images ./line_crops \
        --num-classes 7000 \
        --epochs 10 \
        --output student.pt

Requirements: ``pip install -r tools/requirements.txt``.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".bmp", ".webp"}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Distill a CTC recognizer into a small mobile student model."
    )
    parser.add_argument(
        "--teacher",
        required=True,
        type=Path,
        help="TorchScript teacher model: [1, C, H, W] image in, [T, num_classes] "
        "(or [1, T, num_classes]) logits out.",
    )
    parser.add_argument(
        "--images",
        required=True,
        type=Path,
        help="Directory of unlabeled text-line images (searched recursively).",
    )
    parser.add_argument("--num-classes", required=True, type=int, help="Vocabulary size incl. blank.")
    parser.add_argument("--width", type=int, default=320, help="Input width for both models.")
    parser.add_argument("--height", type=int, default=48, help="Input height for both models.")
    parser.add_argument(
        "--channels", type=int, default=3, choices=(1, 3), help="Input channels for both models."
    )
    parser.add_argument("--blank-index", type=int, default=0, help="CTC blank class index.")
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument(
        "--temperature", type=float, default=2.0, help="Softmax temperature for distillation."
    )
    parser.add_argument(
        "--ctc-weight",
        type=float,
        default=0.3,
        help="Weight of the hard-target CTC term (soft KL term gets 1 - weight).",
    )
    parser.add_argument(
        "--hidden", type=int, default=192, help="Hidden size of the student's recurrent head."
    )
    parser.add_argument("--device", default="cpu", help="torch device, e.g. cpu, cuda, mps.")
    parser.add_argument(
        "--output", required=True, type=Path, help="Where to write the TorchScript student model."
    )
    return parser.parse_args(argv)


def build_student(channels: int, num_classes: int, hidden: int):
    """A compact CRNN: conv feature extractor + BiGRU head + per-timestep
    classifier. Roughly 3–6 MB of fp16 weights at default sizes."""
    import torch
    from torch import nn

    class StudentCRNN(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            def block(cin: int, cout: int, pool: tuple[int, int]) -> nn.Sequential:
                return nn.Sequential(
                    nn.Conv2d(cin, cout, kernel_size=3, padding=1, bias=False),
                    nn.BatchNorm2d(cout),
                    nn.ReLU(inplace=True),
                    nn.MaxPool2d(pool),
                )

            # Height shrinks aggressively, width (the time axis) gently.
            self.features = nn.Sequential(
                block(channels, 32, (2, 2)),
                block(32, 64, (2, 2)),
                block(64, 128, (2, 1)),
                block(128, 128, (2, 1)),
            )
            self.rnn = nn.GRU(
                input_size=128 * 3,  # 48 / 2 / 2 / 2 / 2 = 3 rows left
                hidden_size=hidden,
                num_layers=2,
                bidirectional=True,
                batch_first=True,
            )
            self.classifier = nn.Linear(hidden * 2, num_classes)

        def forward(self, image: "torch.Tensor") -> "torch.Tensor":
            feat = self.features(image)                # [B, C, H', W']
            # flatten(2) instead of reshape(shape-derived ints): dynamic
            # Int casts from Tensor.shape break Core ML conversion of the
            # traced graph (verified against coremltools).
            feat = feat.permute(0, 3, 1, 2).flatten(2)  # [B, T, C*H']
            seq, _ = self.rnn(feat)                    # [B, T, 2*hidden]
            return self.classifier(seq)                # [B, T, num_classes]

    return StudentCRNN()


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    try:
        import torch
        import torch.nn.functional as functional
        from PIL import Image
        from torch.utils.data import DataLoader, Dataset
    except ImportError as error:
        print(
            f"missing dependency: {error.name}. "
            "Run: pip install -r tools/requirements.txt",
            file=sys.stderr,
        )
        return 1

    if not args.teacher.exists():
        print(f"teacher checkpoint not found: {args.teacher}", file=sys.stderr)
        return 1

    paths = sorted(
        p for p in args.images.rglob("*") if p.suffix.lower() in IMAGE_SUFFIXES
    )
    if not paths:
        print(f"no images found under {args.images}", file=sys.stderr)
        return 1
    print(f"dataset: {len(paths)} line images")

    class LineImages(Dataset):
        def __len__(self) -> int:
            return len(paths)

        def __getitem__(self, index: int) -> "torch.Tensor":
            mode = "RGB" if args.channels == 3 else "L"
            with Image.open(paths[index]) as img:
                img = img.convert(mode).resize(
                    (args.width, args.height), Image.Resampling.BILINEAR
                )
                tensor = torch.frombuffer(bytearray(img.tobytes()), dtype=torch.uint8)
            tensor = tensor.reshape(args.height, args.width, args.channels)
            return tensor.permute(2, 0, 1).float() / 255.0

    device = torch.device(args.device)
    teacher = torch.jit.load(str(args.teacher), map_location=device)
    teacher.eval()

    student = build_student(args.channels, args.num_classes, args.hidden).to(device)
    optimizer = torch.optim.AdamW(student.parameters(), lr=args.lr)
    loader = DataLoader(LineImages(), batch_size=args.batch_size, shuffle=True, drop_last=False)

    def teacher_logits(batch: "torch.Tensor") -> "torch.Tensor":
        """Runs the teacher image-by-image (traced teachers are often
        batch-1 only) and returns [B, T, num_classes]."""
        outputs = []
        for image in batch:
            logits = teacher(image.unsqueeze(0))
            while logits.dim() > 2 and logits.shape[0] == 1:
                logits = logits.squeeze(0)
            outputs.append(logits)
        return torch.stack(outputs)

    def align_timesteps(logits: "torch.Tensor", length: int) -> "torch.Tensor":
        """Linearly interpolates [B, T, C] along T to the given length."""
        if logits.shape[1] == length:
            return logits
        return functional.interpolate(
            logits.transpose(1, 2), size=length, mode="linear", align_corners=False
        ).transpose(1, 2)

    def greedy_labels(logits: "torch.Tensor") -> tuple["torch.Tensor", "torch.Tensor"]:
        """CTC-collapses teacher argmax paths into label sequences."""
        labels: list[int] = []
        lengths: list[int] = []
        for path in logits.argmax(dim=-1):
            sequence: list[int] = []
            previous = args.blank_index
            for index in path.tolist():
                if index != args.blank_index and index != previous:
                    sequence.append(index)
                previous = index
            labels.extend(sequence)
            lengths.append(len(sequence))
        return (
            torch.tensor(labels, dtype=torch.long, device=device),
            torch.tensor(lengths, dtype=torch.long, device=device),
        )

    temperature = args.temperature
    for epoch in range(1, args.epochs + 1):
        student.train()
        epoch_loss = 0.0
        batches = 0
        for batch in loader:
            batch = batch.to(device)
            with torch.no_grad():
                t_logits = teacher_logits(batch)
            s_logits = student(batch)                          # [B, T_s, C]
            t_aligned = align_timesteps(t_logits, s_logits.shape[1])

            # Soft targets: timestep-wise KL on temperature-scaled dists.
            kl = functional.kl_div(
                functional.log_softmax(s_logits / temperature, dim=-1),
                functional.log_softmax(t_aligned / temperature, dim=-1),
                reduction="batchmean",
                log_target=True,
            ) * (temperature * temperature)

            # Hard targets: CTC on the teacher's greedy transcription.
            labels, label_lengths = greedy_labels(t_logits)
            log_probs = functional.log_softmax(s_logits, dim=-1).transpose(0, 1)
            input_lengths = torch.full(
                (batch.shape[0],), s_logits.shape[1], dtype=torch.long, device=device
            )
            if labels.numel() > 0:
                ctc = functional.ctc_loss(
                    log_probs,
                    labels,
                    input_lengths,
                    label_lengths,
                    blank=args.blank_index,
                    zero_infinity=True,
                )
            else:
                ctc = torch.zeros((), device=device)

            loss = (1.0 - args.ctc_weight) * kl + args.ctc_weight * ctc
            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(student.parameters(), 5.0)
            optimizer.step()
            epoch_loss += float(loss.detach())
            batches += 1
        print(f"epoch {epoch}/{args.epochs}: mean loss {epoch_loss / max(batches, 1):.4f}")

    student.eval()
    example = torch.rand(1, args.channels, args.height, args.width, device=device)
    traced = torch.jit.trace(student, example)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    traced.save(str(args.output))
    print(f"saved TorchScript student to {args.output}")
    print("next: convert it with tools/convert_recognizer.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
