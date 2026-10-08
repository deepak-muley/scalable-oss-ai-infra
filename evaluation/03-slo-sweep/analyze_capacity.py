#!/usr/bin/env python3
"""Find per-replica SLO capacity from a rate sweep and size a deployment.

Inputs (one of):
  --json  GuideLLM benchmark report (schema varies by version; parsed defensively)
  --csv   columns: rps,ttft_p95_ms,itl_p95_ms   (transcribe from any tool)

Capacity C = highest measured achieved RPS whose TTFT p95 and ITL p95 meet the SLO.
replicas   = ceil(peak_rps / (C * target_util))
"""
import argparse, csv, json, math, sys


def rows_from_csv(path):
    with open(path) as f:
        return [
            {"rps": float(r["rps"]), "ttft": float(r["ttft_p95_ms"]), "itl": float(r["itl_p95_ms"])}
            for r in csv.DictReader(f)
        ]


def dig(d, *paths):
    """Return first value found among alternative key paths (schema drift)."""
    for path in paths:
        cur = d
        try:
            for k in path:
                cur = cur[k]
            if cur is not None:
                return float(cur)
        except (KeyError, IndexError, TypeError, ValueError):
            continue
    return None


def rows_from_guidellm(path):
    report = json.load(open(path))
    benches = report.get("benchmarks") or []
    if not benches and "benchmarks" not in report:
        # some versions nest under a list of reports
        for v in report.values() if isinstance(report, dict) else []:
            if isinstance(v, list):
                benches = v
    rows = []
    for b in benches:
        m = b.get("metrics", b)
        rps = dig(m, ("requests_per_second", "successful", "mean"),
                  ("requests_per_second", "mean"), ("request_rate",))
        ttft = dig(m, ("time_to_first_token_ms", "successful", "percentiles", "p95"),
                   ("time_to_first_token_ms", "percentiles", "p95"), ("ttft_p95_ms",))
        itl = dig(m, ("inter_token_latency_ms", "successful", "percentiles", "p95"),
                  ("inter_token_latency_ms", "percentiles", "p95"), ("itl_p95_ms",))
        if None not in (rps, ttft, itl):
            rows.append({"rps": rps, "ttft": ttft, "itl": itl})
    if not rows:
        sys.exit("Could not parse this GuideLLM report version; transcribe to CSV and use --csv.")
    return rows


def main():
    ap = argparse.ArgumentParser()
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--json")
    src.add_argument("--csv")
    ap.add_argument("--ttft-p95-ms", type=float, required=True)
    ap.add_argument("--itl-p95-ms", type=float, required=True)
    ap.add_argument("--peak-rps", type=float, required=True)
    ap.add_argument("--gpus-per-replica", type=int, default=1)
    ap.add_argument("--target-util", type=float, default=0.7,
                    help="plan to run replicas at this fraction of C (burst + cold-start headroom)")
    ap.add_argument("--spare-replicas", type=int, default=1, help="N+k for failures/rollouts")
    a = ap.parse_args()

    rows = sorted(rows_from_csv(a.csv) if a.csv else rows_from_guidellm(a.json), key=lambda r: r["rps"])
    print(f"{'RPS':>8} {'TTFT p95 ms':>12} {'ITL p95 ms':>11}  SLO")
    for r in rows:
        ok = r["ttft"] <= a.ttft_p95_ms and r["itl"] <= a.itl_p95_ms
        r["ok"] = ok
        print(f"{r['rps']:8.2f} {r['ttft']:12.0f} {r['itl']:11.1f}  {'PASS' if ok else 'fail'}")

    passing = [r for r in rows if r["ok"]]
    if not passing:
        sys.exit("\nNo rate meets the SLO: relax the SLO, change the setup (TP, FP8, routing) or reduce prompt size.")
    c = max(r["rps"] for r in passing)
    replicas = math.ceil(a.peak_rps / (c * a.target_util))
    total = replicas + a.spare_replicas
    print(f"""
SLO: TTFT p95 <= {a.ttft_p95_ms:.0f} ms, ITL p95 <= {a.itl_p95_ms:.0f} ms
Per-replica capacity C          = {c:.2f} req/s
Planned load per replica        = {c * a.target_util:.2f} req/s (target util {a.target_util:.0%})
Replicas for peak {a.peak_rps:g} req/s  = {replicas}  (+{a.spare_replicas} spare = {total})
GPUs                            = {total * a.gpus_per_replica}  ({a.gpus_per_replica} per replica)
KEDA hint: scale out before a replica exceeds ~{c * a.target_util:.1f} req/s or its queue grows.""")


if __name__ == "__main__":
    main()
