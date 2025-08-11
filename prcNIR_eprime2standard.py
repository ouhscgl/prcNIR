#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Sat Feb  1 17:28:20 2025
Modified to create Excel-compatible CSV files

@author: medicabg
"""

import csv
import re
import os

def parse_eprime_text(text_content):
    """Parse E-Prime text file content into header and trial data"""
    # Extract header information
    stx = r'\*\*\* Header Start \*\*\*(.*?)\*\*\* Header End \*\*\*'
    header_match = re.search(stx, text_content, re.DOTALL)
    header_info = {}
    if header_match:
        header_text = header_match.group(1)
        for line in header_text.strip().split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                header_info[key.strip()] = value.strip()

    # Extract trial data
    trials = []
    etx = r'Level: 3\s+\*\*\* LogFrame Start \*\*\*(.*?)\*\*\* LogFrame End \*\*\*'
    trial_blocks = re.findall(etx, text_content, re.DOTALL)
    
    for block in trial_blocks:
        trial = {}
        trial.update(header_info)
        
        # Parse trial-specific information
        lines = block.strip().split('\n')
        for line in lines:
            line = line.strip()
            if ':' in line:
                key, value = line.split(':', 1)
                trial[key.strip()] = value.strip()
        
        trials.append(trial)
    
    return trials

def write_csv(trials, output_file):
    """Write trials data to CSV file in a format Excel can read properly"""
    if not trials:
        return
    
    # Get all unique fields
    fieldnames = set()
    for trial in trials:
        fieldnames.update(trial.keys())
    fieldnames = sorted(list(fieldnames))

    # Write CSV with Excel-friendly settings
    with open(output_file, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter=',', quotechar='"', quoting=csv.QUOTE_MINIMAL)
        writer.writeheader()
        writer.writerows(trials)

def convert_eprime_to_csv(input_file, output_file):
    # Try multiple encodings to handle possible file format variations
    encodings_to_try = ['utf-16', 'utf-8', 'latin1', 'cp1252']
    
    for encoding in encodings_to_try:
        try:
            with open(input_file, 'r', encoding=encoding) as f:
                text_content = f.read()
            break  # If successful, break the loop
        except UnicodeError:
            if encoding == encodings_to_try[-1]:  # If this was the last encoding to try
                raise Exception(f"Could not read file with any of the attempted encodings: {encodings_to_try}")
            continue
    
    trials = parse_eprime_text(text_content)
    write_csv(trials, output_file)
    print(f"Successfully created Excel-compatible CSV with {len(trials)} trials")

if __name__ == '__main__':
    import sys
    if len(sys.argv) > 2:
        input_folder = sys.argv[1]
        output_folder = sys.argv[2]
    else:
        # Default folders for testing
        script_dir = os.path.dirname(os.path.abspath(__file__))
        input_folder = os.path.join(script_dir, 'input')
        output_folder = os.path.join(script_dir, 'output')
        # Create output folder if it doesn't exist
        os.makedirs(output_folder, exist_ok=True)
    
    txt_files = [f for f in os.listdir(input_folder) 
                if f.endswith('.txt') 
                and not f.startswith('.') 
                and not f.startswith('._')]
    
    for file in txt_files:
        file_path = os.path.join(input_folder, file)
        save_path = os.path.join(output_folder, file[:-3]+'csv')
        try:
            print(f"Processing {file}...")
            convert_eprime_to_csv(file_path, save_path)
            print(f"Successfully converted {file} to {file[:-3]}csv")
        except Exception as e:
            print(f"Error processing {file}: {str(e)}")