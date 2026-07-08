"""
plot_results.py -- Generate validation plots for FMU co-simulation results

Produces two plots per signal:
  1. Reference vs FMU output on same graph
  2. Absolute error over time

Usage:
    python plot_results.py reference.csv results.csv
    python plot_results.py reference.csv results.csv --title "Cruise Control"
    python plot_results.py reference.csv results.csv --output plots/
    python plot_results.py reference.csv results.csv --signals Velocity

Examples:
    python plot_results.py cruise_control_reference.csv results_cruise_control.csv --title "Cruise Control"
    python plot_results.py motor_speed_reference.csv results_motor_speed.csv --title "Motor Speed"
    python plot_results.py suspension_reference.csv results_suspension.csv --title "Suspension"
"""

import csv
import os
import sys
import argparse
import math


def load_csv(path):
    """Load CSV file, return (time_array, {signal_name: values_array})."""
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        cols = reader.fieldnames
        data = {c: [] for c in cols}
        for row in reader:
            for c in cols:
                data[c].append(float(row[c]))

    # Find time column
    time_col = None
    for candidate in ["time", "Time", "TIME", "t"]:
        if candidate in data:
            time_col = candidate
            break
    if time_col is None:
        time_col = cols[0]

    t = data.pop(time_col)
    return t, data


def interpolate(source_t, source_vals, target_t):
    """Linearly interpolate source values onto target_t grid."""
    result = []
    j = 0
    for ti in target_t:
        while j < len(source_t) - 2 and source_t[j + 1] < ti - 1e-12:
            j += 1
        if j >= len(source_t) - 1:
            result.append(source_vals[-1])
        elif abs(source_t[j] - ti) < 1e-12:
            result.append(source_vals[j])
        else:
            # Linear interpolation
            t0, t1 = source_t[j], source_t[j + 1]
            v0, v1 = source_vals[j], source_vals[j + 1]
            frac = (ti - t0) / (t1 - t0) if t1 != t0 else 0
            result.append(v0 + frac * (v1 - v0))
    return result


def compute_metrics(ref, out):
    """Compute RMSE, max absolute error, mean error."""
    n = len(ref)
    abs_errs = [abs(r - o) for r, o in zip(ref, out)]
    sq_errs = [(r - o) ** 2 for r, o in zip(ref, out)]
    rmse = math.sqrt(sum(sq_errs) / n)
    max_err = max(abs_errs)
    mean_err = sum(r - o for r, o in zip(ref, out)) / n
    return rmse, max_err, mean_err, abs_errs


def plot_signal(plot_t, ref_vals, out_vals, abs_errs, signal_name, title,
                rmse, max_err, output_dir, reference_label, output_label,
                comparison_title):
    """Generate two plots for one signal."""
    # Import matplotlib here so script can still be used without it
    # for just computing metrics
    import matplotlib
    matplotlib.use("Agg")  # non-interactive backend
    import matplotlib.pyplot as plt

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 7),
                                    gridspec_kw={"height_ratios": [3, 1]})
    fig.suptitle(title, fontsize=14, fontweight="bold")

    # ---- Plot 1: Reference vs FMU output ----
    ax1.plot(plot_t, ref_vals, color="#1f77b4", linewidth=1.5,
             label=reference_label, alpha=0.9)
    ax1.plot(plot_t, out_vals, color="#ff7f0e", linewidth=1.5,
             label=output_label, linestyle="--", alpha=0.9)
    ax1.set_xlabel("Time (s)")
    ax1.set_ylabel(signal_name)
    ax1.legend(loc="best", framealpha=0.9)
    ax1.grid(True, alpha=0.3)
    ax1.set_title(comparison_title, fontsize=11)

    # Add RMSE annotation
    ax1.text(0.98, 0.02,
             f"RMSE = {rmse:.6g}\nMax |err| = {max_err:.6g}",
             transform=ax1.transAxes, fontsize=9,
             verticalalignment="bottom", horizontalalignment="right",
             bbox=dict(boxstyle="round,pad=0.3", facecolor="lightyellow",
                       edgecolor="gray", alpha=0.8))

    # ---- Plot 2: Absolute error over time ----
    ax2.fill_between(plot_t, abs_errs, color="#d62728", alpha=0.3)
    ax2.plot(plot_t, abs_errs, color="#d62728", linewidth=1.0)
    ax2.set_xlabel("Time (s)")
    ax2.set_ylabel("|Error|")
    ax2.set_title(f"Absolute Error Over Time", fontsize=11)
    ax2.grid(True, alpha=0.3)

    # Scientific notation for very small errors
    ax2.ticklabel_format(axis="y", style="scientific", scilimits=(-3, 3))

    plt.tight_layout()

    # Save
    safe_name = signal_name.replace(" ", "_").replace("/", "_")
    if title:
        safe_title = title.replace(" ", "_").replace("/", "_")
        filename = f"{safe_title}_{safe_name}.png"
    else:
        filename = f"plot_{safe_name}.png"

    filepath = os.path.join(output_dir, filename)
    plt.savefig(filepath, dpi=150, bbox_inches="tight")
    plt.close()
    print(f"  Saved: {filepath}")
    return filepath


