function visualizeFnirsProbe(probe)
% -- re-define variables
[srcPos, detPos, links] = deal(probe.srcPos, probe.detPos, probe.link);

% -- simple project to 2D (REDO LATER)
srcPos2D = srcPos(:, 1:2); detPos2D = detPos(:, 1:2);

% -- create figure
figure('Position', [100, 100, 1000, 800]); hold on;

% STEP 1: Draw all SD connections
channel_count = 0; processed_pairs = {}; midpoints = [];
for i = 1:height(links)
    src_idx = links.source(i); det_idx = links.detector(i);
    pair_id = sprintf('%d-%d', src_idx, det_idx);
    
    % -- only process each unique pair once (duplicates from HbO / HbR)
    if ismember(pair_id, processed_pairs)
        continue;
    end
    processed_pairs{end+1} = pair_id;
    channel_count = channel_count + 1;
    
    % -- get source and detector positions
    src_x = srcPos2D(src_idx, 1);
    src_y = srcPos2D(src_idx, 2);
    det_x = detPos2D(det_idx, 1);
    det_y = detPos2D(det_idx, 2);
    
    % -- draw connecting line
    plot([src_x, det_x], [src_y, det_y], '-', 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5);
    
    % -- calculate midpoints
    mid_x = (src_x + det_x) / 2;
    mid_y = (src_y + det_y) / 2;
    midpoints = [midpoints; mid_x, mid_y, channel_count];
end

% STEP 2: Plot sources, detectors. midpoints
plot(srcPos2D(:,1), srcPos2D(:,2), 'ro', ...
     'MarkerSize', 12, 'LineWidth', 2, 'MarkerFaceColor', 'r');
plot(detPos2D(:,1), detPos2D(:,2), 'bs', ...
     'MarkerSize', 12, 'LineWidth', 2, 'MarkerFaceColor', 'b');
plot(midpoints(:,1), midpoints(:,2), 'ko', ...
     'MarkerSize', 6, 'MarkerFaceColor', 'k');

% STEP 3: Add labels
x_range = max([srcPos2D(:,1); detPos2D(:,1)]) - min([srcPos2D(:,1); detPos2D(:,1)]);
y_range = max([srcPos2D(:,2); detPos2D(:,2)]) - min([srcPos2D(:,2); detPos2D(:,2)]);
offset_x = x_range * 0.03;
offset_y = y_range * 0.02;

% -- source labels
for i = 1:size(srcPos2D, 1)
text(srcPos2D(i,1)+offset_x,srcPos2D(i,2)+offset_y,sprintf('S%02d',i),...
    'FontSize', 11, 'FontWeight', 'bold', 'Color', 'r', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);
end

% -- detector labels
for i = 1:size(detPos2D, 1)
text(detPos2D(i,1)+offset_x,detPos2D(i,2)+offset_y, sprintf('D%02d', i),...
    'FontSize', 11, 'FontWeight', 'bold', 'Color', 'b', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);
end

% -- midpoint labels
for i = 1:size(midpoints, 1)
text(midpoints(i,1),midpoints(i,2)+offset_y*2,sprintf('C%02d',midpoints(i,3)), ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', 'k', ...
    'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);
end

% -- title
title('fNIRS Probe Layout', 'FontSize', 14, 'FontWeight', 'bold');
grid off; axis equal; hold off;
end