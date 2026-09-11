#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# =============================================================================
# betaTable_filter.py
# -----------------------------------------------------------------------------
# Developed by: zalkaposzt
# Property of: University of Oklahoma Health Sciences Center, Yabluchanskiy Lab
# Contact:     zalan-kaposzta@ou.edu
# Date:        2024-2026
# -----------------------------------------------------------------------------
# Access docs by command: python betaTable_filter.py --help

from __future__ import annotations
import argparse, json, os, re, shutil, sys
from dataclasses import dataclass, field
from typing import Iterable, Sequence
import pandas as pd

__version__ = "2.0"

# Environment variables
SOURCE_COL = "source"
DETECTOR_COL = "detector"
TYPE_COL = "type"
TABLE_EXTENSIONS = (".csv", ".tsv", ".txt", ".xlsx", ".xls", ".xlsm")
EXCEL_EXTENSIONS = (".xlsx", ".xls", ".xlsm")

# -----------------------------------------------------------------------------
# Montages and channel presets
# -----------------------------------------------------------------------------
# Add to these (similar to the paradigm) to increase the amount of presets;
# additions should theoretically appear in the GUI.

# DEVICE CREATOR
# 'layout' is the device's probe export in layouts/; optional, only the GUI's
# layout viewer uses it.
DEFAULT_MONTAGE = "nirscout"
MONTAGES: dict[str, dict] = {
    "nirscout": {"label": "NIRScout", "note": "Old device", "layout": "nirscout.json"},
    "nirsport": {"label": "NIRSport", "note": "New device", "layout": "nirsport.json"},
}

# PRESET CREATOR
# Acceptable definitions:
#   sources: [x,y,z]
#   pairs: [(x,y),(z,y)]
#   exclude_detectors: [x,y,z] -> avoid central sources pulling in 'rogue' detectors
REGIONS: dict[str, dict] = {
    "prefrontal": {"label": "Prefrontal"},
    "left_dlpfc": {"label": "Left DLPFC"},
}

PRESETS: dict[str, dict[str, dict]] = {
    "nirscout": {
        "prefrontal": {
            "note": "S 1-7, D 10 & 14 dropped.",
            "sources": [1, 2, 3, 4, 5, 6, 7],
            "exclude_detectors": [10, 14],
        },
        "left_dlpfc": {
            "note": "S2-D1, S2-D2, S3-D2, S4-D2.",
            "pairs": [(1,14), (1, 1), (1, 2), (3, 1)],
        },
    },
    "nirsport": {
        "prefrontal": {
            "note": "S 1-4 & 9-13 except 12, D 5 & 12 dropped.",
            "sources": [1, 2, 3, 4, 9, 10, 11, 13],
            "exclude_detectors": [5, 12],
        },
        "left_dlpfc": {
            "note": "Based on 2026/10 lab agreement.",
            "pairs": [(2, 2), (3, 1), (3, 2), (4, 2), (4, 4), (4, 5)],
        },
    },
}

# Rare bug band-aided by Claude, I can't be a**ed to fix it properly, it works.
PRESET_ALIASES: dict[str, tuple[str | None, str]] = {
    "nirscout": ("nirscout", "prefrontal"),
    "nirsport": ("nirsport", "prefrontal"),
    "prefrontal_nirscout": ("nirscout", "prefrontal"),
    "prefrontal_nirsport": ("nirsport", "prefrontal"),
    "ldlfpc": (None, "left_dlpfc"),
}

def split_preset(region: str, montage: str | None = None) -> tuple[str, str]:
    key = str(region).strip().lower()
    if key in PRESET_ALIASES:
        alias_montage, key = PRESET_ALIASES[key]
        if alias_montage:
            return alias_montage, key
    if key not in REGIONS:
        raise KeyError(f"Unknown preset {region!r}. Available: {', '.join(REGIONS)}")
    m = str(montage or DEFAULT_MONTAGE).strip().lower()
    if m not in MONTAGES:
        raise KeyError(f"Unknown montage {montage!r}. Available: {', '.join(MONTAGES)}")
    return m, key


def preset_spec(region: str, montage: str | None = None) -> dict:
    m, r = split_preset(region, montage)
    if r not in PRESETS.get(m, {}):
        raise KeyError(f"No '{r}' preset is defined for the {m} montage.")
    return PRESETS[m][r]


