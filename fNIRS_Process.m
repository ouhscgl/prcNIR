function [results,demograph,stimulus] = fNIRS_Process(load_path, user_vars)
%% ========================================================================
%  Header - VERSION 7.1.2
%  ========================================================================
% This is the core Main processing core for fNIRS pipeline, takes in either
% unprocessed NIRx datasets, unprocessed SNIRF datasets or SATORI processed
% SNIRF datasets. NIRS compatibility in development.
%
% Requires:
%    - nirs-toolbox (github.com/huppertt/nirs-toolbox) w/ patch
%    - full prcNIR package
% 
% Options: 
%    - load_path        - path to fNIRS file or folder system
%    - user_vars        - list of customizable paramaters in the pipeline
% =========================================================================

%% ========================================================================
%  Initial setup
%  ========================================================================
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
defaults.calculate_HbT      = false;
defaults.do_preprocessing   = true;
defaults.early_return       = "";

user_vars = validateAnalyticParameters(user_vars, defaults);

%% ========================================================================
%  Data loading (data_raws.probe.draw - montage easy access)
%  ========================================================================
% Please refer to comments under loadNIRSData() function itself regarding
% implementation, in short allows for dynamic loads and handles various
% data and folder structures gracefully.
data_raws = loadNIRSData(load_path, user_vars);
if contains(user_vars.early_return,'raw data') 
    results = data_raws; return; end
% _________________________________________________________________________

%% ========================================================================
%  Stimulus correction (nirs.getStimNames(data_raws) - stimulus access)
%  ========================================================================
%-- Change stimulus data
job = nirs.modules.ChangeStimulusInfo   ();
[data_raws, mod_stimTable, rename_mapping] = createRobustStimMapping(...
   data_raws,user_vars.stim_names,user_vars.stim_onset,user_vars.stim_dur);
job.ChangeTable = mod_stimTable;
%-- Rename stimuli
job = nirs.modules.RenameStims          (job);
job.listOfChanges = rename_mapping;
data_raws = job.run(data_raws);
% _________________________________________________________________________

%% ========================================================================
%  Pre-processing
%  ========================================================================

%-- Trim dataset to 10s pre and post stimulus period to match internal 
%   Satori consensus
job = nirs.modules.TrimBaseline         ();
[job.preBaseline, job.postBaseline] = deal(10);

%-- Short channel identification
job = nirs.modules.LabelShortSeperation (job);
job.max_distance = user_vars.max_short_distance;

%-- Long channel identification and removal
job = nirs.modules.LabeltooLongDistance (job);
job.min_distance = user_vars.max_regul_distance;
job = nirs.modules.RemovetooLongDistance(job);

%-- Quality assurance
%   Step was removed to match the phylosophy of the Hupper lab which aims
%   to maintain as much data as possible within the regression model,
%   including physiological and external noise, with some obvious
%   corrections implemented via TDDR(). Leaving the commented segment here
%   in case some want to re-implement, but channel count inconsistency for
%   the mixed effects model will be a concern (!).
% data_raws = job.run(data_raws);
% job_qt = nirs.modules.QT();
% job_qt.qThreshold = 0.6;
% qt_results = job_qt.run(data_raws);
% % Apply bad channel info back to data
% for i = 1:length(data_raws)
%     bad_idx = qt_results(i).qMats.bad_links;
%     if ~isempty(bad_idx)
%         % Get the link table for bad channels
%         bad_src = qt_results(i).qMats.good_combo_link(bad_idx, 1);
%         bad_det = qt_results(i).qMats.good_combo_link(bad_idx, 2);
% 
%         % Find matching channels in data (both wavelengths/types)
%         link = data_raws(i).probe.link;
%         for j = 1:length(bad_src)
%             mask = link.source == bad_src(j) & link.detector == bad_det(j);
%             data_raws(i).data(:, mask) = NaN;
%         end
%     end
%     fprintf('Subject %d: %d bad channels marked\n', i, length(bad_idx));
% end

%-- Transform to physiological data & remove noise
job = nirs.modules.OpticalDensity       (job);
job = nirs.modules.TDDR                 (job);
job = nirs.modules.BeerLambertLaw       (job);

