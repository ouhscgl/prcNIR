#!/usr/bin/env python3
import sys, os, csv, re

TYPE_ORDER = ["hbo", "hbr", "hbt"]
HDR = ["source", "detector", "type", "ShortSeperation", "cond", "beta", "se",
       "tstat", "dfe", "p", "q", "minDiscoverableChange", "RelativePower"]


def hb_of(s):
    if "deoxy-Hb" in s: return "hbr"
    if "total-Hb" in s: return "hbt"
    if "oxy-Hb"  in s: return "hbo"
    return None


def se(beta, t):
    try:
        t = float(t)
        return str(float(beta) / t) if t else ""
    except ValueError:
        return ""


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: glm2csv.py <glm_results.txt>")
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()

    pred_names, con_names = {}, {}
    model    = {t: {} for t in TYPE_ORDER}   # hb -> (src,det) -> [(beta,t,p), ...] per predictor
    contrast = {t: {} for t in TYPE_ORDER}   # hb -> (src,det) -> [(t,p), ...]      per contrast
    channels = []                            # (src,det) in first-seen (probe) order
    mode = hb = None

    for raw in lines:
        s = raw.strip()
        if not s:
            continue
        if s == "NAME OF MAIN PREDICTORS":
            mode = None; continue
        if s.startswith("Model fit per channel for "):
            mode, hb = "model", hb_of(s); continue
        if s.startswith("Contrast results per channel for "):
            mode, hb = "contrast", hb_of(s); continue
        m = re.match(r"Predictor\s+(\d+):\s*(.*)$", s)
        if m: pred_names[int(m.group(1))] = m.group(2).strip(); continue
        m = re.match(r"Contrast\s+(\d+):\s*(.*)$", s)
        if m: con_names[int(m.group(1))] = m.group(2).strip(); continue
        m = re.match(r"S(\d+)-D(\d+):\s*(.*)$", s)
        if m and mode:
            key = (int(m.group(1)), int(m.group(2)))
            if key not in channels: channels.append(key)
            t = m.group(3).split()
            if mode == "model":
                model[hb][key] = [tuple(t[i:i + 3]) for i in range(0, len(t) - len(t) % 3, 3)]
            else:
                contrast[hb][key] = [tuple(t[i:i + 2]) for i in range(0, len(t) - len(t) % 2, 2)]

    out = os.path.splitext(path)[0] + ".csv"
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(HDR)
        for pi in sorted(pred_names):                 # non-contrast rows: cond = predictor label
            cond = pred_names[pi]
            for src, det in channels:
                for hb in TYPE_ORDER:
                    r = model[hb].get((src, det))
                    if r and pi - 1 < len(r):
                        b, t, p = r[pi - 1]
                        w.writerow([src, det, hb, 0, cond, b, se(b, t), t, "", p, "", "", ""])
        for ci in sorted(con_names):                  # contrast rows: no beta/se in source
            cond = con_names[ci]
            for src, det in channels:
                for hb in TYPE_ORDER:
                    r = contrast[hb].get((src, det))
                    if r and ci - 1 < len(r):
                        t, p = r[ci - 1]
                        w.writerow([src, det, hb, 0, cond, "", "", t, "", p, "", "", ""])
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
