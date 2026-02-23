function fNIRS_ControlPanel(groupStats, optodeMap, varargin)
% fNIRS_ControlPanel - Creates a control panel for fNIRS data visualization
%
% Usage:
%   1. Interactive mode: 
%      fNIRS_ControlPanel(groupStats, optodeMap)
%      fNIRS_ControlPanel(groupStats, optodeMap, conditionMap)
%   
%   2. Automated mode:
%      fNIRS_ControlPanel(groupStats, optodeMap, 'auto', params)
%      fNIRS_ControlPanel(groupStats, optodeMap, conditionMap, 'auto', params)
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
%  Parse inputs using structured approach (like fNIRS_Process.m)
%  ========================================================================
[conditionMap, autoMode, params] = parseInputs(groupStats, varargin{:});

%% ========================================================================
%  Configuration
%  ========================================================================
% Cosmetic variables
coordY_multiplier = 40;
labelWidth = 200;
sliderWidth = 70;
figlengthlimit = 341;
figureFormat = getParamOrDefault(params, 'figFormat', 'svg');

% Internal figure variables
numConditions = length(groupStats.conditions);
cYm = coordY_multiplier;
baseY = cYm * (numConditions+1) - cYm*1.5;
conditionWidth = labelWidth + sliderWidth;

rightBaseY = max(baseY - cYm * (numConditions - 1) - 100, 300);
figLength = max((cYm * numConditions+1)+cYm/2, figlengthlimit);
figWidth  = conditionWidth * 2;

% State variables (will be modified by UI callbacks)
state = struct();
state.c = zeros(1, numConditions);
state.s = 'p';
state.userText = '';

%% ========================================================================
%  Auto mode: process and exit
%  ========================================================================
if autoMode
    validateAutoModeParams(params, numConditions);
    disp('Automated mode: Processing with provided contrasts');
    processContrastsAutomated(params, groupStats, optodeMap, conditionMap, figureFormat);
    return;
end

%% ========================================================================
%  Interactive mode: Build UI
%  ========================================================================
% Control Window Figure
fig = uifigure('Name', 'Condition Control Panel', ...
         'Position', [100, 100, figWidth, figLength]);

% Condition sliders (left panel)
lg = uibuttongroup(fig, 'Title', 'Individual Contrast Processing', ...
                   'Position', [0 1 conditionWidth+25 rightBaseY+cYm]);
for i = 1:numConditions
    uilabel(lg, ...
            'Position', [10, baseY - cYm * (i - 1), labelWidth, 20], ...
            'Text', groupStats.conditions{i});
    
    uislider(lg, ...
             'Position', [labelWidth + 20, baseY - cYm*(i - 1) + 10, sliderWidth, 3], ...
             'Limits', [-1, 1], 'Value', 0, ...
             'MajorTicks', [-1, 0, 1], ...
             'Tag', sprintf('slider%d', i), ...
             'ValueChangedFcn', @(sld, ~) sliderCallback(sld, i));
end

% Batch contrast matrix (right panel)
mg = uibuttongroup(fig, 'Title', 'Batch Contrast Processing', ...
     'Position', [300 rightBaseY-100 labelWidth 141]);
uitextarea(mg, 'Position', [0 20 labelWidth 100], ...
    'ValueChangedFcn', @(txt, ~) textAreaCallback(txt));
uibutton(mg, 'Text', 'Validate Contrasts', ...
    'Position', [0 0 labelWidth 20], ...
    'ButtonPushedFcn', @(~, ~) contrastreadCallback());

% Significance selector
bg = uibuttongroup(fig, 'Title', 'Significance', ...
    'Position', [300 rightBaseY-170 labelWidth 60]);
rb1 = uiradiobutton(bg, 'Text', 'p-gated', 'Position', [10 20 labelWidth 20]);
uiradiobutton(bg, 'Text', 'q-gated', 'Position', [10 0 labelWidth 20]);
bg.SelectedObject = rb1;
bg.SelectionChangedFcn = @(~, event) significanceChanged(event);

% Save output checkboxes
sg = uibuttongroup(fig, 'Title', 'Save output', ...
     'Position', [300 rightBaseY-220 labelWidth 40]);
