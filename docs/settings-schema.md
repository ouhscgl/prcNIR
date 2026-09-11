# prcNIR settings schema (v1)

One JSON file holds one or more **profiles**. A profile is everything needed to
go from a folder of recordings to a set of figures and tables: paths, montage,
stimulus naming, the processing pipeline, and the contrasts to draw.

The UI reads and writes this file. So can you, by hand. They produce the same
thing — that is the point of the file existing.

```
{
  "schema_version": 1,
  "profiles": { "<key>": { ...profile... } }
}
```

`<key>` must be a valid MATLAB identifier (letters, digits, underscore, not
starting with a digit). The UI enforces this; hand-written files are checked.

---

## Profile

| Field | Type | Notes |
|---|---|---|
| `label` | string | Shown in the UI profile picker |
| `notes` | string | Free text, never read by code |
| `paths` | object | See below |
| `montage` | string | Key into `configs/montages/` |
| `dataset` | object | How subjects are discovered |
| `stimulus` | object | Marker naming and timing |
| `pipeline` | object | The analysis itself |
| `visualize` | object | Contrasts and figure output |

### `paths`

```json
"paths": { "data_root": "", "output_dir": "", "clean_dir": "" }
```

Absolute, or relative to the settings file's own folder. Empty means "ask me".

### `dataset`

```json
"dataset": { "folder_structure": ["group", "subject"] }
```

Folder levels are read **from the leaf upward**, so `["group","subject"]` means
the recording's own folder names the subject and its parent names the group.
Each entry becomes a demographics field on the loaded data. An empty list skips
demographics entirely.

### `stimulus`

```json
"stimulus": { "names": ["nback0a","nback1a","nback0b","nback2a"],
              "onset": null, "duration": 72 }
```

`names` are applied **in sorted marker order** — the first marker in the
recording becomes `names[0]`. This is the single easiest thing to get wrong;
the Process tab shows the resulting mapping before anything runs.

`null` anywhere in the schema means *use the default*. For `onset` and
`duration` the default is "keep whatever the recording carries".

A scalar `duration` applies to every stimulus; a list applies element-wise.

---

## `pipeline`

### `preprocess` — a list of nirs-toolbox modules, in order

```json
"preprocess": [
  {"module": "TrimBaseline",         "preBaseline": 10, "postBaseline": 10},
  {"module": "LabelShortSeperation", "max_distance": 10},
  {"module": "LabeltooLongDistance", "min_distance": 50},
  {"module": "RemovetooLongDistance"},
  {"module": "OpticalDensity"},
  {"module": "TDDR"},
  {"module": "BeerLambertLaw"}
]
```

`module` names a class in `nirs.modules`. Every other key is set as a property
on that module, and is checked against the class's real property list before
the run starts — a typo fails immediately instead of thirty minutes in.

Any step may carry `"enabled": false` to keep it in the file but skip it.

### `glm`

```json
"glm": {
  "module": "GLM",
  "trend": { "type": "dct", "value": 0.009 },
  "add_short_sep_regressors": true,
  "remove_short_seperations": true
}
```

`trend` is sugar for a function handle, which JSON cannot hold:

| `type` | Becomes |
|---|---|
| `"dct"` | `@(t) nirs.design.trend.dctmtx(t, value)` |
| `"legendre"` | `@(t) nirs.design.trend.legendre(t, value)` |
| `"constant"` | `@(t) nirs.design.trend.constant(t)` |
| `"none"` | module default |

`add_short_sep_regressors` is honoured only when the probe actually carries a
`ShortSeperation` column; otherwise it is skipped with a note in the run report.

### `group` — one or more models

```json
"group": {
  "module": "MixedEffects",
  "models": [
    {"name": "group_main",    "formula": "beta ~ -1 + group + (1|subject)"},
    {"name": "group_by_cond", "formula": "beta ~ -1 + group:cond + (1|subject)"}
  ]
}
```

Each model is fitted separately and keeps its `name`. Contrasts reference a
model by that name, which is what stops a contrast built for one formula from
being silently applied to another — the failure mode the old positional
`results(iter)` array invited.

### `post`

```json
"post": [ {"module": "CalculateTotalHb", "enabled": false} ]
```

Modules applied to the fitted stats rather than the time series. This is the
right place for HbT: `CalculateTotalHb` takes the sum in beta space and appends
proper `hbt` rows, instead of summing the signal before the model sees it.

---

## `visualize`

```json
"visualize": {
  "model": "group_by_cond",
  "significance": ["p", "q"],
  "threshold": 0.05,
  "tstat_range": [-8, 8],
  "chromophores": ["hbo", "hbr"],
  "save_table": true,
  "draw_method": "10-20 map",
  "fig_format": "svg",
  "output_prefix": "",
  "contrasts": [ ... ]
}
```

`model` is the default for contrasts that do not name one themselves.
`draw_method` accepts any string `nirs.core.Probe1020` accepts — there are
around thirty, including `"10-20 map zoom label"` and `"3D mesh (left)"`.

### Contrasts

Two forms. Prefer the first.

```json
{"name": "2b-0b", "model": "group_by_cond",
 "weights": [ {"condition": "cond_nback2a", "value":  1},
              {"condition": "cond_nback0a", "value": -1} ]}
```

Named weights are resolved against the model's real condition list at run time,
so they do not care what order the conditions come out in. Unmatched names are
a hard error listing what was actually available.

```json
{"name": "2b-0b", "model": "group_by_cond", "vector": [0, 1, 0, -1]}
```

Positional, legacy, and only valid for one specific condition ordering. Kept so
old configs keep working. The UI writes the named form.

`weights` is a **list of pairs**, not an object, because MATLAB's `jsondecode`
mangles object keys that are not valid identifiers — and condition names from
`MixedEffects` routinely contain `:`.

---

## Round-tripping

`prc.loadSettings` overlays the file onto `prc.defaults`; `prc.saveSettings`
writes back only what differs, so a hand-written file stays readable and does
not acquire fifty default keys the first time someone opens it in the UI.

Shape normalisation happens on load, because `jsondecode` is ambiguous: a list
of objects with identical fields becomes a struct array, with differing fields a
cell array, and a one-element list of strings may come back as a bare string.
Everything list-shaped is normalised to a cell array before any code sees it.
