global fileList fileIndex fig
global params groups output
params = struct();
groups = struct();
output = struct();

%% Main UI window
%-- Parameters
params.figWidth  = 600;
params.figHeight = 900;
params.pad       = 2;
% _________________________________________________________________________
%-- Create the main UI figure
inhHeight = params.figHeight;
fig = uifigure('Name', 'fNIRS Cleaner', ...
         'Position', [100, 100, params.figWidth, params.figHeight]);

%% Load file group
%-- Parameters
params.lfgHeight = 70;
params.lfg_buttonSize1 = [50 20];
params.lfg_buttonSize2 = [544 20];
params.lfg_buttonSize3 = [30 20];
% _________________________________________________________________________
%-- Group creation
lfgWidth  = params.figWidth;
inhHeight = inhHeight - params.lfgHeight;
groups.lfgGroup = uibuttongroup(fig,'Title','Current directory',...
                       'Position',[0 inhHeight lfgWidth params.lfgHeight]);

%-- Display root directory
pos = [2*params.pad+params.lfg_buttonSize1(1) ...
           params.lfgHeight-(params.lfg_buttonSize1(2)+params.pad+20)...
           params.lfg_buttonSize2];
dirLabel = uilabel(groups.lfgGroup, 'Text', '', ...
    'BackgroundColor', 'white', 'Position', pos);

%-- Display current directory
ta = uitextarea(groups.lfgGroup,'Value','','BackgroundColor','white',...
    'Position',[0 0 1 1]);

%-- Open root directory
pos = [2*params.pad ...
       params.lfgHeight-(params.lfg_buttonSize1(2)+params.pad+20)...
       params.lfg_buttonSize1];
uibutton(groups.lfgGroup, 'Text', 'Open...', ...
    'Position', pos, ...
    'ButtonPushedFcn', @(btn,event)setRootDirectory(dirLabel,ta));

%-- Setting auto-loading flag
db = uicheckbox(groups.lfgGroup,'Text',['auto-',newline,'load'],...
                'Value',1,...
                'Position',[params.pad 5 50 20],'FontSize', 10);

%-- Current directory and movement keys
btn_labels = {'<<','<','>','>>','Load'};
btn_position = [params.lfg_buttonSize1(1)+params.pad 5];
for i=1:5
    if i == 5
    params.lfg_buttonSize3(1) = lfgWidth - btn_position(1) - params.pad;
    end
    uibutton(groups.lfgGroup,'Text',btn_labels{i},...
        'Position', [btn_position params.lfg_buttonSize3],...
        'ButtonPushedFcn',...
        @(btn,event)setCurrentDirectory(btn_labels{i},db.Value,ta));
    btn_position(1) = btn_position(1)+params.lfg_buttonSize3(1)+params.pad;
    
    if i == 2
    tex_position =[btn_position ...
        params.figWidth-2*(2*params.pad+btn_position(1)) 20];
    ta.Position = tex_position;
    btn_position(1) = btn_position(1) + tex_position(3) + params.pad;
    end
end

%% Overview Group
%-- Parameters
params.ovgHeight = 80;
% _________________________________________________________________________
%-- Group creation
inhHeight = inhHeight - params.ovgHeight;
groups.ovwGroup = uibuttongroup(fig,'Title','Overview',...
    'Position',[0 inhHeight params.figWidth params.ovgHeight]);

%% Notes Group
%-- Parameters
params.noteHeight = 60;
% _________________________________________________________________________
%-- Group creation
inhHeight = inhHeight - params.noteHeight;
groups.nteGroup = uibuttongroup(fig,'Title','Notes',...
    'Position',[0 inhHeight params.figWidth params.noteHeight]);

%% S-D:Key Group
%-- Parameters
params.sdk_buttonSize   = 22;  % Size of each button
params.sdk_headerHeight = 30;  % Height of the header row
params.sdk_indexWidth   = 40;  % Width of the index column
% _________________________________________________________________________
%-- Group creation
inhHeight = inhHeight-40;
groups.sdkGroup = uibuttongroup(fig,'Title','S-D:Keys',...
    'Position',[0 inhHeight params.figWidth 40]);

