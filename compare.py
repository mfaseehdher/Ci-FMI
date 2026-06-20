"""
compare.py  --  Validate FMU co-simulation output against a golden reference

Metrics computed per signal:
  RMSE     Root Mean Square Error       -- average magnitude of error
  MAE      Mean Absolute Error          -- simpler average of absolute errors
  Max|err| Maximum Absolute Error       -- worst single point error
  Rel RMSE Relative RMSE               -- RMSE as % of reference signal range
  DTW      Dynamic Time Warping         -- shape similarity ignoring time shifts

What each metric tells you:
  RMSE     -- overall accuracy. Sensitive to large errors (squares them).
              If RMSE is small your simulation matches MATLAB well on average.
  MAE      -- same idea as RMSE but does not square errors. Less sensitive
              to outliers. More honest average error. Never cancels out.
  Max|err| -- worst case error at any single time step. Important for safety
              critical systems where you need to bound the error.
  Rel RMSE -- RMSE divided by signal range expressed as percent. Lets you
              compare accuracy across models with different magnitudes.
  DTW      -- measures shape similarity between two signals regardless of
              time shifts. If two signals have the same shape but one is
              shifted by a few steps, RMSE is high but DTW is low.
              Low DTW means correct shape even if slightly shifted in time.
              Used when co-simulation introduces communication delays.

Usage:
    python compare.py reference.csv output.csv
    python compare.py reference.csv output.csv --tol 0.01
    python compare.py reference.csv output.csv --signals Velocity --tol 0.01
    python compare.py reference.csv output.csv --no-dtw

Exit codes:
    0  all signals within tolerance (or no tolerance given)
    1  one or more signals exceed tolerance
    2  bad arguments or file not found
"""

import argparse
import csv
import math
import sys
from typing import Dict, List, Optional, Tuple


# ─────────────────────────────────────────────────────────────────────────────
# CSV loading
# ─────────────────────────────────────────────────────────────────────────────

def load_csv(path: str) -> Tuple[List[float], Dict[str, List[float]]]:
    """Load CSV into (time_vector, {signal_name: [values]}).
    Time column identified by name 'time'. Skips malformed rows."""
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        fields = list(reader.fieldnames or [])
        rows = list(reader)

    has_time = "time" in fields
    signal_fields = [f for f in fields if f != "time"]
    times: List[float] = []
    signals: Dict[str, List[float]] = {s: [] for s in signal_fields}

    for i, row in enumerate(rows):
        try:
            t = float(row["time"]) if has_time else float(i)
            vals = {s: float(row[s]) for s in signal_fields}
        except (KeyError, ValueError, TypeError):
            continue
        times.append(t)
        for s, v in vals.items():
            signals[s].append(v)

    return times, signals


# ─────────────────────────────────────────────────────────────────────────────
# Alignment -- interpolate output onto reference time grid
# ─────────────────────────────────────────────────────────────────────────────

def align(
    ref_t: List[float],
    ref_sig: List[float],
    out_t: List[float],
    out_sig: List[float],
    shift: float = 0.0,
) -> Tuple[List[float], List[float]]:
    """Linearly interpolate output onto reference time grid.
    Optional time shift applied to output before interpolation.
    Points outside output range are clamped to endpoint values."""
    shifted_out_t = [t + shift for t in out_t]

    def interp(t_query: float) -> float:
        if t_query <= shifted_out_t[0]:
            return out_sig[0]
        if t_query >= shifted_out_t[-1]:
            return out_sig[-1]
        lo, hi = 0, len(shifted_out_t) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if shifted_out_t[mid] <= t_query:
                lo = mid
            else:
                hi = mid
        t0, t1 = shifted_out_t[lo], shifted_out_t[hi]
        v0, v1 = out_sig[lo], out_sig[hi]
        alpha = (t_query - t0) / (t1 - t0) if t1 != t0 else 0.0
        return v0 + alpha * (v1 - v0)

    return ref_sig, [interp(t) for t in ref_t]


# ─────────────────────────────────────────────────────────────────────────────
# Metrics
# ─────────────────────────────────────────────────────────────────────────────

def compute_rmse(ref: List[float], out: List[float]) -> float:
    """Root Mean Square Error.
    Formula: sqrt( sum((ref-out)^2) / n )
    Squares each error -- outliers have large influence."""
    n = len(ref)
    if n == 0:
        return float("nan")
    return math.sqrt(sum((r - o) ** 2 for r, o in zip(ref, out)) / n)


