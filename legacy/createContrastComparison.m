function createContrastComparison(parent_dir, group_folders, options)
%CREATESVGCOMPARISON Creates side-by-side comparison PNGs from multiple folders
%
%   createSVGComparison(parent_dir, group_folders) scans subfolders within
%   parent_dir for SVG files matching the pattern *_p.svg and *_q.svg, then
%   creates combined comparison figures with groups as columns and p/q as rows.
%
%   INPUTS:
%       parent_dir    - Path to parent directory containing group subfolders
%       group_folders - Cell array of subfolder names in desired order (left to right)
%
%   OPTIONS (name-value pairs):
%       'GroupLabels'  - Cell array of display names for column headers
%                        (default: uses folder names)
%       'OutputDir'    - Output directory for comparison PNGs
%                        (default: parent_dir/comparisons)
%       'CellWidth'    - Width of each cell in pixels (default: 400)
%       'CellHeight'   - Height of each cell in pixels (default: 300)
%       'RowLabels'    - Cell array of row labels (default: {'p', 'q'})
%
%   EXAMPLE:
%       createSVGComparison(res_dir, ...
%           {'healthy_controls', 'normal_performers', 'low_performers'}, ...
%           'GroupLabels', {'Healthy', 'Normal', 'Low'});

    arguments
        parent_dir (1,:) char {mustBeFolder}
        group_folders (1,:) cell {mustBeText}
        options.GroupLabels (1,:) cell = {}
        options.OutputDir (1,:) char = ''
        options.CellWidth (1,1) double {mustBePositive} = 400
        options.CellHeight (1,1) double {mustBePositive} = 300
        options.RowLabels (1,:) cell = {'p', 'q'}
    end

    % Set defaults
    if isempty(options.GroupLabels)
        options.GroupLabels = cellfun(@(x) strrep(x, '_', ' '), ...
                                       group_folders, 'UniformOutput', false);
    end
    if isempty(options.OutputDir)
        options.OutputDir = fullfile(parent_dir, 'comparisons');
    end

    % Create output directory
    if ~isfolder(options.OutputDir)
        mkdir(options.OutputDir);
    end

    % Collect base names from all SVG files
    base_names = {};
    row_pattern = strjoin(options.RowLabels, '|');
    
    for g = 1:length(group_folders)
        grp_dir = fullfile(parent_dir, group_folders{g});
        if ~isfolder(grp_dir), continue; end
        
        svg_list = dir(fullfile(grp_dir, '*.svg'));
        for s = 1:length(svg_list)
            pattern = sprintf('^(.+)_(%s)\\.svg$', row_pattern);
            tokens = regexp(svg_list(s).name, pattern, 'tokens');
            if ~isempty(tokens)
                base_names{end+1} = tokens{1}{1}; %#ok<AGROW>
            end
        end
    end
    base_names = unique(base_names);

    if isempty(base_names)
        warning('createSVGComparison:NoFiles', 'No matching SVG files found.');
        return;
    end

    fprintf('Creating %d comparison figures...\n', length(base_names));

    % Layout parameters
    label_height = 40;
    row_label_width = 40;
    nCols = length(group_folders);
    nRows = length(options.RowLabels);
    total_width = row_label_width + nCols * options.CellWidth + 20;
    total_height = label_height + nRows * options.CellHeight + 20;

    % Create comparison PNG for each unique base name
    for b = 1:length(base_names)
        base = base_names{b};
        
        % Create figure
        fig = uifigure('Visible', 'off', ...
                       'Position', [100 100 total_width total_height], ...
                       'Color', 'white');
        
        % Add column headers (group labels)
        for g = 1:nCols
            x_pos = row_label_width + (g - 1) * options.CellWidth;
            uilabel(fig, 'Position', [x_pos, total_height - label_height, options.CellWidth, label_height], ...
                    'Text', options.GroupLabels{g}, ...
                    'FontWeight', 'bold', ...
                    'FontSize', 12, ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'center');
        end
        
        % Add row labels
        for r = 1:nRows
            y_pos = total_height - label_height - r * options.CellHeight;
            uilabel(fig, 'Position', [0, y_pos, row_label_width, options.CellHeight], ...
                    'Text', options.RowLabels{r}, ...
                    'FontWeight', 'bold', ...
                    'FontSize', 12, ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'center');
        end
        
        % Add SVG panels
        for g = 1:nCols
            grp_dir = fullfile(parent_dir, group_folders{g});
            
            for r = 1:nRows
                suffix = options.RowLabels{r};
                svg_file = fullfile(grp_dir, sprintf('%s_%s.svg', base, suffix));
                
                x_pos = row_label_width + (g - 1) * options.CellWidth;
                y_pos = total_height - label_height - r * options.CellHeight;
                
                panel = uihtml(fig, 'Position', [x_pos, y_pos, options.CellWidth, options.CellHeight]);
                
                if isfile(svg_file)
                    svg_content = fileread(svg_file);
                    html = sprintf(['<html><head><style>' ...
                                    'body{margin:0;padding:0;display:flex;justify-content:center;align-items:center;height:100vh;background:white;}' ...
                                    'svg{max-width:100%%;max-height:100%%;object-fit:contain;}' ...
                                    '</style></head><body>%s</body></html>'], svg_content);
                    panel.HTMLSource = html;
                else
                    html = ['<html><body style="margin:0;display:flex;justify-content:center;' ...
                            'align-items:center;height:100vh;background:#f0f0f0;color:#999;' ...
                            'font-family:sans-serif;">N/A</body></html>'];
                    panel.HTMLSource = html;
                end
            end
        end
        
        % Let UI render
        drawnow;
        pause(0.5);
        
        % Export to PNG
        out_file = fullfile(options.OutputDir, sprintf('%s_comparison.png', base));
        exportgraphics(fig, out_file, 'Resolution', 150);
        
        close(fig);
        fprintf('  ✓ %s_comparison.png\n', base);
    end

    fprintf('Saved %d comparison figures to: %s\n', length(base_names), options.OutputDir);
end