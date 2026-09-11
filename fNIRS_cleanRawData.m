function fNIRS_cleanRawData(options)

arguments
    options.InputDir        (1,1) string 
    options.OptodeLink      (1,1) string  = ""
    options.OptodeGeom      (1,1) string  = ""
    options.RevisedMarkers  (1,1) string  = ""
    options.RealignNIRScout (1,1) logical = false
    options.OutputDir       (1,1) string  = fullfile(pwd,"clean")
end
disp('___________________________________________________________________')
disp(' ')
disp('                         CLEANING STARTED                          ')
disp('___________________________________________________________________')

%% STEP.01: Setup in temporary working directory
%-- user feedback (immediate)
fprintf('[1/5]: Setting up working directories...\n');
if contains(options.InputDir,'OneDrive')
disp('       (this may take a while, grab a coffee)'); end

% -- initialize folders
udir.temp = fullfile(pwd, 'temp');
udir.outp = options.OutputDir;
structfun(@(d) mkdir(d), udir, 'UniformOutput', false);
cleanupObj = onCleanup(@() safeCleanup(udir.temp));

% -- copy files to working directory (yes, I know its leaves but...)
leafs = getLeafs(options.InputDir); leafs{end+1} = options.InputDir;
if length(dir(udir.temp)) < 3 %setup didnt't happen before (expensive step)
    for l = 1:length(leafs)
        dstDir = strrep(leafs{l}, options.InputDir, udir.temp);
        copyfile(leafs{l}, dstDir);
    end
end
leafs = getLeafs(udir.temp); leafs{end+1} = udir.temp;

% -- categorize leafs: SNIRF takes priority over HDR when both exist
[snirfLeafs, hdrLeafs] = categorizeLeafs(leafs);
fprintf('       → Found %d SNIRF folders, %d HDR-only folders\n', ...
        length(snirfLeafs), length(hdrLeafs));

%% STEP.02: Realign NIRScout channels to NIRSport layout (if enabled)
if options.RealignNIRScout
    fprintf('[2/5]: Realigning NIRScout channels to NIRSport layout...\n');
    % Only process HDR-only folders (SNIRF folders are skipped)
    for leaf = 1:length(hdrLeafs)
        hdrFiles = dir(fullfile(hdrLeafs{leaf}, '*.hdr'));
        if isempty(hdrFiles), continue; end
        [~, baseName] = fileparts(hdrFiles(1).name);
        realign_nirscout_channels(hdrLeafs{leaf}, baseName);
        fprintf('       ✓ Realigned: %s\n', baseName);
    end
else
    fprintf('[2/5]: Skipping NIRScout realignment...\n');
end

