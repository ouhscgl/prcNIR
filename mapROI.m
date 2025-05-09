function mapROI(data, selected_indices, save_path)
% Accepts data_raws, data_stat

%% Parameters _____________________________________________________________
% -- sources
sources   = data.optodes(strcmp(data.optodes.Type,    'Source'), :);
source_x   =   sources.X; source_y   =   sources.Y;
% -- detectors
detectors = data.optodes(strcmp(data.optodes.Type,  'Detector'), :);
detector_x = detectors.X; detector_y = detectors.Y;
% -- landmarks
landmarks = data.optodes(strcmp(data.optodes.Type, 'FID-anchor'), :);
landmark_x = landmarks.X; landmark_y = landmarks.Y;
% -- links
u = unique(data.link.type); u = u(1);
if ischar(u) || iscell(u) || isstring(u), mask = strcmp(data.link.type, u);
else, mask = (data.link.type == u); end
links = data.link; 
if ~isempty(selected_indices), links_csv = links(selected_indices, :);  end
% -- display figure
h = figure('Position', [100, 100, 800, 600], 'Color','white'); hold on;
set(h,'MenuBar','none','ToolBar','none')
% _________________________________________________________________________
%% Plotting midpoints  ____________________________________________________
mid_x = zeros(height(links),1); mid_y = zeros(height(links),1); 
midpoint_labels = cell(height(links),1);
% .. iterate through links
for i = 1:height(links)
if ~mask(i), continue, end
% -- midpoint values
mid_x(i) = (source_x(links.source(i)) + detector_x(links.detector(i))) / 2;
mid_y(i) = (source_y(links.source(i)) + detector_y(links.detector(i))) / 2;
% -- midpoint labels
midpoint_labels{i} = sprintf('S%d-D%d', links.source(i),links.detector(i));
% -- graph source - detector connection
plot([source_x(links.source(i)), detector_x(links.detector(i))], ...
     [source_y(links.source(i)), detector_y(links.detector(i))], ...
     'k--', 'LineWidth', 0.5);
end
% _________________________________________________________________________
%% Highlighting selected regions __________________________________________
sel_x = mid_x(selected_indices); sel_y = mid_y(selected_indices);

% -- blob highlight for many datapoints
if length(selected_indices) >= 3
% >> blob variables
k = convhull(sel_x, sel_y); hull_x = sel_x(k); hull_y = sel_y(k);
centroid_x = mean(hull_x); centroid_y = mean(hull_y);
% >> padding
padding_factor = 1.2; % Adjust this to control the blob size
expanded_hull_x = centroid_x + (hull_x - centroid_x) * padding_factor;
expanded_hull_y = centroid_y + (hull_y - centroid_y) * padding_factor;
% >> create blob & settings
pgon = polyshape(expanded_hull_x, expanded_hull_y);
pg = plot(pgon);
pg.FaceColor = [0.8 0.2 0.2];
pg.FaceAlpha = 0.2;
pg.EdgeColor = [0.8 0.2 0.2];
pg.LineWidth = 2;

% -- ellipsoid highlight for 2 points
elseif length(selected_indices) == 2
% >> ellipse parameters
cen_x = mean(sel_x); cen_y = mean(sel_y);
dist = sqrt((sel_x(1) - sel_x(2))^2 + (sel_y(1) - sel_y(2))^2);
a = dist * 0.75; b = dist * 0.5; theta = linspace(0, 2*pi, 100);
ellipse_x = cen_x + a * cos(theta); ellipse_y = cen_y + b * sin(theta);
% >> create ellipse    
fill(ellipse_x, ellipse_y, [0.8 0.2 0.2], 'FaceAlpha', 0.2, ...
     'EdgeColor', [0.8 0.2 0.2], 'LineWidth', 2);

% -- circular highlight for single point    
elseif isscalar(selected_indices)
% >> circle parameters
theta = linspace(0, 2*pi, 100);
cen_x = sel_x; cen_y = sel_y; radius = 0.1;
cir_x = cen_x + radius * cos(theta); cir_y = cen_y + radius * sin(theta);
% >> create circle
fill(cir_x, cir_y, [0.8 0.2 0.2], 'FaceAlpha', 0.2, ...
     'EdgeColor', [0.8 0.2 0.2], 'LineWidth', 2);
end
% _________________________________________________________________________
%% Plotting sources  ______________________________________________________
% -- values
scatter(source_x, source_y, 100, 'r', 'filled');
% -- labels
for i = 1:length(source_x)
    text(source_x(i), source_y(i), ...
         sprintf(' S%d', i), 'FontSize', 10, 'VerticalAlignment','bottom');
end
% _________________________________________________________________________
%% Plotting detectors _____________________________________________________
% -- values
scatter(detector_x, detector_y, 100, 'b', 'filled');
% -- labels
for i = 1:length(detector_x)
    text(detector_x(i), detector_y(i)-0.02, ...
         sprintf(' D%d', i), 'FontSize', 10, 'VerticalAlignment','bottom');
end
% _________________________________________________________________________
%% Plotting midpoints _____________________________________________________
% -- unselected values
scatter(mid_x, mid_y, ...
        50, 'g', 'filled');
% -- selected values
scatter(mid_x(selected_indices), mid_y(selected_indices), ...
        80, 'r', 'filled');
% -- labels
for i = 1:length(mid_x)
    text(mid_x(i), mid_y(i), ...
         sprintf(' %s', num2str(i)), 'FontSize', 8, ...
         'VerticalAlignment', 'bottom');
end
scatter(0, 0, 600, 'k', 'filled');
% _________________________________________________________________________
%% Plotting landmarks _____________________________________________________
% -- values
scatter(landmark_x, landmark_y, 60, 'k', 'filled');
% -- labels
for i = 1:length(landmark_x)
    text(landmark_x(i)-0.04, landmark_y(i)-0.04, ...
         sprintf(' %s', landmarks.Name{i}), 'FontSize', 10, ...
         'VerticalAlignment', 'bottom');
end
% _________________________________________________________________________
%% Formatting figure ______________________________________________________
% -- legend
% legend({'Region of Interest', 'Sources', 'Detectors', 'Channels', ...
%         'Selected Channels', 'Landmarks'}, 'Location', 'best');
% -- axis labels, scaling, grid
title('fNIRS Probe Configuration'); axis equal; grid on; axis off;
% -- padding
ax = gca;
ax.XLim = [min([source_x; detector_x; landmark_x])*1.1, ...
           max([source_x; detector_x; landmark_x])*1.1];
ax.YLim = [min([source_y; detector_y; landmark_y])*1.1, ...
           max([source_y; detector_y; landmark_y])*1.1];
hold off;
% _________________________________________________________________________
%% Save variables _________________________________________________________
if isempty(save_path), return, end
writetable(links_csv,fullfile(save_path,'beta_ROI.csv'))
saveas    (h,        fullfile(save_path,'beta_ROI.png'))
% _________________________________________________________________________
end