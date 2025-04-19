function EEG_ControlPanel(EEGStats, channel_locations, varargin)
% EEG_ControlPanel - Creates a control panel for EEG data visualization
%
% Usage:
%   1. Interactive mode: 
%      EEG_ControlPanel(EEGStats, channel_locations)
%      EEG_ControlPanel(EEGStats, channel_locations, event_map)
%   
%   2. Automated mode:
%      EEG_ControlPanel(EEGStats, channel_locations, 'auto', params)
%      EEG_ControlPanel(EEGStats, channel_locations, event_map, 'auto', params)
%
% Inputs:
%   EEGStats           - Structure containing processed EEG data
%   channel_locations  - Channel locations for topographical plotting (EEGLAB format)
%   event_map          - (Optional) Container Map for event type mapping
%   'auto'             - (Optional) String to indicate automated mode
%   params             - (Optional) Parameters structure for automated mode with fields:
%                         - bands: cell array of frequency bands to visualize
%                         - event_types: cell array of event types to visualize
%                         - save_power: boolean to save power spectra
%                         - save_erp: boolean to save ERPs
%                         - save_connectivity: boolean to save connectivity matrices
%                         - save_timefreq: boolean to save time-frequency plots
%                         - output_dir: directory for saving results
%                         - figFormat: format for saving figures ('png', 'svg', etc.)
%
% Description:
%   This function creates a control panel for visualizing and extracting EEG data
%   analysis results. It supports interactive and automated modes for flexibility.

% Parse variable input arguments and determine mode
event_map = [];
autoMode = false;
params = struct();
handles = struct();

% Check if event_map is provided
if nargin >= 3
    if ischar(varargin{1}) && strcmpi(varargin{1}, 'auto')
        % No event_map, but auto mode
        autoMode = true;
        if nargin >= 4
            params = varargin{2};
        else
            error('When using auto mode, params struct must be provided');
        end
    else
        % event_map is provided
        event_map = varargin{1};
        
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

