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
%      where params is a struct with fields:
%         - contrasts: matrix of contrasts or cell array of contrast vectors
%         - significance: 'p' or 'q' for significance gating
%         - saveHbo: true/false
%         - saveHbr: true/false
%         - saveCoeff: true/false
%         - visMethod: '10-20 map' or '3d mesh'
%         - figFormat: 'svg', 'png', etc.

% Parse variable input arguments and determine mode
conditionMap = [];
autoMode = false;
params = struct();

% Check if conditionMap is provided
if nargin >= 3
    if ischar(varargin{1}) && strcmpi(varargin{1}, 'auto')
        % No conditionMap, but auto mode
        autoMode = true;
        if nargin >= 4
            params = varargin{2};
        else
            error('When using auto mode, params struct must be provided');
        end
    else
        % conditionMap is provided
        conditionMap = varargin{1};
        
        % Check if also in auto mode
        if nargin >= 4 && ischar(varargin{2}) && strcmpi(varargin{2}, 'auto')
            autoMode = true;
            if nargin >= 5
                params = varargin{3};
            else
                error('When using auto mode, params struct must be provided');
            end
        end
    end
end

% Create default conditionMap if not provided
if isempty(conditionMap)
    % Create default conditionMap that just returns the original condition names
    conditionMap = containers.Map();
    for i = 1:length(groupStats.conditions)
        conditionMap(groupStats.conditions{i}) = {groupStats.conditions{i}};
    end
end

% Cosmetic variables ______________________________________________________
coordY_multiplier = 40;
labelWidth = 200;
sliderWidth = 70;
figlengthlimit = 341;
figureFormat = 'svg';

if isfield(params, 'figFormat')
    figureFormat = params.figFormat;
end
% _________________________________________________________________________

% Internal figure variables _______________________________________________
numConditions = length(groupStats.conditions);
c = zeros(1,numConditions);
s = 'p';
userText = '';
cYm = coordY_multiplier;
baseY = cYm * (numConditions+1) - cYm*1.5;
conditionWidth = labelWidth+sliderWidth;

rightBaseY = max(baseY - cYm * (numConditions - 1) - 100, 300);
figLength = max((cYm * numConditions+1)+cYm/2,figlengthlimit);
figWidth  = conditionWidth*2;
% _________________________________________________________________________

% Setup autoMode parameters if provided
if autoMode
    % Set contrast values
    if isfield(params, 'contrasts')
        % Store the contrasts in the proper format for automated processing
        % This will be processed in processContrastsAutomated()
        c = params.contrasts;
        
        % Validate contrasts
        if iscell(c)
            % Cell array - check each contrast vector
            for i = 1:length(c)
                if length(c{i}) ~= numConditions
                    error('Contrast %d has %d elements but should have %d to match conditions', ...
                          i, length(c{i}), numConditions);
                end
            end
        else
            % Matrix or vector - check dimensions
            if size(c, 2) ~= numConditions
                error('Contrast matrix has %d columns but should have %d to match conditions', ...
                      size(c, 2), numConditions);
            end
        end
        
        disp('Automated mode: Processing with provided contrasts');
    else
        error('In automated mode, params.contrasts must be provided');
    end
    
    % Set significance gating
    if ~isfield(params, 'significance')
        params.significance = {'p'}; % Take first character (p or q)
    end
    
    % Set visualization method
    if isfield(params, 'visMethod')
        visMethod = params.visMethod;
    else
        visMethod = '10-20 map';
    end
    
    % Auto-process immediately
    processContrastsAutomated();
    return; % Exit function after automated processing
end

% Control Window Figure ___________________________________________________
fig = uifigure('Name', 'Condition Control Panel', ...
         'Position', [100, 100, figWidth, figLength]);
% _________________________________________________________________________

% Condition definition ____________________________________________________
%-- Condition / silder pair (solo-contrast)
lg = uibuttongroup(fig,'Title','Individual Contrast Processing',...
                   'Position',[0 1 conditionWidth+25 rightBaseY+cYm]);
