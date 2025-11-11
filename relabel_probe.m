function [probe_new, link_permutation, bad_channels_mask] = relabel_probe(probe_old, src_map, det_map, remove_detector)
% RELABEL_PROBE - Relabel source and detector numbers and optionally remove bad detectors
%
% This is NOT A STANDALONE script and should be used within the scope of 
% fNIRS_Process.

if nargin < 4, remove_detector = []; end
probe_new = probe_old;

%% 1. Update optodes table
if ~isempty(probe_new.optodes)
for i = 1:height(probe_new.optodes)
    name = probe_new.optodes.Name{i};
    % -- modify source
    if startsWith(name, 'Source')
        old_num = str2double(regexp(name, '\d+', 'match', 'once'));
        if isKey(src_map, old_num)
            new_num = src_map(old_num);
            probe_new.optodes.Name{i} = sprintf('Source-%04d', new_num);
        end
    end
    
    % -- modify detector
    if startsWith(name, 'Detector')
        old_num = str2double(regexp(name, '\d+', 'match', 'once'));
        if isKey(det_map, old_num)
            new_num = det_map(old_num);
            probe_new.optodes.Name{i} = sprintf('Detector-%04d', new_num);
        end
    end
end

% -- sort each group separately
isSrc = startsWith(probe_new.optodes.Type, 'Source');
isDet = startsWith(probe_new.optodes.Type, 'Detector');
isOther = ~isSrc & ~isDet;

sources = probe_new.optodes(isSrc, :);
sources = sortrows(sources, 'Name');

detectors = probe_new.optodes(isDet, :);
detectors = sortrows(detectors, 'Name');

others = probe_new.optodes(isOther, :);
probe_new.optodes = [sources; detectors; others];
end

%% 2. Update optodes_registered table
if ~isempty(probe_new.optodes_registered)
for i = 1:height(probe_new.optodes_registered)
    name = probe_new.optodes_registered.Name{i};
    % -- modify source
    if startsWith(name, 'Source')
        old_num = str2double(regexp(name, '\d+', 'match', 'once'));
        if isKey(src_map, old_num)
            new_num = src_map(old_num);
            probe_new.optodes_registered.Name{i} = sprintf('Source-%04d', new_num);
        end
    end
    % -- modify detector
    if startsWith(name, 'Detector')
        old_num = str2double(regexp(name, '\d+', 'match', 'once'));
        if isKey(det_map, old_num)
            new_num = det_map(old_num);
            probe_new.optodes_registered.Name{i} = sprintf('Detector-%04d', new_num);
        end
    end
end

% -- sort each group separately
isSrc = startsWith(probe_new.optodes_registered.Type, 'Source');
isDet = startsWith(probe_new.optodes_registered.Type, 'Detector');
isOther = ~isSrc & ~isDet;

sources = probe_new.optodes_registered(isSrc, :);
sources = sortrows(sources, 'Name');

detectors = probe_new.optodes_registered(isDet, :);
detectors = sortrows(detectors, 'Name');

others = probe_new.optodes_registered(isOther, :);
probe_new.optodes_registered = [sources; detectors; others];
end

%% 3. Update link table and track reordering
if ~isempty(probe_new.link)
    % -- store original
    original_indices = (1:height(probe_new.link))';
    
    for i = 1:height(probe_new.link)
        old_src = probe_new.link.source(i);
        old_det = probe_new.link.detector(i);
        % -- modify source index
        if isKey(src_map, old_src)
            probe_new.link.source(i) = src_map(old_src);
        end
        % -- modify detector index
        if isKey(det_map, old_det)
            probe_new.link.detector(i) = det_map(old_det);
        end
    end
    % -- sort by new source, then new detector
    probe_new.link.OriginalIndex = original_indices;
    probe_new.link = sortrows(probe_new.link, {'source', 'detector'});
    link_permutation = probe_new.link.OriginalIndex;
    probe_new.link.OriginalIndex = [];
    
    %% 4. Remove detector channels
    if ~isempty(remove_detector)
        % -- identify channels with the bad detector
        bad_channels_mask = (probe_new.link.detector == remove_detector);
        
        if any(bad_channels_mask)
            
            if ~isempty(probe_new.fixeddistances)
                probe_new.fixeddistances(bad_channels_mask) = [];
            end

            % -- remove from link table
            probe_new.link(bad_channels_mask, :) = [];
            link_permutation(bad_channels_mask) = [];
        end
    else
        bad_channels_mask = false(height(probe_new.link), 1);
    end
else
    link_permutation = [];
    bad_channels_mask = [];
end
end