def compute_mae(ref: List[float], out: List[float]) -> float:
    """Mean Absolute Error.
    Formula: sum(|ref-out|) / n
    Uses absolute values so errors never cancel out.
    Your supervisor specifically asked for absolute error values."""
    n = len(ref)
    if n == 0:
        return float("nan")
    return sum(abs(r - o) for r, o in zip(ref, out)) / n


def compute_max_abs(ref: List[float], out: List[float]) -> float:
    """Maximum Absolute Error -- worst single point error."""
    if not ref:
        return float("nan")
    return max(abs(r - o) for r, o in zip(ref, out))


def compute_rel_rmse(ref: List[float], out: List[float]) -> float:
    """Relative RMSE = RMSE / range(reference).
    Returns a fraction -- multiply by 100 for percentage.
    Allows fair comparison across models with different signal magnitudes."""
    rng = max(ref) - min(ref) if ref else 0.0
    if rng == 0:
        return float("nan")
    return compute_rmse(ref, out) / rng


def compute_dtw(ref: List[float], out: List[float]) -> float:
    """Dynamic Time Warping distance.

    What it measures: shape similarity between two signals regardless of
    time shifts. If your FMU output has the same shape as MATLAB reference
    but shifted by a few timesteps due to co-simulation delay, RMSE will be
    large but DTW will be small.

    Interpretation:
      DTW near 0   -- signals have nearly identical shape
      DTW large    -- signals have different shapes (not just shifted)

    Uses dtaidistance library if installed (pip install dtaidistance).
    Falls back to pure Python DTW if library not available."""
    try:
        import array
        from dtaidistance import dtw as dtw_lib
        return float(dtw_lib.distance(
            array.array('d', ref),
            array.array('d', out)
        ))
    except ImportError:
        pass

    # Pure Python fallback -- dynamic programming DTW
    n, m = len(ref), len(out)
    INF = float("inf")
    prev = [INF] * (m + 1)
    curr = [INF] * (m + 1)
    prev[0] = 0.0
    for i in range(1, n + 1):
        curr[0] = INF
        for j in range(1, m + 1):
            cost = abs(ref[i-1] - out[j-1])
            curr[j] = cost + min(prev[j], curr[j-1], prev[j-1])
        prev, curr = curr, prev
    return prev[m]


def compute_abs_errors(ref: List[float], out: List[float]) -> List[float]:
    """Per-timestep absolute error. Always positive. Never cancels out."""
    return [abs(r - o) for r, o in zip(ref, out)]


# ─────────────────────────────────────────────────────────────────────────────
# Sparkline
# ─────────────────────────────────────────────────────────────────────────────

_SPARK = " ▁▂▃▄▅▆▇█"


