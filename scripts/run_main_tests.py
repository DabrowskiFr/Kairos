#!/usr/bin/env python3
import argparse
import os
import re
import subprocess
import sys


RESULT_RE = re.compile(r"Prover result is:\s*([A-Za-z]+)")


def run_cmd(cmd, cwd, timeout=None):
    try:
        res = subprocess.run(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        return res.returncode, res.stdout + res.stderr
    except subprocess.TimeoutExpired as exc:
        output = ""
        if exc.stdout:
            output += exc.stdout
        if exc.stderr:
            output += exc.stderr
        return 124, output


def parse_why3_output(output):
    results = RESULT_RE.findall(output)
    total = len(results)
    proved = sum(1 for r in results if r.lower() == "valid")
    return total, proved


def format_table(rows, headers):
    widths = [len(h) for h in headers]
    for row in rows:
        for i, col in enumerate(row):
            widths[i] = max(widths[i], len(col))
    line = "+".join("-" * (w + 2) for w in widths)
    out = []
    out.append(line)
    out.append(
        "|".join(" " + h.ljust(widths[i]) + " " for i, h in enumerate(headers))
    )
    out.append(line)
    for row in rows:
        out.append(
            "|".join(" " + row[i].ljust(widths[i]) + " " for i in range(len(headers)))
        )
    out.append(line)
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(
        description="Run main examples and report VC stats."
    )
    parser.add_argument(
        "--provers",
        default="alt-ergo,z3",
        help="Comma-separated prover list (default: alt-ergo,z3).",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Why3 per-goal timeout in seconds (default: 30).",
    )
    parser.add_argument(
        "--example",
        help="Run a single example (path or filename under examples/main).",
    )
    args = parser.parse_args()

    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    examples_dir = os.path.join(root_dir, "examples", "main")
    out_dir = os.path.join(root_dir, "out")
    os.makedirs(out_dir, exist_ok=True)

    provers = [p.strip() for p in args.provers.split(",") if p.strip()]
    if not provers:
        print("No provers specified.", file=sys.stderr)
        return 2

    if args.example:
        if args.example.endswith(".obc"):
            ex_name = os.path.basename(args.example)
        else:
            ex_name = args.example + ".obc"
        if os.path.isabs(args.example) or os.path.sep in args.example:
            ex_path_full = os.path.normpath(args.example)
            if not ex_path_full.startswith(examples_dir + os.path.sep):
                print("Example must be under examples/main.", file=sys.stderr)
                return 2
            ex_name = os.path.basename(ex_path_full)
        examples = [ex_name]
    else:
        examples = sorted(
            f for f in os.listdir(examples_dir) if f.endswith(".obc")
        )
    if not examples:
        print("No examples found in examples/main.", file=sys.stderr)
        return 2

    rows = []
    total_examples = len(examples)
    for idx, ex in enumerate(examples, start=1):
        ex_path = os.path.join("examples", "main", ex)
        base = os.path.splitext(ex)[0]
        out_why = os.path.join("out", base + "_monitor.why")

        print(f"[{idx}/{total_examples}] generate {ex} (monitor)", file=sys.stderr)
        gen_cmd = ["dune", "exec", "--", "obc2why3"]
        gen_cmd.append("--monitor")
        gen_cmd.append(ex_path)
        gen_code, gen_out = run_cmd(gen_cmd, cwd=root_dir)
        if gen_code == 0:
            with open(os.path.join(root_dir, out_why), "w", encoding="utf-8") as f:
                f.write(gen_out)
            gen_ok = True
        else:
            gen_ok = False

        for prover in provers:
            if not gen_ok:
                print(
                    f"[{idx}/{total_examples}] prove {ex} with {prover}: fail",
                    file=sys.stderr,
                )
                rows.append(
                    [
                        ex,
                        prover,
                        "KO",
                        "0",
                        "0",
                        "0",
                        "KO",
                    ]
                )
                continue

            prove_cmd = [
                "why3",
                "prove",
                "-P",
                prover,
                "-t",
                str(args.timeout),
                "-a",
                "split_vc",
                out_why,
            ]
            code, output = run_cmd(prove_cmd, cwd=root_dir, timeout=None)
            total, proved = parse_why3_output(output)
            unproved = total - proved
            ok = gen_ok and total > 0 and unproved == 0 and code == 0
            status = "success" if ok else "fail"
            print(
                f"[{idx}/{total_examples}] prove {ex} with {prover}: {status}",
                file=sys.stderr,
            )
            rows.append(
                [
                    ex,
                    prover,
                    "OK" if gen_ok else "KO",
                    str(total),
                    str(proved),
                    str(unproved),
                    "OK" if ok else "KO",
                ]
            )

    headers = ["Example", "Prover", "Gen", "VC", "Proved", "Unproved", "Status"]
    print(format_table(rows, headers))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