def preset_label(region: str, montage: str | None = None) -> str:
    m, r = split_preset(region, montage)
    return f"{REGIONS[r]['label']} ({MONTAGES[m]['label']})"


def resolve_preset(region: str, pairs_present: Iterable[tuple[int, int]],
                   montage: str | None = None) -> list[tuple[int, int]]:
    """Which of the pairs actually in the data the preset asks to keep."""
    spec = preset_spec(region, montage)
    present = {tuple(p) for p in pairs_present}
    if "pairs" in spec:
        return sorted(present & {tuple(p) for p in spec["pairs"]})
    sources = set(spec.get("sources", []))
    drop_det = set(spec.get("exclude_detectors", []))
    return sorted((s, d) for s, d in present
                  if (not sources or s in sources) and d not in drop_det)


# -----------------------------------------------------------------------------
# Probe layouts
# -----------------------------------------------------------------------------
# Straight from the device's probe export (the JSON with srcPos/detPos/link).
# Drop a new one in layouts/ and point MONTAGES at it; nothing else needs it.
LAYOUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "layouts")


def load_layout(montage: str | None = None) -> dict:
    """Flattened probe geometry: sources/detectors at (x, y), channels with
    their separation in mm, and 10-20 names where the export carries them."""
    m = str(montage or DEFAULT_MONTAGE).strip().lower()
    if m not in MONTAGES:
        raise KeyError(f"Unknown montage {montage!r}. Available: {', '.join(MONTAGES)}")
    name = MONTAGES[m].get("layout")
    if not name:
        raise FileNotFoundError(f"No layout is configured for the {m} montage.")
    with open(os.path.join(LAYOUT_DIR, name), "r", encoding="utf-8") as fh:
        raw = json.load(fh)
    sources = {i: (p[0], p[1]) for i, p in enumerate(raw["srcPos"], start=1)}
    detectors = {i: (p[0], p[1]) for i, p in enumerate(raw["detPos"], start=1)}
    mm = raw.get("distances") or []
    channels: dict[tuple[int, int], float | None] = {}
    for i, link in enumerate(raw.get("link", [])):
        channels.setdefault((int(link["source"]), int(link["detector"])),
                            mm[i] if i < len(mm) else None)
    # anchors sit on the optode they name, so match them in the registered set
    anchors = [(o["Name"], o["X"], o["Y"], o["Z"])
               for o in raw.get("optodes_registered", [])
               if o.get("Type") in ("FID-anchor", "Landmark")]
    labels = {}
    for prefix, key in (("S", "srcPos3D"), ("D", "detPos3D")):
        for n, p in enumerate(raw.get(key, []), start=1):
            for anchor, ax, ay, az in anchors:
                if abs(ax - p[0]) < 1e-3 and abs(ay - p[1]) < 1e-3 \
                        and abs(az - p[2]) < 1e-3:
                    labels[f"{prefix}{n}"] = anchor
                    break
    return {"sources": sources, "detectors": detectors,
            "channels": channels, "labels": labels}


# -----------------------------------------------------------------------------
# I/O helpers -> graphics design isn't my passion
# -----------------------------------------------------------------------------
def read_table(path: str) -> pd.DataFrame:
    ext = os.path.splitext(path)[1].lower()
    if ext in EXCEL_EXTENSIONS:
        return pd.read_excel(path)
    return pd.read_csv(path, sep="\t" if ext == ".tsv" else ",")


