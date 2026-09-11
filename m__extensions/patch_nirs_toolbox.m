function [status, allOk] = patch_nirs_toolbox(root_folder, options)
% PATCH_NIRS_TOOLBOX  Apply (or check) patches to the nirs-toolbox.
%
%   patch_nirs_toolbox()                        — prompts user to select the folder
%   patch_nirs_toolbox(root_folder)             — uses the provided path directly
%   status = patch_nirs_toolbox(root, 'CheckOnly', true)   — reports, changes nothing
%   [status, allOk] = patch_nirs_toolbox(...)
%
%   Example (from setup script):
%       patch_nirs_toolbox(fullfile(target_dir, 'nirs-toolbox'))
%
%   status is a struct array, one entry per patch:
%       .file    target filename
%       .label   what the patch is for
%       .state   'ok' | 'unpatched' | 'missing'
%       .path    where the file was found ('' when missing)
%   allOk is true only when every patch reports 'ok'. prcNIR treats an
%   unpatched toolbox as fatal, so this is what the setup check gates on.
%
%   Detection notes:
%   Patch state is read from the file with comments stripped, so a patch that
%   someone applied by hand — commenting the offending line out rather than
%   deleting it — still reads as applied. Each patch also carries a signature
%   string that must be present whatever its state; if the signature is missing
%   the file is not the one we think it is (wrong folder, or a toolbox version
%   that moved the code) and the patch reports 'missing' rather than quietly
%   claiming success. The old "strrep changed nothing, so it must already be
%   patched" test could not tell those two cases apart.

arguments
    root_folder             (1,:) char   = ''
    options.CheckOnly       (1,1) logical = false
    options.Verbose         (1,1) logical = true
end

%% Resolve root folder
if isempty(root_folder)
    root_folder = uigetdir('', 'Select nirs-toolbox folder.');
    if isequal(root_folder, 0)
        fprintf('Patch cancelled.\n');
        status = emptyStatus(); allOk = false;
        return;
    end
end

if ~exist(root_folder, 'dir')
    error('patch_nirs_toolbox: folder not found: %s', root_folder);
end

%% Patches to be applied
%  signature  - proves we are looking at the right file, patched or not
%  find       - regex that must NOT survive (searched with comments stripped)
%  literal    - exact text to substitute when applying a 'replace'
%  marker     - regex that MUST be present after a 'replace' ('' to skip)
patches = [
    struct('file',      'loadNIRx.m', ...
           'label',     'stop loadNIRx overwriting the short-detector S-D mask', ...
           'signature', 'function raw = loadNIRx', ...
           'mode',      'comment', ...
           'find',      ['S_D_Mask\(\s*:\s*,\s*info\.Detectors\s*-\s*' ...
                         'info\.ShortDetectors\s*\+\s*1\s*:\s*end\s*\)\s*=\s*' ...
                         'eye\(\s*info\.ShortDetectors\s*\)'], ...
           'literal',   '', ...
           'marker',    '', ...
           'replaced',  ''), ...
    struct('file',      'LabeltooLongDistance.m', ...
           'label',     'fix the misspelled class reference', ...
           'signature', 'classdef LabeltooLongDistance', ...
           'mode',      'replace', ...
           'find',      'LabeltooLongSeperation', ...
           'literal',   'LabeltooLongSeperation', ...
           'marker',    '', ...
           'replaced',  'LabeltooLongDistance'), ...
    struct('file',      'loadSNIRF.m', ...
           'label',     'bridge SATORI-written SNIRF into nirs-toolbox', ...
           'signature', 'function data = loadSNIRF', ...
           'mode',      'replace', ...
           'find',      'snirf\s*=\s*array2struct\(array\)\s*;', ...
           'literal',   'snirf = array2struct(array);', ...
           'marker',    'loadSNIRF_repairStructFields', ...
           'replaced',  ['array = loadSNIRF_repairStructFields(array);' newline ...
                         'snirf = array2struct(array) ;' newline ...
                         '[snirf.nirs.data.measurementList, mask] = loadSNIRF_filterStructArray(snirf.nirs.data.measurementList);' newline ...
                         'snirf.nirs.data.dataTimeSeries = snirf.nirs.data.dataTimeSeries(mask, :);']), ...
    struct('file',      'ChangeStimulusInfo.m', ...
           'label',     'drop the redundant stimulus-table rebuild', ...
           'signature', 'classdef ChangeStimulusInfo', ...
           'mode',      'comment', ...
           'find',      'oldstiminfo\s*=\s*nirs\.createStimulusTable\(data\)\s*;', ...
           'literal',   '', ...
           'marker',    '', ...
           'replaced',  '')
];

