"""
generate_fmu_metadata_report.py

Create a CSV report of the FMI interface exposed by every FMU in the
experiments folder.

This is a lightweight CI evidence artifact: it records what each FMU exposes
before validation results are interpreted.
"""

import argparse
import csv
from pathlib import Path
from typing import Iterable, Optional

from fmpy import read_model_description


def join_names(values: Iterable[str]) -> str:
    return ";".join(values)


def default_experiment_value(md, name: str) -> str:
    default_experiment = getattr(md, "defaultExperiment", None)
    if default_experiment is None:
        return ""

    value = getattr(default_experiment, name, None)
    return "" if value is None else str(value)


def fmu_type(md) -> str:
    types = []
    if getattr(md, "coSimulation", None) is not None:
        types.append("CoSimulation")
    if getattr(md, "modelExchange", None) is not None:
        types.append("ModelExchange")
    return ";".join(types) if types else "Unknown"


def category_for(experiments_dir: Path, fmu_path: Path) -> str:
    try:
        rel_parts = fmu_path.parent.relative_to(experiments_dir).parts
    except ValueError:
        return ""
    return rel_parts[0] if rel_parts else ""


def row_for_fmu(experiments_dir: Path, fmu_path: Path) -> dict:
    category = category_for(experiments_dir, fmu_path)
    experiment = fmu_path.parent.name
    rel_path = fmu_path.relative_to(experiments_dir)

    row = {
        "category": category,
        "experiment": experiment,
        "fmu_file": str(rel_path).replace("\\", "/"),
        "model_name": "",
        "fmi_version": "",
        "fmu_type": "",
        "inputs": "",
        "outputs": "",
        "parameters": "",
        "start_time": "",
        "stop_time": "",
        "step_size": "",
        "tolerance": "",
        "status": "OK",
        "error": "",
    }

    try:
        md = read_model_description(str(fmu_path))
        inputs = []
        outputs = []
        parameters = []

        for var in md.modelVariables:
            if var.causality == "input":
                inputs.append(var.name)
            elif var.causality == "output":
                outputs.append(var.name)
            elif var.causality in ("parameter", "calculatedParameter"):
                parameters.append(var.name)

        row.update({
            "model_name": getattr(md, "modelName", "") or fmu_path.stem,
            "fmi_version": getattr(md, "fmiVersion", ""),
            "fmu_type": fmu_type(md),
            "inputs": join_names(inputs),
            "outputs": join_names(outputs),
            "parameters": join_names(parameters),
            "start_time": default_experiment_value(md, "startTime"),
            "stop_time": default_experiment_value(md, "stopTime"),
            "step_size": default_experiment_value(md, "stepSize"),
            "tolerance": default_experiment_value(md, "tolerance"),
        })
    except Exception as exc:  # noqa: BLE001
        row["status"] = "ERROR"
        row["error"] = str(exc)

    return row


def write_report(experiments_dir: Path, out_path: Path) -> int:
    fmus = sorted(experiments_dir.rglob("*.fmu"))
    fieldnames = [
        "category",
        "experiment",
        "fmu_file",
        "model_name",
        "fmi_version",
        "fmu_type",
        "inputs",
        "outputs",
        "parameters",
        "start_time",
        "stop_time",
        "step_size",
        "tolerance",
        "status",
        "error",
    ]

    out_path.parent.mkdir(parents=True, exist_ok=True)
    rows = [row_for_fmu(experiments_dir, fmu_path) for fmu_path in fmus]

    with out_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    ok_count = sum(1 for row in rows if row["status"] == "OK")
    error_count = len(rows) - ok_count
    print(f"Metadata report written to: {out_path}")
    print(f"FMUs inspected: {len(rows)}  OK: {ok_count}  Errors: {error_count}")

    if not rows:
        print(f"ERROR: no FMUs found under {experiments_dir}")
        return 2
    return 1 if error_count else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a CSV report from FMU modelDescription metadata."
    )
    parser.add_argument("--experiments", type=Path, default=Path("experiments"))
    parser.add_argument("--out", type=Path, default=Path("fmu_metadata_report.csv"))
    args = parser.parse_args()

    if not args.experiments.is_dir():
        print(f"ERROR: experiments directory not found: {args.experiments}")
        return 2

    return write_report(args.experiments, args.out)


if __name__ == "__main__":
    raise SystemExit(main())
