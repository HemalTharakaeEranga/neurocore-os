# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Gate 6 CI self-test: PyTorch 2.15.0 + Fashion-MNIST + MLflow 3.18.0 autologging."""

from __future__ import annotations

import gzip
import os
import struct
import sys
from pathlib import Path
from urllib.parse import urlparse

import mlflow
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

FASHION_DIR = Path("/usr/share/neurocore/datasets/fashion-mnist")
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}


def _validate_tracking_uri(uri: str) -> str:
    """Enforces loopback-only MLflow URI unless explicitly overridden."""
    parsed = urlparse(uri)
    if parsed.scheme in ("http", "https"):
        if parsed.hostname not in LOOPBACK_HOSTS and os.environ.get("NEUROCORE_ALLOW_REMOTE_MLFLOW") != "1":
            raise ValueError(
                f"Refusing non-loopback MLFLOW_TRACKING_URI '{uri}' "
                "(set NEUROCORE_ALLOW_REMOTE_MLFLOW=1 to override)."
            )
    return uri


def load_fashion_mnist_subset(limit: int = 1024) -> tuple[torch.Tensor, torch.Tensor]:
    img_path = FASHION_DIR / "train-images-idx3-ubyte.gz"
    lbl_path = FASHION_DIR / "train-labels-idx1-ubyte.gz"
    if img_path.exists() and lbl_path.exists():
        with gzip.open(img_path, "rb") as f:
            magic, num, rows, cols = struct.unpack(">IIII", f.read(16))
            if magic != 0x00000803 or rows != 28 or cols != 28:
                raise ValueError(f"Corrupted Fashion-MNIST image header: magic={magic:#x}")
            take = min(num, limit)
            raw = np.frombuffer(f.read(take * rows * cols), dtype=np.uint8)
            x = torch.from_numpy(raw.copy()).float().view(take, rows * cols) / 255.0
        with gzip.open(lbl_path, "rb") as f:
            magic_l, num_l = struct.unpack(">II", f.read(8))
            if magic_l != 0x00000801:
                raise ValueError(f"Corrupted Fashion-MNIST label header: magic={magic_l:#x}")
            take_l = min(num_l, limit)
            raw_l = np.frombuffer(f.read(take_l), dtype=np.uint8)
            y = torch.from_numpy(raw_l.copy()).long()
        return x, y

    torch.manual_seed(2026)
    return torch.randn(limit, 784), torch.randint(0, 10, (limit,))


def main() -> int:
    tracking_uri = _validate_tracking_uri(
        os.environ.get("MLFLOW_TRACKING_URI", "http://127.0.0.1:5000")
    )
    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment("neurocore-v0.1-selftest")
    mlflow.pytorch.autolog(log_models=False)

    device = torch.device("cpu")
    if os.environ.get("NEUROCORE_FORCE_CPU") != "1":
        if hasattr(torch, "xpu") and torch.xpu.is_available():
            device = torch.device("xpu")
        elif torch.cuda.is_available():
            device = torch.device("cuda")

    x, y = load_fashion_mnist_subset(limit=512)
    loader = DataLoader(TensorDataset(x, y), batch_size=64, shuffle=True)

    model = nn.Sequential(
        nn.Linear(784, 128),
        nn.ReLU(),
        nn.Linear(128, 10),
    ).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=1e-2)
    loss_fn = nn.CrossEntropyLoss()

    with mlflow.start_run(run_name="fashion-mnist-mlp-smoke") as run:
        mlflow.log_param("device", str(device))
        mlflow.log_param("torch_version", torch.__version__)
        final_loss = 0.0
        for epoch in range(2):
            for bx, by in loader:
                bx, by = bx.to(device), by.to(device)
                opt.zero_grad()
                loss = loss_fn(model(bx), by)
                loss.backward()
                opt.step()
                final_loss = float(loss.item())
            mlflow.log_metric("train_loss", final_loss, step=epoch)

        print(
            f"[PASS] PyTorch {torch.__version__} ({device}) logged run_id={run.info.run_id} "
            f"to {tracking_uri} (loss={final_loss:.4f})"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