% Create default event_map if not provided
if isempty(event_map)
    % Get all unique event types across all datasets
    all_event_types = {};
    
    % Method 1: Check for events in ERP structure
    for i = 1:length(EEGStats)
        if isfield(EEGStats(i), 'erp') && ~isempty(EEGStats(i).erp)
            all_event_types = [all_event_types, fieldnames(EEGStats(i).erp)'];
        end
    end
    
    % Method 2: Check for events in subject names/IDs (for block-separated data)
    for i = 1:length(EEGStats)
        if isfield(EEGStats(i), 'subject')
            % Check if the subject name contains an event marker
            % Common pattern after block separation is "Original_Name_EventType"
            subject_name = EEGStats(i).subject;
            parts = strsplit(subject_name, '_');
            
            % If there are multiple parts (like "Subject_1_rest1"), 
            % the last part might be an event type
            if length(parts) > 2
                potential_event = parts{end};
                all_event_types = [all_event_types, {potential_event}];
            end
        end
    end
    
    % Method 3: Look for any ID fields that might contain event types
    for i = 1:length(EEGStats)
        if isfield(EEGStats(i), 'id')
            % Check if ID contains event info (common in block-separated data)
            id_string = EEGStats(i).id;
            parts = strsplit(id_string, '_');
            
            % The last part after splitting by underscore is often the event type
            if length(parts) > 1
                potential_event = parts{end};
                all_event_types = [all_event_types, {potential_event}];
            end
        end
    end
    
    % Get unique event types
    all_event_types = unique(all_event_types);
    
    % Create default event_map that just returns the original event types
    event_map = containers.Map();
    for i = 1:length(all_event_types)
        event_map(all_event_types{i}) = all_event_types{i};
    end
    
    % If still no events found, add a default "unknown" event
    if isempty(all_event_types)
        event_map('unknown') = 'unknown';
    end
end

% Cosmetic variables ______________________________________________________
coordY_multiplier = 40;
labelWidth = 200;
dropdownWidth = 150;
buttonWidth = 100;
figWidth = 800;
figHeight = 700;
figFormat = 'png';

if isfield(params, 'figFormat')
    figFormat = params.figFormat;
end
% _________________________________________________________________________

% Internal variables ______________________________________________________
% Get all frequency bands
band_names = {};
for i = 1:length(EEGStats)
    if isfield(EEGStats(i), 'bands')
        band_names = [band_names, fieldnames(EEGStats(i).bands)'];
    end
end
band_names = unique(band_names);

event_types = {};

% Method 1: Get events from ERP structure
for i = 1:length(EEGStats)
    if isfield(EEGStats(i), 'erp') && ~isempty(EEGStats(i).erp)
        event_types = [event_types, fieldnames(EEGStats(i).erp)'];
    end
end

% Method 2: Extract events from subject names (for block-separated data)
for i = 1:length(EEGStats)
    if isfield(EEGStats(i), 'subject')
        % Check if the subject name contains an event marker
        subject_name = EEGStats(i).subject;
        parts = strsplit(subject_name, '_');
        
        % If there are multiple parts, the last part might be an event type
        if length(parts) > 2
            potential_event = parts{end};
            event_types = [event_types, {potential_event}];
        end
    end
end

% Method 3: Check IDs for event types
for i = 1:length(EEGStats)
    if isfield(EEGStats(i), 'id')
        % Check if ID contains event info
        id_string = EEGStats(i).id;
        parts = strsplit(id_string, '_');
        
        % The last part after splitting might be the event type
        if length(parts) > 1
            potential_event = parts{end};
            event_types = [event_types, {potential_event}];
        end
    end
end

% Get unique event types
event_types = unique(event_types);

% If no events found, provide a default one
if isempty(event_types)
    event_types = {'unknown'};
end

% Get subject IDs
subject_ids = {};
for i = 1:length(EEGStats)
    if isfield(EEGStats(i), 'subject')
        subject_ids{end+1} = EEGStats(i).subject;
    else
        subject_ids{end+1} = ['Subject_', num2str(i)];
    end
end
% _________________________________________________________________________

% Setup autoMode parameters if provided
if autoMode
    % Auto-process immediately
    if isfield(params, 'bands')
        selected_bands = params.bands;
    else
        selected_bands = band_names;
    end
    
    if isfield(params, 'event_types')
        selected_events = params.event_types;
    else
        selected_events = event_types;
    end
    
    % Set default output directory if not provided
    if ~isfield(params, 'output_dir')
        params.output_dir = fullfile(pwd, 'EEG_Results');
    end
    
    % Create output directory if it doesn't exist
    if ~exist(params.output_dir, 'dir')
        mkdir(params.output_dir);
    end
    
    % Set default save options if not provided
    if ~isfield(params, 'save_power')
        params.save_power = true;
    end
    
    if ~isfield(params, 'save_erp')
        params.save_erp = true;
    end
    
    if ~isfield(params, 'save_connectivity')
        params.save_connectivity = true;
    end
    
    if ~isfield(params, 'save_timefreq')
        params.save_timefreq = true;
    end
    
    % Process all subjects or the specified subjects
    if isfield(params, 'subjects')
        subject_indices = find(ismember(subject_ids, params.subjects));
    else
        subject_indices = 1:length(EEGStats);
    end
    
    % Process automatically
    processAutomated(subject_indices, selected_bands, selected_events);
    return;
end

% Control Window Figure ___________________________________________________
fig = uifigure('Name', 'EEG Control Panel', ...
    'Position', [100, 100, figWidth, figHeight]);
% _________________________________________________________________________

% Selection Panel _________________________________________________________
selectionPanel = uipanel(fig, 'Title', 'Data Selection', ...
    'Position', [10, figHeight-200, figWidth-20, 190]);

% Subject selection
uilabel(selectionPanel, 'Text', 'Subject:', ...
    'Position', [10, 150, 60, 20]);
subjectDropdown = uidropdown(selectionPanel, ...
    'Position', [80, 150, dropdownWidth, 20], ...
    'Items', subject_ids, ...
    'Value', subject_ids{1});

% Frequency band selection
uilabel(selectionPanel, 'Text', 'Frequency Band:', ...
    'Position', [10, 110, 100, 20]);
bandDropdown = uidropdown(selectionPanel, ...
    'Position', [120, 110, dropdownWidth, 20], ...
    'Items', band_names, ...
    'Value', band_names{1});

% Event type selection (for ERP and time-frequency)
uilabel(selectionPanel, 'Text', 'Event Type:', ...
    'Position', [10, 70, 80, 20]);
eventDropdown = uidropdown(selectionPanel, ...
    'Position', [100, 70, dropdownWidth, 20], ...
    'Items', event_types, ...
    'Value', event_types{min(1, length(event_types))});

% Channel selection
uilabel(selectionPanel, 'Text', 'Channel:', ...
    'Position', [10, 30, 60, 20]);

% Get channel names from channel_locations if available
channel_names = {};
if ~isempty(channel_locations)
    if isstruct(channel_locations)
        for i = 1:length(channel_locations)
            if isfield(channel_locations, 'labels')
                channel_names{i} = channel_locations(i).labels;
            end
        end
    end
end

% If no channel names from locations, try to get from EEGStats
if isempty(channel_names)
    for i = 1:length(EEGStats)
        if isfield(EEGStats(i).bands, band_names{1})
            band_data = EEGStats(i).bands.(band_names{1});
            if isfield(band_data, 'chanlocs')
                for j = 1:length(band_data.chanlocs)
                    channel_names{j} = band_data.chanlocs(j).labels;
                end
                break;
            end
        end
    end
end

% If still no channel names, use default naming
if isempty(channel_names)
    % Try to determine number of channels from data
    num_channels = 0;
    for i = 1:length(EEGStats)
        if isfield(EEGStats(i).power, band_names{1})
            num_channels = length(EEGStats(i).power.(band_names{1}));
            break;
        end
    end
    
    if num_channels > 0
        channel_names = arrayfun(@(x) sprintf('Channel %d', x), 1:num_channels, 'UniformOutput', false);
    else
        channel_names = {'Channel 1'}; % Default
    end
end

channelDropdown = uidropdown(selectionPanel, ...
    'Position', [80, 30, dropdownWidth, 20], ...
    'Items', channel_names, ...
    'Value', channel_names{1});

% Group selection (if groups exist)
group_ids = {};
for i = 1:length(EEGStats)
    if isfield(EEGStats(i), 'group') && ~isempty(EEGStats(i).group)
        group_ids{end+1} = EEGStats(i).group;
    end
end
group_ids = unique(group_ids);

if ~isempty(group_ids)
    uilabel(selectionPanel, 'Text', 'Group:', ...
        'Position', [300, 150, 60, 20]);
    groupDropdown = uidropdown(selectionPanel, ...
        'Position', [370, 150, dropdownWidth, 20], ...
        'Items', group_ids, ...
        'Value', group_ids{1});
end

% Visualization buttons
powerButton = uibutton(selectionPanel, 'Text', 'Power Spectrum', ...
    'Position', [300, 110, buttonWidth, 20], ...
    'ButtonPushedFcn', @(btn,event) plotPowerSpectrum());

erpButton = uibutton(selectionPanel, 'Text', 'ERP', ...
    'Position', [300, 70, buttonWidth, 20], ...
    'ButtonPushedFcn', @(btn,event) plotERP());

connectivityButton = uibutton(selectionPanel, 'Text', 'Connectivity', ...
    'Position', [300, 30, buttonWidth, 20], ...
    'ButtonPushedFcn', @(btn,event) plotConnectivity());

timefreqButton = uibutton(selectionPanel, 'Text', 'Time-Frequency', ...
    'Position', [410, 70, buttonWidth, 20], ...
    'ButtonPushedFcn', @(btn,event) plotTimeFrequency());

topoButton = uibutton(selectionPanel, 'Text', 'Topography', ...
    'Position', [410, 30, buttonWidth, 20], ...
    'ButtonPushedFcn', @(btn,event) plotTopography());

% Save options
savePanel = uipanel(selectionPanel, 'Title', 'Save Options', ...
    'Position', [520, 10, 250, 160]);

savePowerCheck = uicheckbox(savePanel, 'Text', 'Power', ...
    'Position', [10, 120, 100, 20], 'Value', true);

saveERPCheck = uicheckbox(savePanel, 'Text', 'ERP', ...
    'Position', [10, 90, 100, 20], 'Value', true);

saveConnectivityCheck = uicheckbox(savePanel, 'Text', 'Connectivity', ...
    'Position', [10, 60, 100, 20], 'Value', true);

saveTimeFreqCheck = uicheckbox(savePanel, 'Text', 'Time-Frequency', ...
    'Position', [10, 30, 120, 20], 'Value', true);

saveButton = uibutton(savePanel, 'Text', 'Save All Selected', ...
    'Position', [130, 30, 110, 50], ...
    'ButtonPushedFcn', @(btn,event) saveSelectedData());

% Main display area
displayPanel = uipanel(fig, 'Title', 'Results', ...
    'Position', [10, 10, figWidth-20, figHeight-220]);

% Textual display for results
resultsText = uitextarea(displayPanel, ...
    'Position', [10, 10, figWidth-40, 100], ...
    'Editable', 'off');

% Plot area for visualization
plotArea = uiaxes(displayPanel, ...
    'Position', [10, 120, figWidth-40, figHeight-360]);

% Auxilliary functions ____________________________________________________
function plotPowerSpectrum()
    % Get selected subject and band
    subject_idx = find(strcmp(subject_ids, subjectDropdown.Value));
    band = bandDropdown.Value;
    
    % Check if power data exists for this subject and band
    if ~isfield(EEGStats(subject_idx).power, band)
        resultsText.Value = ['No power spectrum data available for subject ', ...
            subjectDropdown.Value, ' and band ', band];
        return;
    end
    
    % Get power data
    power_data = EEGStats(subject_idx).power.(band);
    
    % Plot power spectrum
    cla(plotArea);
    
    % Determine which channel to plot
    channel_idx = find(strcmp(channel_names, channelDropdown.Value));
    
    if isempty(channel_idx) || channel_idx > length(power_data)
        resultsText.Value = ['Channel ', channelDropdown.Value, ' not found or out of range'];
        return;
    end
    
    % Get frequency axis if available
    freq_axis = [];
    if isfield(EEGStats(subject_idx).bands, band) && isfield(EEGStats(subject_idx).bands.(band), 'srate')
        srate = EEGStats(subject_idx).bands.(band).srate;
        freq_axis = linspace(0, srate/2, length(power_data));
    else
        freq_axis = 1:length(power_data);
    end
    
    % Plot power
    plot(plotArea, freq_axis, power_data);
    title(plotArea, ['Power Spectrum - ', subjectDropdown.Value, ' - ', band, ' - ', channelDropdown.Value]);
    xlabel(plotArea, 'Frequency (Hz)');
    ylabel(plotArea, 'Power (dB)');
    grid(plotArea, 'on');
    
    % Update results text
    resultsText.Value = ['Power spectrum for subject ', subjectDropdown.Value, ...
        ', band ', band, ', channel ', channelDropdown.Value, ' displayed'];
end

function plotERP()
    % Get selected subject and event
    subject_idx = find(strcmp(subject_ids, subjectDropdown.Value));
    event = eventDropdown.Value;
    
    % Check if ERP data exists for this subject and event
    if ~isfield(EEGStats(subject_idx), 'erp') || ~isfield(EEGStats(subject_idx).erp, event)
        resultsText.Value = ['No ERP data available for subject ', ...
            subjectDropdown.Value, ' and event ', event];
        return;
    end
    
    % Get ERP data
    erp_data = EEGStats(subject_idx).erp.(event);
    
    % Plot ERP
    cla(plotArea);
    
    % Determine which channel to plot
    channel_idx = find(strcmp(channel_names, channelDropdown.Value));
    
    if isempty(channel_idx) || channel_idx > size(erp_data, 1)
        resultsText.Value = ['Channel ', channelDropdown.Value, ' not found or out of range'];
        return;
    end
    
    % Get time axis if available
    time_axis = [];
    if isfield(EEGStats(subject_idx), 'bands')
        band_names = fieldnames(EEGStats(subject_idx).bands);
        if ~isempty(band_names)
            band_data = EEGStats(subject_idx).bands.(band_names{1});
            if isfield(band_data, 'times')
                time_axis = band_data.times;
            elseif isfield(band_data, 'xmin') && isfield(band_data, 'xmax') && isfield(band_data, 'pnts')
                time_axis = linspace(band_data.xmin * 1000, band_data.xmax * 1000, band_data.pnts);
            end
        end
    end
    
    if isempty(time_axis)
        time_axis = 1:size(erp_data, 2);
    end
    
    % Plot ERP
    plot(plotArea, time_axis, erp_data(channel_idx, :));
    title(plotArea, ['ERP - ', subjectDropdown.Value, ' - Event: ', event, ' - ', channelDropdown.Value]);
    xlabel(plotArea, 'Time (ms)');
    ylabel(plotArea, 'Amplitude (µV)');
    grid(plotArea, 'on');
    
    % Add vertical line at time 0 if time_axis includes 0
    if min(time_axis) <= 0 && max(time_axis) >= 0
        hold(plotArea, 'on');
        plot(plotArea, [0 0], ylim(plotArea), 'k--');
        hold(plotArea, 'off');
    end
    
    % Update results text
    resultsText.Value = ['ERP for subject ', subjectDropdown.Value, ...
        ', event ', event, ', channel ', channelDropdown.Value, ' displayed'];
end

function plotConnectivity()
    % Get selected subject and band
    subject_idx = find(strcmp(subject_ids, subjectDropdown.Value));
    band = bandDropdown.Value;
    
    % Check if connectivity data exists
    if ~isfield(EEGStats(subject_idx), 'connectivity') || ~isfield(EEGStats(subject_idx).connectivity, band)
        resultsText.Value = ['No connectivity data available for subject ', subjectDropdown.Value, ' and band ', band];
        return;
    end
    
    % Get connectivity data - FIXED to access the dccc field
    if isfield(EEGStats(subject_idx).connectivity.(band), 'dccc')
        conn_data = EEGStats(subject_idx).connectivity.(band).dccc;
    else
        conn_data = EEGStats(subject_idx).connectivity.(band);
    end
    
    % Handle 3D matrix
    if ndims(conn_data) == 3
        % Add dropdown to select scale if not already there
        if ~isfield(handles, 'scaleDropdown')
            scaleLabel = uilabel(displayPanel, 'Text', 'Scale:', 'Position', [10, figHeight-380, 40, 20]);
            scaleItems = arrayfun(@num2str, 1:size(conn_data, 3), 'UniformOutput', false);
            handles.scaleDropdown = uidropdown(displayPanel, 'Position', [60, figHeight-380, 100, 20], ...
                                  'Items', scaleItems, 'Value', scaleItems{1});
        end
        
        % Get selected scale
        scale_idx = str2double(handles.scaleDropdown.Value);
        conn_data = conn_data(:,:,scale_idx);
        resultsText.Value = ['Showing scale ' num2str(scale_idx) ' of connectivity matrix'];
    end
    
    % Plot connectivity matrix
    cla(plotArea);
    imagesc(plotArea, conn_data);
    colorbar(plotArea);
    colormap(plotArea, 'jet');
    axis(plotArea, 'square');
    title(plotArea, ['Connectivity Matrix - ', subjectDropdown.Value, ' - ', band]);
    xlabel(plotArea, 'Channel');
    ylabel(plotArea, 'Channel');
end

function plotTimeFrequency()
    % Get selected subject and event
    subject_idx = find(strcmp(subject_ids, subjectDropdown.Value));
    event = eventDropdown.Value;
    
    % Check if time-frequency data exists for this subject and event
    if ~isfield(EEGStats(subject_idx), 'timefreq') || ~isfield(EEGStats(subject_idx).timefreq, event)
        resultsText.Value = ['No time-frequency data available for subject ', ...
            subjectDropdown.Value, ' and event ', event];
        return;
    end
    
    % Get time-frequency data
    tf_data = EEGStats(subject_idx).timefreq.(event);
    
    % Determine which channel to plot
    channel_idx = find(strcmp(channel_names, channelDropdown.Value));
    
    if isempty(channel_idx) || channel_idx > length(tf_data.power)
        resultsText.Value = ['Channel ', channelDropdown.Value, ' not found or out of range'];
        return;
    end
    
    % Plot time-frequency
    cla(plotArea);
    
    % Extract TF data for selected channel
    channel_tf = tf_data.power{channel_idx};
    
    % Plot as image
    imagesc(plotArea, tf_data.times, tf_data.freqs, channel_tf);
    colorbar(plotArea);
    colormap(plotArea, 'jet');
    title(plotArea, ['Time-Frequency - ', subjectDropdown.Value, ' - Event: ', event, ' - ', channelDropdown.Value]);
    xlabel(plotArea, 'Time (ms)');
    ylabel(plotArea, 'Frequency (Hz)');
    
    % Add vertical line at time 0 if time axis includes 0
    if min(tf_data.times) <= 0 && max(tf_data.times) >= 0
        hold(plotArea, 'on');
        plot(plotArea, [0 0], ylim(plotArea), 'k--');
        hold(plotArea, 'off');
    end
    
    % Update results text
    resultsText.Value = ['Time-frequency data for subject ', subjectDropdown.Value, ...
        ', event ', event, ', channel ', channelDropdown.Value, ' displayed'];
end

function plotTopography()
    % Get selected subject and band
    subject_idx = find(strcmp(subject_ids, subjectDropdown.Value));
    band = bandDropdown.Value;
    
    % Check if power data exists for this subject and band
    if ~isfield(EEGStats(subject_idx).power, band)
        resultsText.Value = ['No power data available for subject ', ...
            subjectDropdown.Value, ' and band ', band];
        return;
    end
    
    % Check if channel locations are available
    if isempty(channel_locations)
        resultsText.Value = 'Channel locations not provided, cannot plot topography';
        return;
    end
    
    % Get power data
    power_data = EEGStats(subject_idx).power.(band);
    
    % Plot topography
    cla(plotArea);
    
    % New figure for topography (because uiaxes don't fully support topoplot)
    h = figure('Name', ['Topography - ', subjectDropdown.Value, ' - ', band], ...
        'Visible', 'off');
    topoplot(power_data, channel_locations, 'electrodes', 'on');
    colorbar;
    title(['Topography - ', subjectDropdown.Value, ' - ', band]);
    
    % Capture the figure as an image
    frame = getframe(h);
    close(h);
    
    % Display the captured image in the UI
    image(plotArea, frame.cdata);
    axis(plotArea, 'image');
    axis(plotArea, 'off');
    
    % Update results text
    resultsText.Value = ['Topography for subject ', subjectDropdown.Value, ...
        ', band ', band, ' displayed'];
end

function saveSelectedData()
    % Get selected subject, band, and event
    subject_idx = find(strcmp(subject_ids, subjectDropdown.Value));
    band = bandDropdown.Value;
    event = eventDropdown.Value;
    
    % Create output directory if it doesn't exist
    output_dir = fullfile(pwd, 'EEG_Results');
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    
    % Start with empty saved list for display
    saved_items = {};
    
    % Save power spectrum if selected
    if savePowerCheck.Value
        try
            if isfield(EEGStats(subject_idx).power, band)
                % Create new figure for saving
                h = figure('Visible', 'off');
                
                % Determine which channel to use
                channel_idx = find(strcmp(channel_names, channelDropdown.Value));
                
                % Get power data
                power_data = EEGStats(subject_idx).power.(band);
                
                % Get frequency axis if available
                freq_axis = [];
                if isfield(EEGStats(subject_idx).bands, band) && isfield(EEGStats(subject_idx).bands.(band), 'srate')
                    srate = EEGStats(subject_idx).bands.(band).srate;
                    freq_axis = linspace(0, srate/2, length(power_data));
                else
                    freq_axis = 1:length(power_data);
                end
                
                % Plot and save
                plot(freq_axis, power_data);
                title(['Power Spectrum - ', subjectDropdown.Value, ' - ', band, ' - ', channelDropdown.Value]);
                xlabel('Frequency (Hz)');
                ylabel('Power (dB)');
                grid on;
                
                % Save figure
                filename = fullfile(output_dir, ['Power_', subjectDropdown.Value, '_', band, '_', channelDropdown.Value, '.', figFormat]);
                saveas(h, filename);
                close(h);
                
                saved_items{end+1} = ['Power spectrum saved as ', filename];
            end
        catch e
            saved_items{end+1} = ['Error saving power spectrum: ', e.message];
        end
    end
    
    % Save ERP if selected
    if saveERPCheck.Value
        try
            if isfield(EEGStats(subject_idx), 'erp') && isfield(EEGStats(subject_idx).erp, event)
                % Create new figure for saving
                h = figure('Visible', 'off');
                
                % Determine which channel to use
                channel_idx = find(strcmp(channel_names, channelDropdown.Value));
                
                % Get ERP data
                erp_data = EEGStats(subject_idx).erp.(event);
                
                % Get time axis if available
                time_axis = [];
                if isfield(EEGStats(subject_idx), 'bands')
                    band_names = fieldnames(EEGStats(subject_idx).bands);
                    if ~isempty(band_names)
                        band_data = EEGStats(subject_idx).bands.(band_names{1});
                        if isfield(band_data, 'times')
                            time_axis = band_data.times;
                        elseif isfield(band_data, 'xmin') && isfield(band_data, 'xmax') && isfield(band_data, 'pnts')
                            time_axis = linspace(band_data.xmin * 1000, band_data.xmax * 1000, band_data.pnts);
                        end
                    end
                end
                
                if isempty(time_axis)
                    time_axis = 1:size(erp_data, 2);
                end
                
                % Plot and save
                plot(time_axis, erp_data(channel_idx, :));
                title(['ERP - ', subjectDropdown.Value, ' - Event: ', event, ' - ', channelDropdown.Value]);
                xlabel('Time (ms)');
                ylabel('Amplitude (µV)');
                grid on;
                
                % Add vertical line at time 0 if time_axis includes 0
                if min(time_axis) <= 0 && max(time_axis) >= 0
                    hold on;
                    plot([0 0], ylim, 'k--');
                    hold off;
                end
                
                % Save figure
                filename = fullfile(output_dir, ['ERP_', subjectDropdown.Value, '_', event, '_', channelDropdown.Value, '.', figFormat]);
                saveas(h, filename);
                close(h);
                
                saved_items{end+1} = ['ERP saved as ', filename];
            end
        catch e
            saved_items{end+1} = ['Error saving ERP: ', e.message];
        end
    end
    
    % Save connectivity if selected
    if saveConnectivityCheck.Value
        try
            if isfield(EEGStats(subject_idx), 'connectivity') && isfield(EEGStats(subject_idx).connectivity, band)
                % Create new figure for saving
                h = figure('Visible', 'off');
                
                % Get connectivity data - Handle the dccc field
                if isfield(EEGStats(subject_idx).connectivity.(band), 'dccc')
                    conn_data = EEGStats(subject_idx).connectivity.(band).dccc;
                else
                    conn_data = EEGStats(subject_idx).connectivity.(band);
                end
                
                % Handle 3D matrices
                if ndims(conn_data) == 3
                    % Use currently selected scale if available
                    if isfield(handles, 'scaleDropdown')
                        scale_idx = str2double(handles.scaleDropdown.Value);
                    else
                        scale_idx = size(conn_data, 3); % Default to largest scale
                    end
                    
                    % Extract 2D slice for visualization
                    conn_data_2d = conn_data(:,:,scale_idx);
                    
                    % Save scale information for filenames
                    scale_info = ['_scale', num2str(scale_idx)];
                    
                    % Plot 2D slice
                    imagesc(conn_data_2d);
                    colorbar;
                    colormap('jet');
                    axis square;
                    title(['Connectivity Matrix - ', subjectDropdown.Value, ' - ', band, ' - Scale ', num2str(scale_idx)]);
                    xlabel('Channel');
                    ylabel('Channel');
                    
                    % Save figure of 2D slice
                    filename = fullfile(output_dir, ['Connectivity_', subjectDropdown.Value, '_', band, scale_info, '.', figFormat]);
                    saveas(h, filename);
                    close(h);
                    
                    % Save 2D slice as CSV
                    csvname = fullfile(output_dir, ['Connectivity_', subjectDropdown.Value, '_', band, scale_info, '.csv']);
                    dlmwrite(csvname, conn_data_2d, 'delimiter', ',', 'precision', 10);
                    
                    % Save full 3D matrix as MAT file
                    matname = fullfile(output_dir, ['Connectivity3D_', subjectDropdown.Value, '_', band, '.mat']);
                    save(matname, 'conn_data');
                    
                    saved_items{end+1} = ['Connectivity matrix (scale ', num2str(scale_idx), ') saved as ', filename];
                    saved_items{end+1} = ['Full 3D connectivity data saved as ', matname];
                else
                    % Standard 2D matrix handling
                    imagesc(conn_data);
                    colorbar;
                    colormap('jet');
                    axis square;
                    title(['Connectivity Matrix - ', subjectDropdown.Value, ' - ', band]);
                    xlabel('Channel');
                    ylabel('Channel');
                    
                    % Save figure
                    filename = fullfile(output_dir, ['Connectivity_', subjectDropdown.Value, '_', band, '.', figFormat]);
                    saveas(h, filename);
                    close(h);
                    
                    % Save as CSV
                    csvname = fullfile(output_dir, ['Connectivity_', subjectDropdown.Value, '_', band, '.csv']);
                    dlmwrite(csvname, conn_data, 'delimiter', ',', 'precision', 10);
                    
                    saved_items{end+1} = ['Connectivity matrix saved as ', filename, ' and ', csvname];
                end
            else
                saved_items{end+1} = ['No connectivity data found for band ', band];
            end
        catch e
            saved_items{end+1} = ['Error saving connectivity: ', e.message];
        end
    end
    
    % Save time-frequency if selected
    if saveTimeFreqCheck.Value
        try
            if isfield(EEGStats(subject_idx), 'timefreq') && isfield(EEGStats(subject_idx).timefreq, event)
                % Create new figure for saving
                h = figure('Visible', 'off');
                
                % Determine which channel to use
                channel_idx = find(strcmp(channel_names, channelDropdown.Value));
                
                % Get time-frequency data
                tf_data = EEGStats(subject_idx).timefreq.(event);
                
                % Extract TF data for selected channel
                channel_tf = tf_data.power{channel_idx};
                
                % Plot and save
                imagesc(tf_data.times, tf_data.freqs, channel_tf);
                colorbar;
                colormap('jet');
                title(['Time-Frequency - ', subjectDropdown.Value, ' - Event: ', event, ' - ', channelDropdown.Value]);
                xlabel('Time (ms)');
                ylabel('Frequency (Hz)');
                
                % Add vertical line at time 0 if time axis includes 0
                if min(tf_data.times) <= 0 && max(tf_data.times) >= 0
                    hold on;
                    plot([0 0], ylim, 'k--');
                    hold off;
                end
                
                % Save figure
                filename = fullfile(output_dir, ['TimeFreq_', subjectDropdown.Value, '_', event, '_', channelDropdown.Value, '.', figFormat]);
                saveas(h, filename);
                close(h);
                
                saved_items{end+1} = ['Time-frequency plot saved as ', filename];
            end
        catch e
            saved_items{end+1} = ['Error saving time-frequency: ', e.message];
        end
    end
    
    % Update results text with saved items
    if isempty(saved_items)
        resultsText.Value = 'No data was saved. Check if data exists for the selected options.';
    else
        resultsText.Value = saved_items;
    end
end

function processAutomated(subject_indices, selected_bands, selected_events)
    % Process each subject
    for subj_idx = subject_indices
        subject_id = subject_ids{subj_idx};
        
        % Create subject directory
        subject_dir = fullfile(params.output_dir, sanitizeFilename(subject_id));
        if ~exist(subject_dir, 'dir')
            mkdir(subject_dir);
        end
        
        % Process power spectra
        if params.save_power
            for b = 1:length(selected_bands)
                band = selected_bands{b};
                if isfield(EEGStats(subj_idx).power, band)
                    % Process each channel or average
                    processPowerSpectrum(subj_idx, band, subject_dir);
                end
            end
        end
        
        % Process ERPs
        if params.save_erp
            for e = 1:length(selected_events)
                event = selected_events{e};
                if isfield(EEGStats(subj_idx), 'erp') && isfield(EEGStats(subj_idx).erp, event)
                    processERP(subj_idx, event, subject_dir);
                end
            end
        end
        
        % Process connectivity
        if params.save_connectivity
            for b = 1:length(selected_bands)
                band = selected_bands{b};
                if isfield(EEGStats(subj_idx), 'connectivity') && isfield(EEGStats(subj_idx).connectivity, band)
                    processConnectivity(subj_idx, band, subject_dir);
                end
            end
        end
        
        % Process time-frequency
        if params.save_timefreq
            for e = 1:length(selected_events)
                event = selected_events{e};
                if isfield(EEGStats(subj_idx), 'timefreq') && isfield(EEGStats(subj_idx).timefreq, event)
                    processTimeFrequency(subj_idx, event, subject_dir);
                end
            end
        end
    end
    
    disp('Automated processing completed successfully!');
end

    function processPowerSpectrum(subj_idx, band, output_dir)
    % Get power data
    power_data = EEGStats(subj_idx).power.(band);
    
    % Get stimulus info if available
    stimulus_info = '';
    if isfield(EEGStats(subj_idx), 'stimulus') && ~isempty(EEGStats(subj_idx).stimulus)
        stimulus_info = ['_' sanitizeFilename(EEGStats(subj_idx).stimulus)];
    end
    
    % Handle negative power values by ignoring them in calculations
    % Replace negative values with NaN so they won't affect our averages
    power_data_clean = power_data;
    power_data_clean(power_data_clean < 0) = NaN;
    
    % Calculate the AVERAGE of positive power across frequencies for each channel
    avg_power = nanmean(power_data_clean, 2);  % Average across frequency dimension, ignoring NaNs
    
    % In case all values for a channel were negative, replace NaNs with zeros
    avg_power(isnan(avg_power)) = 0;
    
    % BAR PLOT OF CHANNEL POWER AVERAGES
    h = figure('Visible', 'off');
    bar(avg_power, 'FaceColor', [0.3 0.6 0.9]);
    title(['Average Channel Power - ', subject_ids{subj_idx}, ' - ', band, stimulus_info]);
    xlabel('Channel');
    ylabel(['Mean Power in ', band, ' band']);
    grid on;
    set(gca, 'XTick', 1:length(avg_power), 'XTickLabel', 1:length(avg_power));
    
    % Add data values above bars
    for ap = 1:length(avg_power)
        text(ap, avg_power(ap) + max(avg_power)*0.02, num2str(avg_power(ap), '%.2f'), ...
             'HorizontalAlignment', 'center', 'FontSize', 8);
    end
    
    % Save the plot
    filename = fullfile(output_dir, ['PowerAvg_', sanitizeFilename(band), stimulus_info, '.', figFormat]);
    saveas(h, filename);
    close(h);
    
    % TOPOGRAPHIC MAP OF POWER AVERAGES (if channel locations available)
    if ~isempty(channel_locations)
        h2 = figure('Visible', 'off');
        topoplot(avg_power, channel_locations, 'electrodes', 'on');
        colorbar;
        title(['Power Distribution - ', subject_ids{subj_idx}, ' - ', band, stimulus_info]);
        
        % Save the map
        topo_filename = fullfile(output_dir, ['TopoAvg_', sanitizeFilename(band), stimulus_info, '.', figFormat]);
        saveas(h2, topo_filename);
        close(h2);
    end
    
    % OPTIONAL: Frequency plots for specific channels
    % Create a directory for frequency domain plots
    freq_dir = fullfile(output_dir, 'Frequency_Plots');
    if ~exist(freq_dir, 'dir')
        mkdir(freq_dir);
    end
    
    % Select top 3 channels with highest average power
    [~, top_channels] = sort(avg_power, 'descend');
    top_channels = top_channels(1:min(3, length(top_channels)));
    
    % Get frequency axis if available
    freq_axis = [];
    if isfield(EEGStats(subj_idx).bands, band) && isfield(EEGStats(subj_idx).bands.(band), 'srate')
        srate = EEGStats(subj_idx).bands.(band).srate;
        freq_axis = linspace(0, srate/2, size(power_data, 2));
    else
        freq_axis = 1:size(power_data, 2);
    end
    
    % Plot frequency domain for top channels
    for tc = 1:length(top_channels)
        ch = top_channels(tc);
        h3 = figure('Visible', 'off');
        
        % Plot only positive power values
        chan_power = power_data(ch, :);
        valid_freqs = freq_axis(chan_power >= 0);
        valid_power = chan_power(chan_power >= 0);
        
        if ~isempty(valid_power)
            plot(valid_freqs, valid_power, 'LineWidth', 1.5);
            title(['Frequency Domain - Channel ' num2str(ch) ' - ', subject_ids{subj_idx}, ' - ', band]);
            xlabel('Frequency (Hz)');
            ylabel('Power');
            grid on;
            
            % Save the plot
            freq_filename = fullfile(freq_dir, ['FreqDomain_Ch' num2str(ch) '_', sanitizeFilename(band), stimulus_info, '.', figFormat]);
            saveas(h3, freq_filename);
        end
        close(h3);
    end
    
    % CSV EXPORT OF POWER AVERAGES
    csvname = fullfile(output_dir, ['PowerAvg_', sanitizeFilename(band), stimulus_info, '.csv']);
    
    % Create header and data
    header = 'Channel,AveragePower';
    output_data = [(1:length(avg_power))', avg_power];
    
    % Write to file
    fid = fopen(csvname, 'w');
    fprintf(fid, '%s\n', header);
    fclose(fid);
    dlmwrite(csvname, output_data, 'delimiter', ',', 'precision', 10, '-append');
    
    disp(['Saved power visualization for ', subject_ids{subj_idx}, ...
          ', band ', band, stimulus_info]);
end
function processERP(subj_idx, event, output_dir)
    % Create new figure for saving
    h = figure('Visible', 'off');
    
    % Get ERP data
    erp_data = EEGStats(subj_idx).erp.(event);
    
    % Get time axis if available
    time_axis = [];
    if isfield(EEGStats(subj_idx), 'bands')
        band_names = fieldnames(EEGStats(subj_idx).bands);
        if ~isempty(band_names)
            band_data = EEGStats(subj_idx).bands.(band_names{1});
            if isfield(band_data, 'times')
                time_axis = band_data.times;
            elseif isfield(band_data, 'xmin') && isfield(band_data, 'xmax') && isfield(band_data, 'pnts')
                time_axis = linspace(band_data.xmin * 1000, band_data.xmax * 1000, size(erp_data, 2));
            end
        end
    end
    
    if isempty(time_axis)
        time_axis = 1:size(erp_data, 2);
    end
    
    % Plot all channels
    plot(time_axis, erp_data');
    title(['ERP - ', subject_ids{subj_idx}, ' - Event: ', event]);
    xlabel('Time (ms)');
    ylabel('Amplitude (µV)');
    grid on;
    
    % Add vertical line at time 0 if time_axis includes 0
    if min(time_axis) <= 0 && max(time_axis) >= 0
        hold on;
        plot([0 0], ylim, 'k--');
        hold off;
    end
    
    % Save figure
    filename = fullfile(output_dir, ['ERP_', sanitizeFilename(event), '.', figFormat]);
    saveas(h, filename);
    close(h);
    
    % Also save data as CSV
    csvname = fullfile(output_dir, ['ERP_', sanitizeFilename(event), '.csv']);
    dlmwrite(csvname, [time_axis(:), erp_data'], 'delimiter', ',', 'precision', 10);
    
    disp(['Saved ERP for ', subject_ids{subj_idx}, ', event ', event]);
end

    function processConnectivity(subj_idx, band, output_dir)
    % Get connectivity data
    if isfield(EEGStats(subj_idx).connectivity.(band), 'dccc')
        conn_data = EEGStats(subj_idx).connectivity.(band).dccc;
    else
        conn_data = EEGStats(subj_idx).connectivity.(band);
    end
    
    % Get stimulus info if available
    stimulus_info = '';
    if isfield(EEGStats(subj_idx), 'stimulus') && ~isempty(EEGStats(subj_idx).stimulus)
        stimulus_info = ['_' sanitizeFilename(EEGStats(subj_idx).stimulus)];
    end
    
    % Extract 2D connectivity matrix
    if ndims(conn_data) == 3
        scale_idx = size(conn_data, 3);
        conn_data_2d = conn_data(:,:,scale_idx);
        scale_info = ['_scale', num2str(scale_idx)];
    else
        conn_data_2d = conn_data;
        scale_info = '';
    end
    
    % Basic matrix visualization
    h = figure('Visible', 'off');
    imagesc(conn_data_2d);
    colorbar;
    colormap('jet');
    axis square;
    title(['Connectivity Matrix - ', subject_ids{subj_idx}, ' - ', band, scale_info, stimulus_info]);
    xlabel('Channel');
    ylabel('Channel');
    
    % Save basic matrix visualization
    filename = fullfile(output_dir, ['Connectivity_', sanitizeFilename(band), scale_info, stimulus_info, '.', figFormat]);
    saveas(h, filename);
    close(h);
    
    % Save data as CSV
    csvname = fullfile(output_dir, ['Connectivity_', sanitizeFilename(band), scale_info, stimulus_info, '.csv']);
    dlmwrite(csvname, conn_data_2d, 'delimiter', ',', 'precision', 10);
    
    % If 3D matrix, save as MAT file
    if ndims(conn_data) == 3
        matname = fullfile(output_dir, ['Connectivity3D_', sanitizeFilename(band), stimulus_info, '.mat']);
        save(matname, 'conn_data');
    end
    
    % Network visualization with improved edge display
    try
        h2 = figure('Visible', 'off');
        
        % Prepare connectivity matrix
        conn_vis = double(full(conn_data_2d));
        
        % Zero out diagonal
        for i = 1:size(conn_vis,1)
            conn_vis(i,i) = 0;
        end
        
        % IMPROVED THRESHOLDING:
        % Only keep strongest connections (top 15% of weights)
        all_values = conn_vis(:);
        all_values = all_values(all_values > 0);
        if ~isempty(all_values)
            thresh = prctile(all_values, 85); % Higher percentile = fewer connections
        else
            thresh = 0;
        end
        
        % Further limit maximum number of connections if needed
        conn_mask = conn_vis > thresh;
        num_connections = sum(conn_mask(:));
        max_connections = 30; % Adjust based on your visualization needs
        
        if num_connections > max_connections
            % Sort all connections by strength and keep only the top ones
            [sorted_values, sorted_idx] = sort(conn_vis(:), 'descend');
            conn_mask = false(size(conn_vis));
            for i = 1:min(max_connections, sum(sorted_values > 0))
                [row, col] = ind2sub(size(conn_vis), sorted_idx(i));
                conn_mask(row, col) = true;
            end
        end
        
        % Find indices and extract weights
        [sourceNodes, targetNodes] = find(conn_mask);
        weights = zeros(length(sourceNodes), 1);
        for i = 1:length(sourceNodes)
            weights(i) = conn_vis(sourceNodes(i), targetNodes(i));
        end
        
        % If we have valid weights, create topographic connectivity plot
        if ~isempty(weights) && all(isfinite(weights)) && ~issparse(weights)
            % Create graph
            G = graph(sourceNodes, targetNodes, weights);
            
            % Get unique nodes in the graph (important: might not include all channels)
            uniqueNodes = unique([sourceNodes; targetNodes]);
            num_graph_nodes = length(uniqueNodes);
            
            % Total number of channels
            num_channels = size(conn_vis, 1);
            
            % Create mapping from original channel indices to graph node indices
            node_mapping = zeros(num_channels, 1);
            for i = 1:length(uniqueNodes)
                node_mapping(uniqueNodes(i)) = i;
            end
            
            % Initialize node positions for the GRAPH nodes
            nodeX = zeros(num_graph_nodes, 1);
            nodeY = zeros(num_graph_nodes, 1);
            
            % Initialize channel labels for the GRAPH nodes
            graph_channel_labels = cell(num_graph_nodes, 1);
            
            % Check if we have valid channel_locations
            if isstruct(channel_locations) && length(channel_locations) >= num_channels
                % Extract X, Y coordinates and labels for the nodes IN THE GRAPH
                for i = 1:length(uniqueNodes)
                    chan_idx = uniqueNodes(i);
                    
                    if isfield(channel_locations(chan_idx), 'X') && isfield(channel_locations(chan_idx), 'Y')
                        nodeX(i) = channel_locations(chan_idx).X;
                        nodeY(i) = channel_locations(chan_idx).Y;
                    elseif isfield(channel_locations(chan_idx), 'theta') && isfield(channel_locations(chan_idx), 'radius')
                        % Convert polar to cartesian
                        theta_rad = channel_locations(chan_idx).theta * pi/180;
                        nodeX(i) = channel_locations(chan_idx).radius * cos(theta_rad);
                        nodeY(i) = channel_locations(chan_idx).radius * sin(theta_rad);
                    end
                    
                    if isfield(channel_locations(chan_idx), 'labels')
                        graph_channel_labels{i} = channel_locations(chan_idx).labels;
                    else
                        graph_channel_labels{i} = num2str(chan_idx);
                    end
                end
            else
                % Generate circular layout as fallback
                angles = linspace(0, 2*pi, num_graph_nodes+1);
                angles = angles(1:end-1);
                nodeX = cos(angles);
                nodeY = sin(angles);
                
                % Generate labels for fallback
                for i = 1:num_graph_nodes
                    graph_channel_labels{i} = num2str(uniqueNodes(i));
                end
            end
            
            % Create an edge list with remapped indices to match the graph node order
            edgeSourceIdx = zeros(length(sourceNodes), 1);
            edgeTargetIdx = zeros(length(targetNodes), 1);
            
            for i = 1:length(sourceNodes)
                edgeSourceIdx(i) = node_mapping(sourceNodes(i));
                edgeTargetIdx(i) = node_mapping(targetNodes(i));
            end
            
            % Normalize weights for coloring
            if max(weights) > min(weights)
                norm_weights = (weights - min(weights)) / (max(weights) - min(weights));
            else
                norm_weights = ones(size(weights));
            end
            
            % IMPROVED EDGE VISUALIZATION:
            % Directly plot the graph with manual node and edge specifications
            hold on;
            
            % First, plot all nodes
            scatter(nodeX, nodeY, 100, 'filled', 'MarkerFaceColor', 'blue');
            
            % Then plot all edges with colors based on weight
            colormap(jet);
            cmap = colormap;
            
            % Draw edges manually instead of using graph plot
            for i = 1:length(weights)
                srcIdx = edgeSourceIdx(i);
                tgtIdx = edgeTargetIdx(i);
                
                % Get color index based on normalized weight
                colorIdx = max(1, min(size(cmap, 1), round(norm_weights(i) * (size(cmap, 1)-1) + 1)));
                edgeColor = cmap(colorIdx, :);
                
                % Draw the edge
                line([nodeX(srcIdx), nodeX(tgtIdx)], [nodeY(srcIdx), nodeY(tgtIdx)], ...
                     'Color', edgeColor, 'LineWidth', 2.5);
            end
            
            % Add node labels
            for i = 1:num_graph_nodes
                text(nodeX(i), nodeY(i), graph_channel_labels{i}, ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                     'FontWeight', 'bold', 'Color', 'white', 'FontSize', 8);
            end
            
            % Add colorbar
            colorbar('Ticks', [0, 0.25, 0.5, 0.75, 1], ...
                    'TickLabels', {'Weakest', '', 'Medium', '', 'Strongest'});
            
            % Draw a head outline
            th = linspace(0, 2*pi, 100);
            radius = 1.1 * max(sqrt(nodeX.^2 + nodeY.^2));
            plot(radius * cos(th), radius * sin(th), 'k-', 'LineWidth', 2);
            
            % Add nose and ears for orientation
            % Nose at top (0 degrees)
            plot([0, 0], [radius, 1.15*radius], 'k-', 'LineWidth', 2);
            % Left ear
            ear_angle = pi/2;
            ear_x = [radius*cos(ear_angle), 1.15*radius*cos(ear_angle)];
            ear_y = [radius*sin(ear_angle), 1.15*radius*sin(ear_angle)];
            plot(ear_x, ear_y, 'k-', 'LineWidth', 2);
            % Right ear
            ear_angle = -pi/2;
            ear_x = [radius*cos(ear_angle), 1.15*radius*cos(ear_angle)];
            ear_y = [radius*sin(ear_angle), 1.15*radius*sin(ear_angle)];
            plot(ear_x, ear_y, 'k-', 'LineWidth', 2);
            
            hold off;
            axis equal;
            axis off;
            
            title(['Brain Connectivity - ', subject_ids{subj_idx}, ' - ', band, stimulus_info]);
        else
            % Fallback visualization if needed
            spy(conn_mask, 'k', 10);
            title(['Connectivity (Adjacency) - ', subject_ids{subj_idx}, ' - ', band, stimulus_info]);
            xlabel('Channel');
            ylabel('Channel');
        end
        
        % Save network visualization
        netname = fullfile(output_dir, ['BrainNetwork_', sanitizeFilename(band), scale_info, stimulus_info, '.', figFormat]);
        saveas(h2, netname);
        close(h2);
        
    catch e
        disp(['Connectivity visualization error: ', e.message]);
        disp(getReport(e, 'extended'));
        
        % Create a simpler fallback visualization in case of error
        try
            h3 = figure('Visible', 'off');
            imagesc(conn_vis > thresh);
            colormap([1 1 1; 0 0 0]); % Black and white
            title(['Connectivity Fallback - ', subject_ids{subj_idx}, ' - ', band, stimulus_info]);
            xlabel('Channel');
            ylabel('Channel');
            axis square;
            
            % Save fallback visualization
            fallback_name = fullfile(output_dir, ['ConnFallback_', sanitizeFilename(band), scale_info, stimulus_info, '.', figFormat]);
            saveas(h3, fallback_name);
            close(h3);
            disp(['Created fallback visualization: ', fallback_name]);
        catch
            disp('Even fallback visualization failed');
        end
    end
end
    

function processTimeFrequency(subj_idx, event, output_dir)
    % Get time-frequency data
    tf_data = EEGStats(subj_idx).timefreq.(event);
    
    % Process each channel
    for ch = 1:length(tf_data.power)
        % Create new figure for saving
        h = figure('Visible', 'off');
        
        % Extract TF data for current channel
        channel_tf = tf_data.power{ch};
        
        % Plot and save
        imagesc(tf_data.times, tf_data.freqs, channel_tf);
        colorbar;
        colormap('jet');
        title(['Time-Frequency - ', subject_ids{subj_idx}, ' - Event: ', event, ' - Channel ', num2str(ch)]);
        xlabel('Time (ms)');
        ylabel('Frequency (Hz)');
        
        % Add vertical line at time 0 if time axis includes 0
        if min(tf_data.times) <= 0 && max(tf_data.times) >= 0
            hold on;
            plot([0 0], ylim, 'k--');
            hold off;
        end
        
        % Save figure
        filename = fullfile(output_dir, ['TimeFreq_', sanitizeFilename(event), '_Ch', num2str(ch), '.', figFormat]);
        saveas(h, filename);
        close(h);
        
        % For efficiency, only save CSV for first channel
        if ch == 1
            % Save times and freqs
            timesname = fullfile(output_dir, ['TimeFreq_', sanitizeFilename(event), '_times.csv']);
            dlmwrite(timesname, tf_data.times, 'delimiter', ',', 'precision', 10);
            
            freqsname = fullfile(output_dir, ['TimeFreq_', sanitizeFilename(event), '_freqs.csv']);
            dlmwrite(freqsname, tf_data.freqs, 'delimiter', ',', 'precision', 10);
        end
        
        % Save TF data as CSV
        csvname = fullfile(output_dir, ['TimeFreq_', sanitizeFilename(event), '_Ch', num2str(ch), '.csv']);
        dlmwrite(csvname, channel_tf, 'delimiter', ',', 'precision', 10);
    end
    
    disp(['Saved time-frequency data for ', subject_ids{subj_idx}, ', event ', event]);
end

function filename = sanitizeFilename(name)
    % Convert a string to a valid filename
    % Remove spaces and special characters
    filename = regexprep(name, '[^a-zA-Z0-9]', '_');
end

end