%% STEP.03: Standardize S-D configuration & (generate) add probeInfo file
% Check if optode processing should be done
if options.OptodeLink ~= "" && options.OptodeGeom ~= ""
    fprintf('[3/5]: Standardizing configuration...\n')
    links = readtable(options.OptodeLink);
    
    % Only process HDR-only folders (SNIRF folders don't need this)
    for leaf=1:length(hdrLeafs)
        % 3.1: Edit S-D-Matrix, ShortDetector section
        fprintf('       ✓ Formatted S-D-Matrix & short channels\n');
        hdrFiles = dir(fullfile(hdrLeafs{leaf}, '*.hdr'));
        if isempty(hdrFiles), continue; end
        hdrPath = fullfile(hdrLeafs{leaf}, hdrFiles(1).name); 
        [content, fileName,nD] = update_hdr_mask(fileread(hdrPath), links);
        fid=fopen(hdrPath,'w'); fprintf(fid,'%s',content); fclose(fid);
        
        % 3.2: Standardize file names
        fprintf('       ✓ Standardized filenames\n');
        standardize_filenames(hdrLeafs{leaf}, fileName)

        % 3.3: Update probeInfo files
        fprintf('       ✓ Formatted _probeInfo\n');
        pInfoname = fullfile(hdrLeafs{leaf}, [fileName '_probeInfo.mat']);
        generateProbeInfo(options.OptodeLink, options.OptodeGeom, ...
                               'nDet', nD, 'OutputFile', pInfoname);
    end
else
    fprintf('[3/5]: Skipping configuration...\n')
end

%% Step.04: Update markers
switch options.RevisedMarkers
    case ""
        fprintf('[4/5]: Skipping marker processing...\n');
    case "[]"
        fprintf('[4/5]: Manually revising markers...\n');
        markerfile = revise_hdr_events(leafs);
        update_hdr_events(markerfile, leafs, udir.temp)
        delete(markerfile)
    otherwise
        fprintf('[4/5]: Updating markers using provided file...\n');
        update_hdr_events(options.RevisedMarkers, leafs, udir.temp)
end

%% Step.05: Deliver clean files, remove temporary folder
fprintf('[5/5]: Copying cleaned files to output directory...\n');

% -- Combined log for both HDR and SNIRF files
reqExts = {'_probeInfo.mat', '.hdr', '.wl1', '.wl2'};
combinedLogData = {};
logRowCounter = 0;

% -- HDR file delivery (only from hdrLeafs)
for leaf = 1:length(hdrLeafs)
    [~, folderName] = fileparts(hdrLeafs{leaf});
    logRowCounter = logRowCounter + 1;
    
    % Initialize row with folder name
    currentRow = cell(1, length(reqExts) + 4);
    currentRow{1} = folderName;
    currentRow{2} = dir(fullfile(hdrLeafs{leaf}, ['*' '.hdr'])).name;
    
    %-- check which required files exist
    allExist = true;
    for e = 2:length(reqExts)+1
        matches = dir(fullfile(hdrLeafs{leaf}, ['*' reqExts{e-1}]));
        if ~isempty(matches)
            currentRow{e+1} = '✓';
        else
            currentRow{e+1} = '✗';
            allExist = false;
        end
    end
    
    %-- SnirfFile column (empty for HDR)
    currentRow{length(reqExts)+3} = '';
    
    %-- copy only if all files present
    if allExist
        dstDir = strrep(hdrLeafs{leaf}, udir.temp, udir.outp);
        if ~exist(dstDir, 'dir'), mkdir(dstDir); end
        for e = 1:length(reqExts)
            matches = dir(fullfile(hdrLeafs{leaf}, ['*' reqExts{e}]));
            src = fullfile(hdrLeafs{leaf}, matches(1).name);
            dst = fullfile(dstDir, matches(1).name);
            copyfile(src, dst);
        end
        currentRow{end} = 'SUCCESS';
    else
        currentRow{end} = 'FAILED';
    end
    
    combinedLogData{logRowCounter} = currentRow;
end

% -- SNIRF file delivery (only from snirfLeafs)
for leaf = 1:length(snirfLeafs)
    [~, folderName] = fileparts(snirfLeafs{leaf});
    
    % Find all .snirf files that have companion .csv marker files
    snirfFiles = dir(fullfile(snirfLeafs{leaf}, '*.snirf'));
    for sn = 1:length(snirfFiles)
        [~, snirfBase] = fileparts(snirfFiles(sn).name);
        companionCsv = fullfile(snirfLeafs{leaf}, [snirfBase '.csv']);
        
        logRowCounter = logRowCounter + 1;
        currentRow = cell(1, length(reqExts) + 4);
        currentRow{1} = folderName;
        currentRow{2} = snirfFiles(sn).name;
        
        %-- HDR-related columns (not applicable for SNIRF)
        for e = 2:length(reqExts)
            currentRow{e+1} = ' ';
        end
        
        if exist(companionCsv, 'file')
            % Companion CSV exists, copy both files
            dstDir = strrep(snirfLeafs{leaf}, udir.temp, udir.outp);
            if ~exist(dstDir, 'dir'), mkdir(dstDir); end
            
            srcSnirf = fullfile(snirfLeafs{leaf}, snirfFiles(sn).name);
            srcCsv = companionCsv;
            dstSnirf = fullfile(dstDir, snirfFiles(sn).name);
            dstCsv = fullfile(dstDir, [snirfBase '.csv']);
            
            copyfile(srcSnirf, dstSnirf);
            copyfile(srcCsv, dstCsv);
            
            currentRow{length(reqExts)+3} = '✓';
            currentRow{end} = 'SUCCESS';
            fprintf('       ✓ Copied SNIRF: %s/%s\n', ...
                    folderName, snirfFiles(sn).name);
        else
            currentRow{length(reqExts)+3} = '✗';
            currentRow{end} = 'FAILED (could not process)';
        end
        
        combinedLogData{logRowCounter} = currentRow;
    end
end

% -- Write combined log (only if there are any entries)
if ~isempty(combinedLogData)
    % Convert cell array to matrix
    logMatrix = vertcat(combinedLogData{:});
    
    % Create table with appropriate column names
    columnNames = ['Folder','File', reqExts, '.snirf', 'Export'];
    logTable = cell2table(logMatrix, 'VariableNames', columnNames);
    
    % Write to file
    logFile = fullfile(udir.outp, sprintf('cleanlog_%s.csv', ...
                        datetime('now', 'Format', 'yyyy-MM-dd_HH-mm')));
    writetable(logTable, logFile);
    fprintf('       → Combined log saved: %s\n', logFile);
    
    % Display summary statistics
    totalRows = height(logTable);
    successCount = sum(strcmp(logTable.Export, 'SUCCESS'));
    hdrCount = sum(strcmp(logTable.('.hdr'),'✓'));
    snirfCount = sum(strcmp(logTable.('.snirf'),'✓'));
    
    fprintf(['       → Summary: %d total, %d successful ' ...
             '(%d HDR, %d SNIRF)\n'], ...
            totalRows, successCount, hdrCount, snirfCount);
end

fprintf('       ✓ Finished copying clean files\n');

% -- cleanup
rmdir(udir.temp, 's');

disp(' ')
disp('                         CLEANING COMPLETE                         ')
disp('___________________________________________________________________')

% _________________________________________________________________________

%% Auxilliary functions ___________________________________________________

function [snirfLeafs, hdrLeafs] = categorizeLeafs(leafs)
    % CATEGORIZELEAFS - Split leaf folders into SNIRF and HDR-only categories
    %
    % When a folder contains BOTH .snirf and .hdr files, only the .snirf
    % is processed. HDR processing only happens for folders without .snirf.
    %
    % Outputs:
    %   snirfLeafs - Cell array of folders containing .snirf files
    %   hdrLeafs   - Cell array of folders with .hdr but NO .snirf files
    
    snirfLeafs = {};
    hdrLeafs = {};
    
    for i = 1:length(leafs)
        hasSnirf = ~isempty(dir(fullfile(leafs{i}, '*.snirf')));
        hasHdr = ~isempty(dir(fullfile(leafs{i}, '*.hdr')));
        
        if hasSnirf
            % SNIRF takes priority - folder goes to snirfLeafs
            snirfLeafs{end+1} = leafs{i}; %#ok<AGROW>
        elseif hasHdr
            % HDR-only folder
            hdrLeafs{end+1} = leafs{i}; %#ok<AGROW>
        end
        % Folders with neither are ignored
    end
end

    function realign_nirscout_channels(folderPath, baseName)
% REALIGN_NIRSCOUT_CHANNELS  Remap NIRScout S-D indices to NIRSport layout
%
%   Permutes: .wl1/.wl2 data columns, S-D-Mask, Gains, DarkNoise, ChanDis
%   so that the resulting files look as if they were recorded on a NIRSport
%   using the NIRSport's native source/detector numbering.
%
%   SRC_MAP(i) = j means: NIRScout source i → NIRSport source j
%   DET_MAP(i) = j means: NIRScout detector i → NIRSport detector j
%   Detectors beyond length(DET_MAP) (i.e. short detectors) keep their
%   original index — their data is replicated across D17-D24 per source
%   on NIRScout, so only the source remapping matters for intensity values.

    SRC_MAP = [4, 2, 3, 13, 1, 10, 11, 9, 12, 15, 14, 16, 6, 8, 7, 5];
    DET_MAP = [2, 4, 1, 3, 11, 9, 10, 16, 13, 12, 15, 14, 7, 5, 8, 6];

    % -- Load .hdr
    hdrPath = fullfile(folderPath, [baseName '.hdr']);
    hdrContent = fileread(hdrPath);
    oldMask = parse_sd_mask(hdrContent);
    [nSrc, nDet] = size(oldMask);

    % -- Step 1: Get active channels in scan order (row-major traversal)
    oldActiveList = [];
    for s = 1:nSrc
        for d = 1:nDet
            if oldMask(s, d) == 1
                oldActiveList(end+1, :) = [s, d]; %#ok<AGROW>
            end
        end
    end
    nChannels = size(oldActiveList, 1);

    % -- Step 2: Compute remapped (s,d) for each channel
    newActiveList = zeros(size(oldActiveList));
    for i = 1:nChannels
        s_old = oldActiveList(i, 1);
        d_old = oldActiveList(i, 2);
        if s_old <= length(SRC_MAP), newActiveList(i,1) = SRC_MAP(s_old);
        else,                        newActiveList(i,1) = s_old; end
        if d_old <= length(DET_MAP), newActiveList(i,2) = DET_MAP(d_old);
        else,                        newActiveList(i,2) = d_old; end
    end

    % -- Step 3: Build new S-D-Mask
    newMask = zeros(nSrc, nDet);
    for i = 1:nChannels
        newMask(newActiveList(i,1), newActiveList(i,2)) = 1;
    end

    % -- Step 4: Build column permutation for full grid
    %   fullPerm(newCol) = oldCol  →  output(:,newCol) = input(:,oldCol)
    fullPerm = 1:(nSrc * nDet);          % identity baseline
    for i = 1:nChannels
        oldCol = (oldActiveList(i,1)-1)*nDet + oldActiveList(i,2);
        newCol = (newActiveList(i,1)-1)*nDet + newActiveList(i,2);
        fullPerm(newCol) = oldCol;
    end

    % -- Step 5: Permute .wl1 and .wl2 columns (preserve formatting)
    for wl = 1:2
        wlPath = fullfile(folderPath, sprintf('%s.wl%d', baseName, wl));
        if ~exist(wlPath, 'file'), continue; end
        wlData = readmatrix(wlPath, 'FileType', 'text', 'Delimiter', ' ');
        wlData = wlData(:, fullPerm);
        dlmwrite(wlPath, wlData, 'delimiter', ' ', 'precision', '%.7f');
    end

    % -- Step 6: Permute Gains matrix
    oldGains = parse_block(hdrContent, 'Gains');
    if ~isempty(oldGains)
        newGains = oldGains;
        for i = 1:nChannels
            sO = oldActiveList(i,1); dO = oldActiveList(i,2);
            sN = newActiveList(i,1); dN = newActiveList(i,2);
            newGains(sN, dN) = oldGains(sO, dO);
        end
        hdrContent = replace_block(hdrContent, 'Gains', newGains, '%d');
    end

    % -- Step 7: Permute DarkNoise (detector-indexed, 1×nDet)
    for wlTag = ["Wavelength1", "Wavelength2"]
        oldDN = parse_block(hdrContent, wlTag);
        if isempty(oldDN), continue; end
        newDN = oldDN;
        for d = 1:min(length(DET_MAP), length(oldDN))
            newDN(DET_MAP(d)) = oldDN(d);
        end
        hdrContent = replace_block(hdrContent, wlTag, newDN, '%.3f');
    end

    % -- Step 8: Permute ChannelsDistance (scan-order indexed)
    hdrContent = permute_chandis(hdrContent, oldMask, newMask, ...
                                  oldActiveList, newActiveList, nChannels);

    % -- Step 9: Write updated S-D-Mask and save
    hdrContent = replace_sd_mask(hdrContent, newMask);
    fid = fopen(hdrPath, 'w');
    fprintf(fid, '%s', hdrContent);
    fclose(fid);
end

% =========================================================================
%  Block parse/replace helpers
% =========================================================================

function mat = parse_block(content, tag)
%PARSE_BLOCK  Extract a "#...#" delimited numeric block by tag name.
%   Works for both matrix blocks (Gains) and vector blocks (Wavelength1).
    pattern = [char(tag) '="#\s*([\s\S]*?)#"'];
    tokens = regexp(content, pattern, 'tokens', 'once');
    if isempty(tokens), mat = []; return; end
    lines = strsplit(strtrim(tokens{1}), newline);
    mat = [];
    for i = 1:length(lines)
        line = strtrim(lines{i});
        if isempty(line), continue; end
        rowVals = str2num(line); %#ok<ST2NM>
        if ~isempty(rowVals), mat(end+1,:) = rowVals; end %#ok<AGROW>
    end
end

function content = replace_block(content, tag, newMat, fmt)
%REPLACE_BLOCK  Rewrite a "#...#" delimited block with new values.
    blockStr = '';
    for r = 1:size(newMat, 1)
        rowVals = sprintf([fmt '\t'], newMat(r, :));
        blockStr = [blockStr, strtrim(rowVals), newline]; %#ok<AGROW>
    end
    pattern = ['(' char(tag) '="#)[^#]*(#")'];
    if ~isempty(regexp(content, pattern, 'once'))
        content = regexprep(content, pattern, ['$1' newline blockStr '$2']);
    end
end

% =========================================================================
%  ChannelsDistance permutation
% =========================================================================

function content = permute_chandis(content, oldMask, newMask, ...
                                    oldActiveList, newActiveList, nCh)
    pat = 'ChanDis="([^"]*)"';
    tokens = regexp(content, pat, 'tokens', 'once');
    if isempty(tokens), return; end
    oldDist = str2num(tokens{1}); %#ok<ST2NM>
    if isempty(oldDist) || length(oldDist) ~= nCh, return; end

    % Map each old channel to its old scan-order position
    %   oldScanPos(i) = position of channel i in the old scan order
    %   (trivially = i, since oldActiveList is already in scan order)
    % Map each new position to the channel index that lands there
    [nSrc, nDet] = size(newMask);
    
    % Build lookup: (newS,newD) → which channel index
    chanLookup = containers.Map('KeyType','char','ValueType','int32');
    for i = 1:nCh
        key = sprintf('%d-%d', newActiveList(i,1), newActiveList(i,2));
        chanLookup(key) = i;
    end

    % Walk new mask in scan order, pull distance from the original channel
    newDist = zeros(1, nCh);
    distIdx = 0;
    for s = 1:nSrc
        for d = 1:nDet
            if newMask(s, d) ~= 1, continue; end
            distIdx = distIdx + 1;
            key = sprintf('%d-%d', s, d);
            if chanLookup.isKey(key)
                origIdx = chanLookup(key);   % which channel lives here now
                newDist(distIdx) = oldDist(origIdx); % its original distance
            end
        end
    end

    distStr = strtrim(sprintf('%.1f\t', newDist));
    content = regexprep(content, pat, ['ChanDis="' distStr '"']);
end

% =========================================================================
%  S-D-Mask parse/replace
% =========================================================================

function mask = parse_sd_mask(hdrContent)
    pattern = 'S-D-Mask="#\s*([\s\S]*?)#"';
    tokens = regexp(hdrContent, pattern, 'tokens', 'once');
    if isempty(tokens), error('S-D-Mask not found in header file'); end
    lines = strsplit(strtrim(tokens{1}), newline);
    mask = [];
    for i = 1:length(lines)
        line = strtrim(lines{i});
        if isempty(line), continue; end
        rowVals = str2num(line); %#ok<ST2NM>
        if ~isempty(rowVals), mask(end+1,:) = rowVals; end %#ok<AGROW>
    end
end

function content = replace_sd_mask(content, newMask)
    maskStr = '';
    for r = 1:size(newMask, 1)
        rowVals = sprintf('%d\t', newMask(r, :));
        maskStr = [maskStr, strtrim(rowVals), newline]; %#ok<AGROW>
    end
    pattern = '(S-D-Mask="#)[^#]*(#")';
    if ~isempty(regexp(content, pattern, 'once'))
        content = regexprep(content, pattern, ['$1' newline maskStr '$2']);
    else
        warning('S-D-Mask not found in header');
    end
end

function [content, fileName, nDetectors] = update_hdr_mask(content, links)
    %-- parse content
    nSources   = str2double(regexp(content, 'Sources=(\d+)', ...
                                            'tokens', 'once'));
    nDetectors = str2double(regexp(content, 'Detectors=(\d+)', ...
                                            'tokens', 'once'));
    fileName   = regexp(content,'FileName="([^"]+)"','tokens','once'); 
    fileName   = fileName{1};
    
    %-- build new [S-D-Mask] from [links]
    newMask = zeros(nSources, nDetectors);
    for row = 1:height(links)
        s = links.source(row); d = links.detector(row);
        if d <= nDetectors && s <= nSources, newMask(s, d) = 1; end
    end
    shortDets = find(any(newMask(:, 17:end), 1)) + 16;
    
    maskStr = '';
    for r = 1:size(newMask, 1)
        rowVals = sprintf('%d\t', newMask(r, :));
        maskStr = [maskStr, strtrim(rowVals), newline]; %#ok<AGROW>
    end
    
    pattern = '(S-D-Mask="#)[^#]*(#")';
    if ~isempty(regexp(content, pattern, 'once'))
        content = regexprep(content, pattern, ['$1' newline maskStr '$2']);
        else, warning('S-D-Mask not found in header');
    end
    %-- update short detector field
    if ~isempty(shortDets)
        shortStr = strtrim(sprintf('%d\t', shortDets));
        if contains(content, 'ShortBundles=')
            content=regexprep(content,'ShortBundles=\d+','ShortBundles=1');
            content=regexprep(content,'ShortDetIndex="[^"]*"', ...
                                      ['ShortDetIndex="' shortStr '"']);
        else
            content = regexprep(content, '(Detectors=\d+\r?\n)', ...
                ['$1ShortBundles=1\nShortDetIndex="' shortStr '"\n']);
        end
    else
        content = regexprep(content, 'ShortBundles=\d+\r?\n', '');
        content = regexprep(content, 'ShortDetIndex="[^"]*"\r?\n', '');
    end
end

function standardize_filenames(folderPath, baseName)
    files = dir(folderPath);
    for k = 1:numel(files)
        if files(k).isdir, continue; end
        [~, ~, ext] = fileparts(files(k).name);
        oldPath = fullfile(folderPath, files(k).name);
        newPath = fullfile(folderPath, [baseName, ext]);
        if ~strcmp(oldPath, newPath)
            movefile(oldPath, newPath);
        end
    end
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
    remaining = file_content(content_start:end);
    end_pos = strfind(remaining, end_marker);
    
    if isempty(end_pos)
        events = [];
        return;
    end
    
    events_str = file_content(content_start:(content_start+end_pos(1)-2));
    events_str = strtrim(events_str);
    
    % Parse the events
    if isempty(events_str)
        events = [];
        return;
    end
    
    lines = strsplit(events_str, '\n');
    events = [];
    
    for i = 1:length(lines)
        line = strtrim(lines{i});
        if isempty(line)
            continue;
        end
        
        % Parse the line (format: time type value)
        parts = strsplit(line);
        if length(parts) >= 3
            time_val = str2double(parts{1});
            type_val = str2double(parts{2});
            calc_val = str2double(parts{3});
            
            if ~isnan(time_val) && ~isnan(type_val)
                events = [events; time_val, type_val, calc_val];%#ok<AGROW>
            end
        end
    end
end

function extract_hdr_events(folderList, outputFile, tempdir)
    % Create a CSV file for manual marker editing
    % Check if nirs-toolbox is available for SNIRF loading
    snirfAvailable = ~isempty(which('nirs.io.loadSNIRF'));
    if snirfAvailable
        fprintf(['       ℹ nirs-toolbox detected, ' ...
                'SNIRF files will be processed\n']);
    else
        fprintf(['       ℹ nirs-toolbox not found, ' ...
                'skipping SNIRF files\n']);
    end
    
    maxMarkers = 0; rowData = {};
    for f = 1:length(folderList)
        folderName = strrep(folderList{f}, [tempdir filesep], '');
        snirfFiles = dir(fullfile(folderList{f}, '*.snirf'));
        hasSnirfFiles = ~isempty(snirfFiles);

        % Process HDR files only if NO snirf files exist
        if ~hasSnirfFiles || ~snirfAvailable
            hdrFiles = dir(fullfile(folderList{f}, '*.hdr'));
            for h = 1:length(hdrFiles)
                content = fileread(fullfile(folderList{f}, ...
                                   hdrFiles(h).name));
                events = extract_events(content);
                
                newRow = {folderName, 'hdr', hdrFiles(h).name};
                if ~isempty(events)
                    markerTimes = events(:, 1)';
                    newRow = [newRow, num2cell(markerTimes)]; %#ok<AGROW>
                    maxMarkers = max(maxMarkers, length(markerTimes));
                end
                rowData{end+1} = newRow; %#ok<AGROW>
            end
        end
        
        % Process SNIRF files (if toolbox available and snirf exists)
        if snirfAvailable && hasSnirfFiles
            for s = 1:length(snirfFiles)
                snirfPath = fullfile(folderList{f}, snirfFiles(s).name);
                try
                    data = nirs.io.loadSNIRF(snirfPath);
                    
                    % Extract all onsets from all stimulus types
                    allOnsets = [];
                    if isprop(data, 'stimulus') && ~isempty(data.stimulus)
                        stimValues = data.stimulus.values;
                        for n = 1:length(stimValues)
                            if isprop(stimValues{n}, 'onset') ...
                               || isfield(stimValues{n}, 'onset')
                                onsets = stimValues{n}.onset;
                                allOnsets = [allOnsets; onsets(:)];
                            end
                        end
                    end
                    
                    % Sort onsets chronologically
                    allOnsets = sort(allOnsets);
                    
                    newRow = {folderName, 'snirf', snirfFiles(s).name};
                    if ~isempty(allOnsets)
                        newRow = [newRow, num2cell(allOnsets')];%#ok<AGROW>
                        maxMarkers = max(maxMarkers, length(allOnsets));
                    end
                    rowData{end+1} = newRow; %#ok<AGROW>
                    clear data;
                catch ME
                    fprintf('       ⚠ Failed to load SNIRF: %s (%s)\n', ...
                            snirfFiles(s).name, ME.message);
                end
            end
        end
    end
    
    % Build output table with consistent column count
    markerCols = arrayfun(@(x) sprintf('Marker%d', x), 1:maxMarkers, ...
                          'UniformOutput', false);
    nCols = 3 + maxMarkers;  % Folder, SourceType, SourceFile, Marker1...
    outData = cell(length(rowData), nCols);
    
    for r = 1:length(rowData)
        row = rowData{r};
        for c = 1:length(row)
            outData{r, c} = row{c};
        end
    end
    
    outTable = cell2table(outData, 'VariableNames', ...
                          ['Folder','SourceType','SourceFile',markerCols]);
    writetable(outTable, outputFile);
    
    fprintf('       ✓ Extracted markers from %d sources\n',...
            length(rowData));
end

function update_hdr_events(markerFile, folderList, tempdir)
    % Read the marker file (now includes SourceType and SourceFile columns)
    marker_table = readtable(markerFile, ...
    'Delimiter',         ',', ...
    'TextType',          'string', ...
    'VariableNamingRule','preserve');
    sample_rate = NaN;
    
    % Get required markers (count marker columns)
    varNames = marker_table.Properties.VariableNames;
    markerCols = startsWith(varNames, 'Marker');
    required_markers = sum(markerCols);
    
    % Process each row in the marker table
    for row_idx = 1:height(marker_table)
        folder_name = marker_table.Folder{row_idx};
        source_type = marker_table.SourceType{row_idx};
        source_file = marker_table.SourceFile{row_idx};
        
        % Find the corresponding folder in folderList
        folder_path = '';
        for f = 1:length(folderList)
            fn = strrep(folderList{f}, [tempdir filesep], '');
            if strcmp(fn, folder_name)
                folder_path = folderList{f};
                break;
            end
        end
        
        if isempty(folder_path)
        fprintf('       ⚠ Folder %s not found. Skipping.\n', folder_name);
        continue;
        end
        
        marker_values = table2array(marker_table(row_idx, 4:end));
        valid_markers = marker_values(~isnan(marker_values) ...
                                      & marker_values ~= 0);
        
        if isempty(valid_markers)
            fprintf('       ⚠ No valid markers for %s/%s. Skipping.\n', ...
                    folder_name, source_file);
            continue;
        end
        
        % Branch based on source type
        switch lower(source_type)
            case 'hdr'
                % Existing HDR update logic
                update_single_hdr(folder_path, source_file, ...
                                  valid_markers, sample_rate, ...
                                  required_markers);
                
            case 'snirf'
                % Create companion CSV for SNIRF
                create_snirf_marker_csv(folder_path, source_file, ...
                                        valid_markers);
                
            otherwise
                fprintf('       ⚠ Unknown source type: %s. Skipping.\n',...
                        source_type);
        end
    end
    
    fprintf('       ✓ Event update complete.\n');
end

function update_single_hdr(folder_path,hdr_filename,markers,sample_rate,...
                           required_markers)

    file_path = fullfile(folder_path, hdr_filename);
    if ~exist(file_path, 'file')
        fprintf('       ⚠ HDR file not found: %s. Skipping.\n', file_path);
        return;
    end
    
    % Read the file content
    file_content = fileread(file_path);
    
    % If sample_rate not provided, try to extract it from the file
    current_sample_rate = sample_rate;
    if isnan(current_sample_rate)
        current_sample_rate = extract_sample_rate(file_content);
        if isnan(current_sample_rate)
        fprintf('       ⚠ Could not extract sample rate. Using 1.0.\n');
        current_sample_rate = 1.0;
        end
    end
    
    % Generate new events (use required number of markers)
    new_events = '';
    for i = 1:required_markers
        if i > length(markers), break; end
        time_value = markers(i);
        calc_value = time_value * current_sample_rate;
        new_events = [new_events, sprintf('%.2f\t%d\t%.0f\n', ...
                     time_value, i, calc_value)]; %#ok<AGROW>
    end
    
    % Replace events section in the file
    updated_content = replace_events_section(file_content, new_events);
    
    % Write the updated content back to the file
    fid = fopen(file_path, 'w');
    if fid == -1
    fprintf('       ⚠ Could not open file %s for writing.\n',file_path);
    return;
    end
    fprintf(fid, '%s', updated_content);
    fclose(fid);
end

function create_snirf_marker_csv(folder_path,snirf_filename, marker_values)
    
    [~, baseName] = fileparts(snirf_filename);
    csv_path = fullfile(folder_path, [baseName '.csv']);
    
    % Build marker table
    nMarkers = length(marker_values);
    markerNames = arrayfun(@(x) sprintf('marker_%d', x), 1:nMarkers, ...
                           'UniformOutput', false)';
    markerTimes = marker_values(:);
    
    markerTable = table(markerNames, markerTimes, ...
                        'VariableNames', {'Marker', 'Time'});
    
    % Write CSV
    writetable(markerTable, csv_path);
    
    fprintf('       → Created marker CSV: %s.csv (%d markers)\n', ...
            baseName, nMarkers);
end

function outputFile = revise_hdr_events(folderList)
    %-- create marker list from .hdr and .snirf files
    outputFile = fullfile(pwd,'temp.csv');
    extract_hdr_events(folderList, outputFile, udir.temp); tic
    
    %-- open marker list in default csv viewer application
    fprintf('       ☷ Opening default spreadsheet viewer application\n');
    if ispc
        winopen(char(outputFile));
        checkCmd = sprintf(['powershell -c "(Get-Process | Where-Object'...
                            ' {$_.MainWindowTitle -like ''*%s*''})' ...
                            '.Count -gt 0"'], outputFile);
    elseif ismac
        system(['open "' char(outputFile) '"']);
        checkCmd = ['lsof "' char(outputFile) '" > /dev/null 2>&1'];
    else
        system(['xdg-open "' char(outputFile) '"']);
        checkCmd = ['lsof "' char(outputFile) '" > /dev/null 2>&1'];
    end
    
    %-- wait for user to process markers
    fprintf('       ⚙ Manually processing markers\n'); pause(5);
    fileClosed = false;
    while ~fileClosed
        [status, ~] = system(checkCmd);
        fileClosed = (status ~= 0);
        if ispc, fileClosed = (status == 0); end
        if ~fileClosed, pause(2); end
    end
    
    %-- fallback confirmation dialog
    if toc < 10
        questdlg('Finished editing markers?', ...
                 'Confirm', 'Continue', 'Continue');
    end

    fprintf('       ✓ Markers revised.\n');
end

function sample_rate = extract_sample_rate(file_content)

    sample_rate = NaN;
    rate_marker = 'SamplingRate=';
    rate_pos = strfind(file_content, rate_marker);
    
    if ~isempty(rate_pos)
        % Extract the line with the sampling rate
        line_end = strfind(file_content(rate_pos:end), newline);
        
        if ~isempty(line_end)
            rate_line = file_content(rate_pos:(rate_pos + line_end(1)-2));
            
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
        %-- no markers, append
        updated_content = [file_content, ...
                           sprintf('\n[Markers]\nEvents="#\n'), ...
                           new_events, sprintf('#"\n')];
        return;
    end
    
    % Find the start of the Events field
    events_field_start=strfind(file_content(events_start:end),'Events="#');
    
    if isempty(events_field_start)
        % If no Events field, insert one after [Markers]
        next_section = strfind(file_content((events_start + 9):end), '[');
        
        if isempty(next_section)
            % If this is the last section, append at the end
            insert_pos = length(file_content);
        else
            insert_pos = events_start + 9 + next_section(1) - 2;
        end
        
        updated_content = [file_content(1:insert_pos), ...
                           sprintf('\nEvents="#\n'), ...
                           new_events, sprintf('#"\n'), ...
                           file_content((insert_pos + 1):end)];
        return;
    end
    
    % Calculate absolute position of Events field
    events_field_pos = events_start + events_field_start(1) - 1;
    
    % Find the end of the Events field
    events_end_marker = strfind(file_content(events_field_pos:end), '#"');
    
    if isempty(events_end_marker)
        % If no end marker, something is wrong with the file
        fprintf('Warning: Could not find end of Events section.\n');
        updated_content = file_content;
        return;
    end
    
    % Calculate the positions to replace
    events_end_pos = events_field_pos + events_end_marker(1) + 1;
    
    % Replace the content
    updated_content = [file_content(1:(events_field_pos + 8)), ...
                      newline, new_events, ...
                      sprintf('#"'), file_content((events_end_pos+1):end)];
end

function safeCleanup(tempDir)
    fclose('all'); pause(0.5);
    if exist(tempDir, 'dir'), try rmdir(tempDir, 's'); catch; end; end
end
end
