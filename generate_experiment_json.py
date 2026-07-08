"""
generate_experiment_json.py

Create generic.py experiment JSON files from FMU metadata.

This is intended for normal single-FMU experiments:

    <model>.fmu + <model>_ref.csv -> <model>.json

MATLAB/Simulink may still be used to run the source model and export the FMU,
but JSON generation can be owned by Python.
"""

import argparse
import csv
import json
import os
import re
from pathlib import Path
from typing import Iterable, List, Optional

from fmpy import read_model_description


def clean_name(raw: str) -> str:
    name = re.sub(r"[^A-Za-z0-9_]", "_", raw)
    if name and name[0].isdigit():
        name = "_" + name
    return name or "signal"


def unique_name(base: str, used: set) -> str:
    if base not in used:
        used.add(base)
        return base

    i = 2
    while f"{base}_{i}" in used:
        i += 1
    name = f"{base}_{i}"
    used.add(name)
    return name


def read_reference_signal_names(model_dir: Path, model_name: str) -> List[str]:
    ref_path = model_dir / f"{model_name}_ref.csv"
    if not ref_path.is_file():
        refs = sorted(model_dir.glob("*_ref.csv"))
        if not refs:
            return []
        ref_path = refs[0]

    with ref_path.open(newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            return []

    if len(header) <= 1:
        return []
    return [h.strip() for h in header[1:] if h.strip()]


def read_reference_time_info(
    model_dir: Path,
    model_name: str,
) -> tuple[Optional[float], Optional[float], Optional[float]]:
    ref_path = model_dir / f"{model_name}_ref.csv"
    if not ref_path.is_file():
        refs = sorted(model_dir.glob("*_ref.csv"))
        if not refs:
            return None, None, None
        ref_path = refs[0]

    times = []
    with ref_path.open(newline="") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            return None, None, None
        time_col = reader.fieldnames[0]
        for row in reader:
            try:
                times.append(float(row[time_col]))
            except (KeyError, TypeError, ValueError):
                continue

    if not times:
        return None, None, None

    ref_dt = None
    if len(times) >= 2:
        ref_dt = times[1] - times[0]

    return times[0], times[-1], ref_dt


def get_default_experiment_value(md, name: str, fallback: float) -> float:
    de = getattr(md, "defaultExperiment", None)
    if de is None:
        return fallback

    value = getattr(de, name, None)
    if value in (None, ""):
        return fallback

    try:
        return float(value)
    except (TypeError, ValueError):
        return fallback


def fmu_ports(fmu_path: Path) -> tuple[List[str], List[str]]:
    md = read_model_description(str(fmu_path))

    inputs = []
    outputs = []
    for var in md.modelVariables:
        if var.causality == "input":
            inputs.append(var.name)
        elif var.causality == "output":
            outputs.append(var.name)

    return inputs, outputs


def create_single_fmu_config(
    fmu_path: Path,
    model_name: Optional[str] = None,
    start: Optional[float] = None,
    stop: Optional[float] = None,
    dt: Optional[float] = None,
) -> dict:
    model_dir = fmu_path.parent
    model_name = model_name or fmu_path.stem

    md = read_model_description(str(fmu_path))
    ref_start, ref_stop, ref_dt = read_reference_time_info(model_dir, model_name)
    start_fallback = ref_start if ref_start is not None else 0.0
    stop_fallback = ref_stop if ref_stop is not None else 1.0
    dt_fallback = ref_dt if ref_dt is not None and ref_dt > 0 else 0.01

    start = get_default_experiment_value(md, "startTime", start_fallback) if start is None else start
    stop = get_default_experiment_value(md, "stopTime", stop_fallback) if stop is None else stop
    dt = get_default_experiment_value(md, "stepSize", dt_fallback) if dt is None else dt

    inputs = []
    outputs = []
    for var in md.modelVariables:
        if var.causality == "input":
            inputs.append(var.name)
        elif var.causality == "output":
            outputs.append(var.name)

    ref_signal_names = read_reference_signal_names(model_dir, model_name)

    components = {}
    connections = []

    if inputs:
        used_ports = set()
        ports = {}
        for input_name in inputs:
            stim_port = unique_name(clean_name(input_name), used_ports)
            ports[stim_port] = {
                "initial": 0.0,
                "step": 1.0,
                "step_time": 0.0,
            }
            connections.append({
                "src_comp": "stim",
                "src_port": stim_port,
                "dst_comp": "fmu",
                "dst_port": input_name,
            })
        components["stim"] = {"type": "step", "ports": ports}

    components["fmu"] = {
        "type": "fmu",
        "file": fmu_path.name,
    }
    components["log"] = {
        "type": "logger",
        "file": f"results_{model_name}.csv",
    }

    for i, output_name in enumerate(outputs):
        log_name = output_name
        if i < len(ref_signal_names):
            log_name = ref_signal_names[i]
        connections.append({
            "src_comp": "fmu",
            "src_port": output_name,
            "dst_comp": "log",
            "dst_port": log_name,
        })

    return {
        "start": start,
        "stop": stop,
        "dt": dt,
        "components": components,
        "connections": connections,
    }


def choose_fmu(model_dir: Path, model_name: Optional[str]) -> Path:
    if model_name:
        preferred = model_dir / f"{model_name}.fmu"
        if preferred.is_file():
            return preferred

    fmus = sorted(model_dir.glob("*.fmu"))
    if not fmus:
        raise FileNotFoundError(f"No .fmu file found in {model_dir}")
    if len(fmus) > 1 and not model_name:
        names = ", ".join(f.name for f in fmus)
        raise ValueError(
            f"Multiple FMUs found in {model_dir}: {names}. "
            "Pass --model-name for single-folder generation."
        )
    return fmus[0]


def write_json(path: Path, cfg: dict, overwrite: bool) -> None:
    if path.exists() and not overwrite:
        raise FileExistsError(f"JSON already exists: {path} (use --overwrite)")

    with path.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")


def generate_for_directory(
    model_dir: Path,
    model_name: Optional[str],
    start: Optional[float],
    stop: Optional[float],
    dt: Optional[float],
    overwrite: bool,
) -> Path:
    fmu_path = choose_fmu(model_dir, model_name)
    case_name = model_name or fmu_path.stem
    cfg = create_single_fmu_config(
        fmu_path=fmu_path,
        model_name=case_name,
        start=start,
        stop=stop,
        dt=dt,
    )
    json_path = model_dir / f"{case_name}.json"
    write_json(json_path, cfg, overwrite=overwrite)
    return json_path


def iter_standard_fmu_dirs(experiments_dir: Path) -> Iterable[Path]:
    for fmu in sorted(experiments_dir.rglob("*.fmu")):
        model_dir = fmu.parent
        if (model_dir / "coupled_experiment.json").exists():
            continue
        yield model_dir


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate generic.py JSON configs from single-FMU metadata."
    )
    parser.add_argument(
        "--experiment-dir",
        type=Path,
        help="One experiment folder containing a single .fmu",
    )
    parser.add_argument(
        "--experiments",
        type=Path,
        help="Root experiments folder; generates JSON for all standard FMU folders",
    )
    parser.add_argument(
        "--model-name",
        help="Model/case name to use for one folder, e.g. Motor_Model",
    )
    parser.add_argument("--start", type=float, default=None)
    parser.add_argument("--stop", type=float, default=None)
    parser.add_argument("--dt", type=float, default=None)
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite an existing JSON file",
    )
    args = parser.parse_args()

    if bool(args.experiment_dir) == bool(args.experiments):
        parser.error("Use exactly one of --experiment-dir or --experiments")

    try:
        if args.experiment_dir:
            json_path = generate_for_directory(
                model_dir=args.experiment_dir,
                model_name=args.model_name,
                start=args.start,
                stop=args.stop,
                dt=args.dt,
                overwrite=args.overwrite,
            )
            print(f"Generated: {json_path}")
            return 0

        generated = []
        seen = set()
        for model_dir in iter_standard_fmu_dirs(args.experiments):
            if model_dir in seen:
                continue
            seen.add(model_dir)
            generated.append(generate_for_directory(
                model_dir=model_dir,
                model_name=None,
                start=args.start,
                stop=args.stop,
                dt=args.dt,
                overwrite=args.overwrite,
            ))

        if not generated:
            print(f"No standard FMU folders found in {args.experiments}")
            return 2

        for path in generated:
            print(f"Generated: {path}")
        return 0

    except Exception as e:
        print(f"ERROR: {e}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
