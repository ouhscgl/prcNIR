function leaf_paths = getLeafDirectories(base_path)
    % Initialize empty cell array for leaf directory paths
    leaf_paths = {};
    
    % Get current level directories
    dir_items = dir(base_path);
    sub_dirs = dir_items([dir_items.isdir] & ~ismember({dir_items.name}, {'.','..'}));
    
    if isempty(sub_dirs)
        % If no subdirectories, this base_path itself is a leaf directory
        % But we don't add it as we're looking for subdirectories
        return;
    end
    
    % Check each subdirectory
    for i = 1:length(sub_dirs)
        current_path = fullfile(base_path, sub_dirs(i).name);
        current_subs = dir(current_path);
        current_subs = current_subs([current_subs.isdir] & ~ismember({current_subs.name}, {'.','..'}));
        
        if isempty(current_subs)
            % This is a leaf directory, add its path to our results
            leaf_paths{end+1} = current_path;
        else
            % This has subdirectories, search deeper
            deeper_leaves = getLeafDirectories(current_path);
            leaf_paths = [leaf_paths, deeper_leaves];
        end
    end
end