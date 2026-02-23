function fNIRS_Visualize(groupStats, optodeMap, varargin)
% fNIRS_ControlPanel - Automated fNIRS contrast processing and figure saving
%
% Usage:
%   fNIRS_ControlPanel(groupStats, optodeMap, params)
%   fNIRS_ControlPanel(groupStats, optodeMap, conditionMap, params)
%   fNIRS_ControlPanel(groupStats, optodeMap, 'auto', params)          % legacy
%   fNIRS_ControlPanel(groupStats, optodeMap, conditionMap, 'auto', params) % legacy
%
%   params struct fields:
%      - contrasts:      matrix of contrasts (NxM) or cell array of contrast vectors
%      - contrastNames:  cell array of short names for contrasts (optional)
%                        e.g., {'2b-EO', 'EO-EC', 'MainEffect'}
%                        If fewer names than contrasts, remaining use auto-generated names
%      - significance:   cell array, e.g. {'p'} or {'q'} or {'p','q'}
%      - saveHbo:        true/false
%      - saveHbr:        true/false
%      - saveCoeff:      true/false
%      - visMethod:      '10-20 map' or '3d mesh'
%      - figFormat:      'svg', 'png', etc.
%      - output_dir:     directory for output files
%      - output_prefix:  prefix for output filenames

%% ========================================================================
%  Parse inputs
%  ========================================================================
[conditionMap, params] = parseInputs(groupStats, varargin{:});

numConditions = length(groupStats.conditions);
figureFormat  = getParamOrDefault(params, 'figFormat', 'svg');

%% ========================================================================
%  Validate and process
%  ========================================================================
validateParams(params, numConditions);
disp('Processing with provided contrasts...');
processContrastsAutomated(params, groupStats, optodeMap, conditionMap, figureFormat);

end % End of main function

%% ========================================================================
%  Input Parsing
%  ========================================================================
function [conditionMap, params] = parseInputs(groupStats, varargin)
    conditionMap = [];
    params = struct();

    args = varargin;

    % Strip legacy 'auto' keyword anywhere it appears
    autoIdx = find(cellfun(@(x) ischar(x) && strcmpi(x, 'auto'), args));
    args(autoIdx) = [];

    if isempty(args)
        % Nothing provided — params will fail validation below
    elseif isstruct(args{1})
        % Pattern: (groupStats, optodeMap, params)
        params = args{1};
    elseif isstruct(args{end})
        % Pattern: (groupStats, optodeMap, conditionMap, params)  or with 'auto'
        conditionMap = args{1};
        params = args{end};
    else
        error('fNIRS_ControlPanel:BadArgs', ...
              'Could not parse inputs. Expected params struct as last argument.');
    end

    % Build default conditionMap if not provided
    if isempty(conditionMap)
        conditionMap = containers.Map();
        for i = 1:length(groupStats.conditions)
            conditionMap(groupStats.conditions{i}) = {groupStats.conditions{i}};
        end
    end
end

%% ========================================================================
%  Validation
%  ========================================================================
function validateParams(params, numConditions)
    if ~isfield(params, 'contrasts')
        error('fNIRS_ControlPanel:MissingContrasts', ...
              'params.contrasts must be provided');
    end

    c = params.contrasts;
    if iscell(c)
        for i = 1:length(c)
            if length(c{i}) ~= numConditions
                error('fNIRS_ControlPanel:ContrastMismatch', ...
                      'Contrast %d has %d elements but should have %d to match conditions', ...
                      i, length(c{i}), numConditions);
            end
        end
    else
        if size(c, 2) ~= numConditions
            error('fNIRS_ControlPanel:ContrastMismatch', ...
                  'Contrast matrix has %d columns but should have %d to match conditions', ...
                  size(c, 2), numConditions);
        end
    end

    if isfield(params, 'contrastNames') && ~iscell(params.contrastNames)
        error('fNIRS_ControlPanel:InvalidContrastNames', ...
              'params.contrastNames must be a cell array of strings');
    end
end

function val = getParamOrDefault(params, fieldName, defaultVal)
    if isfield(params, fieldName)
        val = params.(fieldName);
    else
        val = defaultVal;
    end
end

