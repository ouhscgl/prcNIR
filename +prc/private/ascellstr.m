function c = ascellstr(v)
% ASCELLSTR - Normalise anything jsondecode may hand back into a cellstr.
%
% jsondecode turns ["a","b"] into a cell, but a bare "a" into a char row, and
% an empty list into 0x0 double. Callers should never have to care.

if isempty(v),              c = {};              return; end
if ischar(v),               c = {v};             return; end
if isstring(v),             c = cellstr(v(:)');  return; end
if iscell(v)
    c = cell(1, numel(v));
    for k = 1:numel(v)
        if isstring(v{k}),      c{k} = char(v{k});
        elseif isnumeric(v{k}), c{k} = num2str(v{k});
        else,                   c{k} = v{k};
        end
    end
    return
end
c = {v};
end
