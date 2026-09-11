function p = abspath(p, root)
% PRC.ABSPATH - Resolve a settings-file path against the file's own folder.
%
% Usage:
%   [cfg, meta] = prc.loadSettings(f);
%   dataRoot    = prc.abspath(cfg.paths.data_root, meta.root);
%
% Settings files keep paths exactly as written -- relative stays relative on
% disk so a profile can travel with its data -- and resolution happens here, at
% the moment a path is actually used.

if isempty(p), return; end
p = char(p);

%-- already absolute? (POSIX root, drive letter, or UNC share)
if startsWith(p, {'/','\\'}) || ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once'))
    return
end

%-- leading ~ is the user's home on every platform MATLAB runs on
if startsWith(p, '~')
    if ispc, home = getenv('USERPROFILE'); else, home = getenv('HOME'); end
    if ~isempty(home), p = fullfile(home, p(2:end)); return; end
end

if nargin > 1 && ~isempty(root), p = fullfile(root, p); end
end
