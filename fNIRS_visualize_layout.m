function fNIRS_visualize_layout(json_file)
% VISUALIZE_NIRS_LAYOUT  Create a universal visualization of NIRS optode layout
%   This function loads a JSON file containing NIRS probe data and creates a
%   standardized visualization of the source, detector, and channel layout.
%   Works with both newer and older format NIRx data.
%
%   Example:
%       visualize_nirs_layout('data_new.json')
%       visualize_nirs_layout('data_old.json')

% Load the JSON file
%jsonData = jsonencode(json_file, PrettyPrint=true);
%jsonData = jsondecode(fileread(json_file));
jsonData = json_file;

% Determine if old or new format based on source naming pattern
if istable(jsonData.optodes_registered)
    % Convert table to struct array for consistent processing
    optodes = table2struct(jsonData.optodes_registered);
    num_optodes = height(jsonData.optodes_registered);
else
    % Already a struct array
    optodes = jsonData.optodes_registered;
    num_optodes = length(jsonData.optodes_registered);
end

% Determine if old or new format based on source naming pattern
first_source = '';
for i = 1:num_optodes
    if contains(optodes(i).Type, 'Source')
        first_source = optodes(i).Name;
        break;
    end
end

% Check format based on naming pattern
isOldFormat = contains(first_source, '-0');

% Check format based on naming pattern
isOldFormat = contains(first_source, '-0');

% Extract data for plotting
data = struct();
data.Name = {jsonData.optodes_registered.Name}';
data.Type = {jsonData.optodes_registered.Type}';
data.X = [jsonData.optodes_registered.X]';
data.Y = [jsonData.optodes_registered.Y]';
data.Z = [jsonData.optodes_registered.Z]';

% Set up the links - handle both formats
links = jsonData.link;

% Pre-determine the bounds of source-detector cloud for scaling
sd_indices = contains(data.Type, 'Source') | contains(data.Type, 'Detector');
sd_x_values = data.X(sd_indices);
sd_y_values = data.Y(sd_indices);
x_min = min(sd_x_values) - 20;
x_max = max(sd_x_values) + 20;
y_min = min(sd_y_values) - 20;
y_max = max(sd_y_values) + 20;

% Track source and detector positions for legend
source_h = [];
detector_h = [];
landmark_h = [];
midpoint_h = [];

figure('Position', [100, 100, 1000, 800]);
hold on;

% Loop through the data points
for i = 1:length(data.Name)
    % Set color and properties based on the type
    if contains(data.Type{i}, 'Source')
        color = 'r'; % Red for sources
        marker = 'o';
        markerSize = 12;
        lineWidth = 2;
        fontWeight = 'bold';
        fontSize = 11;
        
        % Plot the point
        h = plot(data.X(i), data.Y(i), [marker, color], 'MarkerSize', markerSize, 'LineWidth', lineWidth, 'MarkerFaceColor', color);
        if isempty(source_h)
            source_h = h;
        end
        
        % Add label with the name
        text(data.X(i)+2, data.Y(i), data.Name{i}, 'FontSize', fontSize, 'FontWeight', fontWeight, 'Color', 'r');
        
    elseif contains(data.Type{i}, 'Detector')
        color = 'b'; % Blue for detectors
        marker = 's';
        markerSize = 12;
        lineWidth = 2;
        fontWeight = 'bold';
        fontSize = 11;
        
        % Plot the point
        h = plot(data.X(i), data.Y(i), [marker, color], 'MarkerSize', markerSize, 'LineWidth', lineWidth, 'MarkerFaceColor', color);
        if isempty(detector_h)
            detector_h = h;
        end
        
        % Add label with the name
        text(data.X(i)+2, data.Y(i), data.Name{i}, 'FontSize', fontSize, 'FontWeight', fontWeight, 'Color', 'b');
        
    else
        % Landmarks with transparency
        color = [0.5 0.5 0.5]; % Gray for landmarks
        marker = '.';
        markerSize = 6;
        
        % Check if landmark is within the source-detector cloud bounds
        if data.X(i) >= x_min && data.X(i) <= x_max && data.Y(i) >= y_min && data.Y(i) <= y_max
            % Plot the point with transparency
            h = plot(data.X(i), data.Y(i), marker, 'MarkerSize', markerSize, 'Color', [color 0.3]); % Alpha = 0.3
            if isempty(landmark_h)
                landmark_h = h;
            end
            
            % Add smaller label with transparency (only for landmarks within frame)
            text(data.X(i)+1, data.Y(i), data.Name{i}, 'FontSize', 6, 'Color', [color 0.3]);
        end
    end
end

% Define recommended source-detector pairs based on format
if isOldFormat
    dlPFC_pairs = {
        {'Source-0004', 'Detector-0002'}, % Left dlPFC
        {'Source-0011', 'Detector-0010'} % Right dlPFC
    };
    
    PFC_pairs = {
        {'Source-0003', 'Detector-0001'}, % Left PFC
        {'Source-0010', 'Detector-0009'} % Right PFC
    };
else
    dlPFC_pairs = {
        {'Source-4', 'Detector-2'}, % Left dlPFC
        {'Source-11', 'Detector-10'} % Right dlPFC
    };
    
    PFC_pairs = {
        {'Source-3', 'Detector-1'}, % Left PFC
        {'Source-10', 'Detector-9'} % Right PFC
    };
end

% Highlight recommended pairs
highlightPairs(data, dlPFC_pairs, [1 0.4 0.4], 'dlPFC Pairs');
highlightPairs(data, PFC_pairs, [0.4 0.4 1], 'PFC Pairs');

% Plot midpoints from the .probe.link file
midpoint_total_x = 0;
midpoint_total_y = 0;
midpoint_count = 0;

