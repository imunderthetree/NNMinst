from __future__ import annotations

import json
import os
from pathlib import Path

import matplotlib


matplotlib.use("Agg")


PROJECT_ROOT = Path(__file__).resolve().parents[1]
NOTEBOOK_PATH = PROJECT_ROOT / "training" / "nnminst.ipynb"
TRAINING_CELLS = [2, 3, 4, 5, 6, 7, 9, 12]


def main() -> None:
    os.chdir(PROJECT_ROOT)
    notebook = json.loads(NOTEBOOK_PATH.read_text(encoding="utf-8"))
    namespace: dict[str, object] = {"__name__": "__main__"}

    for cell_index in TRAINING_CELLS:
        cell = notebook["cells"][cell_index]
        source = "".join(cell.get("source", []))
        print(f"\n--- Executing notebook cell {cell_index} ---", flush=True)
        exec(compile(source, f"{NOTEBOOK_PATH}:cell-{cell_index}", "exec"), namespace)

    print("\nTraining/export complete.", flush=True)


if __name__ == "__main__":
    main()