%% ========================================================================
%  Automated batch processing
%  ========================================================================
function processContrastsAutomated(params, groupStats, optodeMap, conditionMap, figureFormat)
    c = params.contrasts;
    contrastNames = getParamOrDefault(params, 'contrastNames', {});

    % Normalize significance to cell array
    if ~isfield(params, 'significance') || isempty(params.significance)
        params.significance = {'p'};
    elseif ~iscell(params.significance)
        params.significance = {params.significance};
    end

    if iscell(c)
        for i = 1:length(c)
            customName = getContrastName(contrastNames, i);
            disp(['Processing contrast ' num2str(i) ': ' customName]);
            disp(c{i});
            processContrast(c{i}, params, groupStats, optodeMap, ...
                            conditionMap, figureFormat, customName);
        end
    else
        for i = 1:size(c, 1)
            customName = getContrastName(contrastNames, i);
            disp(['Processing contrast ' num2str(i) ': ' customName]);
            disp(c(i, :));
            processContrast(c(i, :), params, groupStats, optodeMap, ...
                            conditionMap, figureFormat, customName);
        end
    end
end

function name = getContrastName(contrastNames, index)
    if ~isempty(contrastNames) && index <= length(contrastNames) && ~isempty(contrastNames{index})
        name = sanitizeFilename(contrastNames{index});
    else
        name = '';
    end
end

%% ========================================================================
%  Core processing function
%  ========================================================================
function processContrast(contrast, params, groupStats, optodeMap, ...
                         conditionMap, figureFormat, customName)

    % Calculate statistics
    ContrastStatsCE  = groupStats.ttest(contrast);
    ContrastStatsTable = ContrastStatsCE.table;

    % Set visualization method
    if isfield(params, 'visMethod')
        ContrastStatsCE.probe.defaultdrawfcn = params.visMethod;
    end

    % Set optode map
    if ~isequal(optodeMap, 0)
        ContrastStatsCE.probe.optodes_registered = optodeMap;
    end

    % Process each significance level
    for si = 1:length(params.significance)
        s = params.significance{si};
        ContrastStatsCE.draw('tstat', [-8 8], [s, '<0.05']);

        if getParamOrDefault(params, 'saveHbo', false)
            saveContrastFigure('hbo', figureFormat, params, conditionMap, ...
                               groupStats, contrast, s, customName);
        end
        if getParamOrDefault(params, 'saveHbr', false)
            saveContrastFigure('hbr', figureFormat, params, conditionMap, ...
                               groupStats, contrast, s, customName);
        end
        if getParamOrDefault(params, 'saveCoeff', false)
            saveContrastTable(ContrastStatsTable, contrast, params, ...
                              conditionMap, groupStats, customName);
        end

        closePlotFigures();
    end
end

function closePlotFigures()
    figHandles = findall(0, 'Type', 'figure');
    for fi = 1:length(figHandles)
        close(figHandles(fi));
    end
end

%% ========================================================================
%  File saving functions
%  ========================================================================
function saveContrastTable(ContrastStatsTable, contrast, params, conditionMap, groupStats, customName)
    if ~isempty(customName)
        CST_name = customName;
    else
        CST_name = buildContrastName(contrast, groupStats, conditionMap);
    end

    outputDir    = getParamOrDefault(params, 'output_dir', '');
    outputPrefix = getParamOrDefault(params, 'output_prefix', '');
    if ~isempty(outputPrefix)
        outputPrefix = [outputPrefix, '_'];
    end

    safeName   = truncateFilename(CST_name, 180);
    outputPath = fullfile(outputDir, [outputPrefix, safeName, '.csv']);

    try
        writetable(ContrastStatsTable, outputPath);
        disp(['Saved contrast table to: ', outputPath]);
    catch ME
        warning('fNIRS_ControlPanel:SaveFailed', ...
                'Failed to save contrast table: %s\nPath: %s', ME.message, outputPath);
    end
end