for i = 1:numConditions
    % Create label for each condition
    uilabel(lg, ...
            'Position', [10, baseY - cYm * (i - 1), labelWidth, 20],...
            'Text', groupStats.conditions{i});
    
    % Create slider for each condition
    uislider(lg, ...
             'Position',[labelWidth + 20, baseY - cYm*(i - 1) + 10, ...
                         sliderWidth, 3], ...
             'Limits', [-1, 1], 'Value', 0, ...
             'MajorTicks', [-1, 0, 1], ...
             'Tag', sprintf('slider%d', i), ...
             'ValueChangedFcn', @(sld,event) sliderCallback(sld, i));
end
%-- Batch contrast matrix definer (poly-contrast)
mg = uibuttongroup(fig,'Title','Batch Contrast Processing',...
     'Position',[300 rightBaseY-100 labelWidth 141]);
uitextarea(mg, 'Position', [0 20 labelWidth 100], ...
    'ValueChangedFcn', @(txt,event) textAreaCallback(txt));
uibutton(mg,'Text','Validate Contrasts', ...
    'Position', [0 0 labelWidth 20],...
    'ButtonPushedFcn',@(btn,event)contrastreadCallback(numConditions));
% _________________________________________________________________________

% Display and storage _____________________________________________________
%-- Significance selector
bg = uibuttongroup(fig,'Title','Significance',...
    'Position',[300 rightBaseY-170 labelWidth 60]);
rb1 = uiradiobutton(bg,'Text','p-gated',...
    'Position',[10 20 labelWidth 20]);
rb2 = uiradiobutton(bg,'Text','q-gated',...
    'Position',[10 0 labelWidth 20]);
bg.SelectedObject = rb1;
bg.SelectionChangedFcn = @(bg,event) significanceChanged(event);

%-- Saved output selector
sg = uibuttongroup(fig,'Title','Save output',...
     'Position',[300 rightBaseY-220 labelWidth 40]);
cb1 = uicheckbox(sg,'Text','hbo','Value',1,...
      'Position',[10 0 labelWidth 20]);
cb2 = uicheckbox(sg,'Text','hbr','Value',0,...
      'Position',[70 0 labelWidth 20]);
cb3 = uicheckbox(sg,'Text','coeff','Value',1,...
      'Position',[130 0 labelWidth 20]);

%-- Visualization method selector
vg = uibuttongroup(fig,'Title','Visualization',...
     'Position',[300 rightBaseY-260 labelWidth 40]);
vb1 = uidropdown(vg,"Items",{'10-20 map','3d mesh'},...   
      'Position',[0 0 labelWidth 20]);

%-- Process button
uibutton(fig, 'Text', 'Process', ...
         'Position', [300, 10, labelWidth, 20], ...
         'Tag', 'processButton',...
         'ButtonPushedFcn', @(btn,event) processCallback());
% _________________________________________________________________________

% Contrast Example #1
% -1  0  0  0  0  0  1  0
%  0 -1  0  0  0  0  0  1
% -1  1 -1  1 -1  1 -1  1
% -1  1  0  0  0  0 -1  1
% -1  1  0  0 -1  1 -1  1
%  0  0 -1  1 -1  1 -1  1

% Contrast Example #2
% -1  1  0  0  0  0  1 -1
%  0  0 -1  1  0  0  1 -1
% -1  1 -1  1  0  0  1 -1
% -1  1  0  0  1 -1  0  0
%  0  0 -1  1  1 -1  0  0
% -1  1 -1  1  1 -1  0  0
%  0  0  0  0 -1  1  1 -1

% Auxilliary functions ____________________________________________________
% Manual contrast definition
function sliderCallback(src, index)
    newValue = round(get(src, 'Value'));
    c(index) = newValue;
end

% Generate graphs
function processCallback()
    % Display contrasts for visual confirmation / validation
    disp('Creating plots with contrasts:')
    disp(c)
    
    % Calculate statistics and create table(s), figure(s)
    processContrast(c, false);
end

