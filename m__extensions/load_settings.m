function settings = load_settings(json_file)
% -- Read JSON file
fid = fopen(json_file, 'r');
if fid == -1, error('Could not open JSON file: %s', json_file); end
json_text = fread(fid, '*char')';
fclose(fid);
% -- Parse JSON
raw_settings = jsondecode(json_text);
settings = procinp(raw_settings);
fprintf('✓ Successfully loaded settings.\n');
end
% Auxilliary functions
function processed = procinp(input)
% -- process struct
if isstruct(input), processed = input; fs = fieldnames(input);
    for i = 1:length(fs)
        f = fs{i}; 
        % Special handling for contrasts structure
        if strcmp(f, 'contrasts')
            processed.(f) = process_contrasts(input.(f));
        else
            processed.(f) = procinp(input.(f));
        end
    end
% -- process cell
elseif iscell(input), processed = input;
    for i = 1:length(input), processed{i} = procinp(input{i});end
% -- process NaN
elseif ischar(input) && strcmp(input, 'NaN'), processed = NaN;
% -- process num. arrays
%elseif isnumeric(input) && ~isscalar(input), processed = num2cell(input);
elseif isnumeric(input) && isvector(input) && ~isscalar(input), processed = input(:)';
% -- process str. arrays
elseif isstring(input) && ~isscalar(input), processed = cellstr(input);
% -- process miscellaneous
else, processed = input;
end
end

function p = process_contrasts(contrasts)
p = contrasts; fields = fieldnames(contrasts);
for i = 1:length(fields), field = fields{i}; v = contrasts.(field);
    if isnumeric(v) && size(v, 1) > 1
        p.(field) = mat2cell(v, ones(size(v, 1), 1), size(v, 2));
    else
        p.(field) = procinp(v);
    end
end
end