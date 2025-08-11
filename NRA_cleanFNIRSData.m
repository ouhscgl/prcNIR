function NRA_cleanFNIRSData(input_dir, optode_data_link, optode_data_geom, revised_markers, output_dir)
% NRA_CLEANFNIRSDATA - Clean and standardize fNIRS dataset
%
% Inputs:
%   input_dir        - Base directory containing raw data (REQUIRED)
%   optode_data_link - CSV file with optode linkage data (optional, use 0/nan/empty to skip)
%   optode_data_geom - CSV file with optode geometry data (optional, use 0/nan/empty to skip)
%   revised_markers  - CSV file with revised marker information (optional, use 0/nan/empty to skip, empty to prompt)
%   output_dir       - Custom output directory (optional)

% Handle optional parameters
if nargin < 2, optode_data_link = []; end
if nargin < 3, optode_data_geom = []; end  
if nargin < 4, revised_markers = []; end
if nargin < 5, output_dir = []; end

% Rename for consistency with original code
raw_dir = input_dir;

disp('-------------------------------------------------------------------')
disp('|                        CLEANING STARTED                         |')
disp('-------------------------------------------------------------------')

%% STEP.01: Setup in temporary working directory
fprintf('STEP 1: Setting up working directories...\n');
% -- initialize folder variables
dL = {'edit','temp'}; udir = struct(); nL = getLeafDirs(raw_dir);

% Handle output directory specification
if ~isempty(output_dir)
    % Use custom output directory
    udir.edit = output_dir;
    [parent_dir, ~] = fileparts(output_dir);
    udir.temp = fullfile(parent_dir, 'temp');
else
    % Backwards compatible behavior
    if contains(raw_dir, 'raws')
        % Original logic - replace 'raws' with folder names
        for d = 1:length(dL), udir.(dL{d}) = strrep(raw_dir,'raws',dL{d}); end
    else
        % New logic for paths without 'raws'
        [parent_dir, folder_name] = fileparts(raw_dir);
        udir.edit = fullfile(parent_dir, [folder_name '_edit']);
        udir.temp = fullfile(parent_dir, [folder_name '_temp']);
    end
end

cellfun(@(d) mkdir(udir.(d)), dL); 

% -- check if setup happened before; new run -> copy files over
if length(dir(udir.temp)) < 3
    for i = 1:length(nL)
        source_dir = nL{i};
        target_dir = strrep(source_dir, raw_dir, udir.temp);
        copyfile(source_dir, target_dir);
    end
end

%% STEP.02: Standardize S-D configuration & (generate) add probeInfo file
% Check if optode processing should be done
do_optode_processing = should_process_optodes(optode_data_link, optode_data_geom);

