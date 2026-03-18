function coords = visualizeFnirsProbe(probe, chanlocs)
%VISUALIZEFNIRSPROBE  Plot fNIRS probe layout with optional EEG overlay.
%
%   coords = visualizeFnirsProbe(probe)
%   coords = visualizeFnirsProbe(probe, chanlocs)
%
%   Short channels are drawn as dashed grey lines but are NOT assigned a
%   C-number, so channel indices in the output table and figure match the
%   HbO column order produced by nirs.modules.RemoveShortSeperations with
%   the same max_distance threshold.
%
%   Inputs:
%     probe      - nirs-toolbox probe struct (e.g. data_prps(1).probe)
%     chanlocs   - (optional) EEGLab chanlocs struct array for overlay
%
%   Output:
%     coords     - table: Name, X, Y, Type
%                  fNIRS = long-channel midpoints only (C01, C02, ...)
%                  EEG   = all electrodes (by .labels)

SHORT_DIST_MM  = 10;   % must match job.max_distance in preprocessing
overlay_eeg    = nargin == 2 && ~isempty(chanlocs);

%% ========================================================================
%  Setup
%  ========================================================================
[srcPos, detPos, links] = deal(probe.srcPos, probe.detPos, probe.link);
srcPos2D = srcPos(:, 1:2);
detPos2D = detPos(:, 1:2);

figure('Position', [100, 100, 1000, 800]); hold on;

%% ========================================================================
%  STEP 1: Draw SD connections and collect long-channel midpoints
%  ========================================================================
channel_count   = 0;
processed_pairs = {};
midpoints       = [];    % [mid_x, mid_y, channel_index]  — long only

for i = 1:height(links)
    src_idx = links.source(i);
    det_idx = links.detector(i);
    pair_id = sprintf('%d-%d', src_idx, det_idx);

    if ismember(pair_id, processed_pairs), continue; end
    processed_pairs{end+1} = pair_id;

    src_x = srcPos2D(src_idx, 1);   src_y = srcPos2D(src_idx, 2);
    det_x = detPos2D(det_idx, 1);   det_y = detPos2D(det_idx, 2);

    % -- 3D distance to classify short vs long
    dist = norm(srcPos(src_idx,:) - detPos(det_idx,:));
    is_short = dist <= SHORT_DIST_MM;

    if is_short
        % draw but do not count or label
        plot([src_x, det_x], [src_y, det_y], '--', ...
             'Color', [0.85 0.85 0.85], 'LineWidth', 0.5, ...
             'HandleVisibility', 'off');
    else
        channel_count = channel_count + 1;
        plot([src_x, det_x], [src_y, det_y], '-', ...
             'Color', [0.7 0.7 0.7], 'LineWidth', 0.5, ...
             'HandleVisibility', 'off');
        mid_x = (src_x + det_x) / 2;
        mid_y = (src_y + det_y) / 2;
        midpoints = [midpoints; mid_x, mid_y, channel_count];
    end
end

%% ========================================================================
%  STEP 2: Plot sources, detectors, midpoints
%  ========================================================================
plot(srcPos2D(:,1), srcPos2D(:,2), 'ro', ...
     'MarkerSize', 12, 'LineWidth', 2, 'MarkerFaceColor', 'r', ...
     'DisplayName', 'fNIRS Sources');
plot(detPos2D(:,1), detPos2D(:,2), 'bs', ...
     'MarkerSize', 12, 'LineWidth', 2, 'MarkerFaceColor', 'b', ...
     'DisplayName', 'fNIRS Detectors');
plot(midpoints(:,1), midpoints(:,2), 'ko', ...
     'MarkerSize', 6, 'MarkerFaceColor', 'k', ...
     'DisplayName', 'fNIRS Channels');

%% ========================================================================
%  STEP 3: Labels — offset scaled to full data range
%  ========================================================================
all_x = [srcPos2D(:,1); detPos2D(:,1)];
all_y = [srcPos2D(:,2); detPos2D(:,2)];
if overlay_eeg
    all_x = [all_x; -[chanlocs.Y]' * 0.7];
    all_y = [all_y; [chanlocs.X]' * 0.7];
end
offset_x = (max(all_x) - min(all_x)) * 0.03;
offset_y = (max(all_y) - min(all_y)) * 0.02;

for i = 1:size(srcPos2D, 1)
    text(srcPos2D(i,1)+offset_x, srcPos2D(i,2)+offset_y, sprintf('S%02d',i), ...
        'FontSize', 11, 'FontWeight', 'bold', 'Color', 'r', ...
        'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);
end
for i = 1:size(detPos2D, 1)
    text(detPos2D(i,1)+offset_x, detPos2D(i,2)+offset_y, sprintf('D%02d',i), ...
        'FontSize', 11, 'FontWeight', 'bold', 'Color', 'b', ...
        'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);
end
for i = 1:size(midpoints, 1)
    text(midpoints(i,1), midpoints(i,2)+offset_y*2, ...
         sprintf('C%02d', midpoints(i,3)), ...
        'FontSize', 8, 'HorizontalAlignment', 'center', 'Color', 'k', ...
        'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);
end

%% ========================================================================
%  STEP 4: Optional EEG overlay
%  ========================================================================
if overlay_eeg
    eeg_x      = -[chanlocs.Y]' * 0.7;
    eeg_y      = [chanlocs.X]' * 0.7;
    eeg_labels = {chanlocs.labels}';

    plot(eeg_x, eeg_y, 'g^', ...
        'MarkerSize', 10, 'LineWidth', 2, 'MarkerFaceColor', 'g', ...
        'DisplayName', 'EEG Electrodes');

    for i = 1:length(chanlocs)
        text(eeg_x(i)+offset_x, eeg_y(i)+offset_y, eeg_labels{i}, ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', [0 0.6 0], ...
            'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 1);
    end
    title('fNIRS Probe Layout with EEG Electrodes', ...
          'FontSize', 14, 'FontWeight', 'bold');
else
    title('fNIRS Probe Layout', 'FontSize', 14, 'FontWeight', 'bold');
end

legend('Location', 'best');
grid off; axis equal; hold off;

% Expand axis limits by 10% to prevent labels clipping outside
ax = gca;
xl = ax.XLim; yl = ax.YLim;
x_pad = (xl(2) - xl(1)) * 0.10;
y_pad = (yl(2) - yl(1)) * 0.10;
ax.XLim = [xl(1) - x_pad, xl(2) + x_pad];
ax.YLim = [yl(1) - y_pad, yl(2) + y_pad];

%% ========================================================================
%  STEP 5: Output table (long-channel midpoints + EEG if provided)
%  ========================================================================
n_fnirs     = size(midpoints, 1);
fnirs_names = arrayfun(@(k) sprintf('C%02d',k), midpoints(:,3), ...
                       'UniformOutput', false);
fnirs_type  = repmat({'fNIRS'}, n_fnirs, 1);

if overlay_eeg
    coords = table( ...
        [fnirs_names;        eeg_labels        ], ...
        [midpoints(:,1);     eeg_x             ], ...
        [midpoints(:,2);     eeg_y             ], ...
        [fnirs_type;         repmat({'EEG'}, length(chanlocs), 1)], ...
        'VariableNames', {'Name','X','Y','Type'});
else
    coords = table( ...
        fnirs_names, midpoints(:,1), midpoints(:,2), fnirs_type, ...
        'VariableNames', {'Name','X','Y','Type'});
end

end
