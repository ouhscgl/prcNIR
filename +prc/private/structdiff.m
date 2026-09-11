function d = structdiff(base, cur, keep)
% STRUCTDIFF - The keys of `cur` worth writing to disk.
%
% A key is written when it differs from the default, or when it was already
% present in `keep` (the keys the user's file actually carried). That is what
% keeps a round-trip honest in both directions: opening a hand-written file in
% the UI and saving it back neither strips the keys someone deliberately wrote
% out, nor buries them under fifty defaults they never asked for.

if nargin < 3 || ~isstruct(keep), keep = struct(); end

d = struct();
f = fieldnames(cur);
for i = 1:numel(f)
    key = f{i}; val = cur.(key);
    hasBase = isfield(base, key);
    inKeep  = isfield(keep,  key);

    %-- both scalar structs: recurse, carrying `keep` down with us
    if hasBase && isstruct(val) && isscalar(val) ...
            && isstruct(base.(key)) && isscalar(base.(key))
        if inKeep && isstruct(keep.(key)) && isscalar(keep.(key))
            sub = structdiff(base.(key), val, keep.(key));
        else
            sub = structdiff(base.(key), val);
        end
        if ~isempty(fieldnames(sub)), d.(key) = sub; end

    %-- leaf: write it if it is new, changed, or was already in the file
    elseif ~hasBase || inKeep || ~isequaln(base.(key), val)
        d.(key) = val;
    end
end
end