%-- Apply preprocessing
if user_vars.do_preprocessing, data_prps = job.run(data_raws);
else,                          data_prps = data_raws;
end

%-- Calculate total hemoglobin
if user_vars.calculate_HbT, data_prps = calculate_total_hb(data_prps); end

%-- Early termination (pre-processed data)
if contains(user_vars.early_return,'preprocessed data') 
    results = data_prps; return; end

%% ========================================================================
%  GLM
%  ========================================================================
%-- Motion correction(Auto-regressive Iteratively Reweighted Least Squares)
% Barker, J. W., Aarabi, A., & Huppert, T. J. (2013). 
% Autoregressive model based algorithm for correcting motion and serially 
% correlated errors in fNIRS. Biomedical optics express, 4(8), 1366–1379. 
% https://doi.org/10.1364/BOE.4.001366
job = nirs.modules.GLM                  (); 
job.trend_func=@(t)nirs.design.trend.dctmtx(t, user_vars.dct_value);
if isfield(data_prps(1).probe.link, 'ShortSeperation')
    job.AddShortSepRegressors = true;
end
job = nirs.modules.RemoveShortSeperations(job);
data_stat = job.run(data_prps);

%% ========================================================================
%  Statistics (Mixed Effects Model)
%  ========================================================================
%-- Extract auxilliary data from the preprocessing pipeline
demograph = nirs.createDemographicsTable(data_prps);
stimulus  = nirs.createStimulusTable(data_prps);

%-- Statistical analysis via Mixed Effects Model using Wilkinson notations
job = nirs.modules.MixedEffects         ();
for iter = 1:length(user_vars.regression_formula)
    job.formula = user_vars.regression_formula{iter};
    results(iter) = job.run(data_stat);
    disp(['Conditions for formula: ', user_vars.regression_formula{iter}])
    disp(results(iter).conditions)
end
disp('Finished processing data.')

%% ========================================================================
%  Auxilliary Functions
%  ========================================================================
function data_raws = loadNIRSData(load_path, user_vars)
    % Handle specific files only (e.g.: {'data1.snirf','data2.nirs'})
    % Uses a nested loop to read in individually defined data into a single
    % set. Use case: analyzing one individual's before and after states.
    % if iscell(load_path)
    %     data_raws = cellfun(@(p) loadNIRSData(p, user_vars), load_path,...
    %                         'UniformOutput', false);
    %     data_raws = [data_raws{:}];
    %     return
    % end
    if iscell(load_path)
        data_raws = [];
        for p = 1:numel(load_path)
            data_raws = [data_raws, loadNIRSData(load_path{p}, user_vars)];
        end
        return
    end
    
    % -- user specified: directory
    if isfolder(load_path)
        
        % Check low-level directories
        leaf_dirs = getLeafs(load_path);
        if isempty(leaf_dirs)
            leaf_dirs{1} = load_path;
        end

        % Gather supported files
        load_dirs = {};  file_types = {};
        for i = 1:length(leaf_dirs)
            dir_path = leaf_dirs{i};
            
            % :: .snirf
            snirf_files = dir(fullfile(dir_path, '*.snirf'));
            if ~isempty(snirf_files)
                load_dirs{end+1} = dir_path;
                file_types{end+1} = 'snirf';
                continue;
            end
            
            % :: NIRx
            wl1_files = dir(fullfile(dir_path, '*.wl1'));
            if ~isempty(wl1_files)
                load_dirs{end+1} = dir_path; %#ok<*AGROW>
                file_types{end+1} = 'nirx';
            end
        end
        if isempty(load_dirs)
        error('No valid data files found in: %s', load_path); end
        
        % Load valid files
        data_raws = [];
        for i = 1:length(load_dirs)
            % -- set iterable directory
            dir_path = load_dirs{i}; file_type = file_types{i};
            fprintf('[%d/%d] Loading: %s\n',i,length(load_dirs),dir_path);
            
            try
            % -- load file
            if strcmp(file_type, 'snirf')
                snirf_files = dir(fullfile(dir_path, '*.snirf'));
                data = nirs.io.loadSNIRF(...
                       fullfile(dir_path, snirf_files(1).name));
                mrk = strrep(fullfile(dir_path, snirf_files(1).name),...
                             'snirf','csv');

                if isfile(mrk)
                    marker_table = readtable(mrk, 'VariableNamingRule',...
                                                  'preserve');
                    data.stimulus = Dictionary();
                    
                    for m = 1:height(marker_table)
                        stim = nirs.design.StimulusEvents();
                        stim.name = marker_table.Marker{m};
                        stim.onset = marker_table.Time(m);
                        stim.dur = 1;
                        stim.amp = 1;
                        data.stimulus(stim.name) = stim;
                    end
                end
            else
                data = nirs.io.loadNIRx(dir_path);
            end
            
            % -- extract file tree demographics
            demographics = extractDemographics(dir_path, load_path, ...
                                             user_vars.folder_structure);
            
            % -- assign demographics to data
            if ~isempty(fieldnames(demographics))
                demo_fields = fieldnames(demographics);
                for j = 1:length(demo_fields)
                    field = demo_fields{j};
                    data.demographics(field) = demographics.(field);
                end
            end
            
            % -- assign description to data
            data.description = [dir_path, '/', file_type];
            
            % -- append to master array
            if isempty(data_raws), data_raws = data;
            else, data_raws(end+1) = data; end
                
            catch e
                warning('Error loading %s: %s', dir_path, e.message);
                fprintf('  Stack trace:\n');
                for k = 1:length(e.stack)
                    fprintf('    %s (line %d)\n', ...
                            e.stack(k).name, e.stack(k).line);
                end
            end
        end
        if isempty(data_raws)
        error('Failed to load any NIRS data from: %s', load_path); end

        % Convert to column vector (ref. nirs.io.loadDirectory)
        data_raws = data_raws(:);

    % -- user specified: file
    elseif isfile(load_path)
        [~, ~, ext] = fileparts(load_path);
        % -- file is snirf file
        if strcmpi(ext, '.snirf')
            data_raws = nirs.io.loadSNIRF(load_path);
        % -- file is NIRx file
        elseif strcmpi(ext, '.wl1')
            [parent_dir, ~, ~] = fileparts(load_path);
            data_raws = nirs.io.loadNIRx(parent_dir);
        else
            error('Unsupported file type: %s', ext);
        end
    else
        error('Invalid path: %s', load_path);
    end