%% Short Channel Group
%-- Parameters
params.schHeight = 50;
% _________________________________________________________________________
%-- Group creation
inhHeight = inhHeight-params.schHeight;
groups.schGroup = uibuttongroup(fig,'Title','Short channels',...
    'Position',[0 inhHeight params.figWidth params.schHeight]);

%% ProbeInfo Group
%-- Parameters
params.pinHeight = 50;
% _________________________________________________________________________
%-- Group creation
inhHeight = inhHeight-params.pinHeight;
groups.pinGroup = uibuttongroup(fig,'Title','Probe info file',...
    'Position',[0 inhHeight params.figWidth params.pinHeight]);
%% Event Group
%-- Parameters
params.evtHeight = 100;
params.evtField1Width = 100;
params.evtField2Width = 40;
params.evtFieldSep = 20;
% _________________________________________________________________________
%-- Group creation
inhHeight = inhHeight-params.evtHeight;
evtWidth  = params.evtField1Width + params.evtFieldSep + ...
            params.evtField2Width + 2*params.pad;
groups.evtGroup = uibuttongroup(fig,'Title','Events',...
    'Position',[0 inhHeight evtWidth params.evtHeight]);

%% Distance Group
params.dis_simpleField = 80;
%-- Group creation
groups.disGroup = uibuttongroup(fig,'Title','Distances',...
    'Position',[evtWidth inhHeight ...
    params.figWidth-evtWidth params.evtHeight]);

%% Logging Group
%-- Parameters
params.logHeight = 70;
params.logSaveWidth = 70;
% _________________________________________________________________________
%-- Group creation
inhHeight = inhHeight-params.logHeight;
groups.logGroup = uibuttongroup(fig,'Title','Logging user actions',...
    'Position',[0 inhHeight ...
    params.figWidth params.logHeight]);

pos1 = [params.pad params.pad ...
       params.figWidth - params.logSaveWidth - params.pad * 3 ...
       params.logHeight - 20 - params.pad * 2];
uitextarea(groups.logGroup,'Value','',...
    'Position',pos1);
pos2 = [params.figWidth - params.logSaveWidth - params.pad ...
       params.pad ...
       params.logSaveWidth params.logHeight - 20 - params.pad * 2];
uibutton(groups.logGroup, 'Text', 'Save', ...
    'Position', pos2, ...
    'ButtonPushedFcn', @(btn,event)saveCleanerToNirx());

%% Data loading ___________________________________________________________
function setRootDirectory(dirLabel, ta)
    global fileList fileIndex root
    root = uigetdir(pwd, 'Please select directory containing your data');
    if root ~= 0  % Check if the user selected a directory
        fileList = dir(fullfile(root, '**', '*.hdr'));
        dirLabel.Text = [root, ' (',num2str(length(fileList)),' files.)'];
        fileIndex = 1;
        ta.Value = erase(fileList(fileIndex).folder,root);
        loadNirxToCleaner(fileIndex)
    end
end

function setCurrentDirectory(valLabel, autoLoadFlag, ta)
    global fileList fileIndex root
    if isempty(root)
        return
    end
    toLoad = false;
    switch valLabel
        case '<'
            fileIndex = max([1,fileIndex - 1]);
            toLoad = true;
        case '<<'
            fileIndex = 1;
            toLoad = true;
        case '>'
            fileIndex = min([length(fileList),fileIndex+1]);
            toLoad = true;
        case '>>'
            fileIndex = length(fileList);
            toLoad = true;
        case 'Load'
            loadNirxToCleaner(fileIndex)
        otherwise
            targetPath = fullfile(root, valLabel);
            for i = 1:length(fileList)
                if strcmp(fileList(i).folder, targetPath)
                    fileIndex = i;
                    toLoad = true;
                    break;
                end
            end

    end
    if toLoad == true
        ta.Value = erase(fileList(fileIndex).folder,root);
        if autoLoadFlag == true
            loadNirxToCleaner(fileIndex)
        end
    end
