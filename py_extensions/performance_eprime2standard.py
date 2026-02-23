#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# =============================================================================
# performance_eprime2standard.py
# E-Prime to Standard N-back CSV Converter
# -----------------------------------------------------------------------------
# Developed by: zalkaposzt
# Property of: University of Oklahoma Health Sciences Center, Yabluchanskiy Lab
# Contact:     zalan-kaposzta@ou.edu
# Date:        2025
# -----------------------------------------------------------------------------
# Usage (req. params.: input_dir):
# python performance_eprime2standard <input_dir> <output_dir>
# =============================================================================

import csv, re, os, sys
from pathlib import Path


# Map E-Prime block procedures to stimulus type labels
BLOCK_MAP = {
    'Block1': 'nback_0a',
    'Block2': 'nback_1a', 
    'Block3': 'nback_0b',
    'Block4': 'nback_2a',
}


def clean_utf16_text(text: str) -> str:
    cleaned = text.replace('\x00', '')
    cleaned = cleaned.replace('\r\n', '\n').replace('\r', '\n')
    return cleaned


def parse_eprime_file(filepath: str) -> list[dict]:
    try:
        with open(filepath, 'r', encoding='utf-16') as f:
            text = f.read()
    except UnicodeError:
        with open(filepath, 'rb') as f:
            raw = f.read()
        text = raw.decode('utf-16', errors='ignore')
    
    text = clean_utf16_text(text)
    
    # Find all Level 3 LogFrame blocks (these contain trial data)
    pattern = r'Level:\s*3\s*\*\*\*\s*LogFrame Start\s*\*\*\*(.*?)\*\*\*\s*LogFrame End\s*\*\*\*'
    blocks = re.findall(pattern, text, re.DOTALL)
    
    trials = []
    for block in blocks:
        trial = {}
        for line in block.strip().split('\n'):
            line = line.strip()
            if ':' in line:
                key, value = line.split(':', 1)
                trial[key.strip()] = value.strip()
        
        # Only include actual trial blocks (not resting state etc.)
        if trial.get('Procedure', '').startswith('Block'):
            trials.append(trial)
    
    return trials


def get_response_fields(trial: dict) -> tuple[str, str]:
    procedure = trial.get('Procedure', '')
    prefix_map = {
        'Block1': 'Letter1',
        'Block2': 'Letter2',
        'Block3': 'Letter3',
        'Block4': 'Letter4',
    }
    
    prefix = prefix_map.get(procedure, 'Letter1')
    
    resp = trial.get(f'{prefix}.RESP', '')
    rt = trial.get(f'{prefix}.RT', '0')
    
    return resp, rt


def convert_trial(trial: dict) -> dict:
    procedure = trial.get('Procedure', '')
    stimulus_type = BLOCK_MAP.get(procedure, procedure)
    
    stimulus = trial.get('Letter', '')
    
    # ExpectedResponse: 1 if a response was expected, 0 otherwise
    correct_resp = trial.get('CorrectResponse', '').strip()
    expected_response = 1 if correct_resp == '1' else 0
    
    # Get response and RT from the appropriate fields
    resp, rt_ms = get_response_fields(trial)
    
    # ActualResponse: the key pressed (typically 1 or empty)
    # In your example CSV, responses show as "32.0" (space bar ASCII code)
    # but E-Prime often records as "1" for left-click
    actual_response = resp if resp else ''
    
    # ReactionTime: convert from ms to seconds, or 'inf' if no response
    try:
        rt_val = float(rt_ms)
        if rt_val > 0:
            reaction_time = rt_val / 1000.0  # Convert ms to seconds
        else:
            reaction_time = 'inf'
    except (ValueError, TypeError):
        reaction_time = 'inf'
    
    # TotTrialDur for offset calculation (in ms)
    try:
        tot_trial_dur = int(trial.get('TotTrialDur', 0))
    except (ValueError, TypeError):
        tot_trial_dur = 0
    
    return {
        'StimulusType': stimulus_type,
        'Stimulus': stimulus,
        'ExpectedResponse': expected_response,
        'ActualResponse': actual_response,
        'ReactionTime': reaction_time,
        '_TotTrialDur': tot_trial_dur,  # Internal, used for offset calc
        '_Procedure': procedure,  # Internal, used for block detection
    }


def calculate_offsets(trials: list[dict]) -> list[dict]:
    current_block = None
    cumulative_offset = 0
    
    for trial in trials:
        procedure = trial.pop('_Procedure')
        tot_trial_dur = trial.pop('_TotTrialDur')
        
        if procedure != current_block:
            current_block = procedure
            cumulative_offset = 0
        
        trial['StimOffset'] = cumulative_offset
        cumulative_offset += tot_trial_dur
    return trials


def write_csv(trials: list[dict], output_path: str):
    fieldnames = ['StimulusType', 'Stimulus', 'ExpectedResponse', 'ActualResponse', 'ReactionTime', 'StimOffset']
    
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(trials)


def process_file(input_path: str, output_path: str) -> bool:
    try:
        raw_trials = parse_eprime_file(input_path)
        
        if not raw_trials:
            print(f"  Warning: No trials found in {input_path}")
            return False
        
        converted = [convert_trial(t) for t in raw_trials]
        converted = calculate_offsets(converted)
        write_csv(converted, output_path)
        
        print(f"  Converted {len(converted)} trials")
        return True
        
    except Exception as e:
        print(f"  Error: {e}")
        return False


def main():
    if len(sys.argv) >= 3:
        input_folder = sys.argv[1]
        output_folder = sys.argv[2]
    else:
        script_dir = Path(__file__).parent
        input_folder = script_dir / 'input'
        output_folder = script_dir / 'output'
    
    input_folder = Path(input_folder)
    output_folder = Path(output_folder)
    output_folder.mkdir(parents=True, exist_ok=True)
    
    # Find all .txt files recursively (excluding hidden/resource fork files)
    txt_files = [f for f in input_folder.rglob('*.txt') 
                 if not f.name.startswith('.') and not f.name.startswith('._')]
    
    if not txt_files:
        print(f"No .txt files found in {input_folder}")
        return
    
    print(f"Found {len(txt_files)} file(s) to process\n")
    
    success = 0
    for txt_file in txt_files:
        # Preserve subfolder structure: input/sub/file.txt -> output/sub/file.csv
        relative_path = txt_file.relative_to(input_folder)
        output_file = output_folder / relative_path.with_suffix('.csv')
        
        # Create output subdirectory if needed
        output_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Show relative path for clarity
        print(f"Processing: {relative_path}")
        
        if process_file(str(txt_file), str(output_file)):
            print(f"  -> {output_file.relative_to(output_folder)}\n")
            success += 1
        else:
            print()
    
    print(f"Completed: {success}/{len(txt_files)} files converted")


if __name__ == '__main__':
    main()