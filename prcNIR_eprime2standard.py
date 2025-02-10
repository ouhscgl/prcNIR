#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Sat Feb  1 17:28:20 2025

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
    """Write trials data to CSV file"""
    if not trials:
        return
    
    # Get all unique fields
    fieldnames = set()
    for trial in trials:
        fieldnames.update(trial.keys())
    fieldnames = sorted(list(fieldnames))

    # Write CSV
    with open(output_file, 'w', newline='', encoding='utf-16') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(trials)

def convert_eprime_to_csv(input_file, output_file):

    with open(input_file, 'r', encoding='utf-16') as f:
        text_content = f.read()
    
    trials = parse_eprime_text(text_content)
    write_csv(trials, output_file)

input_folder ='/Users/medicabg/Documents/Projects/001_NPH/data/NIR/cog/raw'
output_folder='/Users/medicabg/Documents/Projects/001_NPH/data/NIR/cog/ext'

txt_files = [f for f in os.listdir(input_folder) 
             if f.endswith('.txt') 
             and not f.startswith('.') 
             and not f.startswith('._')]

for file in txt_files:
    file_path = os.path.join(input_folder, file)
    save_path = os.path.join(output_folder, file[:-3]+'csv')
    try:
        convert_eprime_to_csv(file_path, save_path)
        print(f"Processing {file}.")
    except Exception as e:
        print(f"Error processing {file}: {str(e)}")