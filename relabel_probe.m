function probe_new = relabel_probe(probe_old, src_map, det_map)
% RELABEL_PROBE - Relabel source and detector numbers
%
% This is NOT A STANDALONE script and should be used within the scope of 
% fNIRS_Process.

% Clone the probe
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
    % -- sort by new names
    probe_new.optodes = sortrows(probe_new.optodes, 'Name');
end

%% 2. Update optodes_registered table
if isfield(probe_new, 'optodes_registered') && ~isempty(probe_new.optodes_registered)
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
    % -- sort by new names
    probe_new.optodes_registered = sortrows(probe_new.optodes_registered, 'Name');
end

%% 3. Update link table
if ~isempty(probe_new.link)
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
    probe_new.link = sortrows(probe_new.link, {'source', 'detector'});
end

%% 4. Reorder position arrays to match new numbering
if ~isempty(probe_new.srcPos3D)
    max_new_idx = max(cell2mat(values(src_map)));
    new_srcPos3D = nan(max_new_idx, size(probe_new.srcPos3D, 2));
    
    for old_idx = 1:size(probe_new.srcPos3D, 1)
        if isKey(src_map, old_idx)
            new_idx = src_map(old_idx);
            new_srcPos3D(new_idx, :) = probe_new.srcPos3D(old_idx, :);
        end
    end
    probe_new.srcPos3D = new_srcPos3D;
end

if ~isempty(probe_new.detPos3D)
    disp('    Reordering detPos3D...');
    max_new_idx = max(cell2mat(values(det_map)));
    new_detPos3D = nan(max_new_idx, size(probe_new.detPos3D, 2));
    
    for old_idx = 1:size(probe_new.detPos3D, 1)
        if isKey(det_map, old_idx)
            new_idx = det_map(old_idx);
            new_detPos3D(new_idx, :) = probe_new.detPos3D(old_idx, :);
        end
    end
    probe_new.detPos3D = new_detPos3D;
end

if isfield(probe_new, 'srcPos') && ~isempty(probe_new.srcPos)
    disp('    Reordering srcPos (2D)...');
    max_new_idx = max(cell2mat(values(src_map)));
    new_srcPos = nan(max_new_idx, size(probe_new.srcPos, 2));
    
    for old_idx = 1:size(probe_new.srcPos, 1)
        if isKey(src_map, old_idx)
            new_idx = src_map(old_idx);
            new_srcPos(new_idx, :) = probe_new.srcPos(old_idx, :);
        end
    end
    probe_new.srcPos = new_srcPos;
end

if isfield(probe_new, 'detPos') && ~isempty(probe_new.detPos)
    disp('    Reordering detPos (2D)...');
    max_new_idx = max(cell2mat(values(det_map)));
    new_detPos = nan(max_new_idx, size(probe_new.detPos, 2));
    
    for old_idx = 1:size(probe_new.detPos, 1)
        if isKey(det_map, old_idx)
            new_idx = det_map(old_idx);
            new_detPos(new_idx, :) = probe_new.detPos(old_idx, :);
        end
    end
    probe_new.detPos = new_detPos;
end
end
