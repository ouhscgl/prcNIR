function fileList = getSymlinks(rootdir, extension)
    fileList = {};
    
    if ~isempty(extension) && extension(1) ~= '.'
        extension = ['.' extension];
    end
    
    if ~exist(rootdir, 'dir')
        error('fullfileSymlinks:DirNotFound', 'Directory not found: %s', rootdir);
    end
    
    fileList = searchDirectory(rootdir, extension, {}, containers.Map());
    
    function fileList = searchDirectory(currentDir, extension, fileList, visited)
        currentDir = char(java.io.File(currentDir).getCanonicalPath());
        
        if isKey(visited, currentDir)
            return;
        end
        visited(currentDir) = true;
        
        items = dir(currentDir);
        items = items(~ismember({items.name}, {'.', '..'}));
        
        for i = 1:length(items)
            itemPath = fullfile(currentDir, items(i).name);
            
            isAliasFlag = false;
            if ismac
                [status, result] = system(['mdls -name kMDItemKind "' itemPath '" 2>/dev/null']);
                if status == 0
                    isAliasFlag = contains(result, 'Alias');
                end
            end
            
            if isAliasFlag
                try
                    aliasPathExpanded = char(java.io.File(itemPath).getCanonicalPath());
                    
                    if ~exist(aliasPathExpanded, 'file')
                        error('resolveAlias:FileNotFound', ...
                              'Alias file not found: %s', aliasPathExpanded);
                    end
                    
                    script = sprintf(['tell application "Finder"\n' ...
                                      'POSIX path of (original item of ' ...
                                      '(POSIX file "%s" as alias) as text)\n' ...
                                      'end tell'], aliasPathExpanded);
                    
                    [status, result] = system(['osascript -e ''' script '''']);
                    
                    if status ~= 0
                        error('resolveAlias:ResolutionFailed', ...
                              'Failed to resolve alias. Error: %s', strtrim(result));
                    end
                    
                    originalPath = strtrim(result);
                    
                    if exist(originalPath, 'dir')
                        fileList = searchDirectory(originalPath, extension, fileList, visited);
                    elseif exist(originalPath, 'file')
                        [~, ~, ext] = fileparts(originalPath);
                        if strcmpi(ext, extension)
                            fileList{end+1} = originalPath;
                        end
                    end
                catch ME
                    warning('fullfileSymlinks:AliasResolutionFailed', ...
                            'Failed to resolve alias: %s\nError: %s', ...
                            itemPath, ME.message);
                end
            elseif items(i).isdir
                fileList = searchDirectory(itemPath, extension, fileList, visited);
            else
                [~, ~, ext] = fileparts(items(i).name);
                if strcmpi(ext, extension)
                    fileList{end+1} = itemPath;
                end
            end
        end
    end
end