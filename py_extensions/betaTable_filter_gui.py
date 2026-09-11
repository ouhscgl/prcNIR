#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# =============================================================================
# betaTable_filter_gui.py
# -----------------------------------------------------------------------------
# Developed by: zalkaposzt
# Property of: University of Oklahoma Health Sciences Center, Yabluchanskiy Lab
# Contact:     zalan-kaposzt@ou.edu
# -----------------------------------------------------------------------------
# Point-and-click front end for betaTable_filter.py. All filtering logic lives
# in the backend; this file only collects settings and shows what happened.
#
#   python betaTable_filter_gui.py
#
# Needs: pandas, and tkinter (bundled with Python on Windows and macOS;
# `sudo apt install python3-tk` on Debian/Ubuntu).
# 'Show layout' needs the device probe exports in layouts/ (see MONTAGES).
# =============================================================================

from __future__ import annotations

import json
import math
import os
import queue
import sys
import threading
import traceback

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import betaTable_filter as btf
except ImportError:
    raise SystemExit(
        "betaTable_filter.py was not found next to betaTable_filter_gui.py.\n"
        "Keep the two files in the same folder."
    )

APP_TITLE = "Beta table filter"
SETTINGS_FILE = os.path.join(os.path.expanduser("~"), ".betaTable_filter_gui.json")
PAD = 8


