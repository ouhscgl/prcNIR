#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# conda install -c conda-forge mne-nirs mne
import mne
from mne_nirs.io import write_raw_snirf
path = '/Users/medicabg/Downloads/2024-05-22_003.snirf'
path2= '/Users/medicabg/Downloads/2024-05-22_003_2.snirf'

# Load NIRx file
# Documentation @:
# https://mne.tools/stable/generated/mne.io.read_raw_nirx.html
nirx_path='/Users/medicabg/Downloads/TestItems/CC201/NIRS-2023-04-28_001.hdr'
raw = mne.io.read_raw_nirx(nirx_path, verbose=True)

snirf_path = '/Users/medicabg/Downloads/TestItems/TRE001_V1/2024-05-13_002.snirf'
raw = mne.io.read_raw_snirf(snirf_path, preload=True, verbose=True)



write_raw_snirf(raw, path2)