if do_optode_processing
    fprintf('STEP 2: Standardizing configuration\n')
    pInfo_base = NRA_generate_probeInfo(optode_data_link, optode_data_geom);
    % .. iterate through clean folders to perform cleaning
    nL = getLeafDirs(udir.temp);
    
    for n=1:length(nL)
        disp(['[',num2str(n),'/',num2str(length(nL)),'] Processing file...'])
        % -- load header file
        hdrFiles = dir(fullfile(nL{n}, '*.hdr'));
        if ~isempty(hdrFiles)
        hdrFile = fullfile(nL{n}, hdrFiles(1).name);
        fid = fopen(hdrFile, 'r'); content = fscanf(fid, '%c'); fclose(fid);
        
        %-- extract name
        name = regexp(content, 'FileName="([^"]+)"', 'tokens', 'once');

        % -- extract detector count
        dm = regexp(content, 'Detectors=(\d+)', 'tokens', 'once');
        nDet = str2double(dm{1});

        % -- extract S-D Mask
        sp = 'S-D-Mask="#\s*([\s\S]*?)#"'; sm = regexp(content, sp, 'tokens');
        ml = strsplit(sm{1}{1},'\n'); ml = ml(~cellfun(@isempty,ml));

        % -- determine number of detectors and create empty matrix
        mtxcol=length(strsplit(strtrim(ml{1}),'\t')); mtxnew=zeros(16,mtxcol);

        % -- activate correct distribution
        probeInfo=pInfo_base; idx = probeInfo.probes.index_c;
        for t=1:length(idx), mtxnew(idx(t,1), idx(t,2))=1; end

        % -- convert the new mask to a string
        newmsk = '';
        for m = 1:size(mtxnew, 1)
        r = sprintf('%d', mtxnew(m, 1));
        for j = 2:size(mtxnew, 2), r = [r, sprintf('\t%d', mtxnew(m, j))];  end
        newmsk = [newmsk, r, sprintf('\r\n')];                     %#ok<*AGROW>
        end
        
        % 2.1: Replace S-D Mask
        % -- replace the old S-D mask with the new one, remove short channels
        fprintf(' -- updating S-D mask...');
        newcnt = regexprep(content, sp, ['S-D-Mask="#\n', newmsk, '#"']);
        newcnt = regexprep(newcnt,'Short(Bundles|DetIndex)\s*=.*?[\r\n]+','');
        fid = fopen(hdrFile, 'w'); fprintf(fid, '%s', newcnt); fclose(fid);
        fprintf('COMPLETE\n');

        % 2.2: Ensure naming convention
        fprintf(' -- updating filenames to %s ...', name{1});
        fL = dir(fullfile(nL{n}));
        for k = 1:numel(fL)
        if fL(k).isdir, continue; end; [~, ~, ext] = fileparts(fL(k).name);
        of = fullfile(nL{n}, fL(k).name); nf = fullfile(nL{n}, [name{1} ext]);
        % -- update messy names only
        if ~strcmp(of,nf), movefile(of, nf); end
        end
        fprintf('COMPLETE\n');

        % 2.3: Update probeInfo files
        fprintf(' -- updating probeInfo files...');
        epi = dir(fullfile(nL{n}, '*_probeInfo.mat'));
        if ~isempty(epi), delete(fullfile(nL{n}, epi(1).name)); end
        pinFile = fullfile(nL{n},[name{1},'_probeInfo.mat']);
        probeInfo.probes.nDetector0           = nDet;
        probeInfo.probes.coords_d2(17:nDet,:) = 0;
        probeInfo.probes.coords_d3(17:nDet,:) = 0;
        probeInfo.probes.normals_d(17:nDet,:) = 0;
        probeInfo.probes.labels_d(1,17:nDet)  = {'Dx'};
        save(pinFile,"probeInfo");
        fprintf('COMPLETE\n');
        disp(['Samples processed: ', hdrFiles(1).name])
        end
    end
else
    fprintf('STEP 2: Skipping optode processing (no valid optode files provided)\n')
    % Still need to update nL for subsequent steps
    nL = getLeafDirs(udir.temp);
end

%% Step.03: Update markers
% Determine marker processing behavior
marker_behavior = get_marker_behavior(revised_markers);

if marker_behavior == 0
    fprintf('STEP 3: Skipping marker processing\n');
elseif marker_behavior == 1
    fprintf('STEP 3: Revising markers (prompting user)...\n');
    % -- analyze markers
    rmk = 'temp.csv'; extract_hdr_events(nL, rmk); revised_markers = rmk;
    
    % -- open in default program
    fprintf('☷ Opening default viewer application...\n');pause(5);
    if      ispc,  winopen(rmk);
    elseif  ismac, system(['open "',     rmk, '"']);
    else,          system(['xdg-open "', rmk, '"']);
    end

    if     ispc
    winopen(rmk); check_cmd = sprintf('move /Y "%s" "%s"', rmk, rmk);
    elseif ismac
    system(['open "',rmk, '"']); check_cmd=['lsof "' rmk '" > /dev/null'];
    else
    system(['xdg-open "',rmk,'"']);check_cmd=['lsof "' rmk '" > /dev/null'];
    end
    
    % -- wait for user to finish manually sorting
    file_closed = false; fprintf('⚙ Manually processing markers\n')
    while ~file_closed
        [status, ~] = system(check_cmd);
        if ispc,  file_closed = (status == 0);
        else,     file_closed = (status ~= 0);
        end
        
        if ~file_closed, pause(5); end
    end
    fprintf('✓ File received - proceeding with analysis.\n');
    
    update_hdr_events(revised_markers, nL)
    
elseif marker_behavior == 2
    fprintf('STEP 3: Updating markers using provided file...\n');
    update_hdr_events(revised_markers, nL)
end

%% Step.04: Deliver clean files, remove temporary folder
fprintf('STEP 4: Copying files to cleaned directory...\n');
for f=1:length(nL)
% -- pick out required files 
mvds = {'.mat','.hdr','.wl1','.wl2','COG.txt'};
fL = dir(fullfile(nL{f})); fL = fL(~[fL.isdir] & endsWith({fL.name},mvds));

% -- create harbour
p = strrep(nL{f}, udir.temp, udir.edit); if ~exist(p, 'dir'), mkdir(p); end