def main():
    parser = argparse.ArgumentParser(
        description="Generate validation plots for FMU co-simulation results")
    parser.add_argument("reference", help="MATLAB reference CSV file")
    parser.add_argument("results", help="FMU results CSV file")
    parser.add_argument("--title", default="",
                        help="Plot title (e.g. 'Cruise Control')")
    parser.add_argument("--output", default=".",
                        help="Output directory for PNG files")
    parser.add_argument("--signals", nargs="*", default=None,
                        help="Specific signals to plot (default: all shared)")
    parser.add_argument("--reference-label", default="MATLAB Reference",
                        help="Legend label for the reference signal")
    parser.add_argument("--output-label", default="FMU Output (generic.py)",
                        help="Legend label for the generated output signal")
    parser.add_argument("--comparison-title", default="Reference vs FMU Output",
                        help="Subtitle for the comparison plot")
    args = parser.parse_args()

    # Create output directory if needed
    if args.output != "." and not os.path.exists(args.output):
        os.makedirs(args.output)

    # Load both files
    print(f"Loading reference: {args.reference}")
    ref_t, ref_sigs = load_csv(args.reference)
    print(f"  {len(ref_t)} rows, signals: {list(ref_sigs.keys())}")

    print(f"Loading results:   {args.results}")
    out_t, out_sigs = load_csv(args.results)
    print(f"  {len(out_t)} rows, signals: {list(out_sigs.keys())}")

    # Find shared signals
    shared = sorted(set(ref_sigs.keys()) & set(out_sigs.keys()))
    if args.signals:
        shared = [s for s in args.signals if s in shared]

    if not shared:
        print("ERROR: no shared signal columns between the two files.")
        print(f"  Reference signals: {list(ref_sigs.keys())}")
        print(f"  Results signals:   {list(out_sigs.keys())}")
        return 1

    print(f"Shared signals: {shared}")
    print()

    # Interpolate output onto reference time grid, matching compare.py.
    need_interp = len(ref_t) != len(out_t) or any(
        abs(a - b) > 1e-12 for a, b in zip(ref_t, out_t)
    )
    if need_interp:
        print(f"  Reference has {len(ref_t)} rows, results has {len(out_t)} rows")
        print(f"  Interpolating results onto reference time grid")
        print()

    # Plot each signal
    all_files = []
    for sig in shared:
        plot_t = ref_t
        ref_vals = ref_sigs[sig]
        if need_interp:
            out_vals = interpolate(out_t, out_sigs[sig], ref_t)
        else:
            out_vals = out_sigs[sig]

        rmse, max_err, mean_err, abs_errs = compute_metrics(ref_vals, out_vals)

        plot_title = f"{args.title} -- {sig}" if args.title else sig

        print(f"Signal: {sig}")
        print(f"  RMSE       = {rmse:.6g}")
        print(f"  Max |err|  = {max_err:.6g}")
        print(f"  Mean err   = {mean_err:.6g}")

        filepath = plot_signal(
            plot_t, ref_vals, out_vals, abs_errs, sig, plot_title, rmse,
            max_err, args.output, args.reference_label, args.output_label,
            args.comparison_title,
        )
        all_files.append(filepath)
        print()

    print(f"Done. {len(all_files)} plot(s) generated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
