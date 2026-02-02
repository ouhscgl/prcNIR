function [GroupStats, demograph, stimulus] ...
    = fNIRS_Process(load_path, nirstoolbox_path, user_vars)
% fNIRS_Process - Main processing core for fNIRS pipeline.
% 
% Options: 
%     load_path        - path to fNIRS file or folder system
%     nirstoolbox_path - path to nirs-toolbox (Huppert, T. et al.)
%     user_vars        - list of customizable paramaters in the pipeline
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Data loading ____________________________________________________________
%-- Adding nirs-toolbox to path
addpath(genpath(nirstoolbox_path))
%-- Default analysis variables
defaults = struct();
defaults.folder_structure   = {'group', 'subject'};
defaults.dct_value          = 0.009;
defaults.stim_names         = {'nback0a', 'nback1a', 'nback0b', 'nback2a'};
defaults.stim_onset         = NaN;
defaults.stim_dur           = 72;
defaults.max_short_distance = 10;
defaults.max_regul_distance = 50;
defaults.regression_formula = {'beta ~ -1 + group + (1|subject)', ...
                               'beta ~ -1 + group:cond + (1|subject)'};
defaults.save_as_snirf_flag = false;
defaults.overwrite_as_snirf = false;
defaults.calculate_total_hb = false;
defaults.do_preprocessing   = true;
%--Validating user variables, setting to default if variable not present
user_vars = validateAnalyticParameters(user_vars, defaults);
%-- Solo or directory data loading ( data_raws.probe.draw )
data_raws = loadNIRSData(load_path);
% _________________________________________________________________________

% Stimulus correction _____________________________________________________
%-- Change stimulus data ( nirs.getStimNames(data_raws) );
job = nirs.modules.ChangeStimulusInfo   ();
[data_raws, mod_stimTable, rename_mapping] = createRobustStimMapping(...
   data_raws,user_vars.stim_names,user_vars.stim_onset,user_vars.stim_dur);
job.ChangeTable = mod_stimTable;
%-- Rename stimuli
job = nirs.modules.RenameStims          (job);
job.listOfChanges = rename_mapping;
data_raws = job.run(data_raws);
% _________________________________________________________________________

% Identify short channels and exclude faux channels _______________________
%-- Short channel identification
job = nirs.modules.LabelShortSeperation ();
job.max_distance = user_vars.max_short_distance;
%-- Long channel identification and removal
job = nirs.modules.LabeltooLongDistance (job);
job.min_distance = user_vars.max_regul_distance;
job = nirs.modules.RemovetooLongDistance(job);
% _________________________________________________________________________

% Transform to physiological data _________________________________________
job = nirs.modules.OpticalDensity       (job);
job = nirs.modules.BeerLambertLaw       (job);
%-- Apply preprocessing if necessary
if user_vars.do_preprocessing
    data_prps = job.run(data_raws);
else
    data_prps = data_raws;
end
% Calculate total hemoglobin - INDEV
if user_vars.calculate_total_hb
    temp = data_prps.data;
    for row=1:2:size(temp,2)
        data_prps.data(:,row) = temp(:,row) + temp(:,row+1);
    end
end
% _________________________________________________________________________

% Motion correction (Auto-regressive Iteratively Reweighted Least Squares)_
% Barker, J. W., Aarabi, A., & Huppert, T. J. (2013). 
% Autoregressive model based algorithm for correcting motion and serially 
% correlated errors in fNIRS. Biomedical optics express, 4(8), 1366–1379. 
% https://doi.org/10.1364/BOE.4.001366
job = nirs.modules.GLM                  ();
if isfield(data_prps(1).probe.link, 'ShortSeperation') && ...
       any(data_prps(1).probe.link.ShortSeperation == 1)
    job.AddShortSepRegressors = true;
end
job.trend_func=@(t)nirs.design.trend.dctmtx(t, user_vars.dct_value);
data_stat = job.run(data_prps);
% _________________________________________________________________________

% Extract data from the preprocessing pipeline ____________________________
demograph = nirs.createDemographicsTable(data_prps);
stimulus  = nirs.createStimulusTable(data_prps);
% _________________________________________________________________________

% Statistical analysis (Mixed Effects Model, Wilkinson notation) __________
job = nirs.modules.MixedEffects         ();
for iter = 1:length(user_vars.regression_formula)
    job.formula = user_vars.regression_formula{iter};
    GroupStats(iter) = job.run(data_stat);
    disp(['Conditions for formula: ', user_vars.regression_formula{iter}])
    disp(GroupStats(iter).conditions)