end

function loadNirxToCleaner(fileIndex)
%-- Setting up metrics    
global fig fileList
set(fig,'Name',['fNIRS Cleaner [',num2str(fileIndex),'/',...
    num2str(length(fileList)),']'])

hdr_file = fileread(fullfile(fileList(fileIndex).folder,...
                fileList(fileIndex).name));

con_path = dir(fullfile(fileList(fileIndex).folder,'*.txt'));
con_file = fileread(fullfile(con_path(1).folder,con_path(1).name));

inf_path = dir(fullfile(fileList(fileIndex).folder,'*.inf'));
inf_file = fileread(fullfile(inf_path(1).folder,inf_path(1).name));

pin_path = dir(fullfile(fileList(fileIndex).folder,'*.mat'));
if ~isempty(pin_path)
    pin_path = fullfile(pin_path(1).folder,pin_path(1).name);
else
    pin_path = '';
end

%-- Load in panels
loadOverview(con_file, inf_file)
loadNote(inf_file)
loadSDKey(hdr_file);
loadShort(hdr_file)

loadProbeInfo(pin_path)
loadEvent(hdr_file)
loadDistance(hdr_file)
end

function saveCleanerToNirx()
    global groups fileIndex fileList
    
    if isempty(fileIndex)
        disp('Please load in a file first')
        return
    end

    hdr_file = fileread(fullfile(fileList(fileIndex).folder,...
                fileList(fileIndex).name));

    con_path = dir(fullfile(fileList(fileIndex).folder,'*.txt'));
    con_file = fileread(fullfile(con_path(1).folder,con_path(1).name));
    
    inf_path = dir(fullfile(fileList(fileIndex).folder,'*.inf'));
    inf_file = fileread(fullfile(inf_path(1).folder,inf_path(1).name));
    
    pin_path = dir(fullfile(fileList(fileIndex).folder,'*.mat'));
    if ~isempty(pin_path)
        pin_path = fullfile(pin_path(1).folder,pin_path(1).name);
    else
        pin_path = '';
    end

% Save Overview: Name / Age / Visit / Gender
% & Save Notes
    entries = regexp(inf_file, '(?<=\n)(.+?)=(.+?)(?=\n)', 'tokens');
    existing_entries = containers.Map();
    for i = 1:length(entries)
        existing_entries(entries{i}{1}) = entries{i}{2};
    end

    ovwOutputs = findobj(groups.ovwGroup, 'Type', 'uitextarea');
    nteOutputs = findobj(groups.nteGroup, 'Type', 'uitextarea');
    outputs = [ovwOutputs; nteOutputs];
    for i=1:length(outputs)
        tag = get(outputs(i), 'Tag');
        val = strjoin(cellstr(get(outputs(i), 'Value')),'\n');
        if isnumeric(val)
            val = num2str(val);
        end
        val = ['"', strtrim(val), '"'];
        existing_entries(tag) = val;
    end

    ordered_params = {'Name', 'Visit', 'Age', 'Gender','Additional Notes'};
    new_info = ['[Subject Demographics]', w_newline];
    
    % Add ordered parameters first
    for i = 1:length(ordered_params)-1
        if isKey(existing_entries, ordered_params{i})
            new_info = [new_info, ordered_params{i}, ...
                '=', existing_entries(ordered_params{i}), w_newline];
            existing_entries.remove(ordered_params{i});
        end
    end
    
    % Add remaining entries (except 'Additional Notes')
    keys = existing_entries.keys;
    for i = 1:length(keys)
        if ~strcmp(keys{i}, ordered_params{end})
            new_info = [new_info, keys{i}, ...
                '=', existing_entries(keys{i}), w_newline];
        end
    end

    % Add 'Additional Notes' at the end if it exists
    if isKey(existing_entries, ordered_params{end})
        new_info = [new_info, ordered_params{end}, ...
            '=', existing_entries(ordered_params{end}), w_newline];
    end
