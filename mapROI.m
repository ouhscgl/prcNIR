data = data_raws(1);
selected_indices = [ 1	 2	 4	 5	 6	 7	 8 	 9	10	11	12	13	...
                    14	15	16	17	18	19	20	21	23	24];


sources   = data.probe.optodes(strcmp(data_raws(1).probe.optodes.Type,...
                                    'Source'), :);
detectors = data.probe.optodes(strcmp(data_raws(1).probe.optodes.Type,...
                                    'Detector'), :);
landmarks = data.probe.optodes(strcmp(data_raws(1).probe.optodes.Type,...
                                    'FID-anchor'), :);
links = data.probe.link(1:height(data.probe.link)/2,:);
source_x = sources.X;
source_y = sources.Y;
detector_x = detectors.X;
detector_y = detectors.Y;
landmark_x = landmarks.X;
landmark_y = landmarks.Y;

% Create a new figure with a specified size
figure('Position', [100, 100, 800, 600]);
hold on;

% Calculate all midpoints between linked sources and detectors
midpoint_x = [];
midpoint_y = [];
midpoint_labels = [];

for i = 1:height(links)
    source_idx = links.source(i);
    detector_idx = links.detector(i);
    
    % Calculate midpoint
    mid_x = (source_x(source_idx) + detector_x(detector_idx)) / 2;
    mid_y = (source_y(source_idx) + detector_y(detector_idx)) / 2;
    
    midpoint_x = [midpoint_x; mid_x];
    midpoint_y = [midpoint_y; mid_y];
    midpoint_labels{i} = sprintf('S%d-D%d', source_idx, detector_idx);
    
    % Draw a line connecting source and detector
    plot([source_x(source_idx), detector_x(detector_idx)], [source_y(source_idx), detector_y(detector_idx)], 'k--', 'LineWidth', 0.5);
end

% ---- HIGHLIGHT SELECTED REGION ----
% Extract coordinates of selected midpoints
selected_x = midpoint_x(selected_indices);
selected_y = midpoint_y(selected_indices);

% Create a blob (convex hull with padding) around selected points
if length(selected_indices) >= 3
    % Create convex hull of selected points
    k = convhull(selected_x, selected_y);
    
    % Add some padding to the hull to make it "blobby"
    hull_x = selected_x(k);
    hull_y = selected_y(k);
    
    % Calculate centroid of the hull
    centroid_x = mean(hull_x);
    centroid_y = mean(hull_y);
    
    % Expand points outward from centroid for padding
    padding_factor = 1.2; % Adjust this to control the blob size
    expanded_hull_x = centroid_x + (hull_x - centroid_x) * padding_factor;
    expanded_hull_y = centroid_y + (hull_y - centroid_y) * padding_factor;
    
    % Create a smooth blob using a filled polygon with alpha transparency
    pgon = polyshape(expanded_hull_x, expanded_hull_y);
    
    % Plot the smooth blob with semi-transparency
    pg = plot(pgon);
    pg.FaceColor = [0.8 0.2 0.2]; % Red blob
    pg.FaceAlpha = 0.2;          % 20% opacity
    pg.EdgeColor = [0.8 0.2 0.2]; % Red edge
    pg.LineWidth = 2;             % Thicker edge
    
elseif length(selected_indices) == 2
    % For only 2 points, create an ellipse around them
    center_x = mean(selected_x);
    center_y = mean(selected_y);
    
    % Calculate distance between points and use it for ellipse size
    dist = sqrt((selected_x(1) - selected_x(2))^2 + (selected_y(1) - selected_y(2))^2);
    a = dist * 0.75; % Semi-major axis
    b = dist * 0.5;  % Semi-minor axis
    
    % Create ellipse points
    theta = linspace(0, 2*pi, 100);
    ellipse_x = center_x + a * cos(theta);
    ellipse_y = center_y + b * sin(theta);
    
    % Plot filled ellipse
    fill(ellipse_x, ellipse_y, [0.8 0.2 0.2], 'FaceAlpha', 0.2, 'EdgeColor', [0.8 0.2 0.2], 'LineWidth', 2);
    
elseif length(selected_indices) == 1
    % For a single point, create a circle around it
    center_x = selected_x;
    center_y = selected_y;
    radius = 0.1; % Adjust based on your coordinate scale
    
    % Create circle points
    theta = linspace(0, 2*pi, 100);
    circle_x = center_x + radius * cos(theta);
    circle_y = center_y + radius * sin(theta);
    
    % Plot filled circle
    fill(circle_x, circle_y, [0.8 0.2 0.2], 'FaceAlpha', 0.2, 'EdgeColor', [0.8 0.2 0.2], 'LineWidth', 2);
end

% Plot sources (red)
scatter(source_x, source_y, 100, 'r', 'filled');
% Add source labels (indices)
for i = 1:length(source_x)
    text(source_x(i), source_y(i), sprintf(' S%d', i), 'FontSize', 10, 'VerticalAlignment', 'bottom');
end

% Plot detectors (blue)
scatter(detector_x, detector_y, 100, 'b', 'filled');
% Add detector labels (indices)
for i = 1:length(detector_x)
    text(detector_x(i), detector_y(i), sprintf(' D%d', i), 'FontSize', 10, 'VerticalAlignment', 'bottom');
end

% Plot all midpoints
scatter(midpoint_x, midpoint_y, 50, 'g', 'filled');

% Highlight selected midpoints with a different color and size
scatter(midpoint_x(selected_indices), midpoint_y(selected_indices), 80, 'r', 'filled');

% Add midpoint labels
for i = 1:length(midpoint_x)
    text(midpoint_x(i), midpoint_y(i), sprintf(' %s', num2str(i)), 'FontSize', 8, 'VerticalAlignment', 'bottom');
end

% Plot landmarks (black)
scatter(landmark_x, landmark_y, 60, 'k', 'filled');
% Add landmark labels (Names)
for i = 1:length(landmark_x)
    text(landmark_x(i)-0.04, landmark_y(i)-0.04, sprintf(' %s', landmarks.Name{i}), 'FontSize', 10, 'VerticalAlignment', 'bottom');
end

% Add a legend
legend({'Region of Interest', 'Sources', 'Detectors', 'Channels', 'Selected Channels', 'Landmarks'}, 'Location', 'best');

% Set axis labels
xlabel('X Coordinate');
ylabel('Y Coordinate');
title('fNIRS Probe Configuration');

% Set equal axis scaling and add grid
axis equal;
grid on;

% Add some padding around the plots
ax = gca;
ax.XLim = [min([source_x; detector_x; landmark_x])*1.1, max([source_x; detector_x; landmark_x])*1.1];
ax.YLim = [min([source_y; detector_y; landmark_y])*1.1, max([source_y; detector_y; landmark_y])*1.1];

hold off;