% Automated processing function for both interactive and auto modes
function processContrast(contrast, autoClose)
    if ~exist('autoClose', 'var')
        autoClose = false;
    end
    
    % Calculate statistics and create table(s), figure(s)
    ContrastStatsCE = groupStats.ttest(contrast);
    ContrastStatsTable = ContrastStatsCE.table;
    
    % Use the visualization method
    if autoMode && isfield(params, 'visMethod')
        ContrastStatsCE.probe.defaultdrawfcn = params.visMethod;
    else
        ContrastStatsCE.probe.defaultdrawfcn = vb1.Value;
    end
    
    if optodeMap ~= 0
        ContrastStatsCE.probe.optodes_registered = optodeMap;
    end
    if ~autoMode
        params.significance = s;
    end
    for sign = 1:length(params.significance)
        s = params.significance{sign};
        ContrastStatsCE.draw('tstat',[-8 8], [s,'<0.05']);

        % Save statistics table(s), figure(s)
        if autoMode
            % Use params for saving choices
            if isfield(params, 'saveHbo') && params.saveHbo
                saveContrastFigure('hbo', figureFormat);
            end
            if isfield(params, 'saveHbr') && params.saveHbr
                saveContrastFigure('hbr', figureFormat);
            end
            if isfield(params, 'saveCoeff') && params.saveCoeff
                saveContrastTable(ContrastStatsTable, contrast);
            end
        else
            % Use UI checkboxes for saving choices
            if cb1.Value == 1
                saveContrastFigure('hbo', figureFormat);
            end
            if cb2.Value == 1
                saveContrastFigure('hbr', figureFormat);
            end
            if cb3.Value == 1
                saveContrastTable(ContrastStatsTable, contrast);
            end
        end
        
        % Close figures if in auto mode
        if autoClose
            figHandles = findall(0, 'Type', 'figure');
            for figcount = 1:length(figHandles)
                originName = figHandles(figcount).Name;
                if ~strcmp(originName, 'Condition Control Panel')
                    pause(0.5); % Give a brief pause to ensure saving completes
                    close(figHandles(figcount));
                end
            end
        end
    end
end

% Automated processing for handling multiple contrasts if provided
function processContrastsAutomated()
    if iscell(c)
        % Process each contrast separately
        for i = 1:length(c)
            disp(['Processing contrast ' num2str(i) ':']);
            disp(c{i});
            processContrast(c{i}, true);
        end
    else
        % Process single contrast matrix
        if size(c, 1) > 1
            % Multiple rows - process each row as a separate contrast
            for i = 1:size(c, 1)
                disp(['Processing contrast ' num2str(i) ':']);
                disp(c(i,:));
                processContrast(c(i,:), true);
            end
        else
            % Single row - process as one contrast
            disp('Processing contrast:');
            disp(c);
            processContrast(c, true);
        end
    end
end

% Defining alpha treshold
function significanceChanged(event)
    s = {event.NewValue.Text(1)};
end

% Storing user defined contrast matrix, resetting matrix if empty 
function textAreaCallback(txt)
    userText = txt.Value;
    if isempty(userText)
        c = zeros(1,numConditions);
    end
end

% BODGY, REFRACTOR WHEN POSSIBLE
function contrastreadCallback(numConditions)
    c = zeros(1,numConditions);
    str = userText;
    for line=1:length(str)
        curstr = split(str{line},' ');
        index = 1;
        for digit=1:length(curstr)
            if ~isempty(curstr{digit})
                converted = str2double(curstr{digit});
                if ismember(converted, [-1, 0, 1])
                    c(line,index) = converted;
                    index = index + 1;
                else
                    disp('Error: Please revise contrasts.')
                end
            end
        end
    end
    for line=1:size(c,1)
        disp(c(line,:))
    end
end

function saveContrastTable(ContrastStatsTable, currentContrast)
    % If currentContrast is not provided, use the global c
    if ~exist('currentContrast', 'var')
        currentContrast = c;
    end
    
    CST_name = '';
    for cs=1:length(groupStats.conditions)
        switch currentContrast(cs)
            case 1
                if isKey(conditionMap, groupStats.conditions{cs})
                    temp = conditionMap(groupStats.conditions{cs});
                    if iscell(temp)
                        CST_name = [CST_name,'+',temp{1}];
                    else
                        CST_name = [CST_name,'+',temp];
                    end
                else
                    CST_name = [CST_name,'+',groupStats.conditions{cs}];
                end
            case -1
                if isKey(conditionMap, groupStats.conditions{cs})
                    temp = conditionMap(groupStats.conditions{cs});
                    if iscell(temp)
                        CST_name = [CST_name,'-',temp{1}];
                    else
                        CST_name = [CST_name,'-',temp];
                    end
                else
                    CST_name = [CST_name,'-',groupStats.conditions{cs}];
                end
            otherwise
                % Do nothing for zero coefficients
        end
    end
    
    if isempty(CST_name)
        CST_name = 'contrast'; % Default name if no non-zero coefficients
    end
    if isfield(params, 'output_dir')
        od = params.output_dir;
    else
        od = '';
    end
    if isfield(params, 'output_prefix')
        op = [params.output_prefix, '_'];
    else
        op = '';
    end
    writetable(ContrastStatsTable, [od filesep op CST_name,'.csv'])
    disp(['Saved contrast to:', od filesep op CST_name,'.csv.'])