cb1 = uicheckbox(sg, 'Text', 'hbo', 'Value', 1, 'Position', [10 0 labelWidth 20]);
cb2 = uicheckbox(sg, 'Text', 'hbr', 'Value', 0, 'Position', [70 0 labelWidth 20]);
cb3 = uicheckbox(sg, 'Text', 'coeff', 'Value', 1, 'Position', [130 0 labelWidth 20]);

% Visualization method selector
vg = uibuttongroup(fig, 'Title', 'Visualization', ...
     'Position', [300 rightBaseY-260 labelWidth 40]);
vb1 = uidropdown(vg, 'Items', {'10-20 map', '3d mesh'}, ...   
      'Position', [0 0 labelWidth 20]);

% Process button
uibutton(fig, 'Text', 'Process', ...
         'Position', [300, 10, labelWidth, 20], ...
         'Tag', 'processButton', ...
         'ButtonPushedFcn', @(~, ~) processCallback());

%% ========================================================================
%  Nested callback functions (access state via closure)
%  ========================================================================
function sliderCallback(src, index)
    state.c(index) = round(get(src, 'Value'));
end

function significanceChanged(event)
    state.s = event.NewValue.Text(1);
end

function textAreaCallback(txt)
    state.userText = txt.Value;
    if isempty(state.userText)
        state.c = zeros(1, numConditions);
    end
end

function contrastreadCallback()
    state.c = parseContrastText(state.userText, numConditions);
    for line = 1:size(state.c, 1)
        disp(state.c(line, :));
    end
end

function processCallback()
    disp('Creating plots with contrasts:');
    disp(state.c);
    
    % Build params from UI state
    uiParams = struct();
    uiParams.significance = {state.s};
    uiParams.saveHbo = cb1.Value == 1;
    uiParams.saveHbr = cb2.Value == 1;
    uiParams.saveCoeff = cb3.Value == 1;
    uiParams.visMethod = vb1.Value;
    
    processContrast(state.c, false, uiParams, groupStats, optodeMap, ...
                    conditionMap, figureFormat, []);
end

end % End of main function

%% ========================================================================
%  Input Parsing (like fNIRS_Process.m approach)
%  ========================================================================
function [conditionMap, autoMode, params] = parseInputs(groupStats, varargin)
    % Defaults
    conditionMap = [];
    autoMode = false;
    params = struct();
    
    if isempty(varargin)
        % No additional args - use defaults
    elseif ischar(varargin{1}) && strcmpi(varargin{1}, 'auto')
        % Pattern: (groupStats, optodeMap, 'auto', params)
        autoMode = true;
        if length(varargin) >= 2
            params = varargin{2};
        else
            error('fNIRS_ControlPanel:MissingParams', ...
                  'When using auto mode, params struct must be provided');
        end
    else
        % Pattern: (groupStats, optodeMap, conditionMap, ...)
        conditionMap = varargin{1};
        
        if length(varargin) >= 2 && ischar(varargin{2}) && strcmpi(varargin{2}, 'auto')
            % Pattern: (groupStats, optodeMap, conditionMap, 'auto', params)
            autoMode = true;
            if length(varargin) >= 3
                params = varargin{3};
            else
                error('fNIRS_ControlPanel:MissingParams', ...
                      'When using auto mode, params struct must be provided');
            end
        end
    end
    
    % Create default conditionMap if not provided
    if isempty(conditionMap)
        conditionMap = containers.Map();
        for i = 1:length(groupStats.conditions)
            conditionMap(groupStats.conditions{i}) = {groupStats.conditions{i}};
        end
    end
end

function validateAutoModeParams(params, numConditions)
    if ~isfield(params, 'contrasts')
        error('fNIRS_ControlPanel:MissingContrasts', ...
              'In automated mode, params.contrasts must be provided');
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
    
    % Validate contrastNames if provided
    if isfield(params, 'contrastNames')
        if ~iscell(params.contrastNames)
            error('fNIRS_ControlPanel:InvalidContrastNames', ...
                  'params.contrastNames must be a cell array of strings');
        end
    end
    
    % Set defaults for missing fields
    if ~isfield(params, 'significance')
        params.significance = {'p'};
    elseif ~iscell(params.significance)
        params.significance = {params.significance};
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
%  Contrast text parsing
%  ========================================================================
function c = parseContrastText(userText, numConditions)
    c = zeros(1, numConditions);
    if isempty(userText)
        return;
    end
    
    for line = 1:length(userText)
        curstr = split(userText{line}, ' ');
        index = 1;
        for digit = 1:length(curstr)
            if ~isempty(curstr{digit})
                converted = str2double(curstr{digit});
                if ismember(converted, [-1, 0, 1])
                    c(line, index) = converted;
                    index = index + 1;
                else
                    disp('Error: Please revise contrasts. Values must be -1, 0, or 1.');
                    return;
                end
            end
        end
    end