% _________________________________________________________________________
% ProbeInfo
    %-- Get new probeinfo
    pinOutputs = findobj(groups.pinGroup, 'Type', 'uilabel');
    
    %-- Construct and replace old probeinfo
    val = pinOutputs(1).Text;
    if ~isequal(pin_path,val)
        try
            [~, name, ext] = fileparts(val);
            copyfile(val, fullfile(fileList(fileIndex).folder,...
                [name ext]), 'f');
            if ~isempty(pin_path)
                delete(pin_path)
            end
        catch ME
            warning(['Failed to update probe info file:','%s',ME.message]);
        end
    end
% _________________________________________________________________________
% Events
    %-- Get new events
    stp = findobj(groups.evtGroup, 'Tag', "stamp").Value;
    mrk = findobj(groups.evtGroup, 'Tag', "marker").Value;
    if isequal(length(stp),length(mrk))
            evtOutputs = [stp, mrk];
    end
    
    %-- Construct new events
    [roi,~] = extractROI(hdr_file,{'SamplingRate=',newline},{0,2});
    roi = str2double(roi);
    newMarker = ['[Markers]',w_newline,'Events="#'];
    for i=1:size(evtOutputs,1)
        if ~isempty(stp{i}) && ~isempty(mrk{i})
            tick = num2str(round(str2double(stp{i}) * roi));
            newMarker = [newMarker ...
                         w_newline stp{i} char(9) mrk{i} char(9) tick];
        end
    end
    newMarker = [newMarker w_newline '#"'];
    
    %-- Replace old events with new events
    mask = {'[Markers]','#"'};
    leng = [-length(mask{1}) -length(mask{2})];
    [~,pos] = extractROI(hdr_file,mask,{leng(1), leng(2)});
    hdr_file = [hdr_file(1:pos(1)-1) newMarker hdr_file(pos(2)+1:end)];
% _________________________________________________________________________
% SDMask / Shorts / Distances
    sdM = findobj(groups.sdkGroup, 'Type', 'uistatebutton');
    sdm = [];
    for i=1:length(sdM)
        tags = sdM(i).Tag;
        cord = [str2double(tags(1:2)) str2double(tags(3:4))];
        sdm(cord(1),cord(2)) = sdM(i).Value;
    end
    rs = arrayfun(@(i) sprintf('%.0f\t', sdm(i,:)), 1:size(sdm,1), ...
                               'UniformOutput', false);
    % Remove the trailing tab from each row and add a newline
    rs = cellfun(@(s) [s(1:end-1) w_newline], rs, 'UniformOutput', false);
    % Concatenate all rows into a single char array
    charArray = [rs{:}];
    [~,pos] = extractROI(hdr_file,{'S-D-Mask="#','#"'},{2,0});
    hdr_file = [hdr_file(1:pos(1)-1) charArray hdr_file(pos(2)+1:end)];

% Shorts
    scM = findobj(groups.schGroup, 'Type', 'uistatebutton');
    scm = [];
    for i=length(scM):-1:1
        if scM(i).Value == 1
            scm = [scm scM(i).Tag char(9)];
        end
    end
    scm = scm(1:end-1);
    [~,pos] = extractROI(hdr_file,{'ShortDetIndex="','"'},{0,1});
    if ~isempty(pos)
        hdr_file = [hdr_file(1:pos(1)-1) scm hdr_file(pos(2)+1:end)];
    end

