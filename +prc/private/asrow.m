function r = asrow(v)
% ASROW - Numeric vector as a row. jsondecode returns columns.

if isempty(v), r = []; return; end
if iscell(v),  v = cell2mat(v(:)'); end
r = reshape(v, 1, []);
end