% -- copy files
for k = 1:numel(fL)
src=fullfile(nL{f},fL(k).name);dst=fullfile(p,fL(k).name);copyfile(src,dst)
end
disp(['[',num2str(f),'/',num2str(length(nL)),'] Copied: ', fL(k).name])
end
fprintf('✓ Finished copying files over.\n');

% -- cleanup
rmdir(udir.temp, 's')
disp('                         CLEANING COMPLETE                         ')
disp('___________________________________________________________________')

% _________________________________________________________________________
%% Helper functions for parameter checking ________________________________

function should_process = should_process_optodes(optode_data_link, optode_data_geom)
    % Check if optode processing should be done
    % Skip if either parameter is empty, 0, nan, or '0'
    should_process = ~is_skip_value(optode_data_link) && ~is_skip_value(optode_data_geom);
end

function behavior = get_marker_behavior(revised_markers)
    % Determine marker processing behavior
    % 0 = skip markers, 1 = prompt user, 2 = use provided file
    if is_skip_value(revised_markers)
        behavior = 0; % skip markers
    elseif isempty(revised_markers)
        behavior = 1; % prompt user
    else
        behavior = 2; % use provided file
    end
end

function should_skip = is_skip_value(param)
    % Check if a parameter should be considered a "skip" value
    should_skip = false;
    
    if isempty(param)
        should_skip = false; % Empty is not skip, it's "use default behavior"
    elseif isnumeric(param)
        should_skip = (param == 0 || isnan(param));
    elseif ischar(param)
        should_skip = strcmp(param, '0');
    elseif isstring(param)
        should_skip = (param == "0" || param == "");
    end
end