def sparkline(values: List[float], width: int = 40) -> str:
    """ASCII bar chart of error over time. Shows error pattern at a glance."""
    if not values:
        return ""
    mn, mx = min(values), max(values)
    span = mx - mn or 1.0
    step = max(1, len(values) // width)
    sampled = values[::step][:width]
    return "".join(
        _SPARK[int((v - mn) / span * (len(_SPARK) - 1))]
        for v in sampled
    )


# ─────────────────────────────────────────────────────────────────────────────
# Report
# ─────────────────────────────────────────────────────────────────────────────

def print_report(
    results: List[Dict],
    tol: Optional[float],
    ref_path: str,
    out_path: str,
    use_dtw: bool = True,
) -> bool:
    """Print full metrics report. Returns True if all signals pass."""

    col_w = max(len(r["signal"]) for r in results) + 2

    print()
    print(f"  Reference : {ref_path}")
    print(f"  Output    : {out_path}")
    print()

    # Metric legend
    print("  What each metric means:")
    print("    RMSE     squares errors then averages -- outliers have large influence")
    print("    MAE      averages absolute errors -- more honest, never cancels out")
    print("    Max|err| worst single point error across all time steps")
    print("    Rel RMSE RMSE as percent of signal range -- comparable across models")
    if use_dtw:
        print("    DTW      shape similarity ignoring time shifts -- low = correct shape")
    print()

    # Build header
    if use_dtw:
        header = (
            f"  {'Signal':<{col_w}}  {'RMSE':>12}  {'MAE':>12}  "
            f"{'Max|err|':>12}  {'Rel RMSE':>10}  {'DTW':>12}  {'Status':>6}"
        )
    else:
        header = (
            f"  {'Signal':<{col_w}}  {'RMSE':>12}  {'MAE':>12}  "
            f"{'Max|err|':>12}  {'Rel RMSE':>10}  {'Status':>6}"
        )

    sep = "  " + "-" * (len(header) - 2)
    print(sep)
    print(header)
    print(sep)

    all_pass = True
    for r in results:
        status = "--"
        if tol is not None:
            ok = r["rmse"] <= tol
            status = "PASS" if ok else "FAIL"
            if not ok:
                all_pass = False

        rel = r["rel_rmse"]
        rel_str = f"{rel*100:.4f}%" if not math.isnan(rel) else "N/A"

        if use_dtw:
            dtw_val = r.get("dtw", float("nan"))
            dtw_str = f"{dtw_val:.4g}" if not math.isnan(dtw_val) else "N/A"
            print(
                f"  {r['signal']:<{col_w}}  {r['rmse']:>12.6g}  {r['mae']:>12.6g}  "
                f"{r['max_abs']:>12.6g}  {rel_str:>10}  {dtw_str:>12}  {status:>6}"
            )
        else:
            print(
                f"  {r['signal']:<{col_w}}  {r['rmse']:>12.6g}  {r['mae']:>12.6g}  "
                f"{r['max_abs']:>12.6g}  {rel_str:>10}  {status:>6}"
            )

        # Absolute error sparkline -- shows error pattern over time
        print(f"  {'':>{col_w}}  |err|: {sparkline(r['abs_errors'])}")
        print()

    print(sep)

    if tol is not None:
        verdict = "PASS" if all_pass else "FAIL"
        print(f"\n  Tolerance : {tol:.2e}   Verdict: {verdict}\n")
    else:
        print()

    # Automatic warnings
    for r in results:
        # Warning: errors canceling out (supervisor mentioned this)
        if r["mae"] > 1e-12:
            signed_mean = abs(r.get("mean_signed", 0.0))
            if signed_mean < r["mae"] * 0.01:
                print(
                    f"  [WARNING] '{r['signal']}': positive and negative errors are "
                    f"canceling out.\n"
                    f"            Signed mean error is near zero but MAE = {r['mae']:.4g}.\n"
                    f"            Use MAE and Max|err| for accurate error assessment.\n"
                )

        # Warning: large outliers dominating RMSE
        if r["mae"] > 0 and not math.isnan(r["mae"]):
            ratio = r["rmse"] / r["mae"]
            if ratio > 3.0:
                print(
                    f"  [WARNING] '{r['signal']}': RMSE is {ratio:.1f}x larger than MAE.\n"
                    f"            A few large errors dominate. Check Max|err| "
                    f"and error plot for outliers.\n"
                )

    return all_pass


# ─────────────────────────────────────────────────────────────────────────────
# Core function (importable from CI scripts)
# ─────────────────────────────────────────────────────────────────────────────

def write_metrics_csv(results: List[Dict], metrics_path: str,
                      tol: Optional[float], model_name: str = "") -> None:
    """Write all metrics to a CSV file so they are saved in the results,
    not just printed to the console.

    One row per signal with columns:
      model, signal, RMSE, MAE, Max_abs_err, Rel_RMSE_percent, DTW, Status
    """
    with open(metrics_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "model", "signal", "RMSE", "MAE", "Max_abs_err",
            "Rel_RMSE_percent", "DTW", "Status"
        ])
        for r in results:
            rel = r["rel_rmse"]
            rel_str = f"{rel*100:.6f}" if not math.isnan(rel) else "N/A"
            dtw_val = r.get("dtw", float("nan"))
            dtw_str = f"{dtw_val:.6g}" if not math.isnan(dtw_val) else "N/A"
            if tol is not None:
                status = "PASS" if r["rmse"] <= tol else "FAIL"
            else:
                status = "N/A"
            writer.writerow([
                model_name,
                r["signal"],
                f"{r['rmse']:.10g}",
                f"{r['mae']:.10g}",
                f"{r['max_abs']:.10g}",
                rel_str,
                dtw_str,
                status,
            ])
    print(f"  Metrics saved to: {metrics_path}")


def append_metrics_to_results(results: List[Dict], out_path: str,
                              tol: Optional[float]) -> None:
    """Append metric summary rows to the END of the results CSV itself.

    The supervisor asked for metrics IN the results. This adds a commented
    summary block at the bottom of the output CSV after the data rows, so
    the single results file contains both the time series AND the metrics.
    """
    try:
        with open(out_path, "a", newline="") as f:
            writer = csv.writer(f)
            writer.writerow([])
            writer.writerow(["# === VALIDATION METRICS ==="])
            writer.writerow([
                "# signal", "RMSE", "MAE", "Max_abs_err",
                "Rel_RMSE_percent", "DTW", "Status"
            ])
            for r in results:
                rel = r["rel_rmse"]
                rel_str = f"{rel*100:.6f}" if not math.isnan(rel) else "N/A"
                dtw_val = r.get("dtw", float("nan"))
                dtw_str = f"{dtw_val:.6g}" if not math.isnan(dtw_val) else "N/A"
                if tol is not None:
                    status = "PASS" if r["rmse"] <= tol else "FAIL"
                else:
                    status = "N/A"
                writer.writerow([
                    f"# {r['signal']}",
                    f"{r['rmse']:.10g}",
                    f"{r['mae']:.10g}",
                    f"{r['max_abs']:.10g}",
                    rel_str,
                    dtw_str,
                    status,
                ])
    except Exception as e:
        print(f"  [warn] could not append metrics to results: {e}")