end

    function saveContrastFigure(type, extension)
    figHandles = findall(0, 'Type', 'figure');
    for figcount = 1:length(figHandles)
        originName = figHandles(figcount).Name;
        fragments = split(originName, {' ','+', '-'});
        cpn = 'Condition Control Panel';
        if ~strcmp(type, fragments{1}) || strcmp(originName, cpn)
            continue
        end
        
        % Try to replace condition names with their mapped versions
        for frag=3:length(fragments)
            if isKey(conditionMap, fragments{frag})
                mapped = conditionMap(fragments{frag});
                if iscell(mapped)
                    originName = replace(originName, fragments{frag}, mapped{1});
                else
                    originName = replace(originName, fragments{frag}, mapped);
                end
            end
        end
        
        if isfield(params, 'output_dir')
            od = params.output_dir;
        else
            od = '';
        end
        if isfield(params, 'output_prefix')
            op = [params.output_prefix, '_'];
        else
            op = '';
        end
        
        % Create initial filename
        baseFileName = [op replace(originName,' : ','_'),'_',s];
        baseFileName = replace(baseFileName,':','_');
        
        % Filename length protection
        maxFileNameLength = 200; % Safe limit for most filesystems
        maxPathLength = 240;     % Safe limit for Windows full paths
        
        % Check filename length (without extension)
        if length(baseFileName) > maxFileNameLength - length(extension) - 1
            % Create a hash of the original name for uniqueness
            originalHash = string(java.lang.String(baseFileName).hashCode());
            originalHash = replace(originalHash, '-', 'n'); % Replace negative sign
            
            % Truncate and add hash
            maxBaseLength = maxFileNameLength - length(extension) - length(originalHash) - 2; % -2 for underscore and dot
            if maxBaseLength > 20
                truncatedName = baseFileName(1:maxBaseLength);
                baseFileName = [truncatedName '_' char(originalHash)];
            else
                % If even truncated name would be too long, use only hash-based name
                baseFileName = ['fig_' type '_' originalHash];
            end
            
            warning(['Filename was too long and has been shortened:', baseFileName]);
        end
        
        % Construct full path
        customName = fullfile(od, [baseFileName, '.', extension]);
        
        % Check total path length (important for Windows)
        if ispc && length(customName) > maxPathLength
            % Further shorten the filename
            [pathStr, name, ext] = fileparts(customName);
            availableLength = maxPathLength - length(pathStr) - length(ext) - 1; % -1 for path separator
            
            if availableLength > 10
                % Create a very short name with hash
                shortHash = string(java.lang.String(name).hashCode());
                shortHash = replace(shortHash, '-', 'n');
                shortName = ['fig_' shortHash(1:min(6, length(shortHash)))];
                customName = fullfile(pathStr, [shortName, ext]);
            else
                error('Output directory path is too long to create any filename');
            end
            
            warning('Full path was too long and filename has been further shortened');
        end
        
        try
            saveas(figHandles(figcount), customName);
            disp(['Saved figure to: ', customName]);
        catch ME
            if contains(ME.message, 'Invalid filename') || contains(ME.message, 'name too long')
                % Final fallback: use figure number and timestamp
                timestamp = datestr(now, 'yyyymmdd_HHMMSS');
                fallbackName = fullfile(od, sprintf('fig_%s_%d_%s.%s', type, figcount, timestamp, extension));
                saveas(figHandles(figcount), fallbackName);
                disp(['Saved figure with fallback name to: ', fallbackName]);
                warning('Used fallback filename due to filesystem limitations');
            else
                rethrow(ME);
            end
        end
    end
end
% _________________________________________________________________________
end