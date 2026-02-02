#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# PowelCalculationHelper script
# > From ContrastStatsCE [nirs-toolbox] collate .variables, .p, .q with 
#   appropriate headers (Header value doesn' matter, e.g.: S, D, Type, p, q)
#   into a .csv file (see example.csv)

LOAD_PATH = '/Users/medicabg/Documents/Programs/fNIRS/-0aBEF+2aBEF.csv'
SAVE_PATH = '/Users/medicabg/Desktop/Before_all_p_gated.csv'

# Load in contrast stat .csv
import pandas as pd
df = pd.read_csv(LOAD_PATH)
print(f'Loading {LOAD_PATH}...')

# Extraction
df_hbo = df[~df['type'].str.contains('hbr')]
df_sig = df_hbo[df_hbo['p'] < 0.05]

# Saving extracted significant values
df_sig.to_csv(SAVE_PATH)
print(f'Saved extracted sig. data to {SAVE_PATH} successfully.')

