#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# =============================================================================
# betaTable_filter.py
# -----------------------------------------------------------------------------
# Developed by: zalkaposzt
# Property of: University of Oklahoma Health Sciences Center, Yabluchanskiy Lab
# Contact:     zalan-kaposzta@ou.edu
# Date:        2024
# -----------------------------------------------------------------------------
# Usage (req. params.: input): python filter_beta_tables.py ...
# - trim to prefrontal cx: ... montage input.csv output.csv nirscout|nirsport|ldlfpc
# - gate to p or q values: ... gate data.csv p 0.05 
# - do both, sequentially: ... montage_and_gate input.csv output.csv nirscout|nirsport|ldlfpc p 0.05
# =============================================================================

import pandas as pd
import sys, os, argparse

# -- filter_sheet logic
def filter_spreadsheet(input_file, output_file, montage_type):
    try:
        if input_file.endswith('.csv'):
            df = pd.read_csv(input_file)
        elif input_file.endswith(('.xlsx', '.xls')):
            df = pd.read_excel(input_file)
        else:
            raise ValueError("Unsupported file format. Use CSV or Excel files.")
    except Exception as e:
        print(f"Error reading file: {e}")
        return False

    print(f"Original data: {len(df)} rows")

    if 'type' in df.columns:
        df = df[df['type'].str.contains('hbo', case=False, na=False)].copy()
        print(f"After HBO filter: {len(df)} rows")
    else:
        print("Warning: 'type' column not found. Skipping HBO filter.")

    if 'cond' in df.columns:
        df['cond'] = df['cond'].astype(str).str.replace(r's\d+', '', regex=True)
        print(f"Cleaned s+number patterns from 'cond' column")
    else:
        print("Warning: 'cond' column not found. Skipping pattern cleaning.")

    if 'cond' in df.columns:
        rows_before = len(df)
        df = df[~df['cond'].str.contains('EC', case=False, na=False)].copy()
        print(f"Removed {rows_before - len(df)} EC rows: {len(df)} rows remaining")

    if montage_type.lower() == 'nirscout':
        df = df[df['source'].isin([1, 2, 3, 4, 5, 6, 7])].copy()
        df = df[~df['detector'].isin([10, 14])]
        print(f"Applied CID (nirscout) filter: {len(df)} rows remaining")

    elif montage_type.lower() == 'nirsport':
        source_mask = (
            ((df['source'] >= 1) & (df['source'] <= 4)) |
            ((df['source'] >= 9) & (df['source'] <= 13))
        ) & (df['source'] != 12)
        df = df[source_mask].copy()
        df = df[~df['detector'].isin([5, 12])]
        print(f"Applied TRE (nirsport) filter: {len(df)} rows remaining")

    elif montage_type.lower() == 'ldlfpc':
        valid_pairs = {(2, 2), (2, 1), (3, 2), (4, 2)}
        mask = df.apply(lambda r: (r['source'], r['detector']) in valid_pairs, axis=1)
        df = df[mask].copy()
        print(f"Applied LDLFPC filter: {len(df)} rows remaining")

    else:
        print(f"Error: Unknown montage type '{montage_type}'. Use 'nirscout', 'nirsport', or 'ldlfpc'.")
        return False

    try:
        if output_file.endswith(('.xlsx', '.xls')):
            df.to_excel(output_file, index=False)
        else:
            output_file = output_file if output_file.endswith('.csv') else output_file + '.csv'
            df.to_csv(output_file, index=False)
        print(f"Filtered data saved to: {output_file}")
        return True
    except Exception as e:
        print(f"Error saving file: {e}")
        return False

# -- filter_beta_significance logic
def filter_stats(path, column='p', threshold=0.05, output_path=None):
    df = pd.read_csv(path)
    print(f'Loading {path}...')

    if column not in df.columns:
        print(f'Error: Column "{column}" not found in file.')
        return False

    save_path = output_path if output_path else path
    df[df[column] < threshold].to_csv(save_path, index=False)
    print(f'Saved {column}<{threshold} gated data to {save_path} successfully.')
    return True

# -- CLI
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='fNIRS data filtering utilities')
    subparsers = parser.add_subparsers(dest='command', required=True)

    # montage subcommand
    p_montage = subparsers.add_parser('montage', help='Filter by montage type (nirscout/nirsport)')
    p_montage.add_argument('input_file')
    p_montage.add_argument('output_file', nargs='?', default=None)
    p_montage.add_argument('montage_type', choices=['nirscout', 'nirsport', 'ldlfpc'], default='nirscout')

    # gate subcommand
    p_gate = subparsers.add_parser('gate', help='Filter rows by p or q value')
    p_gate.add_argument('input_file')
    p_gate.add_argument('output_file', nargs='?', default=None)
    p_gate.add_argument('column', nargs='?', default='p', choices=['p', 'q'])
    p_gate.add_argument('threshold', nargs='?', type=float, default=0.05)

    # montage_and_gate subcommand
    p_both = subparsers.add_parser('montage_and_gate', help='Run montage filter then p/q gate')
    p_both.add_argument('input_file')
    p_both.add_argument('output_file', nargs='?', default=None)
    p_both.add_argument('montage_type', choices=['nirscout', 'nirsport', 'ldlfpc'], default='nirscout')
    p_both.add_argument('column', nargs='?', default='p', choices=['p', 'q'])
    p_both.add_argument('threshold', nargs='?', type=float, default=0.05)

    args = parser.parse_args()

    if not os.path.exists(args.input_file):
        print(f'Error: File not found: {args.input_file}')
        sys.exit(1)
    
    if args.command in ('montage', 'both'):
        if args.output_file is None:
            args.output_file = args.input_file
    
    if args.command == 'montage':
        success = filter_spreadsheet(args.input_file, args.output_file, args.montage_type)
    elif args.command == 'gate':
        success = filter_stats(args.input_file, args.column, args.threshold, args.output_file)
    elif args.command == 'montage_and_gate':
        success = filter_spreadsheet(args.input_file, args.output_file, args.montage_type)
        if success:
            success = filter_stats(args.output_file, args.column, args.threshold)

    sys.exit(0 if success else 1)