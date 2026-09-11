function [cfg, meta] = loadSettings(file, profileKey)
% PRC.LOADSETTINGS - Read a profile from a settings JSON file.
%
% Usage:
%   cfg          = prc.loadSettings('configs/profiles/example.json')
%   cfg          = prc.loadSettings(file, 'nback_pairwise')
%   [cfg, meta]  = prc.loadSettings(...)
%
% The file's profile is overlaid onto prc.defaults, so a settings file only has
% to carry what it changes. The result is validated before it is returned;
% anything at 'error' severity raises rather than surfacing thirty minutes into
% a run. Warnings are printed and the profile is still returned.
%
% Outputs:
%   cfg   - the merged, normalised, validated profile
%   meta  - .file      absolute path to the settings file
%           .root      folder the file lives in (relative paths resolve here)
%           .profile   which profile key was loaded
%           .profiles  every profile key the file offers
%           .overlay   the file's own keys, normalised -- prc.saveSettings uses
%                      this to write your file back without either losing keys
%                      you wrote or gaining defaults you did not
%
% See also PRC.DEFAULTS, PRC.SAVESETTINGS, PRC.VALIDATESETTINGS

arguments
    file       (1,:) char
    profileKey (1,:) char = ''
end

%% ========================================================================
%  Read
%  ========================================================================
if ~isfile(file)
    error('prc:loadSettings:NoFile', 'Settings file not found: %s', file);
end

fid = fopen(file, 'r', 'n', 'UTF-8');
if fid == -1
    error('prc:loadSettings:Unreadable', 'Could not open: %s', file);
end
raw = fread(fid, '*char')';
fclose(fid);

try
    doc = jsondecode(raw);
catch e
    error('prc:loadSettings:BadJSON', ...
          'Could not parse %s as JSON.\n  %s', file, e.message);
end

%% ========================================================================
%  Locate the profile
%  ========================================================================
if isfield(doc, 'schema_version')
    if doc.schema_version > 1
        error('prc:loadSettings:FutureSchema', ...
             ['%s declares schema_version %g, but this copy of prcNIR only ', ...
              'understands version 1. Update prcNIR.'], file, doc.schema_version);
    end
    schemaVersion = doc.schema_version;
else
    schemaVersion = 1;
end

if isfield(doc, 'profiles') && isstruct(doc.profiles)
    profileKeys = fieldnames(doc.profiles)';
    if isempty(profileKey)
        if isscalar(profileKeys)
            profileKey = profileKeys{1};
        else
            error('prc:loadSettings:AmbiguousProfile', ...
                 ['%s holds %d profiles, so one has to be named.\n', ...
                  '  Available: %s'], file, numel(profileKeys), strjoin(profileKeys, ', '));
        end
    elseif ~ismember(profileKey, profileKeys)
        error('prc:loadSettings:NoSuchProfile', ...
             ['No profile "%s" in %s.\n  Available: %s'], ...
              profileKey, file, strjoin(profileKeys, ', '));
    end
    overlay = doc.profiles.(profileKey);
else
    %-- a bare profile with no wrapper: accepted, it is a reasonable thing to
    %   hand-write for a one-off analysis
    profileKeys = {'default'};
    profileKey = 'default';
    overlay    = doc;
    overlay    = rmfieldif(overlay, 'schema_version');
end

%% ========================================================================
%  Normalise, merge, validate
%  ========================================================================
overlay = normalizeprofile(overlay);
cfg     = mergeinto(prc.defaults(), overlay);

[ok, problems] = prc.validateSettings(cfg);
printProblems(problems, file, profileKey);
if ~ok
    error('prc:loadSettings:Invalid', ...
          'Profile "%s" in %s is not usable. See the errors above.', ...
          profileKey, file);
end

%% ========================================================================
%  Meta
%  ========================================================================
full        = whichFile(file);
meta        = struct();
meta.file   = full;
meta.root   = fileparts(full);
meta.profile  = profileKey;
meta.profiles = profileKeys;
meta.overlay  = overlay;
meta.schema_version = schemaVersion;
% _________________________________________________________________________
end

%% ========================================================================
%  Auxilliary Functions
%  ========================================================================
function s = rmfieldif(s, f)
    if isstruct(s) && isfield(s, f), s = rmfield(s, f); end
end

function p = whichFile(file)
    d = dir(file);
    p = fullfile(d(1).folder, d(1).name);
end

function printProblems(problems, file, profileKey)
    if isempty(problems), return; end
    [~, nm, ex] = fileparts(file);
    fprintf('\n  %s [%s]\n', [nm ex], profileKey);
    for k = 1:numel(problems)
        if strcmp(problems(k).severity, 'error'), mark = '  ✗';
        else,                                    mark = '  !';
        end
        fprintf('%s  %-34s %s\n', mark, problems(k).path, problems(k).message);
    end
    fprintf('\n');
end