% Distances
    lVal = char(findobj(groups.disGroup, 'Tag', "long").Value);
    sVal = char(findobj(groups.disGroup, 'Tag', "short").Value);
    if isempty(scm)
        sChn = -1;
    else
        sChn = sscanf(scm,'%d');
    end
    dist = [];
    for row=1:size(sdm,1)
        for col=1:size(sdm,2)
            if sdm(row,col) == 1
                if ismember(col,sChn)
                    dist = [dist sVal char(9)];
                else
                    dist = [dist lVal char(9)];
                end
            end
        end
    end
    dist = dist(1:end-1);
    [~,pos] = extractROI(hdr_file,{'ChanDis="','"'},{0,1});
    hdr_file = [hdr_file(1:pos(1)-1) dist hdr_file(pos(2)+1:end)];

    fid = fopen(fullfile(inf_path(1).folder, inf_path(1).name), 'w');
    fwrite(fid, new_info);
    fclose(fid);
    fid = fopen(fullfile(fileList(fileIndex).folder, fileList(fileIndex).name), 'w');
    fwrite(fid, hdr_file);
    fclose(fid);

    disp('Saved changes.')

end

function loadOverview(con_file, inf_file)
    global groups params
% Data management _________________________________________________________
values = struct();
[values.sr,~]  = extractROI(con_file,{'SamplingRate=',';'},{0,1});
[values.src,~] = extractROI(con_file,{'source_N=',';'},{0,1});
[values.det,~] = extractROI(con_file,{'detector_N=',';'},{0,1});
[values.tp,~]  = extractROI(con_file,{'time_point_N=',';'},{0,1});
[values.wl,~]  = extractROI(con_file,{'Wavelengths=',';'},{0,1});
values.sec = num2str(str2double(values.tp) / str2double(values.sr));

[values.Name,  ~]= extractROI(inf_file,{'Name="','"'},{0,1});
[values.Age,  ~] = extractROI(inf_file,{'Age="','"'},{0,1});
[values.Gender,~]= extractROI(inf_file,{'Gender="','"'},{0,1});
[values.Visit,~] = extractROI(inf_file,{'Visit="','"'},{0,1});
    
sections = {"Sampling rate","Source",   "Time points","Name ",  "Age ";...
            'sr',           'src',      'tp',         {'Name'},{'Age'};...
            "Wavelength",   "Detector", "Seconds", "Visit ", "Gender ";...
            'wl',           'det',      'sec',      {'Visit'}, {'Gender'}};

children = get(groups.ovwGroup, 'Children');
if isempty(children)
sectionWidth = round((params.figWidth-params.pad*(1+length(sections)))...
               / length(sections));
sectionHeight = 15;
pos = [0 0 sectionWidth sectionHeight];
    for row=1:size(sections,1)
        pos(2) = params.ovgHeight-30- params.pad*2 - (row-1)*sectionHeight;
        for col=1:size(sections,2)
            pos(1) = params.pad + (col - 1) * sectionWidth;
            pos(3:4) = [sectionWidth sectionHeight];
            if      isstring(sections{row,col})
                uilabel(groups.ovwGroup,'Text',sections{row,col},...
                'HorizontalAlignment','center','Tag',sections{row,col},...
                'Position',pos,'FontSize', 10);
            
            elseif  ischar(sections{row,col})
                pos(3) = pos(3)/2;
                pos(1) = pos(1) + pos(3)/2;
                text = values.(sections{row,col});
                uilabel(groups.ovwGroup,'Text',text,...
                'HorizontalAlignment','center','Tag',sections{row,col},...
                'BackGroundColor','white',...
                'Position',pos,'FontSize', 8);  
            
            elseif  iscell(sections{row,col})
                pos(3) = pos(3)/2;
                pos(1) = pos(1) + pos(3)/2;
                text = sections{row,col};
                text = values.(text{1});
                uitextarea(groups.ovwGroup,'Value',text,...
                    'HorizontalAlignment','center','Tag',string(sections{row,col}),...
                    'Position',pos,'FontSize', 8);
            end
        end
    end
