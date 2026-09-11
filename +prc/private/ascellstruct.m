function c = ascellstruct(v)
% ASCELLSTRUCT - Normalise a JSON array-of-objects into a cell of 1x1 structs.
%
% jsondecode returns a STRUCT ARRAY when every object in the array happens to
% carry identical fields, and a CELL ARRAY when they differ. Pipeline steps
% differ by nature ({"module":"TDDR"} vs {"module":"TrimBaseline",...}), so the
% same file can decode either way depending on which steps it happens to list.
% Everything downstream gets a cell array, always.

if isempty(v),    c = {}; return; end
if iscell(v)
    c = reshape(v, 1, []);
    return
end
if isstruct(v)
    c = cell(1, numel(v));
    for k = 1:numel(v), c{k} = v(k); end
    return
end
c = {v};
end
