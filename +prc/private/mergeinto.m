function base = mergeinto(base, over)
% MERGEINTO - Recursively overlay `over` onto `base`.
%
% A JSON null decodes to [] and means "use the default", so numeric-empty
% values are skipped rather than written. An empty cell {} or empty string ''
% is a real value and does overwrite -- that is how you clear a contrast list.

if ~isstruct(over) || ~isscalar(over), return; end

f = fieldnames(over);
for i = 1:numel(f)
    key = f{i}; val = over.(key);

    %-- both sides are scalar structs: recurse
    if isstruct(val) && isscalar(val) && isfield(base, key) ...
            && isstruct(base.(key)) && isscalar(base.(key))
        base.(key) = mergeinto(base.(key), val);

    %-- JSON null: leave the default in place
    elseif isempty(val) && ~iscell(val) && ~ischar(val) && ~isstring(val)
        continue

    else
        base.(key) = val;
    end
end
end