end

%% ========================================================================
%  Automated batch processing
%  ========================================================================
function processContrastsAutomated(params, groupStats, optodeMap, conditionMap, figureFormat)
    c = params.contrasts;
    contrastNames = getParamOrDefault(params, 'contrastNames', {});
    
    % Ensure significance is a cell array
    if ~isfield(params, 'significance') || isempty(params.significance)
        params.significance = {'p'};
    elseif ~iscell(params.significance)
        params.significance = {params.significance};
    end
    
    if iscell(c)
        % Cell array of contrasts
        for i = 1:length(c)
            customName = getContrastName(contrastNames, i);
            disp(['Processing contrast ' num2str(i) ': ' customName]);
            disp(c{i});
            processContrast(c{i}, true, params, groupStats, optodeMap, ...
                            conditionMap, figureFormat, customName);
        end
    else
        % Matrix of contrasts
        if size(c, 1) > 1
            for i = 1:size(c, 1)
                customName = getContrastName(contrastNames, i);
                disp(['Processing contrast ' num2str(i) ': ' customName]);
                disp(c(i, :));
                processContrast(c(i, :), true, params, groupStats, optodeMap, ...
                                conditionMap, figureFormat, customName);
            end
        else
            customName = getContrastName(contrastNames, 1);
            disp(['Processing contrast: ' customName]);
            disp(c);
            processContrast(c, true, params, groupStats, optodeMap, ...
                            conditionMap, figureFormat, customName);
        end
    end
end

function name = getContrastName(contrastNames, index)
    % Returns custom name if available, otherwise empty string for auto-generation
    if ~isempty(contrastNames) && index <= length(contrastNames) && ~isempty(contrastNames{index})
        name = sanitizeFilename(contrastNames{index});
    else
        name = '';
    end
end

%% ========================================================================
%  Core processing function
%  ========================================================================
function processContrast(contrast, autoClose, params, groupStats, optodeMap, ...
                         conditionMap, figureFormat, customName)
    
    % Calculate statistics
    ContrastStatsCE = groupStats.ttest(contrast);
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
    for sign = 1:length(params.significance)
        s = params.significance{sign};
        ContrastStatsCE.draw('tstat', [-8 8], [s, '<0.05']);
        
        % Save outputs
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
        
        % Close figures if auto mode
        if autoClose
            closePlotFigures();
        end
    end
end

function closePlotFigures()
    figHandles = findall(0, 'Type', 'figure');
    for figcount = 1:length(figHandles)
        originName = figHandles(figcount).Name;
        if ~strcmp(originName, 'Condition Control Panel')
            pause(0.5);
            close(figHandles(figcount));
        end
    end
end

%% ========================================================================
%  File saving functions
%  ========================================================================
function saveContrastTable(ContrastStatsTable, contrast, params, conditionMap, groupStats, customName)
    % Determine output name
    if ~isempty(customName)
        CST_name = customName;
    else
        CST_name = buildContrastName(contrast, groupStats, conditionMap);
    end
    
    % Build output path
    outputDir = getParamOrDefault(params, 'output_dir', '');
    outputPrefix = getParamOrDefault(params, 'output_prefix', '');
    if ~isempty(outputPrefix)
        outputPrefix = [outputPrefix, '_'];
    end
    
    % Ensure filename isn't too long (max 200 chars for safety)
    safeName = truncateFilename(CST_name, 180);
    
    outputPath = fullfile(outputDir, [outputPrefix, safeName, '.csv']);
    
    try
        writetable(ContrastStatsTable, outputPath);
        disp(['Saved contrast to: ', outputPath]);
    catch ME
        warning('Failed to save contrast table:');
        disp(['NOT saved: ', outputPath]);
    end
end

