function fileList = getSymlinks(rootdir, extension)
    fprintf('\n ∿ ∿ ∿\n');
    fprintf('╭─────╮\n');
    fprintf('│     ├─╮ THIS MIGHT TAKE A WHILE, \n');
    fprintf('│     ├─╯ GO GRAB A COFFEE :)\n');
    fprintf('╰─────╯\n\n');
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
            [~, ~, ext] = fileparts(items(i).name);
            
            % --- macOS Alias resolution ---
            isAliasFlag = false;
            if ismac
                [status, result] = system(['mdls -name kMDItemKind "' itemPath '" 2>/dev/null']);
                if status == 0
                    isAliasFlag = contains(result, 'Alias');
                end
            end
            
            % --- Windows .lnk shortcut resolution ---
            isWindowsShortcut = ispc && strcmpi(ext, '.lnk');
            
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
                        [~, ~, resolvedExt] = fileparts(originalPath);
                        if strcmpi(resolvedExt, extension)
                            fileList{end+1} = originalPath;
                        end
                    end
                catch ME
                    warning('fullfileSymlinks:AliasResolutionFailed', ...
                            'Failed to resolve alias: %s\nError: %s', ...
                            itemPath, ME.message);
                end
                
            elseif isWindowsShortcut
                try
                    script = sprintf(['$sh = New-Object -ComObject WScript.Shell; ' ...
                                      '$lnk = $sh.CreateShortcut(''%s''); ' ...
                                      'Write-Output $lnk.TargetPath'], itemPath);
                    [status, result] = system(['powershell -Command "' script '"']);
                    
                    if status ~= 0
                        error('resolveShortcut:Failed', ...
                              'Failed to resolve shortcut. Error: %s', strtrim(result));
                    end
                    
                    originalPath = strtrim(result);
                    
                    if isempty(originalPath)
                        error('resolveShortcut:EmptyTarget', ...
                              'Shortcut target is empty: %s', itemPath);
                    end
                    
                    if exist(originalPath, 'dir')
                        fileList = searchDirectory(originalPath, extension, fileList, visited);
                    elseif exist(originalPath, 'file')
                        [~, ~, resolvedExt] = fileparts(originalPath);
                        if strcmpi(resolvedExt, extension)
                            fileList{end+1} = originalPath;
                        end
                    end
                catch ME
                    warning('fullfileSymlinks:ShortcutResolutionFailed', ...
                            'Failed to resolve shortcut: %s\nError: %s', ...
                            itemPath, ME.message);
                end
                
            elseif items(i).isdir
                fileList = searchDirectory(itemPath, extension, fileList, visited);
            else
                if strcmpi(ext, extension)
                    fileList{end+1} = itemPath;
                end
            end
        end
    end
end