% Create a universal matching approach based on the JSON format
for i = 1:length(links)
    % Get source and detector indices 
    source_idx = links(i).source;
    detector_idx = links(i).detector;
    
    % Convert indices to names based on the data format
    if isOldFormat
        source_name = sprintf('Source-%04d', source_idx);
        detector_name = sprintf('Detector-%04d', detector_idx);
    else
        source_name = sprintf('Source-%d', source_idx);
        detector_name = sprintf('Detector-%d', detector_idx);
    end
    
    % Only process the first wavelength type if multiple exist
    if i > 1 && links(i).type ~= links(1).type
        continue;
    end
    
    % Find coordinates
    source_idx_in_data = find(strcmp(data.Name, source_name));
    detector_idx_in_data = find(strcmp(data.Name, detector_name));
    
    if ~isempty(source_idx_in_data) && ~isempty(detector_idx_in_data)
        source_x = data.X(source_idx_in_data(1));
        source_y = data.Y(source_idx_in_data(1));
        detector_x = data.X(detector_idx_in_data(1));
        detector_y = data.Y(detector_idx_in_data(1));
        
        % Calculate midpoint
        mid_x = (source_x + detector_x)/2;
        mid_y = (source_y + detector_y)/2;
        
        % Plot midpoint in black
        h = plot(mid_x, mid_y, 'ko', 'MarkerSize', 6, 'MarkerFaceColor', 'k');
        if isempty(midpoint_h)
            midpoint_h = h;
        end
        
        % Add channel number label
        text(mid_x, mid_y+1, num2str(i), 'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', 'k');
        
        % Add a light gray line connecting source and detector
        plot([source_x, detector_x], [source_y, detector_y], '-', 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5);
        
        % Add to totals for centroid calculation
        midpoint_total_x = midpoint_total_x + mid_x;
        midpoint_total_y = midpoint_total_y + mid_y;
        midpoint_count = midpoint_count + 1;
    end
end

% Calculate and plot the centroid of all midpoints
if midpoint_count > 0
    centroid_x = midpoint_total_x / midpoint_count;
    centroid_y = midpoint_total_y / midpoint_count;
    
    plot(centroid_x, centroid_y, 'kp', 'MarkerSize', 14, 'MarkerFaceColor', 'y', 'LineWidth', 2);
    text(centroid_x, centroid_y+5, 'Centroid', 'FontSize', 10, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
end

% Set axis to focus on source-detector cloud
axis([x_min x_max y_min y_max]);

% Create legend with necessary handles
legend_entries = {};
legend_handles = [];

if ~isempty(source_h)
    legend_entries{end+1} = 'Sources';
    legend_handles(end+1) = source_h;
end

if ~isempty(detector_h)
    legend_entries{end+1} = 'Detectors';
    legend_handles(end+1) = detector_h;
end

if ~isempty(landmark_h)
    legend_entries{end+1} = 'Landmarks';
    legend_handles(end+1) = landmark_h;
end

if ~isempty(midpoint_h)
    legend_entries{end+1} = 'Channel Midpoints';
    legend_handles(end+1) = midpoint_h;
end

if ~isempty(legend_handles)
    legend(legend_handles, legend_entries, 'Location', 'Best');
end

xlabel('X Coordinate (mm)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Y Coordinate (mm)', 'FontSize', 12, 'FontWeight', 'bold');
title(['Source and Detector Positions - ' strrep(json_file, '.json', '')], 'FontSize', 14, 'FontWeight', 'bold');
grid on;
axis equal;

% Add a head outline that matches the source-detector cloud scale
theta = linspace(0, 2*pi, 100);
head_radius = max(max(abs(sd_x_values)), max(abs(sd_y_values))) * 1.2;
head_x = head_radius * cos(theta);
head_y = head_radius * sin(theta);
plot(head_x, head_y, 'k--', 'LineWidth', 1);

% Add a figure title with information about the montage
annotation('textbox', [0.1, 0.01, 0.8, 0.05], 'String', ...
    'Recommended pairs shown: Left dlPFC, Right dlPFC, Left PFC, Right PFC', ...
    'HorizontalAlignment', 'center', 'FontSize', 10, 'LineStyle', 'none');

hold off;

% Create filename for saved figure
[~, fname, ~] = fileparts(json_file);
saveas(gcf, [fname '_layout.png']);
fprintf('Figure saved as %s_layout.png\n', fname);

end

% Nested function to highlight recommended pairs
function highlightPairs(data, pairs, color, pairLabel)
    for p = 1:length(pairs)
        sourceName = pairs{p}{1};
        detectorName = pairs{p}{2};
        
        % Find coordinates
        source_idx = find(strcmp(data.Name, sourceName));
        detector_idx = find(strcmp(data.Name, detectorName));
        
        if ~isempty(source_idx) && ~isempty(detector_idx)
            source_x = data.X(source_idx(1));
            source_y = data.Y(source_idx(1));
            detector_x = data.X(detector_idx(1));
            detector_y = data.Y(detector_idx(1));
            
            % Draw connecting line
            plot([source_x, detector_x], [source_y, detector_y], '-', 'Color', color, 'LineWidth', 2);
            
            % Add midpoint label with distance
            mid_x = (source_x + detector_x)/2;
            mid_y = (source_y + detector_y)/2;
            distance = sqrt((source_x - detector_x)^2 + (source_y - detector_y)^2);
            
            text(mid_x, mid_y+3, sprintf('%s: %.1f mm', pairLabel, distance), ...
                'FontSize', 8, 'HorizontalAlignment', 'center', 'BackgroundColor', [1 1 1 0.7]);
        end
    end
end