function saveContrastFigure(type, extension, params, conditionMap, groupStats, contrast, sigType, customName)
    figHandles = findall(0, 'Type', 'figure');
    
    for figcount = 1:length(figHandles)
        originName = figHandles(figcount).Name;
        
        % Skip if not the right type or if it's the control panel
        fragments = split(originName, {' ', '+', '-'});
        if isempty(fragments) || ~strcmp(type, fragments{1}) || ...
           strcmp(originName, 'Condition Control Panel')
            continue
        end
        
        % Build output filename
        if ~isempty(customName)
            baseName = [type, '_', customName, '_', sigType];
        else
            % Apply condition mapping to figure name
            mappedName = applyConditionMapping(originName, conditionMap);
            baseName = [replace(mappedName, ' : ', '_'), '_', sigType];
            baseName = replace(baseName, ':', '_');
        end
        
        % Get output directory and prefix
        outputDir = getParamOrDefault(params, 'output_dir', '');
        outputPrefix = getParamOrDefault(params, 'output_prefix', '');
        if ~isempty(outputPrefix)
            baseName = [outputPrefix, '_', baseName];
        end
        
        % Sanitize and truncate filename
        baseName = sanitizeFilename(baseName);
        baseName = truncateFilename(baseName, 180 - length(extension));
        
        outputPath = fullfile(outputDir, [baseName, '.', extension]);
        
        % Handle path length issues on Windows
        if ispc && length(outputPath) > 240
            outputPath = shortenPath(outputPath, extension, outputDir);
        end
        
        try
            saveas(figHandles(figcount), outputPath);
            disp(['Saved figure to: ', outputPath]);
        catch ME
            % Fallback: use timestamp-based name
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            fallbackPath = fullfile(outputDir, sprintf('fig_%s_%d_%s.%s', ...
                                    type, figcount, timestamp, extension));
            try
                saveas(figHandles(figcount), fallbackPath);
                disp(['Saved figure with fallback name to: ', fallbackPath]);
            catch
                warning('Failed to save figure');
            end
        end
    end
end

function name = buildContrastName(contrast, groupStats, conditionMap)
    % Build name from contrast coefficients (original behavior as fallback)
    name = '';
    for cs = 1:length(groupStats.conditions)
        condName = groupStats.conditions{cs};
        
        % Get mapped name if available
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
            case 1
                name = [name, '+', mappedName]; %#ok<AGROW>
            case -1
                name = [name, '-', mappedName]; %#ok<AGROW>
        end
    end
    
    if isempty(name)
        name = 'contrast';
    end
    
    name = sanitizeFilename(name);
end

function mappedName = applyConditionMapping(originName, conditionMap)
    mappedName = originName;
    fragments = split(originName, {' ', '+', '-'});
    
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
    % Remove or replace invalid filename characters
    % Invalid: / \ : * ? " < > |
    safeName = regexprep(name, '[/\\:*?"<>|]', '_');
    
    % Also handle other problematic characters
    safeName = regexprep(safeName, '[\s]+', '_');  % whitespace to underscore
    safeName = regexprep(safeName, '_+', '_');     % collapse multiple underscores
    safeName = regexprep(safeName, '^_|_$', '');   % trim leading/trailing underscores
    
    % Ensure it doesn't start with a dot (hidden file on Unix)
    if ~isempty(safeName) && safeName(1) == '.'
        safeName = ['_', safeName];
    end
end

function truncatedName = truncateFilename(name, maxLength)
    if length(name) <= maxLength
        truncatedName = name;
        return;
    end
    
    % Create a short hash for uniqueness
    hashVal = mod(sum(double(name) .* (1:length(name))), 99999);
    hashStr = sprintf('%05d', hashVal);
    
    % Truncate and append hash
    availableLength = maxLength - length(hashStr) - 1;  % -1 for underscore
    if availableLength > 10
        truncatedName = [name(1:availableLength), '_', hashStr];
    else
        truncatedName = ['contrast_', hashStr];
    end
    
    warning('Filename truncated from %d to %d characters: %s', ...
            length(name), length(truncatedName), truncatedName);
end

function shortPath = shortenPath(fullPath, extension, outputDir)
    % For Windows path length issues
    [~, name, ~] = fileparts(fullPath);
    
    hashVal = mod(sum(double(name) .* (1:length(name))), 99999);
    shortName = sprintf('fig_%05d', hashVal);
    
    shortPath = fullfile(outputDir, [shortName, '.', extension]);
    warning('Path shortened due to Windows limitations');
end