end
% _________________________________________________________________________

% Save preprocessed data as .snirf ________________________________________
if user_vars.save_as_snirf_flag == true
    saveAsSNIRF(data_prps, demograph, load_path, ...
        user_vars.overwrite_as_snirf)
end
disp('Finished processing data.')
% _________________________________________________________________________

% Auxillary functions _____________________________________________________
function data_raws = loadNIRSData(load_path)
    % Check if the input is a directory or a file
    if isfolder(load_path)
        % It's a directory - check what kind of files it contains
        snirf_files = dir(fullfile(load_path, '**','*.snirf'));
        nirx_files = dir(fullfile(load_path, '**','*.wl1'));
        
        % Case 1: Directory contains SNIRF files
        if ~isempty(snirf_files)
            if isscalar(snirf_files)
                % Single SNIRF file in directory
                data_raws = nirs.io.loadSNIRF(fullfile(load_path, ...
                                              snirf_files(1).name));
            else
                % Multiple SNIRF files in directory
                data_raws = nirs.io.loadDirectory(load_path, ...
                    user_vars.folder_structure, ...
                    @nirs.io.loadSNIRF, {'.snirf'});
            end
        
        % Case 2: Directory contains NIRx files (.wl1)
        elseif ~isempty(nirx_files)
            if isscalar(nirx_files)
                % Single NIRx dataset in directory
                data_raws = nirs.io.loadNIRx(load_path);
            else
                % Multiple NIRx datasets in sub-directories
                data_raws = nirs.io.loadDirectory(load_path, ...
                    user_vars.folder_structure, ...
                    @nirs.io.loadNIRx, {'.wl1'});
            end
        
        % Case 3: Unknown file type or empty directory
        else
            error('No supported NIRS data files found in directory');
        end
    
    % It's a file path - determine file type and load accordingly
    elseif isfile(load_path)
        [~, ~, ext] = fileparts(load_path);
        if strcmpi(ext, '.snirf')
            data_raws = nirs.io.loadSNIRF(load_path);
        elseif strcmpi(ext, '.wl1')
            % For .wl1 files, we need the parent directory
            [parent_dir, ~, ~] = fileparts(load_path);
            data_raws = nirs.io.loadNIRx(parent_dir);
        else
            error('Unsupported file type: %s', ext);
        end
    else
        error('Invalid path: %s', load_path);
    end
end

function saveAsSNIRF(data, demo, load_path, overwrite)
    for i=1:length(data)
    visitID = '';
    if ismember('Visit',demo.Properties.VariableNames)
        visitID = strcat('_V',demo.Visit(i));
    end
    save_name = fullfile(load_path,[demo.Name{i},visitID{:},...
                            '.snirf']);
    if isfile(save_name) && ~overwrite
        validate =input('File already exists. Overwrite? [[y]/n]',"s");
        if isequal(lower(validate),'y') | isempty(validate)
            delete(save_name)
            nirs.io.saveSNIRF(data(i,1),save_name)
            disp(['Saved ',save_name,'.']);
        else
            disp(['Discarded ',demo.Name{i},'.snirf.']);
        end
    else
        nirs.io.saveSNIRF(data(i,1),save_name)
        disp(['[',num2str(i),']',' Saved ',save_name,'.']);
    end
    end
end

function params = validateAnalyticParameters(params, defaults)
    if ~exist('user_vars', 'var') || ~isa(params, 'struct')
        params = struct();
    end
    field_names = fieldnames(defaults);
    for i = 1:length(field_names)
        field = field_names{i};
        if ~isfield(params, field) || isempty(params.(field))
            params.(field) = defaults.(field);
        end
    end
    if ~iscell(params.folder_structure)
    warning('folder_structure should be a cell array. Converting...');
    params.folder_structure = {params.folder_structure};
    end
    
    if ~iscell(params.stim_names)
    warning('stim_names should be a cell array. Converting...');
    params.stim_names = {params.stim_names};
    end
    
    if ~iscell(params.regression_formula)
    warning('regression_formula should be a cell array. Converting...');
    params.regression_formula = {params.regression_formula};
    end
end
    