else
    for i = 1:length(children)
    if strcmp(get(children(i), 'Type'), 'uilabel') || ...
       strcmp(get(children(i), 'Type'), 'uitextarea')
        tag = get(children(i), 'Tag');
        if isfield(values, tag)
            if strcmp(get(children(i), 'Type'), 'uilabel')
                set(children(i), 'Text', values.(tag));
            else
                set(children(i), 'Value', values.(tag));
            end
        end
    end
    end
end
end

function loadNote(inf_file)
    global params groups
    [hdr_notes,~] = extractROI(inf_file,{'Additional Notes="','"'},{0,1});
    
    children = get(groups.nteGroup, 'Children');
    if isempty(children)
    uitextarea(groups.nteGroup,'Value',hdr_notes,...
        'Tag',"Additional Notes",...
        'Position',[params.pad params.pad ...
                    params.figWidth-2*params.pad ...
                    params.noteHeight-20-2*params.pad]);
    else
        set(children(1), 'Value', hdr_notes);
    end
end

function loadSDKey(hdr_file)
global params groups output
% Data management _________________________________________________________
%-- Read data
%-- Extract mask coordinates
[roi,~] = extractROI(hdr_file,{'S-D-Mask="#','#"'},{2,2});
hdr_mask_beg= strfind(hdr_file,'S-D-Mask="#')+length('S-D-Mask="#\n');
hdr_mask_end= strfind(hdr_file(hdr_mask_beg:end), '#"')-length('\n#"');
hdr_sdkeys  = hdr_file(hdr_mask_beg:hdr_mask_beg + hdr_mask_end(1));

%-- Parse S-D:Key content
output.SDKeys = [];
hdr_lines = strsplit(hdr_sdkeys, '\n');
for i = 1:length(hdr_lines)
    line = strsplit(strtrim(hdr_lines{i}));
    if ~isempty(line)
        output.SDKeys = [output.SDKeys; str2double(line)];
    end
end
[srcCount, detCount] = size(output.SDKeys);
% _________________________________________________________________________

% Calculate the required width and height
uiHeight = srcCount * params.sdk_buttonSize + params.pad;

%-- Set section group size
sdkHeight = srcCount * (params.sdk_buttonSize+params.pad*2);
cp = get(groups.sdkGroup,'Position');
cp(2) = cp(2) - sdkHeight + cp(4);
ep = cp(4);
cp(4) = sdkHeight;
set(groups.sdkGroup,'Position',cp)

children = get(groups.sdkGroup, 'Children');
prevDetCount = length(findobj(groups.sdkGroup, 'Tag', "detector"));
prevSrcCount = length(findobj(groups.sdkGroup, 'Tag', "source"));
createChildren = false;
if srcCount ~= prevSrcCount || detCount ~= prevDetCount
    if ~isempty(children)
        delete(children)
    end
    createChildren = true;
else
end
%-- Detector header
if createChildren
for det = 1:detCount
    pos = [params.sdk_indexWidth + (det-1)*params.sdk_buttonSize, ...
           uiHeight ...
           params.sdk_buttonSize, ...
           params.sdk_headerHeight];
    uilabel(groups.sdkGroup, 'Text', ['D',newline,sprintf('%02d', det)],...
        'Position', pos, 'HorizontalAlignment', 'center','Tag',"detector");
end
end

%-- Source header and S-D pairs
for src = 1:srcCount
    %-- Source header
    if createChildren
    pos = [0          uiHeight-(src*params.sdk_buttonSize)...
           params.sdk_indexWidth params.sdk_buttonSize];

    uilabel(groups.sdkGroup, 'Text', sprintf('S%02d', src), ...
        'Position', pos, ...
        'HorizontalAlignment', 'right','Tag',"source");
    end
    
    %-- S-D pairs
    buttonHeight = uiHeight-(src*params.sdk_buttonSize);
    for det = 1:detCount
        if createChildren
        pos = [params.sdk_indexWidth + (det-1)*params.sdk_buttonSize ...
               buttonHeight ...
               params.sdk_buttonSize ...
               params.sdk_buttonSize];
        uibutton(groups.sdkGroup, 'state', ...
            'Text',            '', ...
            'Position',        pos, ...
            'Value',           output.SDKeys(src,det), ...
            'Tag',            sprintf('%02d%02d', src, det),...
            'ValueChangedFcn', @(btn,event)updateSDKey(btn, src, det));
        else
            cur = findobj(groups.sdkGroup, 'Tag', sprintf('%02d%02d', src, det));
            set(cur, 'Value', output.SDKeys(src,det));
        end
    end
