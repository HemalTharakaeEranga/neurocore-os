# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""NeuroCore OS PyTorch 2.15 + MLflow 3.18 starter training script."""

import os
import mlflow
import torch
import torch.nn as nn


def main() -> None:
    mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI", "http://127.0.0.1:5000"))
    mlflow.set_experiment("neurocore-starter")
    mlflow.pytorch.autolog(log_models=False)

    x = torch.randn(256, 16)
    y = (x.sum(dim=1) > 0).long()

    model = nn.Sequential(nn.Linear(16, 32), nn.ReLU(), nn.Linear(32, 2))
    opt = torch.optim.Adam(model.parameters(), lr=1e-2)
    loss_fn = nn.CrossEntropyLoss()

    with mlflow.start_run(run_name="pytorch-quickstart"):
        for step in range(25):
            opt.zero_grad()
            loss = loss_fn(model(x), y)
            loss.backward()
            opt.step()
            if step % 5 == 0:
                mlflow.log_metric("loss", float(loss.item()), step=step)
        print(f"Finished training. Final loss={loss.item():.4f} (view at http://127.0.0.1:5000)")


if __name__ == "__main__":
    main()
