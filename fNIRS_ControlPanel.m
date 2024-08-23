function fNIRS_ControlPanel(groupStats, optodeMap, conditionMap)
% Cosmetic variables ______________________________________________________
coordY_multiplier = 40;
labelWidth = 200;
sliderWidth = 70;
figlengthlimit = 341;
figureFormat = 'svg';
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
    ContrastStatsCE = groupStats.ttest(c);
    ContrastStatsTable = ContrastStatsCE.table;
    ContrastStatsCE.probe.defaultdrawfcn=vb1.Value;
    ContrastStatsCE.probe.optodes_registered = optodeMap;
    ContrastStatsCE.draw('tstat',[-8 8], [s,'<0.05']);

    % Save statistics table(s), figure(s)
    if cb1.Value == 1
        saveContrastFigure('hbo',figureFormat)
    end
    if cb2.Value == 1
        saveContrastFigure('hbr',figureFormat)
    end
    if cb3.Value == 1
        saveContrastTable(ContrastStatsTable);
    end
end

% Defining alpha treshold
function significanceChanged(event)
    s = event.NewValue.Text(1);
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

function saveContrastTable(ContrastStatsTable)
    CST_name = '';
    for cs=1:length(groupStats.conditions)
        switch c(cs)
            case 1
                temp = conditionMap(groupStats.conditions{cs});
                CST_name = [CST_name,'+',temp{1}];
            case -1
                    temp = conditionMap(groupStats.conditions{cs});
                CST_name = [CST_name,'-',temp{1}];
            otherwise
        end
    end
    writetable(ContrastStatsTable, [CST_name,'.csv'])
end

function saveContrastFigure(type,extension)
        figHandles = findall(0, 'Type', 'figure');
        for figcount = 1:length(figHandles)
            originName = figHandles(figcount).Name;
            fragments = split(originName, {' ','+', '-'});
            cpn = 'Condition Control Panel';
            if ~strcmp(type, fragments{1}) || strcmp(originName, cpn)
                continue
            end
            
            for frag=3:length(fragments)
                if isKey(conditionMap,fragments{frag})
                    originName = replace(originName,fragments{frag},...
                                         conditionMap(fragments{frag}));
                end
            end
            customName = [replace(originName,' : ','_'),'_',s,'.',...
                          extension];
            customName = replace(customName,':','_');
            saveas(figHandles(figcount), customName);
        end
    end
% _________________________________________________________________________
end