%% Main execution loop
if options.Verbose && ~options.CheckOnly
    disp('-------------------------------------------------------------------')
    disp('Patching nirs-toolbox')
    disp('-------------------------------------------------------------------')
end

status = emptyStatus();
for i = 1:length(patches)
    if options.Verbose && ~options.CheckOnly
        disp(['[' num2str(i) '/' num2str(length(patches)) '] Loading ' ...
              patches(i).file ' ...'])
    end
    status(i) = handle_patch(root_folder, patches(i), options.CheckOnly); %#ok<AGROW>
    if options.Verbose && ~options.CheckOnly
        disp(['      ' status(i).state ' — ' status(i).label])
    end
end

if options.Verbose && ~options.CheckOnly
    disp('-------------------------------------------------------------------')
end

allOk = all(strcmp({status.state}, 'ok'));

if nargout == 0
    clear status allOk
end

end % end of main function

%% ------------------------------------------------------------------------
function s = emptyStatus()
    s = struct('file', {}, 'label', {}, 'state', {}, 'path', {});
end

function s = handle_patch(folder, p, checkOnly)
s = struct('file', p.file, 'label', p.label, 'state', 'missing', 'path', '');

% -- check for root directory
if ~exist(folder, 'dir')
    warning('Root non existant: %s', folder); return;
end

% -- check for files
allfiles = dir(fullfile(folder, '**', p.file));
if isempty(allfiles)
    if ~checkOnly, warning('File not found: %s', p.file); end
    return
end

% -- assign io variables
s.path   = fullfile(allfiles(1).folder, allfiles(1).name);
fileText = fileread(s.path);

% -- the signature proves this is the file the patch was written against
if ~contains(fileText, p.signature)
    if ~checkOnly
        warning(['%s does not look like the file this patch targets. ' ...
                 'Leaving it alone.'], s.path);
    end
    return
end

% -- read state from the code only, so a hand-commented patch still counts
code = strip_comments(fileText);
if ~isempty(p.marker)
    % A marker is authoritative. loadSNIRF needs one because its replacement
    % re-states the very line it replaces, so "is the original still there"
    % answers yes either way and cannot be used.
    patched = ~isempty(regexp(code, p.marker, 'once'));
else
    patched = isempty(regexp(code, p.find, 'once'));
end

if patched
    s.state = 'ok';
    return
end
s.state = 'unpatched';

if checkOnly, return; end

% -- rewrite section
switch p.mode
    case 'comment'
        newText = comment_out(fileText, p.find);
    case 'replace'
        newText = strrep(fileText, p.literal, p.replaced);
    otherwise
        error('patch_nirs_toolbox: unknown mode "%s"', p.mode);
end

if strcmp(newText, fileText)
    warning(['Could not apply the %s patch automatically. The target code is ' ...
             'present but did not match exactly; patch it by hand.'], p.file);
    return
end

% -- write to file
fid = fopen(s.path, 'w');
if fid == -1, error('Could not open file for writing: %s', s.path); end
fprintf(fid, '%s', newText);
fclose(fid);

disp(['Modified file: ' s.path]);
s.state = 'ok';
end

function out = comment_out(text, pattern)
% Comment the offending line rather than deleting it: reversible, visible in a
% diff, and it matches what someone patching by hand would have done anyway.
    lines = regexp(text, '\r?\n', 'split');
    for i = 1:numel(lines)
        codeOnly = strip_comments(lines{i});
        if ~isempty(regexp(codeOnly, pattern, 'once'))
            lines{i} = ['% [prcNIR patch] ' lines{i}];
        end
    end
    out = strjoin(lines, newline);
end

function code = strip_comments(text)
% Cut each line at its first % that is not inside a single-quoted string.
% Good enough for patch detection; it is not a MATLAB parser, and it does not
% try to be one. Block comments (%{ %}) are left alone because none of the
% patched lines live in one.
    lines = regexp(text, '\r?\n', 'split');
    for i = 1:numel(lines)
        ln = lines{i}; inStr = false;
        for c = 1:numel(ln)
            if ln(c) == '''',    inStr = ~inStr;
            elseif ln(c) == '%' && ~inStr
                ln = ln(1:c-1); break
            end
        end
        lines{i} = ln;
    end
    code = strjoin(lines, newline);
end