function [stim_table] = stimTableMapper(stim_table, ...
                                        new_names, new_onsets, new_durs)
    % Input validation
    if isempty(stim_table)
        warning('Empty stimulus table provided');
        return;
    end
    
    for table=1:height(stim_table)
        % Get the number of columns excluding FileIdx
        len = width(stim_table);
        col_names = stim_table.Properties.VariableNames;
        
        % Skip FileIdx column if present
        if ismember('FileIdx', col_names)
            len = len - 1;
            stim_cols = col_names(~strcmp(col_names, 'FileIdx'));
        else
            stim_cols = col_names;
        end
        
        % Handle scalar new_names input
        if isscalar(new_names) && ischar(new_names)
            new_names = arrayfun(@(n) sprintf('%s_%d', new_names, n), ...
                1:len, 'UniformOutput', false);
        elseif length(new_names) < len
            % Pad with default names if needed
            orig_len = length(new_names);
            for i = (orig_len+1):len
                new_names{i} = sprintf('stim_%d', i);
            end
            warning('Not enough stimulus names provided. Added defaults.');
        end
        
        % Handle scalar new_onsets input
        if isscalar(new_onsets)
            if isnan(new_onsets)
                % If NaN, keep original onsets
                new_onsets = NaN(1, len);
            else
                % Replicate the value
                new_onsets = repmat(new_onsets, 1, len);
            end
        elseif length(new_onsets) < len
            % Pad with NaN to keep original onsets
            orig_len = length(new_onsets);
            new_onsets = [new_onsets, NaN(1, len - orig_len)];
            warning(['Not enough stimulus onsets provided. ',...
                     'Will keep original onsets for some stimuli.']);
        end
        
        % Handle scalar new_durs input
        if isscalar(new_durs)
            if isnan(new_durs)
                % If NaN, keep original durations
                new_durs = NaN(1, len);
            else
                % Replicate the value
                new_durs = repmat(new_durs, 1, len);
            end
        elseif length(new_durs) < len
            % Pad with NaN to keep original durations
            orig_len = length(new_durs);
            new_durs = [new_durs, NaN(1, len - orig_len)];
            warning(['Not enough stimulus durations provided. ',...
                     'Will keep original durations for some stimuli.']);
        end
        
        % Update the stimulus table
        for c = 1:length(stim_cols)
            col_name = stim_cols{c};
            
            try
                % Get the current stimulus
                curr_stim = stim_table(table, :).(col_name);
                
                % Update name if provided and not empty
                if c <= length(new_names) && ~isempty(new_names{c})
                    curr_stim.name = new_names{c};
                end
                
                % Update onset if provided and not NaN
                if c <= length(new_onsets) && ~isnan(new_onsets(c))
                    curr_stim.onset = new_onsets(c);
                end
                
                % Update duration if provided and not NaN
                if c <= length(new_durs) && ~isnan(new_durs(c))
                    if length(curr_stim.onset) > 1 && isscalar(new_durs(c))
                        curr_stim.dur = repmat(new_durs(c), ...
                                               size(curr_stim.onset));
                    else
                        curr_stim.dur = new_durs(c);
                    end
                end
                
                % Update the table
                stim_table(table, :).(col_name) = curr_stim;
                
            catch e
                warning('Error updating stimulus %s: %s', col_name, ...
                        e.message);
            end
        end
    end
    
    % Log final stimulus table structure
    disp('Final stimulus table structure:');
    disp(stim_table.Properties.VariableNames);
end