def compare(
    ref_path: str,
    out_path: str,
    signals: Optional[List[str]] = None,
    tol: Optional[float] = None,
    shift: float = 0.0,
    use_dtw: bool = True,
    metrics_path: Optional[str] = None,
    append_to_results: bool = True,
) -> bool:
    """Compare two CSV files signal by signal.
    Returns True if all signals pass (RMSE <= tol).
    Importable from CI pipeline scripts.

    metrics_path       : if given, write a standalone metrics CSV here
    append_to_results  : if True, append metric rows to the bottom of out_path
    """
    ref_t, ref_sigs = load_csv(ref_path)
    out_t, out_sigs = load_csv(out_path)

    shared = sorted(set(ref_sigs.keys()) & set(out_sigs.keys()))
    if not shared:
        print("ERROR: no shared signal columns between the two files.")
        print(f"  Reference signals: {list(ref_sigs.keys())}")
        print(f"  Output signals:    {list(out_sigs.keys())}")
        return False

    if signals:
        missing = [s for s in signals if s not in shared]
        if missing:
            print(f"ERROR: signals not found in both files: {missing}")
            return False
        compare_signals = [s for s in signals if s in shared]
    else:
        compare_signals = shared

    results = []
    for sig in compare_signals:
        ref_vals, out_vals = align(
            ref_t, ref_sigs[sig],
            out_t, out_sigs[sig],
            shift
        )
        n = len(ref_vals)
        mean_signed = (
            sum(r - o for r, o in zip(ref_vals, out_vals)) / n if n else 0.0
        )
        dtw_val = float("nan")
        if use_dtw:
            try:
                dtw_val = compute_dtw(ref_vals, out_vals)
            except Exception:
                dtw_val = float("nan")

        results.append({
            "signal":      sig,
            "rmse":        compute_rmse(ref_vals, out_vals),
            "mae":         compute_mae(ref_vals, out_vals),
            "max_abs":     compute_max_abs(ref_vals, out_vals),
            "rel_rmse":    compute_rel_rmse(ref_vals, out_vals),
            "dtw":         dtw_val,
            "abs_errors":  compute_abs_errors(ref_vals, out_vals),
            "mean_signed": mean_signed,
        })

    all_pass = print_report(results, tol, ref_path, out_path, use_dtw)

    # Save metrics so they live in the results, not only on screen
    model_name = ""
    base = out_path.replace("\\", "/").split("/")[-1]
    if base.startswith("results_"):
        model_name = base[len("results_"):].rsplit(".", 1)[0]

    if metrics_path:
        write_metrics_csv(results, metrics_path, tol, model_name)
    if append_to_results:
        append_metrics_to_results(results, out_path, tol)

    return all_pass


# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare FMU simulation output against a golden reference CSV.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("reference", help="Golden reference CSV")
    parser.add_argument("output",    help="FMU pipeline output CSV")
    parser.add_argument(
        "--signals", nargs="+", metavar="SIG",
        help="Signal names to compare (default: all shared columns)"
    )
    parser.add_argument(
        "--tol", type=float, default=None,
        help="RMSE tolerance; exit code 1 if exceeded"
    )
    parser.add_argument(
        "--shift", type=float, default=0.0,
        help="Time shift in seconds applied to output before comparison"
    )
    parser.add_argument(
        "--no-dtw", action="store_true",
        help="Skip DTW (faster, no dtaidistance library needed)"
    )
    parser.add_argument(
        "--metrics-csv", default=None, metavar="PATH",
        help="Write a standalone metrics CSV to this path"
    )
    parser.add_argument(
        "--no-append", action="store_true",
        help="Do not append metric rows to the bottom of the output CSV"
    )
    args = parser.parse_args()

    try:
        passed = compare(
            ref_path=args.reference,
            out_path=args.output,
            signals=args.signals,
            tol=args.tol,
            shift=args.shift,
            use_dtw=not args.no_dtw,
            metrics_path=args.metrics_csv,
            append_to_results=not args.no_append,
        )
    except FileNotFoundError as e:
        print(f"ERROR: {e}")
        return 2

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
