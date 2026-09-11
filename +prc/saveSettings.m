function file = saveSettings(file, cfg, profileKey, meta)
% PRC.SAVESETTINGS - Write a profile back to a settings JSON file.
%
% Usage:
%   prc.saveSettings(file, cfg, 'nback_pairwise')
%   prc.saveSettings(file, cfg, 'nback_pairwise', meta)   % round-trip a load
%
% Other profiles already in the file are left in place. Pass the `meta` from
% prc.loadSettings and the keys the file originally carried are preserved even
% where they match the defaults -- without it, save writes only what differs.
%
% The profile is validated first; a profile with errors is not written, because
% a settings file that cannot be loaded is worse than no settings file.
%
% See also PRC.LOADSETTINGS, PRC.DEFAULTS, PRC.VALIDATESETTINGS

arguments
    file       (1,:) char
    cfg        (1,1) struct
    profileKey (1,:) char
    meta       (1,1) struct = struct()
end

if ~isvarname(profileKey)
    error('prc:saveSettings:BadProfileKey', ...
         ['"%s" cannot be a profile key. Use letters, digits and underscores, ', ...
          'not starting with a digit.'], profileKey);
end

%% ========================================================================
%  Validate before writing
%  ========================================================================
[ok, problems] = prc.validateSettings(cfg);
if ~ok
    for k = 1:numel(problems)
        if strcmp(problems(k).severity,'error')
            fprintf('  ✗  %-34s %s\n', problems(k).path, problems(k).message);
        end
    end
    error('prc:saveSettings:Invalid', ...
          'Profile "%s" has errors and was not written.', profileKey);
end

%% ========================================================================
%  Reduce to what belongs in the file
%  ========================================================================
keep = struct();
if isfield(meta,'overlay') && isstruct(meta.overlay) ...
        && (~isfield(meta,'profile') || strcmp(meta.profile, profileKey))
    keep = meta.overlay;
end
profile = structdiff(prc.defaults(), cfg, keep);

%% ========================================================================
%  Merge into the existing document
%  ========================================================================
doc = struct('schema_version', 1, 'profiles', struct());
if isfile(file)
    fid = fopen(file, 'r', 'n', 'UTF-8');
    if fid ~= -1
        raw = fread(fid, '*char')'; fclose(fid);
        try
            existing = jsondecode(raw);
            if isfield(existing,'profiles') && isstruct(existing.profiles)
                doc.profiles = existing.profiles;
            end
        catch
            warning('prc:saveSettings:Unparseable', ...
                   ['%s could not be parsed, so it is being replaced rather ', ...
                    'than merged into. The old file is kept as .bak'], file);
            copyfile(file, [file '.bak']);
        end
    end
end
doc.profiles.(profileKey) = profile;

%% ========================================================================
%  Write
%  ========================================================================
folder = fileparts(file);
if ~isempty(folder) && ~isfolder(folder), mkdir(folder); end

txt = jsonpretty(jsonencode(doc));

fid = fopen(file, 'w', 'n', 'UTF-8');
if fid == -1
    error('prc:saveSettings:Unwritable', 'Could not write: %s', file);
end
fprintf(fid, '%s\n', txt);
fclose(fid);

if nargout == 0
    fprintf('  ✓ saved profile "%s" to %s\n', profileKey, file);
    clear file
end
end