% _________________________________________________________________________
%% Auxilliary functions ___________________________________________________
function extract_hdr_events(folder_list, output_csv)
% First pass - collect all possible marker IDs across all files
all_marker_ids = {}; folder_names = {}; folder_data = struct();
    
    % Process each folder
    for folder_idx = 1:length(folder_list)
        folder_path = folder_list{folder_idx};
        [~, folder_name] = fileparts(folder_path);
        folder_names{end+1} = folder_name;
        
        % Find all .hdr files in this folder
        hdr_files = dir(fullfile(folder_path, '*.hdr'));
        
        % Initialize the structure for this folder
        valid_name = matlab.lang.makeValidName(folder_name);
        folder_data.(valid_name) = struct('markers',{},'times',{},...
                                          'values', {});
        
        % Process each .hdr file
        for file_idx = 1:length(hdr_files)
            file_path = fullfile(folder_path, hdr_files(file_idx).name);
            
            % Read the file content
            file_content = fileread(file_path);
            
            % Extract events data
            events = extract_events(file_content);
            
            % If events found, store them
            if ~isempty(events)
                current_markers = {};
                current_times = [];  % Change to numeric array
                current_values = [];  % Change to numeric array
                
                for i = 1:size(events, 1)
                    marker_id = sprintf('mrk_%d_%d', i, events(i, 2));
                    
                    % Add to unique marker list if not already there
                    if ~ismember(marker_id, all_marker_ids)
                        all_marker_ids{end+1} = marker_id;
                    end
                    
                    % Store this marker's data
                    current_markers{end+1} = marker_id;
                    current_times(end+1) = events(i, 1);
                    current_values(end+1) = events(i, 3);
                end
                
                % Store in folder data
                folder_data.(valid_name) = struct();
                folder_data.(valid_name).markers = current_markers;
                folder_data.(valid_name).times = current_times;
                folder_data.(valid_name).values = current_values;
            end
        end
    end
    
    % Sort marker IDs for consistent column order
    all_marker_ids = sort(all_marker_ids);
    
    % Create variable types array - first column is string, rest are double
    var_types = cell(1, length(all_marker_ids) + 1);
    var_types{1} = 'string';
    for i = 1:length(all_marker_ids)
        var_types{i+1} = 'double';
    end
    
    % Create output table with markers as column names
    output_table = table('Size', [length(folder_names), ...
                                  length(all_marker_ids) + 1], ...
                         'VariableTypes', var_types, ...
                         'VariableNames', ['Folder', all_marker_ids]);
    
    % Fill in the folder names
    output_table.Folder = string(folder_names');
    
    % Fill in the marker data (using times by default)
    for i = 1:length(folder_names)
        folder_name = folder_names{i};
        valid_name = matlab.lang.makeValidName(folder_name);
        
        % Skip folders with no data
        try
            if ~isfield(folder_data, valid_name) || ...
               ~isfield(folder_data.(valid_name), 'markers') || ...
               isempty(folder_data.(valid_name).markers)
                continue;
            end
        catch
            continue
        end

        
        % Get this folder's marker data
        markers = folder_data.(valid_name).markers;
        times = folder_data.(valid_name).times;
        
        % Fill in each marker's time value
        for qt = 1:length(markers)
            marker_name = markers{qt};
            marker_col = ...
                find(strcmp(output_table.Properties.VariableNames, ...
                            marker_name));
            
            if ~isempty(marker_col)
                output_table{i, marker_col} = times(qt);
            end
        end
    end
    
    % Write to CSV file
    writetable(output_table, output_csv);
    fprintf('Created marker table: %d IDs (%d markers), saved to %s\n', ...
            length(folder_names), length(all_marker_ids), output_csv);
end

function events = extract_events(file_content)
    % Extract the Events section from the hdr file
    event_marker = 'Events="#';
    end_marker = '#"';
    
    event_start = strfind(file_content, event_marker);
    if isempty(event_start)
        events = [];
        return;
    end
    
    content_start = event_start + length(event_marker);
    
    % Find the first non-whitespace character
    remaining = file_content(content_start:end);
    first_content = regexp(remaining, '\S', 'once');
    
    if isempty(first_content)
        events = [];
        return;
    end
    
    content_start = content_start + first_content - 1;
    
    % Find the end marker
    content_end = strfind(file_content(content_start:end), end_marker);
    if isempty(content_end)
        events = [];
        return;
    end
    
    % Extract the events text
    events_text = ...
        file_content(content_start:(content_start + content_end(1) - 2));
    
    % Parse the events into a numeric matrix
    events = [];
    lines = strsplit(strtrim(events_text), '\n');
    
    for i = 1:length(lines)
        if ~isempty(strtrim(lines{i}))
            values = str2double(strsplit(strtrim(lines{i})));
            events = [events; values];
        end
    end
end

function update_hdr_events(csv_file, folder_list, sample_rate)
% Set default sample rate if not provided - update from file
if nargin < 3, sample_rate = NaN; end

% Read the marker table, get folder names
marker_table = readtable(csv_file, 'TextType', 'string', 'TreatAsEmpty', {''}, ...
                        'ReadVariableNames', true, 'DatetimeType', 'text'); 

% Find the folder column (could be 'Folder', 'folder', first column, etc.)
col_names = marker_table.Properties.VariableNames;
folder_col_name = '';
if ismember('Folder', col_names)
    folder_col_name = 'Folder';
elseif ismember('folder', col_names)
    folder_col_name = 'folder';
else
    folder_col_name = col_names{1}; % Use first column
end

table_folders = marker_table.(folder_col_name);
    
    % Process each folder
    for folder_idx = 1:length(folder_list)
        folder_path = folder_list{folder_idx};
        [~, folder_name] = fileparts(folder_path);
        
        % Find this folder in the table
        folder_row_idx = find(strcmp(string(table_folders), folder_name));
        
        if isempty(folder_row_idx)
            fprintf('Warning: Folder %s not found in table. Skipping.\n',...
                    folder_name);
            continue;
        end
        
        % Get the marker data for this folder
        folder_data = marker_table(folder_row_idx, :);
        
        % Find all marker columns (excluding 'Folder')
        marker_cols = marker_table.Properties.VariableNames(2:end);
        
        % Get values for all markers in this folder
        marker_values = table2array(folder_data(:, 2:end));
        
        % Detect dataset type based on folder name or marker count
        % Determine if this is fingertapping (7 markers) or nback (5 markers)
        non_nan_count = sum(~isnan(marker_values) & marker_values ~= 0);
        
        % Check folder name for dataset type or infer from marker count
        if contains(lower(folder_name), 'ftp')
            required_markers = 7;
            dataset_type = 'fingertapping';
        else
            required_markers = 5;
            dataset_type = 'nback';
        end
        
        % Make sure we have enough markers for this dataset type
        if non_nan_count < required_markers
            fprintf('Skipping folder %s: only has %d markers (needs %d for %s).\n', ...
                    folder_name, non_nan_count, required_markers, dataset_type);
            continue;
        end
        
        fprintf('Processing folder %s as %s dataset (%d markers)\n', ...
                folder_name, dataset_type, required_markers);
        
        % Find all .hdr files in this folder
        hdr_files = dir(fullfile(folder_path, '*.hdr'));
        
        % Process each .hdr file
        for file_idx = 1:length(hdr_files)
            file_path = fullfile(folder_path, hdr_files(file_idx).name);
            
            % Read the file content
            file_content = fileread(file_path);
            
            % If sample_rate not provided, try to extract it from the file
            current_sample_rate = sample_rate;
            if isnan(current_sample_rate)
                current_sample_rate = extract_sample_rate(file_content);
                if isnan(current_sample_rate)
                    fprintf('Warning: Could not extract sample rate from %s. Using 1.0.\n', ...
                            hdr_files(file_idx).name);
                    current_sample_rate = 1.0;
                end
            end
            
            % Get the non-NaN marker values
            valid_markers = find(~isnan(marker_values) & marker_values ~= 0);
            if length(valid_markers) < required_markers
                fprintf('Skipping file %s: only has %d valid markers (needs %d for %s).\n', ...
                        file_path, length(valid_markers), required_markers, dataset_type);
                continue;
            end
            
            % Take the required number of valid markers
            markers_to_use = valid_markers(1:required_markers);
            
            % Generate new events
            new_events = '';
            for i = 1:required_markers
                marker_idx = markers_to_use(i);
                time_value = marker_values(marker_idx);
                
                % Calculate 3rd column value (time * sample_rate)
                calc_value = time_value * current_sample_rate;
                
                % Format: time value, event type (i), calculated value
                new_events = [new_events, sprintf('%.2f\t%d\t%.0f\n', ...
                             time_value, i, calc_value)];
            end
            
            % Replace events section in the file
            updated_content = replace_events_section(file_content, new_events);
            
            % Write the updated content back to the file
            fid = fopen(file_path, 'w');
            if fid == -1
                fprintf('Error: Could not open file %s for writing.\n', file_path);
                return;
            end
            fprintf(fid, '%s', updated_content);
            fclose(fid);
        end
    end
    
    fprintf('Event update complete.\n');
end

function sample_rate = extract_sample_rate(file_content)
    % Extract the sampling rate from the .hdr file
    sample_rate = NaN;
    
    % Look for the sampling rate line
    rate_marker = 'SamplingRate=';
    rate_pos = strfind(file_content, rate_marker);
    
    if ~isempty(rate_pos)
        % Extract the line with the sampling rate
        line_end = strfind(file_content(rate_pos:end), sprintf('\n'));
        
        if ~isempty(line_end)
            rate_line = file_content(rate_pos:(rate_pos + line_end(1) - 2));
            
            % Extract the number
            rate_parts = strsplit(rate_line, '=');
            if length(rate_parts) > 1
                sample_rate = str2double(rate_parts{2});
            end
        end
    end
end

function updated_content = replace_events_section(file_content, new_events)
    % Replace the Events section in the .hdr file
    events_start = strfind(file_content, '[Markers]');
    
    if isempty(events_start)
        % If no Markers section, append one
        updated_content = [file_content, sprintf('\n[Markers]\nEvents="#\n'), ...
                          new_events, sprintf('#"\n')];
        return;
    end
    
    % Find the start of the Events field
    events_field_start = strfind(file_content(events_start:end), 'Events="#');
    
    if isempty(events_field_start)
        % If no Events field, insert one after [Markers]
        next_section = strfind(file_content((events_start + 9):end), '[');
        
        if isempty(next_section)
            % If this is the last section, append at the end
            insert_pos = length(file_content);
        else
            insert_pos = events_start + 9 + next_section(1) - 2;
        end
        
        updated_content = [file_content(1:insert_pos), sprintf('\nEvents="#\n'), ...
                          new_events, sprintf('#"\n'), file_content((insert_pos + 1):end)];
        return;
    end
    
    % Calculate absolute position of Events field
    events_field_pos = events_start + events_field_start(1) - 1;
    
    % Find the end of the Events field
    events_end_marker = strfind(file_content(events_field_pos:end), '#"');
    
    if isempty(events_end_marker)
        % If no end marker, something is wrong with the file
        fprintf('Warning: Could not find end of Events section. File may be corrupted.\n');
        updated_content = file_content;
        return;
    end
    
    % Calculate the positions to replace
    events_end_pos = events_field_pos + events_end_marker(1) + 1;
    
    % Replace the content
    updated_content = [file_content(1:(events_field_pos + 8)), ...
                      sprintf('\n'), new_events, ...
                      sprintf('#"'), file_content((events_end_pos + 1):end)];
end
end