class BetaTableFilterApp(ttk.Frame):
    def __init__(self, master: tk.Tk):
        super().__init__(master, padding=PAD)
        self.master = master
        self.grid(row=0, column=0, sticky="nsew")
        master.rowconfigure(0, weight=1)
        master.columnconfigure(0, weight=1)

        # path -> the folder it was added from (used to mirror the tree)
        self.files: dict[str, str] = {}
        self.pair_list: list[tuple[int, int]] = []
        self.pair_source = ""
        self.last_preset: str | None = None
        self.layout_win: LayoutWindow | None = None
        self._programmatic_select = False
        self.queue: queue.Queue = queue.Queue()
        self.worker: threading.Thread | None = None

        self._build_variables()
        self._build_layout()
        self._load_settings()
        self._sync_states()
        self.after(80, self._drain_queue)

    # ------------------------------------------------------------------ setup
    def _build_variables(self) -> None:
        self.recursive = tk.BooleanVar(value=True)
        self.use_channels = tk.BooleanVar(value=True)
        self.montage = tk.StringVar(value=btf.DEFAULT_MONTAGE)
        self.chromophore = tk.StringVar(value="hbo")
        self.use_gate = tk.BooleanVar(value=True)
        self.gate_column = tk.StringVar(value="p")
        self.gate_threshold = tk.StringVar(value="0.05")
        self.output_mode = tk.StringVar(value="folder")  # folder | inplace
        self.out_dir = tk.StringVar(value="")
        self.suffix = tk.StringVar(value="_filtered")
        self.mirror_tree = tk.BooleanVar(value=True)
        self.make_backup = tk.BooleanVar(value=True)
        self.status = tk.StringVar(value="No files yet.")

    def _build_layout(self) -> None:
        self.columnconfigure(0, weight=3, minsize=360)
        self.columnconfigure(1, weight=2, minsize=330)
        self.rowconfigure(0, weight=2)
        self.rowconfigure(1, weight=3)
        self.rowconfigure(3, weight=2)

        self._build_files_frame()
        self._build_channels_frame()
        self._build_settings_column()
        self._build_action_bar()
        self._build_log_frame()

    # --- files -------------------------------------------------------------
    def _build_files_frame(self) -> None:
        f = ttk.LabelFrame(self, text="Files to filter", padding=PAD)
        f.grid(row=0, column=0, columnspan=2, sticky="nsew", pady=(0, PAD))
        f.columnconfigure(0, weight=1)
        f.rowconfigure(1, weight=1)

        bar = ttk.Frame(f)
        bar.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 4))
        ttk.Button(bar, text="Add files…", command=self.add_files).pack(side="left")
        ttk.Button(bar, text="Add folder…", command=self.add_folder).pack(side="left", padx=4)
        ttk.Button(bar, text="Remove selected", command=self.remove_selected).pack(side="left")
        ttk.Button(bar, text="Clear list", command=self.clear_files).pack(side="left", padx=4)
        ttk.Checkbutton(bar, text="Include subfolders", variable=self.recursive
                        ).pack(side="left", padx=(8, 0))
        ttk.Label(bar, textvariable=self.status).pack(side="right")

        self.tree = ttk.Treeview(f, columns=("file", "folder"), show="headings",
                                 selectmode="extended", height=4)
        for col, width in (("file", 220), ("folder", 420)):
            self.tree.heading(col, text=col.capitalize())
            self.tree.column(col, width=width, anchor="w")
        self.tree.grid(row=1, column=0, sticky="nsew")
        sb = ttk.Scrollbar(f, orient="vertical", command=self.tree.yview)
        sb.grid(row=1, column=1, sticky="ns")
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.bind("<Delete>", lambda _e: self.remove_selected())

    # --- channels ----------------------------------------------------------
    def _build_channels_frame(self) -> None:
        f = ttk.LabelFrame(self, text="Channels to keep", padding=PAD)
        f.grid(row=1, column=0, sticky="nsew", padx=(0, PAD))
        f.columnconfigure(0, weight=1)
        f.rowconfigure(2, weight=1)

        self.channel_widgets = []
        top = ttk.Frame(f)
        top.grid(row=0, column=0, columnspan=3, sticky="ew")
        ttk.Checkbutton(top, text="Keep only the selected pairs",
                        variable=self.use_channels, command=self._sync_states
                        ).pack(side="left")
        # packed right in reverse, so they read in MONTAGES order on screen
        for key, spec in reversed(list(btf.MONTAGES.items())):
            r = ttk.Radiobutton(top, text=spec["label"], value=key,
                                variable=self.montage, command=self._on_montage_change)
            r.pack(side="right", padx=(6, 0))
            self.channel_widgets.append(r)

        self.pair_info = ttk.Label(f, text="Add a file to read its channel pairs.",
                                   foreground="#666666")
        self.pair_info.grid(row=1, column=0, columnspan=2, sticky="w", pady=(2, 4))

        self.pair_box = tk.Listbox(f, selectmode="extended", exportselection=False,
                                   activestyle="none", height=10, width=12)
        self.pair_box.grid(row=2, column=0, sticky="nsew")
        psb = ttk.Scrollbar(f, orient="vertical", command=self.pair_box.yview)
        psb.grid(row=2, column=1, sticky="ns")
        self.pair_box.configure(yscrollcommand=psb.set)
        self.pair_box.bind("<<ListboxSelect>>", self._on_pair_select)

        side = ttk.Frame(f)
        side.grid(row=2, column=2, sticky="ns", padx=(PAD, 0))
        ttk.Label(side, text="Presets").pack(anchor="w")
        for key, spec in btf.REGIONS.items():
            b = ttk.Button(side, text=spec["label"], width=20,
                           command=lambda k=key: self.apply_preset(k))
            b.pack(fill="x", pady=1)
            self.channel_widgets.append(b)
        ttk.Separator(side, orient="horizontal").pack(fill="x", pady=5)
        both = ttk.Frame(side)
        both.pack(fill="x")
        for text, command in (("All", lambda: self.set_pair_selection(self.pair_list)),
                              ("None", lambda: self.set_pair_selection(()))):
            b = ttk.Button(both, text=text, width=9, command=command)
            b.pack(side="left", expand=True, fill="x")
            self.channel_widgets.append(b)
        b = ttk.Button(side, text="Rescan all files", width=20, command=self.rescan_pairs)
        b.pack(fill="x", pady=(2, 0))
        self.channel_widgets.append(b)
        # deliberately outside channel_widgets: the map stays readable as a
        # reference even when the channel filter is switched off
        ttk.Separator(side, orient="horizontal").pack(fill="x", pady=5)
        ttk.Button(side, text="Show layout…", width=20, command=self.show_layout
                   ).pack(fill="x")

    # --- cleanup / gate / output ------------------------------------------
    def _build_settings_column(self) -> None:
        col = ttk.Frame(self)
        col.grid(row=1, column=1, sticky="nsew")
        col.columnconfigure(0, weight=1)

        # rows
        c = ttk.LabelFrame(col, text="Rows to keep", padding=PAD)
        c.grid(row=0, column=0, sticky="ew")
        ttk.Label(c, text="Chromophore").grid(row=0, column=0, sticky="w")
        ttk.Combobox(c, textvariable=self.chromophore, state="readonly", width=8,
                     values=["hbo", "hbr", "hbt", "all"]
                     ).grid(row=0, column=1, columnspan=3, sticky="w", padx=4)
        ttk.Separator(c, orient="horizontal").grid(row=1, column=0, columnspan=4,
                                                   sticky="ew", pady=8)
        ttk.Checkbutton(c, text="Keep significant rows only", variable=self.use_gate,
                        command=self._sync_states).grid(row=2, column=0, columnspan=4,
                                                        sticky="w")
        grow = ttk.Frame(c)
        grow.grid(row=3, column=0, columnspan=4, sticky="w", padx=(20, 0))
        self.gate_p = ttk.Radiobutton(grow, text="p", variable=self.gate_column, value="p")
        self.gate_q = ttk.Radiobutton(grow, text="q", variable=self.gate_column, value="q")
        self.gate_p.pack(side="left")
        self.gate_q.pack(side="left", padx=(6, 0))
        ttk.Label(grow, text="<").pack(side="left", padx=(8, 4))
        self.gate_entry = ttk.Entry(grow, textvariable=self.gate_threshold, width=8)
        self.gate_entry.pack(side="left")

        # output
        o = ttk.LabelFrame(col, text="Where results go", padding=PAD)
        o.grid(row=1, column=0, sticky="ew", pady=(PAD, 0))
        o.columnconfigure(1, weight=1)
        ttk.Radiobutton(o, text="Write copies to a folder", variable=self.output_mode,
                        value="folder", command=self._sync_states
                        ).grid(row=0, column=0, columnspan=3, sticky="w")
        self.out_entry = ttk.Entry(o, textvariable=self.out_dir)
        self.out_entry.grid(row=1, column=0, columnspan=2, sticky="ew", padx=(20, 4))
        self.out_button = ttk.Button(o, text="Browse…", command=self.pick_out_dir)
        self.out_button.grid(row=1, column=2, sticky="e")
        row = ttk.Frame(o)
        row.grid(row=2, column=0, columnspan=3, sticky="ew", padx=(20, 0))
        ttk.Label(row, text="Add to file names").pack(side="left")
        self.suffix_entry = ttk.Entry(row, textvariable=self.suffix, width=10)
        self.suffix_entry.pack(side="left", padx=4)
        self.mirror_check = ttk.Checkbutton(row, text="Mirror folders",
                                            variable=self.mirror_tree)
        self.mirror_check.pack(side="left", padx=(8, 0))
        ttk.Radiobutton(o, text="Replace the original files", variable=self.output_mode,
                        value="inplace", command=self._sync_states
                        ).grid(row=3, column=0, columnspan=3, sticky="w", pady=(6, 0))
        self.backup_check = ttk.Checkbutton(o, text="Keep a .bak copy of each original",
                                            variable=self.make_backup)
        self.backup_check.grid(row=4, column=0, columnspan=3, sticky="w", padx=(20, 0))

    # --- actions & log -----------------------------------------------------
    def _build_action_bar(self) -> None:
        bar = ttk.Frame(self)
        bar.grid(row=2, column=0, columnspan=2, sticky="ew", pady=PAD)
        bar.columnconfigure(0, weight=1)
        self.progress = ttk.Progressbar(bar, mode="determinate")
        self.progress.grid(row=0, column=0, sticky="ew", padx=(0, PAD))
        self.preview_button = ttk.Button(bar, text="Preview counts", command=self.preview)
        self.preview_button.grid(row=0, column=1)
        self.run_button = ttk.Button(bar, text="Filter files", command=self.confirm_and_run)
        self.run_button.grid(row=0, column=2, padx=(4, 0))

    def _build_log_frame(self) -> None:
        f = ttk.LabelFrame(self, text="Log", padding=PAD)
        f.grid(row=3, column=0, columnspan=2, sticky="nsew")
        f.rowconfigure(0, weight=1)
        f.columnconfigure(0, weight=1)
        self.log_box = tk.Text(f, height=5, wrap="word", state="disabled")
        self.log_box.grid(row=0, column=0, sticky="nsew")
        sb = ttk.Scrollbar(f, orient="vertical", command=self.log_box.yview)
        sb.grid(row=0, column=1, sticky="ns")
        self.log_box.configure(yscrollcommand=sb.set)
        self.log_box.tag_configure("warn", foreground="#9a6700")
        self.log_box.tag_configure("error", foreground="#b3261e")
        self.log_box.tag_configure("good", foreground="#1a7f37")
        self.log_box.tag_configure("head", font=("TkDefaultFont", 10, "bold"))

    # ------------------------------------------------------------------ log
    def log(self, text: str, level: str = "") -> None:
        self.log_box.configure(state="normal")
        self.log_box.insert("end", text + "\n", level)
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    # ---------------------------------------------------------------- files
    def add_files(self) -> None:
        paths = filedialog.askopenfilenames(
            title="Select beta tables",
            filetypes=[("Tables", "*.csv *.tsv *.txt *.xlsx *.xls"), ("All files", "*.*")],
        )
        self._add_paths([(p, os.path.dirname(os.path.abspath(p))) for p in paths])

    def add_folder(self) -> None:
        folder = filedialog.askdirectory(title="Select a folder of beta tables")
        if not folder:
            return
        found = btf.find_tables([folder], recursive=self.recursive.get())
        if not found:
            self.log(f"No tables found in {folder}"
                     + ("" if self.recursive.get() else " (try 'Include subfolders')"), "warn")
            return
        self._add_paths([(p, folder) for p in found])

    def _add_paths(self, items) -> None:
        added = 0
        for path, root in items:
            full = os.path.abspath(path)
            if full in self.files:
                continue
            self.files[full] = os.path.abspath(root)
            self.tree.insert("", "end", iid=full,
                             values=(os.path.basename(full), os.path.dirname(full)))
            added += 1
        if added:
            self.log(f"Added {added} file(s).")
        self._refresh_status()
        if self.pair_list == [] and self.files:
            self._load_pairs([sorted(self.files)[0]])

    def remove_selected(self) -> None:
        for iid in self.tree.selection():
            self.files.pop(iid, None)
            self.tree.delete(iid)
        self._refresh_status()

    def clear_files(self) -> None:
        self.files.clear()
        self.tree.delete(*self.tree.get_children())
        self._refresh_status()

    def _refresh_status(self) -> None:
        n = len(self.files)
        roots = len(set(self.files.values()))
        self.status.set("No files yet." if not n
                        else f"{n} file(s) from {roots} folder(s)")

    # -------------------------------------------------------------- channels
    def _load_pairs(self, paths: list[str], union: bool = False) -> None:
        label = ("all files" if union else os.path.basename(paths[0])) if paths else ""
        self.pair_info.configure(text=f"Reading channel pairs from {label}…")

        def work():
            found: set[tuple[int, int]] = set()
            problems = []
            for p in paths:
                try:
                    found.update(btf.pairs_in_file(p))
                except Exception as exc:
                    problems.append(f"{os.path.basename(p)}: {exc}")
                if not union:
                    break
            self.queue.put(("pairs", sorted(found), label, problems))

        threading.Thread(target=work, daemon=True).start()

    def rescan_pairs(self) -> None:
        if not self.files:
            messagebox.showinfo(APP_TITLE, "Add some files first.")
            return
        self._load_pairs(sorted(self.files), union=True)

    def _set_pairs(self, pairs, label, problems) -> None:
        self.pair_list = pairs
        self.pair_source = label
        self.pair_box.delete(0, "end")
        for pair in pairs:
            self.pair_box.insert("end", btf.format_pair(pair))
        for p in problems:
            self.log(f"Could not read channel pairs -- {p}", "error")
        if not pairs:
            self.pair_info.configure(text="No source/detector columns found in that file.")
            return
        self._update_pair_info()
        self.log(f"Found {len(pairs)} channel pairs in {label}.")

    def _update_pair_info(self) -> None:
        if not self.pair_list:
            self.pair_info.configure(text="Add a file to read its channel pairs.")
        else:
            self.pair_info.configure(
                text=f"{len(self.pair_box.curselection())} of {len(self.pair_list)} pairs "
                     f"selected (read from {self.pair_source})")
        if self.layout_win is not None:
            self.layout_win.redraw()

    def selected_pairs(self) -> list[tuple[int, int]]:
        return [self.pair_list[i] for i in self.pair_box.curselection()]

    def set_pair_selection(self, pairs, preset: str | None = None) -> None:
        """Select exactly these pairs in the list box, whatever asked for them."""
        wanted = set(pairs)
        first = None
        self._programmatic_select = True
        was = self.pair_box.cget("state")
        self.pair_box.configure(state="normal")  # a disabled box ignores selections
        self.pair_box.selection_clear(0, "end")
        for i, pair in enumerate(self.pair_list):
            if pair in wanted:
                self.pair_box.selection_set(i)
                first = i if first is None else first
        self.pair_box.configure(state=was)
        self._programmatic_select = False
        if first is not None:
            self.pair_box.see(first)
        self.last_preset = preset
        self._update_pair_info()

    def _on_pair_select(self, _event=None) -> None:
        if not self._programmatic_select:
            # hand-picked from here on, so don't overwrite it on a montage switch
            self.last_preset = None
        self._update_pair_info()

    def _on_montage_change(self) -> None:
        if self.last_preset:
            self.apply_preset(self.last_preset)
        else:
            self.log(f"Montage set to {btf.MONTAGES[self.montage.get()]['label']}.")
        if self.layout_win is not None:
            self.layout_win.redraw()

    def apply_preset(self, region: str) -> None:
        if not self.pair_list:
            messagebox.showinfo(APP_TITLE, "Load a file first so the presets know "
                                           "which channels exist.")
            return
        montage = self.montage.get()
        try:
            spec = btf.preset_spec(region, montage)
            wanted = set(btf.resolve_preset(region, self.pair_list, montage))
        except (KeyError, ValueError) as exc:
            messagebox.showwarning(APP_TITLE, str(exc))
            return

        self.set_pair_selection(wanted, preset=region)
        self.use_channels.set(True)
        self._sync_states()

        label = btf.preset_label(region, montage)
        missing = len(spec.get("pairs", [])) - len(wanted) if "pairs" in spec else 0
        self.log(f"{label}: {len(wanted)} pair(s) selected."
                 + (f" {missing} preset pair(s) are not in these files." if missing > 0 else ""),
                 "warn" if missing > 0 or not wanted else "")
        if spec.get("unverified"):
            self.log(f"    {label} is a placeholder in betaTable_filter.py and has not "
                     "been checked against the real probe layout.", "warn")

    def show_layout(self) -> None:
        if self.layout_win is None:
            self.layout_win = LayoutWindow(self)
        else:
            self.layout_win.lift()
            self.layout_win.redraw()

    # ----------------------------------------------------------------- state
    def _sync_states(self) -> None:
        busy = self.worker is not None and self.worker.is_alive()
        ch = "normal" if self.use_channels.get() else "disabled"
        self.pair_box.configure(state=ch)
        for w in self.channel_widgets:
            w.configure(state=ch)
        gate = "normal" if self.use_gate.get() else "disabled"
        for w in (self.gate_p, self.gate_q, self.gate_entry):
            w.configure(state=gate)
        folder = self.output_mode.get() == "folder"
        for w in (self.out_entry, self.out_button, self.suffix_entry, self.mirror_check):
            w.configure(state="normal" if folder else "disabled")
        self.backup_check.configure(state="disabled" if folder else "normal")
        self.run_button.configure(state="disabled" if busy else "normal")
        self.preview_button.configure(state="disabled" if busy else "normal")

    def pick_out_dir(self) -> None:
        folder = filedialog.askdirectory(title="Select an output folder")
        if folder:
            self.out_dir.set(folder)

    # ------------------------------------------------------------- gathering
    def _collect_options(self) -> btf.FilterOptions | None:
        pairs = None
        if self.use_channels.get():
            pairs = tuple(self.selected_pairs())
            if not pairs:
                messagebox.showwarning(APP_TITLE,
                                       "No channel pairs are selected. Pick some, use a "
                                       "preset, or untick the channel filter.")
                return None
        threshold = 0.05
        if self.use_gate.get():
            try:
                threshold = float(self.gate_threshold.get())
            except ValueError:
                messagebox.showwarning(APP_TITLE, "The threshold must be a number, e.g. 0.05.")
                return None
            if not 0 < threshold <= 1:
                messagebox.showwarning(APP_TITLE, "The threshold must be between 0 and 1.")
                return None
        return btf.FilterOptions(
            chromophore=self.chromophore.get(),
            pairs=pairs,
            montage=self.montage.get(),
            preset=None,
            gate_column=self.gate_column.get() if self.use_gate.get() else None,
            gate_threshold=threshold,
        )

    def _build_jobs(self, dry_run: bool):
        """Return [(source, destination_or_None)] or None if something is wrong."""
        if not self.files:
            messagebox.showinfo(APP_TITLE, "Add at least one file.")
            return None
        paths = sorted(self.files)
        if dry_run:
            return [(p, None) for p in paths]

        if self.output_mode.get() == "inplace":
            return [(p, p) for p in paths]

        out = self.out_dir.get().strip()
        if not out:
            messagebox.showwarning(APP_TITLE, "Choose an output folder, or switch to "
                                              "replacing the originals.")
            return None
        multi_root = len(set(self.files.values())) > 1
        jobs, seen = [], {}
        for p in paths:
            dest = btf.plan_output_path(
                p, out, base_root=self.files[p], suffix=self.suffix.get(),
                preserve_tree=self.mirror_tree.get(), prefix_root_name=multi_root)
            if os.path.abspath(dest) == os.path.abspath(p):
                messagebox.showwarning(
                    APP_TITLE,
                    "The output would overwrite the input file:\n\n" + p +
                    "\n\nAdd a suffix, choose another folder, or switch to "
                    "replacing the originals on purpose.")
                return None
            if dest in seen:
                messagebox.showwarning(
                    APP_TITLE,
                    "Two inputs would be written to the same file:\n\n"
                    f"{seen[dest]}\n{p}\n\nTick 'Mirror the input folder structure'.")
                return None
            seen[dest] = p
            jobs.append((p, dest))
        return jobs

    # ------------------------------------------------------------------- run
    def preview(self) -> None:
        opts = self._collect_options()
        jobs = self._build_jobs(dry_run=True) if opts else None
        if jobs:
            self._start(jobs, opts, dry_run=True)

    def confirm_and_run(self) -> None:
        opts = self._collect_options()
        jobs = self._build_jobs(dry_run=False) if opts else None
        if not jobs:
            return
        in_place = self.output_mode.get() == "inplace"
        lines = [f"{len(jobs)} file(s) will be filtered.", ""]
        lines += opts.describe()
        lines.append("")
        if in_place:
            lines.append("Destination: the original files, overwritten.")
            lines.append("Backups: " + ("a .bak copy per file" if self.make_backup.get()
                                        else "none"))
        else:
            lines.append(f"Destination: {self.out_dir.get()}")
            lines.append(f"File names get: {self.suffix.get() or '(no suffix)'}")
        lines.append("")
        lines.append("First few:")
        for src, dst in jobs[:3]:
            lines.append(f"  {os.path.basename(src)}  ->  {dst}")
        if len(jobs) > 3:
            lines.append(f"  … and {len(jobs) - 3} more")

        dialog = ConfirmDialog(self.master, "\n".join(lines), destructive=in_place)
        self.master.wait_window(dialog)
        if dialog.accepted:
            self._start(jobs, opts, dry_run=False)

    def _start(self, jobs, opts, dry_run: bool) -> None:
        self.progress.configure(maximum=len(jobs), value=0)
        self.log("")
        self.log(("Preview — nothing will be written" if dry_run
                  else "Filtering files"), "head")
        for line in opts.describe():
            self.log(f"  {line}")
        backup = self.make_backup.get() and self.output_mode.get() == "inplace"

        def work():
            for i, (src, dst) in enumerate(jobs, start=1):
                try:
                    res = btf.process_file(src, dst, opts, dry_run=dry_run, backup=backup)
                except Exception:
                    res = btf.FileResult(path=src, error=traceback.format_exc(limit=1))
                self.queue.put(("result", res, i, len(jobs)))
            self.queue.put(("finished", dry_run, None, None))

        self.worker = threading.Thread(target=work, daemon=True)
        self.worker.start()
        self._sync_states()

    def _drain_queue(self) -> None:
        try:
            while True:
                kind, *payload = self.queue.get_nowait()
                if kind == "pairs":
                    self._set_pairs(*payload)
                elif kind == "result":
                    res, i, _total = payload
                    self._report(res)
                    self.progress.configure(value=i)
                elif kind == "finished":
                    self.log("Preview done." if payload[0] else "Done.", "good")
                    self.worker = None
                    self._sync_states()
        except queue.Empty:
            pass
        self.after(80, self._drain_queue)

    def _report(self, res) -> None:
        trail = "  ".join(f"{label}: {n}" for label, n in res.steps)
        self.log(f"{os.path.basename(res.path)}: {res.rows_in} rows"
                 + (f"  |  {trail}" if trail else "")
                 + f"  |  {res.rows_out} kept")
        for w in res.warnings:
            self.log(f"    {w}", "warn")
        if res.error:
            self.log(f"    {res.error}", "error")
        elif res.written:
            self.log(f"    written to {res.output}", "good")

    # -------------------------------------------------------------- settings
    def _persisted(self) -> dict:
        # output_mode is deliberately not persisted: nobody should find the app
        # already set to overwrite their data on launch.
        return {k: getattr(self, k) for k in (
            "recursive", "montage", "chromophore", "use_gate", "gate_column",
            "gate_threshold", "out_dir", "suffix", "mirror_tree", "make_backup")}

    def _load_settings(self) -> None:
        try:
            with open(SETTINGS_FILE, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception:
            return
        for key, var in self._persisted().items():
            try:
                var.set(data[key])
            except Exception:
                pass

    def _save_settings(self) -> None:
        try:
            with open(SETTINGS_FILE, "w", encoding="utf-8") as fh:
                json.dump({k: v.get() for k, v in self._persisted().items()}, fh, indent=2)
        except Exception:
            pass

    def on_close(self) -> None:
        if self.worker is not None and self.worker.is_alive():
            if not messagebox.askyesno(APP_TITLE, "Filtering is still running. Quit anyway?"):
                return
        self._save_settings()
        self.master.destroy()


class LayoutWindow(tk.Toplevel):
    """The probe map for the current montage, drawn from layouts/<montage>.json.

    Channels in the loaded files can be clicked (or rubber-band dragged) to
    build the selection; everything else is only there for orientation.
    """

    CHOSEN, PRESENT, ABSENT = "#1a7f37", "#7d848d", "#dfe1e5"
    SRC, DET = "#b3261e", "#1f6feb"
    HINT = "click a channel or an optode, box-drag for several, shift-drag to add"

    def __init__(self, app: BetaTableFilterApp):
        super().__init__(app.master)
        self.app = app
        self.title("Probe layout")
        self.geometry("620x560")
        self.minsize(420, 380)
        self.canvas = tk.Canvas(self, background="#ffffff", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.status = ttk.Label(self, text="", padding=(8, 4), foreground="#666666")
        self.status.pack(fill="x")

        self.pair_at: dict[int, tuple[int, int]] = {}     # canvas item -> pair
        self.optode_at: dict[int, tuple[str, int]] = {}   # canvas item -> optode
        self.middles: dict[tuple[int, int], tuple[float, float]] = {}
        self.separation: dict[tuple[int, int], float | None] = {}
        self.press = self.band = None

        self.canvas.bind("<Configure>", lambda _e: self.redraw())
        self.canvas.bind("<Button-1>", self._on_press)
        self.canvas.bind("<B1-Motion>", self._on_drag)
        self.canvas.bind("<ButtonRelease-1>", self._on_release)
        self.canvas.bind("<Motion>", self._on_hover)
        self.bind("<Escape>", lambda _e: self.destroy())
        self.protocol("WM_DELETE_WINDOW", self.destroy)
        self.redraw()

    def destroy(self) -> None:
        self.app.layout_win = None
        super().destroy()

    # ------------------------------------------------------------------ draw
    def redraw(self) -> None:
        c = self.canvas
        c.delete("all")
        self.pair_at.clear()
        self.optode_at.clear()
        self.middles.clear()
        self.separation.clear()
        montage = self.app.montage.get()
        try:
            lay = btf.load_layout(montage)
        except Exception as exc:
            c.create_text(16, 16, anchor="nw", fill=self.SRC,
                          width=max(c.winfo_width() - 32, 100),
                          text=f"No layout to draw for this montage.\n\n{exc}")
            self.status.configure(text="")
            return

        w, h = c.winfo_width(), c.winfo_height()
        spots = list(lay["sources"].values()) + list(lay["detectors"].values())
        xs, ys = [p[0] for p in spots], [p[1] for p in spots]
        pad = 40
        scale = min((w - 2 * pad) / max(max(xs) - min(xs), 1e-9),
                    (h - 2 * pad) / max(max(ys) - min(ys), 1e-9))
        off_x = (w - (max(xs) - min(xs)) * scale) / 2 - min(xs) * scale
        off_y = (h - (max(ys) - min(ys)) * scale) / 2 + max(ys) * scale
        spot = {(kind, n): (off_x + p[0] * scale, off_y - p[1] * scale)
                for kind, key in (("S", "sources"), ("D", "detectors"))
                for n, p in lay[key].items()}
        self._spread(spot)

        present = set(self.app.pair_list)
        chosen = set(self.app.selected_pairs())
        for pair, mm in sorted(lay["channels"].items()):
            start, end = spot.get(("S", pair[0])), spot.get(("D", pair[1]))
            if start is None or end is None:
                continue
            self.middles[pair] = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2)
            self.separation[pair] = mm
            here = pair in present
            item = c.create_line(*start, *end, dash=() if here else (2, 3),
                                 width=4 if pair in chosen else 2,
                                 fill=(self.CHOSEN if pair in chosen else
                                       self.PRESENT if here else self.ABSENT))
            self.pair_at[item] = pair

        for kind, colour in (("D", self.DET), ("S", self.SRC)):
            for (this, n), (x, y) in spot.items():
                if this != kind:
                    continue
                item = c.create_oval(x - 10, y - 10, x + 10, y + 10,
                                     fill=colour, outline="#ffffff", width=2)
                self.optode_at[item] = (kind, n)
                c.create_text(x, y, text=f"{kind}{n}", fill="#ffffff",
                              font=("TkDefaultFont", 7, "bold"))
                anchor = lay["labels"].get(f"{kind}{n}")
                if anchor:
                    c.create_text(x, y + 18, text=anchor, fill="#5f6368",
                                  font=("TkDefaultFont", 7))

        stray = len(present - set(lay["channels"]))
        self.status.configure(
            wraplength=max(w - 16, 120),
            text=f"{btf.MONTAGES[montage]['label']}: {len(present)} of "
                 f"{len(lay['channels'])} channels are in your files, {len(chosen)} selected"
                 + (f" · {stray} pair(s) in your files are not in this layout" if stray else "")
                 + (f" · {self.HINT}" if present else " · add a beta table first"))

    @staticmethod
    def _spread(spot: dict, gap: float = 13.0) -> None:
        """Short-separation twins are exported on top of their partner; fan any
        such stack out around its centre so both stay visible and clickable."""
        keys, done = list(spot), set()
        for i, first in enumerate(keys):
            if first in done:
                continue
            stack = [first] + [k for k in keys[i + 1:]
                               if abs(spot[k][0] - spot[first][0]) < gap
                               and abs(spot[k][1] - spot[first][1]) < gap]
            if len(stack) < 2:
                continue
            cx = sum(spot[k][0] for k in stack) / len(stack)
            cy = sum(spot[k][1] for k in stack) / len(stack)
            for j, k in enumerate(stack):
                angle = 2 * math.pi * j / len(stack)  # sideways: keeps the
                # 10-20 name under each circle clear of its twin
                spot[k] = (cx + gap * math.cos(angle), cy + gap * math.sin(angle))
                done.add(k)

    # --------------------------------------------------------------- picking
    def _pairs_touching(self, kind: str, n: int) -> set[tuple[int, int]]:
        side = 0 if kind == "S" else 1
        return {p for p in self.app.pair_list if p[side] == n}

    def _item_under(self, x, y, table):
        for item in reversed(self.canvas.find_overlapping(x - 4, y - 4, x + 4, y + 4)):
            if item in table:
                return table[item]
        return None

    def _on_hover(self, event) -> None:
        # optodes sit on top of the lines that end in them, so they win a tie
        spot = self._item_under(event.x, event.y, self.optode_at)
        pair = None if spot else self._item_under(event.x, event.y, self.pair_at)
        self.canvas.configure(cursor="hand2" if spot or pair else "")
        if pair is None:
            return
        mm = self.separation.get(pair)
        self.status.configure(
            text=f"{btf.format_pair(pair)}"
                 + (f" — {mm:.0f} mm" if mm else "")
                 + ("" if pair in set(self.app.pair_list) else " — not in your files"))

    def _on_press(self, event) -> None:
        self.press = (event.x, event.y)

    def _on_drag(self, event) -> None:
        if self.press is None:
            return
        x0, y0 = self.press
        if self.band is None and abs(event.x - x0) < 5 and abs(event.y - y0) < 5:
            return
        if self.band is None:
            self.band = self.canvas.create_rectangle(x0, y0, event.x, event.y,
                                                     outline=self.CHOSEN, dash=(3, 3))
        else:
            self.canvas.coords(self.band, x0, y0, event.x, event.y)

    def _on_release(self, event) -> None:
        if self.press is None:
            return
        x0, y0 = self.press
        self.press = None
        present = set(self.app.pair_list)
        chosen = set(self.app.selected_pairs())
        adding = bool(event.state & 0x0001)  # shift

        if self.band is not None:
            self.canvas.delete(self.band)
            self.band = None
            left, right = sorted((x0, event.x))
            top, bottom = sorted((y0, event.y))
            picked = {p for p, (mx, my) in self.middles.items()
                      if p in present and left <= mx <= right and top <= my <= bottom}
            self.app.set_pair_selection(chosen | picked if adding else picked)
            return

        spot = self._item_under(event.x, event.y, self.optode_at)
        if spot:
            picked = self._pairs_touching(*spot)
        else:
            pair = self._item_under(event.x, event.y, self.pair_at)
            picked = {pair} if pair else set()
        picked &= present
        if not picked:
            return
        self.app.set_pair_selection(chosen - picked if picked <= chosen
                                    else chosen | picked)


class ConfirmDialog(tk.Toplevel):
    """Last stop before anything is written."""

    def __init__(self, master, summary: str, destructive: bool):
        super().__init__(master)
        self.accepted = False
        self.title("Check before filtering")
        self.transient(master)
        self.resizable(False, False)
        frame = ttk.Frame(self, padding=12)
        frame.pack(fill="both", expand=True)

        heading = ("The original files will be replaced" if destructive
                   else "Ready to filter")
        ttk.Label(frame, text=heading, font=("TkDefaultFont", 11, "bold")
                  ).pack(anchor="w", pady=(0, 6))
        box = tk.Text(frame, width=86, height=min(22, summary.count("\n") + 2),
                      wrap="word", relief="flat", background=self.cget("background"))
        box.insert("1.0", summary)
        box.configure(state="disabled")
        box.pack(fill="both", expand=True)

        buttons = ttk.Frame(frame)
        buttons.pack(fill="x", pady=(10, 0))
        ttk.Button(buttons, text="Cancel", command=self.destroy).pack(side="right")
        self.go = ttk.Button(buttons,
                             text="Replace files" if destructive else "Filter files",
                             command=self._accept)
        self.go.pack(side="right", padx=6)

        if destructive:
            self.understood = tk.BooleanVar(value=False)
            self.go.configure(state="disabled")
            self.understood.trace_add(
                "write",
                lambda *_: self.go.configure(
                    state="normal" if self.understood.get() else "disabled"))
            ttk.Checkbutton(
                frame, variable=self.understood,
                text="I understand these files will be overwritten and cannot be undone.",
            ).pack(anchor="w", pady=(8, 0))

        self.update_idletasks()
        x = master.winfo_rootx() + (master.winfo_width() - self.winfo_width()) // 2
        y = master.winfo_rooty() + (master.winfo_height() - self.winfo_height()) // 3
        self.geometry(f"+{max(x, 0)}+{max(y, 0)}")
        self.grab_set()
        self.go.focus_set()
        self.bind("<Escape>", lambda _e: self.destroy())

    def _accept(self) -> None:
        self.accepted = True
        self.destroy()


def main() -> None:
    root = tk.Tk()
    root.title(APP_TITLE)
    root.geometry("920x720")   # a shade over what the widgets ask for
    root.minsize(880, 660)
    try:
        style = ttk.Style()
        if "clam" in style.theme_names() and sys.platform.startswith("linux"):
            style.theme_use("clam")
    except tk.TclError:
        pass
    app = BetaTableFilterApp(root)
    root.protocol("WM_DELETE_WINDOW", app.on_close)
    root.mainloop()


if __name__ == "__main__":
    main()