function saveContrastFigure(type, extension, params, conditionMap, groupStats, contrast, sigType, customName)
    figHandles = findall(0, 'Type', 'figure');

    for fi = 1:length(figHandles)
        originName = figHandles(fi).Name;
        fragments  = split(originName, {' ', '+', '-'});

        % Skip figures that don't match the expected type prefix
        if isempty(fragments) || ~strcmp(type, fragments{1})
            continue
        end

        % Build base filename
        if ~isempty(customName)
            baseName = [type, '_', customName, '_', sigType];
        else
            mappedName = applyConditionMapping(originName, conditionMap);
            baseName   = [replace(mappedName, ' : ', '_'), '_', sigType];
            baseName   = replace(baseName, ':', '_');
        end

        outputDir    = getParamOrDefault(params, 'output_dir', '');
        outputPrefix = getParamOrDefault(params, 'output_prefix', '');
        if ~isempty(outputPrefix)
            baseName = [outputPrefix, '_', baseName];
        end

        baseName   = sanitizeFilename(baseName);
        baseName   = truncateFilename(baseName, 180 - length(extension));
        outputPath = fullfile(outputDir, [baseName, '.', extension]);

        % Handle Windows path length limit
        if ispc && length(outputPath) > 240
            outputPath = shortenPath(outputPath, extension, outputDir);
        end

        try
            saveas(figHandles(fi), outputPath);
            disp(['Saved figure to: ', outputPath]);
        catch ME
            % Fallback: timestamp-based name
            timestamp    = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            fallbackPath = fullfile(outputDir, sprintf('fig_%s_%d_%s.%s', ...
                                    type, fi, timestamp, extension));
            try
                saveas(figHandles(fi), fallbackPath);
                disp(['Saved figure with fallback name to: ', fallbackPath]);
            catch ME2
                warning('fNIRS_ControlPanel:SaveFailed', ...
                        'Failed to save figure: %s', ME2.message);
            end
        end
    end
end

function name = buildContrastName(contrast, groupStats, conditionMap)
    name = '';
    for cs = 1:length(groupStats.conditions)
        condName = groupStats.conditions{cs};

        if isKey(conditionMap, condName)
            temp = conditionMap(condName);
            if iscell(temp)
                mappedName = temp{1};
            else
                mappedName = temp;
            end
        else
            mappedName = condName;
        end

        switch contrast(cs)
            case  1, name = [name, '+', mappedName]; %#ok<AGROW>
            case -1, name = [name, '-', mappedName]; %#ok<AGROW>
        end
    end

    if isempty(name)
        name = 'contrast';
    end

    name = sanitizeFilename(name);
end

function mappedName = applyConditionMapping(originName, conditionMap)
    mappedName = originName;
    fragments  = split(originName, {' ', '+', '-'});

    for frag = 3:length(fragments)
        if isKey(conditionMap, fragments{frag})
            mapped = conditionMap(fragments{frag});
            if iscell(mapped)
                mappedName = replace(mappedName, fragments{frag}, mapped{1});
            else
                mappedName = replace(mappedName, fragments{frag}, mapped);
            end
        end
    end
end

%% ========================================================================
%  Filename utilities
%  ========================================================================
function safeName = sanitizeFilename(name)
    safeName = regexprep(name, '[/\\:*?"<>|]', '_');
    safeName = regexprep(safeName, '[\s]+',    '_');  % whitespace → underscore
    safeName = regexprep(safeName, '_+',       '_');  % collapse multiple underscores
    safeName = regexprep(safeName, '^_|_$',    '');   % trim leading/trailing underscores
    if ~isempty(safeName) && safeName(1) == '.'
        safeName = ['_', safeName];                   % prevent hidden files on Unix
    end
end

function truncatedName = truncateFilename(name, maxLength)
    if length(name) <= maxLength
        truncatedName = name;
        return;
    end

    hashVal  = mod(sum(double(name) .* (1:length(name))), 99999);
    hashStr  = sprintf('%05d', hashVal);
    available = maxLength - length(hashStr) - 1;  % -1 for separator underscore

    if available > 10
        truncatedName = [name(1:available), '_', hashStr];
    else
        truncatedName = ['contrast_', hashStr];
    end

    warning('fNIRS_ControlPanel:FilenameTruncated', ...
            'Filename truncated from %d to %d characters: %s', ...
            length(name), length(truncatedName), truncatedName);
end

function shortPath = shortenPath(fullPath, extension, outputDir)
    [~, name, ~] = fileparts(fullPath);
    hashVal   = mod(sum(double(name) .* (1:length(name))), 99999);
    shortName = sprintf('fig_%05d', hashVal);
    shortPath = fullfile(outputDir, [shortName, '.', extension]);
    warning('fNIRS_ControlPanel:PathShortened', ...
            'Path shortened due to Windows MAX_PATH limit: %s', shortPath);
end