function [data_raws, mod_stimTable, rename_mapping] = ...
    createRobustStimMapping(data_raws, stim_names, stim_onset, stim_dur)
    % First, check if any stimuli have numeric names and fix them
    for i = 1:length(data_raws)
        stim_keys = data_raws(i).stimulus.keys;
        for j = 1:length(stim_keys)
            key = stim_keys{j};
            % Check if the key is numeric or starts with a number
            if ~isempty(str2double(key)) || ...
                    (~isempty(key) && ~isnan(str2double(key(1))))
                % Create a new key with 'x' prefix
                new_key = ['x', key];
                disp(['Renaming numeric stimulus "', key, '" to "', ...
                      new_key, '"']);
                
                % Get the stimulus and rename it
                stim = data_raws(i).stimulus(key);
                stim.name = new_key;
                data_raws(i).stimulus(key) = [];
                data_raws(i).stimulus(new_key) = stim;
            end
        end
    end

    %-- Check available stimuli first
    available_stims = nirs.getStimNames(data_raws);
    disp('Available stimuli in raw data (after fixing numeric names):');
    disp(available_stims);

    %-- Handle NaN in stimulus names (leave original names unchanged)
    use_original_names = false;
    if isscalar(stim_names) && (isnan(stim_names{1}) || ...
            strcmpi(stim_names{1}, 'NaN'))
        use_original_names = true;
        stim_names_to_use = available_stims;
        available_stims_to_use = available_stims;
        disp('Using original stimulus names (NaN provided)');
    %-- Validate stimulus names
    elseif length(stim_names) ~= length(available_stims)
        warning(['Number of provided stimulus names (%d) does not' ...
                 'match available stimuli (%d)'], ...
                length(stim_names), length(available_stims));
        % Create mapping only for available stimuli or expected stimuli
        mapping_length = min(length(stim_names), length(available_stims));
        stim_names_to_use = stim_names(1:mapping_length);
        available_stims_to_use = available_stims(1:mapping_length);
    else
        stim_names_to_use = stim_names;
        available_stims_to_use = available_stims;
    end

    %-- Handle NaN in onsets/durations
    use_original_onsets = false;
    if isscalar(stim_onset) && isnan(stim_onset)
        use_original_onsets = true;
        disp('Using original stimulus onsets (NaN provided)');
    end
    
    use_original_durs = false;
    if isscalar(stim_dur) && isnan(stim_dur)
        use_original_durs = true;
        disp('Using original stimulus durations (NaN provided)');
    end

    %-- Ensure stimulus durations match if not using originals
    if ~use_original_durs
        if length(stim_dur) == 1
            stim_dur = repmat(stim_dur, 1, length(stim_names_to_use));
        elseif length(stim_dur) ~= length(stim_names_to_use)
            warning(['Length of stimulus durations (%d) does not',...
                     'match number of stimuli (%d). Adjusting...'], ...
                length(stim_dur), length(stim_names_to_use));
            if length(stim_dur) > length(stim_names_to_use)
                stim_dur = stim_dur(1:length(stim_names_to_use));
            else
                default_dur = stim_dur(end);
                stim_dur = [stim_dur, repmat(default_dur, 1, ...
                    length(stim_names_to_use) - length(stim_dur))];
            end
        end
    end

    % Create stimulus table with detailed logging
    try
        disp('Creating stimulus table...');
        
        % Get original stimulus table
        orig_stim_table = nirs.createStimulusTable(data_raws);
        
    % If using original names, onsets, and durations, just return the og
    if use_original_names && use_original_onsets && use_original_durs
        mod_stimTable = orig_stim_table;
        disp('Using original stimulus table (all parameters are NaN)');
    else
        % Otherwise, call the mapper with the appropriate values
        if use_original_names
            if use_original_onsets
                onset_to_use = NaN;
            else
                onset_to_use = stim_onset;
            end
            
            if use_original_durs
                dur_to_use = NaN;
            else
                dur_to_use = stim_dur;
            end
            
            mod_stimTable = stimTableMapper(orig_stim_table, ...
                available_stims, onset_to_use, dur_to_use);
        else
            % When not using original names
            if use_original_onsets
                onset_to_use = NaN;
            else
                onset_to_use = stim_onset;
            end
            
            if use_original_durs
                dur_to_use = NaN;
            else
                dur_to_use = stim_dur;
            end
            
            mod_stimTable = stimTableMapper(orig_stim_table, ...
                stim_names_to_use, onset_to_use, dur_to_use);
        end
    end
        
        % Create mapping
        if use_original_names
            % If using original names, create identity mapping
            rename_mapping = cell(length(available_stims), 2);
            for i = 1:length(available_stims)
                rename_mapping{i, 1} = available_stims{i};
                rename_mapping{i, 2} = available_stims{i};
            end
        else
            % Create mapping with proper validation
            rename_mapping = cell(length(available_stims_to_use), 2);
            for i = 1:length(available_stims_to_use)
                rename_mapping{i, 1} = available_stims_to_use{i};
                if i <= length(stim_names_to_use)
                    rename_mapping{i, 2} = stim_names_to_use{i};
                else
                    rename_mapping{i, 2} = available_stims_to_use{i};
                end
            end
        end
        
        % Log the renaming mapping
        disp('Stimulus renaming mapping:');
        disp(rename_mapping);
    catch e
    disp(['Error in stimulus table creation: ' e.message]);
    disp('Stimulus table creation failed, attempting fallback method...');
    mod_stimTable = table();
    rename_mapping = {};
    end
end
% _________________________________________________________________________
end