end
updateFieldPositions('sdkGroup', sdkHeight-ep)
end

function loadShort(hdr_file)
global params groups output
% Data management _________________________________________________________
[hdr_shorts,~] = extractROI(hdr_file,{'ShortDetIndex="','"'},{0,1});
[detCount,~]   = extractROI(hdr_file,{'Detectors=',newline},{0,0});
shortIndices = str2num(hdr_shorts);
detCount = str2num(detCount);
output.shortKeys = zeros(detCount,1);
output.shortKeys(shortIndices) = 1;
% _________________________________________________________________________
children = get(groups.schGroup, 'Children');
for det = 1:detCount
    if isempty(children) || length(children) ~= detCount
        if ~isempty(children)
            delete(children)
        end
    pos = [params.sdk_indexWidth+ 5 + (det-1)*params.sdk_buttonSize 10 ...
           params.sdk_buttonSize/2 params.sdk_buttonSize/2];
        uibutton(groups.schGroup, 'state', ...
        'Text',            '', ...
        'Position',        pos, ...
        'Value',           output.shortKeys(det), ...
        'Tag',             num2str(det),...
        'ValueChangedFcn', @(btn,event)updateSCh(btn, det));
    else
        cur = findobj(groups.schGroup, 'Tag', num2str(det));
        set(cur, 'Value', output.shortKeys(det));
    end
end
end

function loadProbeInfo(pinPath)
global groups params output
if isempty(pinPath)
    pinPath = '';
end
output.probeInfoPath = pinPath;
children = get(groups.pinGroup, 'Children');
if isempty(children)
ta = uilabel(groups.pinGroup, 'Text', pinPath, ...
                      'BackgroundColor', 'white', 'Tag',"label",...
    'Position', [100 + 2*params.pad                   params.pad ...
        params.figWidth-2*params.pad params.pinHeight-20-2*params.pad]);

uibutton(groups.pinGroup, 'Text', 'Open...', ...
    'Position', [params.pad params.pad 100 params.pinHeight-20-2*params.pad], ...
    'ButtonPushedFcn', @(btn,event)updateProbeInfo(ta));
else
    ta = findobj(groups.pinGroup, 'Tag', "label");
    set(ta, 'Text', pinPath);
end
end

function loadEvent(hdr_file)
global params groups
% Data management _________________________________________________________
[hdr_events,~] = extractROI(hdr_file,{'Events="#','#"'},{2,2});
events = [];
time_stamps = '';
time_marker = '';
hdr_lines = strsplit(hdr_events, '\n');

if ~isempty(hdr_lines{1})
    for i = 1:length(hdr_lines)
        line = strsplit(strtrim(hdr_lines{i}));
        if ~isempty(line)
            events = [events; str2double(line)];
        end
    end
    % _____________________________________________________________________
    

    for i=1:size(events,1)
        time_stamps = [time_stamps, num2str(events(i,1)), newline];
        time_marker = [time_marker, num2str(events(i,2)), newline];
    end
end
pos1 = [params.pad            params.pad ...
       params.evtField1Width params.evtHeight-20-2*params.pad];
pos2 = [pos1(1) + pos1(3) + params.evtFieldSep pos1(2) ...
       params.evtField2Width pos1(4)];

