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
end