end

function demographics = extractDemographics(data_p,root_path,folder_struct)
    demographics = struct();
    % -- get rel. path from data root & remove leading/trailing filesep(s)
    if isempty(folder_struct), return; end
    rpath = strrep(data_p, root_path, '');
    rpath = regexprep(rpath, '^[/\\]+|[/\\]+$', '');
    
    % -- split into folder levels & remove empty entries
    folder_levels = strsplit(rpath, filesep);
    folder_levels = folder_levels(~cellfun(@isempty, folder_levels));
    if isempty(folder_levels), return; end
  
    num_to_assign = min(length(folder_levels), length(folder_struct));
    relevant_folders = folder_levels(end - num_to_assign + 1:end);
    relevant_structure = folder_struct(end - num_to_assign + 1:end);
    
    % -- assign demographics
    for i = 1:num_to_assign
        field_name = relevant_structure{i};
        folder_value = relevant_folders{i};
        demographics.(field_name) = folder_value;
    end
end

function params       = validateAnalyticParameters(params, defaults)
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

function data = calculate_total_hb(data)  
    for d = 1:size(data,1)
        link = data(d).probe.link;
        [G, ~] = findgroups(link.source, link.detector);
        for g = 1:max(G)
            idx = find(G == g);
            if numel(idx) == 2
                data(d).data(:, idx(1)) = data(d).data(:, idx(1)) + ...
                                          data(d).data(:, idx(2));
            end
        end
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
        createRobustStimMapping(data_raws, stim_names, stim_onset,stim_dur)
    for i = 1:length(data_raws)
        stim_keys = data_raws(i).stimulus.keys;
        for j = 1:length(stim_keys)
            key = stim_keys{j};
            if ~isempty(str2double(key)) ...
                || (~isempty(key) ...
                && ~isnan(str2double(key(1))))
                
                new_key = ['x', key];
                stim = data_raws(i).stimulus(key);
                stim.name = new_key;
                data_raws(i).stimulus(key) = [];
                data_raws(i).stimulus(new_key) = stim;
            end
        end
    end

    for i = 1:length(data_raws)
        stim_keys = data_raws(i).stimulus.keys;
        
        if ~isempty(stim_keys) && isscalar(stim_keys)
            key = stim_keys{1};
            stim = data_raws(i).stimulus(key);
            
            if stim.count > 1
                for k = 1:stim.count
                    new_key = sprintf('event%d', k);
                    new_stim = nirs.design.StimulusEvents();
                    new_stim.name = new_key;
                    new_stim.onset = stim.onset(k);
                    new_stim.dur = stim.dur(k);
                    if isempty(stim.amp)
                        new_stim.amp = 1;
                    else
                        new_stim.amp = stim.amp(k);
                    end
                    data_raws(i).stimulus(new_key) = new_stim;
                end
                data_raws(i).stimulus(key) = [];
            end
        end
    end

    for i = 1:length(data_raws)
        stim_keys = sort(data_raws(i).stimulus.keys);
        
        % Rename each stimulus to generic marker name based on position
        for j = 1:length(stim_keys)
            old_key = stim_keys{j};
            generic_name = sprintf('marker%02d', j);
            
            % Get stimulus, rename it, and reassign
            stim = data_raws(i).stimulus(old_key);
            stim.name = generic_name;
            data_raws(i).stimulus(old_key) = [];
            data_raws(i).stimulus(generic_name) = stim;
        end
    end
    
    use_user_names = ~(isscalar(stim_names) ...
                     && (isnan(stim_names{1}) ...
                     || strcmpi(stim_names{1}, 'NaN')));
    
    if use_user_names
        % Fix numeric names in user stim_names
        fixed_stim_names = cell(size(stim_names));
        for i = 1:length(stim_names)
            name = stim_names{i};
            if ~isempty(str2double(name)) ...
               || (~isempty(name) && ~isnan(str2double(name(1))))
                fixed_stim_names{i} = ['x', name];
            else
                fixed_stim_names{i} = name;
            end
        end
        
        % Rename from generic to user names in data_raws
        for i = 1:length(data_raws)
            current_keys = data_raws(i).stimulus.keys;
            for j = 1:min(length(fixed_stim_names), length(current_keys))
                generic_name = sprintf('marker%02d', j);
                user_name = fixed_stim_names{j};
                
                % Check if generic_name exists in current keys
                if ismember(generic_name, current_keys)
                    stim = data_raws(i).stimulus(generic_name);
                    stim.name = user_name;
                    data_raws(i).stimulus(generic_name) = [];
                    data_raws(i).stimulus(user_name) = stim;
                end
            end
        end
        
        final_names = fixed_stim_names;
    else
        % Keep generic names
        final_names = {};
        for i = 1:length(data_raws(1).stimulus.keys)
            final_names{i} = sprintf('marker%02d', i);
        end
    end
    
    % Create rename_mapping for reference
    rename_mapping = cell(length(final_names), 2);
    for i = 1:length(final_names)
        rename_mapping{i, 1} = sprintf('marker%02d', i);
        rename_mapping{i, 2} = final_names{i};
    end
    
    disp('Final stimulus mapping:');
    disp(rename_mapping);

    % Now create stimulus table (columns will already have correct names)
    orig_stim_table = nirs.createStimulusTable(data_raws);
    
    % Apply onset/duration if needed
    if (isscalar(stim_onset) && isnan(stim_onset)) ...
        && (isscalar(stim_dur) && isnan(stim_dur))
        mod_stimTable = orig_stim_table;
    else
        if isscalar(stim_onset) && isnan(stim_onset), onset_to_use = NaN;
        else,                                         onset_to_use = stim_onset;
        end
        
        if isscalar(stim_dur) && isnan(stim_dur), dur_to_use = NaN;
        else,                                     dur_to_use = stim_dur;
        end
        
        mod_stimTable = stimTableMapper(orig_stim_table, final_names, ...
                                        onset_to_use, dur_to_use);
    end
    
    disp('Final stimulus table columns:');
    disp(mod_stimTable.Properties.VariableNames);
end
% _________________________________________________________________________
end