% First pass
children = get(groups.evtGroup, 'Children');
if isempty(children)
    uitextarea(groups.evtGroup ,'Value',time_stamps,...
        'Position',pos1,'Tag',"stamp");
    uitextarea(groups.evtGroup ,'Value',time_marker,...
        'Position',pos2,'Tag',"marker");
% If already generated
else
    stamp = findobj(groups.evtGroup, 'Tag', "stamp");
    set(stamp, 'Value', time_stamps);
    marker = findobj(groups.evtGroup, 'Tag', "marker");
    set(marker, 'Value', time_marker);
end
end

function loadDistance(hdr_file)
%--Data management
global groups params
[hdr_distance,~] = extractROI(hdr_file,{'ChanDis="','"'},{0,1});
%--Display field
children = get(groups.disGroup, 'Children');
if isempty(children)

    tasize = get(groups.disGroup,'Position');
    pos = [params.pad tasize(4)-40 75 20];
    uilabel(groups.disGroup,'Text','LongChan (mm)',...
        'HorizontalAlignment', 'left','FontSize',10,'Position',pos);
    pos(2) = pos(2) - 15;
    uitextarea(groups.disGroup,'Value','30.0','FontSize',10,...
        'Tag',"long",'Position',pos);
    
    pos = [params.pad tasize(4)-params.dis_simpleField 75 20];
    uilabel(groups.disGroup,'Text','ShortChan (mm)',...
        'HorizontalAlignment', 'left','FontSize',10,'Position',pos);
    pos(2) = pos(2) - 15;
    uitextarea(groups.disGroup,'Value','8.0','FontSize',10,...
        'Tag',"short",'Position',pos);
    
    pos = [params.pad + params.dis_simpleField ...
           tasize(4)-40 150 20];
    uilabel(groups.disGroup,'Text','Custom Channel Matrix (mm)',...
    'HorizontalAlignment', 'left','FontSize',10,'Position',pos);
    uitextarea(groups.disGroup ,'Value','','Tag',"ta",...
    'Position',[params.pad + 80 params.pad ...
                tasize(3)-77-params.pad tasize(4)-35-2*params.pad]);
else
    ta = findobj(groups.disGroup, 'Tag', "ta");
    set(ta, 'Value', '');
end
end

function updateSDKey(btn, src, det)
    global output
    output.SDKeys(src,det) = btn.Value;
    fprintf('S%02d-D%02d changed to state: %d\n', src, det, btn.Value);
end

function updateSCh(btn, det)
    global output
    output.shortKeys(det) = btn.Value;
    fprintf('D%02d isShortChannel: %d\n', det, btn.Value);
end

function updateProbeInfo(ta)
    global output
    [name,folder,~] = uigetfile('*mat');
    ta.Text = fullfile(folder,name);
    output.probeInfoPath = fullfile(folder,name);
end

% Auxilliary functions
%-- Extract region of interest and its mask values from character array
function [roi,pos] = extractROI(text,mask,offset)
    lens = [length(mask{1})+offset{1}, length(mask{2})+offset{2}];
    mask_beg= strfind(text,mask{1})+lens(1);
    if isempty(mask_beg)
        roi = '';
        pos = [];
        return
    end
    mask_end= strfind(text(mask_beg:end), mask{2})-lens(2);
    if isempty(mask_beg)
        roi = '';
        pos = [];
        return
    end
    pos = [mask_beg mask_beg+mask_end(1)];
    roi  = text(mask_beg:mask_beg + mask_end(1));
end
%-- Shift GUI groups depending on relative position
function updateFieldPositions(groupName, value)
    global groups
    fieldNames = fieldnames(groups);
    index = find(strcmp(fieldNames, groupName));
    for i = index+1:length(fieldNames)
        cp = get(groups.(fieldNames{i}),'Position');
        cp(2) = cp(2) - value;
        set(groups.(fieldNames{i}),'Position',cp)
    end
end
%-- Workaround to match formatting with original file
function w = w_newline()
    w = [char(13) char(10)];
end