def write_table(df: pd.DataFrame, path: str) -> None:
    path = os.path.abspath(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    ext = os.path.splitext(path)[1].lower()
    if ext in EXCEL_EXTENSIONS:
        df.to_excel(path, index=False)
    else:
        df.to_csv(path, sep="\t" if ext == ".tsv" else ",", index=False)


def find_tables(paths: Sequence[str], recursive: bool = True) -> list[str]:
    found: set[str] = set()
    for raw in paths:
        p = os.path.abspath(raw)
        if os.path.isfile(p):
            found.add(p)
            continue
        for root, _dirs, files in os.walk(p):
            found.update(os.path.join(root, f) for f in files
                         if f.lower().endswith(TABLE_EXTENSIONS) and not f.startswith("~$"))
            if not recursive:
                break
    return sorted(found)


def channel_pairs(df: pd.DataFrame) -> list[tuple[int, int]]:
    if SOURCE_COL not in df.columns or DETECTOR_COL not in df.columns:
        return []
    src = pd.to_numeric(df[SOURCE_COL], errors="coerce")
    det = pd.to_numeric(df[DETECTOR_COL], errors="coerce")
    ok = src.notna() & det.notna()
    return sorted({(int(a), int(b)) for a, b in zip(src[ok], det[ok])})


def pairs_in_file(path: str) -> list[tuple[int, int]]:
    return channel_pairs(read_table(path))


def format_pair(pair: tuple[int, int]) -> str:
    return f"S{pair[0]}-D{pair[1]}"


def parse_pairs(text: str) -> list[tuple[int, int]]:
    pairs = []
    for chunk in re.split(r"[,;\s]+", str(text).strip()):
        if not chunk:
            continue
        m = re.fullmatch(r"[Ss]?(\d+)[-_xX:]?[Dd]?(\d+)", chunk)
        if not m:
            raise ValueError(f"Cannot read channel pair {chunk!r}; expected e.g. 2-1 or S2-D1.")
        pairs.append((int(m.group(1)), int(m.group(2))))
    return pairs


# -----------------------------------------------------------------------------
# Filtering
# -----------------------------------------------------------------------------
@dataclass
class FilterOptions:
    #Options: 'hbo', 'hbr', 'hbt' or 'all'
    chromophore: str = "hbo"
    # channel selection: an explicit pair list, or a montage + region preset
    pairs: tuple[tuple[int, int], ...] | None = None
    montage: str = DEFAULT_MONTAGE
    preset: str | None = None
    # significance gate: None disables it
    gate_column: str | None = None
    gate_threshold: float = 0.05

    def describe(self) -> list[str]:
        lines = [f"Chromophore: {self.chromophore}"]
        if self.pairs:
            lines.append(f"Channels: {len(self.pairs)} pairs -- "
                         + ", ".join(format_pair(p) for p in self.pairs))
        elif self.preset:
            lines.append(f"Channels: preset {preset_label(self.preset, self.montage)}")
        else:
            lines.append("Channels: all")
        lines.append(f"Significance gate: {self.gate_column} < {self.gate_threshold}"
                     if self.gate_column else "Significance gate: off")
        return lines


@dataclass
class FileResult:
    path: str
    output: str | None = None
    rows_in: int = 0
    rows_out: int = 0
    steps: list[tuple[str, int]] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    written: bool = False
    error: str | None = None


def apply_filters(df: pd.DataFrame, opts: FilterOptions,
                  result: FileResult | None = None) -> pd.DataFrame:
    """Run every enabled step, in order, and record what each one removed."""
    res = result if result is not None else FileResult(path="<dataframe>")
    res.rows_in = len(df)

    # 1. chromophore
    if opts.chromophore and opts.chromophore.lower() != "all":
        if TYPE_COL in df.columns:
            want = opts.chromophore.lower()
            df = df[df[TYPE_COL].astype(str).str.lower().str.contains(want, na=False)].copy()
            res.steps.append((f"{opts.chromophore} only", len(df)))
        else:
            res.warnings.append(f"no '{TYPE_COL}' column; chromophore filter skipped")

    # 2. channel selection
    wanted = None
    if opts.pairs:
        wanted = {tuple(p) for p in opts.pairs}
    elif opts.preset:
        wanted = set(resolve_preset(opts.preset, channel_pairs(df), opts.montage))
    if wanted is not None:
        if SOURCE_COL in df.columns and DETECTOR_COL in df.columns:
            # -1 stands in for unreadable source/detector cells; it matches nothing
            src = pd.to_numeric(df[SOURCE_COL], errors="coerce").fillna(-1).astype(int)
            det = pd.to_numeric(df[DETECTOR_COL], errors="coerce").fillna(-1).astype(int)
            keys = pd.Series(list(zip(src, det)), index=df.index, dtype=object)
            df = df[keys.isin(wanted)].copy()
            res.steps.append((f"{len(wanted)} channel pairs", len(df)))
        else:
            res.warnings.append(
                f"no '{SOURCE_COL}'/'{DETECTOR_COL}' columns; channel filter skipped")

    # 3. significance gate
    if opts.gate_column:
        if opts.gate_column in df.columns:
            values = pd.to_numeric(df[opts.gate_column], errors="coerce")
            missing = int(values.isna().sum())
            if missing:
                res.warnings.append(
                    f"{missing} row(s) had a non-numeric {opts.gate_column} and were dropped")
            df = df[values < opts.gate_threshold].copy()
            res.steps.append((f"{opts.gate_column} < {opts.gate_threshold}", len(df)))
        else:
            res.warnings.append(
                f"no '{opts.gate_column}' column; significance gate skipped")

    res.rows_out = len(df)
    if res.rows_out == 0 and res.rows_in > 0:
        res.warnings.append("nothing survived the filters -- output would be empty")
    return df


def process_file(input_path: str, output_path: str | None, opts: FilterOptions,
                 dry_run: bool = False, backup: bool = False,
                 skip_empty: bool = False) -> FileResult:
    """Filter one file and (unless dry_run) write the result."""
    res = FileResult(path=input_path, output=output_path)
    try:
        df = read_table(input_path)
    except Exception as exc:
        res.error = f"could not read: {exc}"
        return res

    try:
        out = apply_filters(df, opts, res)
    except Exception as exc:
        res.error = f"could not filter: {exc}"
        return res

    if dry_run or output_path is None:
        return res
    if skip_empty and res.rows_out == 0:
        res.error = "skipped: nothing survived the filters"
        return res

    try:
        same_file = os.path.abspath(output_path) == os.path.abspath(input_path)
        if backup and same_file and os.path.exists(input_path):
            bak = input_path + ".bak"
            if not os.path.exists(bak):
                shutil.copy2(input_path, bak)
        write_table(out, output_path)
        res.written = True
    except Exception as exc:
        res.error = f"could not write: {exc}"
    return res


def plan_output_path(input_path: str, out_dir: str, base_root: str | None = None,
                     suffix: str = "", preserve_tree: bool = True,
                     prefix_root_name: bool = False) -> str:
    """Where a filtered file should land under `out_dir`."""
    src = os.path.abspath(input_path)
    stem, ext = os.path.splitext(os.path.basename(src))
    parts = [os.path.abspath(out_dir)]
    if preserve_tree and base_root:
        root = os.path.abspath(base_root)
        if prefix_root_name and os.path.isdir(root):
            parts.append(os.path.basename(root.rstrip(os.sep)))
        rel = os.path.relpath(os.path.dirname(src), root)
        if rel not in (".", "") and not rel.startswith(".."):
            parts.append(rel)
    parts.append(f"{stem}{suffix}{ext}")
    return os.path.join(*parts)


# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------
def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="betaTable_filter.py",
        description="Filter nirs-toolbox beta tables by chromophore, channel pair "
                    "and statistical significance.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Run betaTable_filter_gui.py for the point-and-click version.",
    )
    p.add_argument("inputs", nargs="*", help="CSV/Excel files, or folders to scan")
    p.add_argument("-r", "--recursive", action="store_true",
                   help="scan folders recursively (default: top level only)")

    ch = p.add_argument_group("channel selection")
    ch.add_argument("--montage", choices=sorted(MONTAGES), default=DEFAULT_MONTAGE,
                    help=f"which system recorded the data (default: {DEFAULT_MONTAGE})")
    grp = ch.add_mutually_exclusive_group()
    grp.add_argument("--preset", choices=sorted(set(REGIONS) | set(PRESET_ALIASES)),
                     metavar="REGION",
                     help="region to keep: " + ", ".join(sorted(REGIONS))
                          + " (see --list-presets)")
    grp.add_argument("--pairs", help="explicit pairs, e.g. 2-1,2-2,3-2 or S2-D1 S2-D2")

    cl = p.add_argument_group("cleanup")
    cl.add_argument("--chromophore", default="hbo",
                    choices=["hbo", "hbr", "hbt", "all"],
                    help="which chromophore to keep (default: hbo)")

    st = p.add_argument_group("significance gate")
    st.add_argument("--gate", choices=["p", "q"], default=None,
                    help="gate rows on this column (default: no gating)")
    st.add_argument("--alpha", type=float, default=0.05,
                    help="threshold for --gate (default: 0.05)")

    out = p.add_argument_group("output")
    og = out.add_mutually_exclusive_group()
    og.add_argument("-o", "--out-dir", help="write into this folder, mirroring the input tree")
    og.add_argument("-O", "--out-file", help="write a single input to this exact path")
    og.add_argument("--in-place", action="store_true", help="overwrite the input files")
    out.add_argument("--suffix", default="_filtered",
                     help="appended to file names when using --out-dir "
                          "(default: _filtered)")
    out.add_argument("--flat", action="store_true",
                     help="do not mirror the input folder structure")
    out.add_argument("--backup", action="store_true",
                     help="keep a .bak copy when overwriting in place")
    out.add_argument("--skip-empty", action="store_true",
                     help="do not write a file when no rows survive "
                          "(default: write the header-only table)")
    out.add_argument("-n", "--dry-run", action="store_true",
                     help="report row counts without writing anything")

    info = p.add_argument_group("information")
    info.add_argument("--list-presets", action="store_true", help="show the presets and exit")
    info.add_argument("--list-pairs", action="store_true",
                      help="show the channel pairs in the first input and exit")
    info.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    return p


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.list_presets:
        for montage, regions in PRESETS.items():
            print(f"{MONTAGES[montage]['label']}  (--montage {montage})")
            for region, spec in regions.items():
                flag = "  [UNVERIFIED]" if spec.get("unverified") else ""
                print(f"  --preset {region:<14} {REGIONS[region]['label']}{flag}")
                print(f"  {'':<23} {spec.get('note', '')}")
            print()
        return 0

    if not args.inputs:
        parser.error("no input given")

    files = find_tables(args.inputs, recursive=args.recursive)
    if not files:
        print("No CSV/Excel files found in the given paths.", file=sys.stderr)
        return 1

    if args.list_pairs:
        pairs = pairs_in_file(files[0])
        print(f"{len(pairs)} channel pairs in {files[0]}:")
        print("  " + ", ".join(format_pair(pr) for pr in pairs))
        return 0

    try:
        montage, preset = (split_preset(args.preset, args.montage) if args.preset
                           else (args.montage, None))
        opts = FilterOptions(
            chromophore=args.chromophore,
            pairs=tuple(parse_pairs(args.pairs)) if args.pairs else None,
            montage=montage,
            preset=preset,
            gate_column=args.gate,
            gate_threshold=args.alpha,
        )
    except (ValueError, KeyError) as exc:
        parser.error(str(exc))

    if args.out_file and len(files) > 1:
        parser.error("--out-file takes a single input; use --out-dir for several")
    if not (args.out_dir or args.out_file or args.in_place or args.dry_run):
        parser.error("choose an output: --out-dir, --out-file, --in-place or --dry-run")

    if opts.preset and preset_spec(opts.preset, opts.montage).get("unverified"):
        print(f"  WARNING: the {preset_label(opts.preset, opts.montage)} preset is a "
              "placeholder and has not been checked against the real probe layout.",
              file=sys.stderr)
    for line in opts.describe():
        print(f"  {line}")
    print(f"  {len(files)} file(s) to process\n")

    failures = 0
    for path in files:
        if args.dry_run:
            dest = None
        elif args.in_place:
            dest = path
        elif args.out_file:
            dest = args.out_file
        else:
            root = next((os.path.abspath(i) for i in args.inputs
                         if os.path.isdir(i)
                         and os.path.abspath(path).startswith(os.path.abspath(i) + os.sep)),
                        None)
            dest = plan_output_path(path, args.out_dir, base_root=root,
                                    suffix=args.suffix,
                                    preserve_tree=not args.flat)

        res = process_file(path, dest, opts, dry_run=args.dry_run,
                           backup=args.backup, skip_empty=args.skip_empty)
        trail = " -> ".join(f"{label}: {n}" for label, n in res.steps)
        print(f"{os.path.basename(path)}: {res.rows_in} rows"
              + (f" -> {trail}" if trail else "")
              + f" -> {res.rows_out} kept")
        for w in res.warnings:
            print(f"    warning: {w}")
        if res.error:
            print(f"    ERROR: {res.error}", file=sys.stderr)
            failures += 1
        elif res.written:
            print(f"    written: {res.output}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
