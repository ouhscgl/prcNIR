function leaf_paths = getLeafs(base_path)
    leaf_paths = {};
    dir_items  = dir(base_path);
    sub_dirs   = dir_items([dir_items.isdir] & ...
                 ~ismember({dir_items.name}, {'.','..'}));
    
    %-- no leaf directories, return empty
    if isempty(sub_dirs), return; end
    
    %-- check branches for leafs
    for i = 1:length(sub_dirs)
        current_path = fullfile(base_path, sub_dirs(i).name);
        current_subs = dir(current_path);
        current_subs = current_subs([current_subs.isdir] & ...
                       ~ismember({current_subs.name}, {'.','..'}));
        
        if isempty(current_subs)
            leaf_paths{end+1} = current_path;
        else
            deeper_leaves = getLeafs(current_path);
            leaf_paths = [leaf_paths, deeper_leaves];
        end
    end
end