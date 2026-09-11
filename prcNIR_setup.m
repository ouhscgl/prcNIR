function [checks, allOk] = prcNIR_setup(options)
% PRCNIR_SETUP  Put prcNIR and nirs-toolbox on the path, then check the result.
%
% Usage:
%   prcNIR_setup                                   % find nirs-toolbox nearby
%   prcNIR_setup('ToolboxRoot', '/path/to/nirs-toolbox')
%   prcNIR_setup('Patch', true)                    % apply missing patches too
%   [checks, allOk] = prcNIR_setup(...)
%
% Options:
%   ToolboxRoot - where nirs-toolbox lives. Left empty, the folder this file
%                 sits in is searched upward for a sibling called nirs-toolbox,
%                 and failing that whatever is already on the path is used.
%   Patch       - apply any missing nirs-toolbox patches (default false, so
%                 nothing is written to the toolbox unless you ask).
%   Legacy      - also add legacy/ to the path (default false).
%   Quiet       - skip the printed report.
%
% Everything prcNIR checks is fatal; see prc.checkEnvironment for why. This
% function is the command-line half of the app's Setup tab — both call the same
% checks, so they can never disagree about whether the machine is ready.
%
% See also PRC.CHECKENVIRONMENT, PATCH_NIRS_TOOLBOX

arguments
    options.ToolboxRoot (1,:) char   = ''
    options.Patch       (1,1) logical = false
    options.Legacy      (1,1) logical = false
    options.Quiet       (1,1) logical = false
end

prcRoot = fileparts(mfilename('fullpath'));

%% ========================================================================
%  prcNIR itself
%  ========================================================================
%-- Listed explicitly rather than genpath'd. genpath would sweep in py_extensions
%   (including its virtualenv, which is 600-odd folders of Python that MATLAB
%   would then search on every single name lookup) and legacy/, where several
%   files carry older versions of functions that still exist today.
addpath(prcRoot);
addpath(fullfile(prcRoot, 'm__extensions'));
if options.Legacy
    addpath(fullfile(prcRoot, 'legacy'));
end

%% ========================================================================
%  nirs-toolbox
%  ========================================================================
root = options.ToolboxRoot;
if isempty(root), root = findToolbox(prcRoot); end

if ~isempty(root) && isfolder(fullfile(root, '+nirs', '+modules'))
    addToolboxPath(root);
elseif ~isempty(root)
    warning('prcNIR_setup:NotAToolbox', ...
            '%s does not contain +nirs/+modules; leaving the path alone.', root);
    root = '';
end

%% ========================================================================
%  Patch (only when asked)
%  ========================================================================
if options.Patch && ~isempty(root)
    patch_nirs_toolbox(root);
end

%% ========================================================================
%  Report
%  ========================================================================
args = {};
if ~isempty(root), args = {'ToolboxRoot', root}; end
[checks, allOk] = prc.checkEnvironment(args{:});

if ~options.Quiet
    fprintf('\n  prcNIR  %s\n', prcRoot);
    for k = 1:numel(checks)
        if strcmp(checks(k).state, 'ok'), mark = '  ✓'; else, mark = '  ✗'; end
        if isempty(checks(k).detail)
            fprintf('%s  %s\n', mark, checks(k).label);
        else
            fprintf('%s  %-38s %s\n', mark, checks(k).label, checks(k).detail);
        end
    end
    if allOk
        fprintf('\n  Ready.\n\n');
    else
        fprintf('\n  Not ready. ');
        if any(strcmp({checks.action}, 'patch'))
            fprintf('For the patch, run:  prcNIR_setup(''Patch'', true)\n\n');
        else
            fprintf('See the failures above.\n\n');
        end
    end
end

if nargout == 0, clear checks allOk; end
% _________________________________________________________________________
end

%% ========================================================================
%  Auxilliary Functions
%  ========================================================================
function root = findToolbox(prcRoot)
% Walk up from prcNIR looking for a sibling nirs-toolbox, then fall back to
% whatever is already on the path. Covers the usual layouts -- side by side, or
% both under a shared Software/ folder -- without anyone configuring anything.
    root = '';
    here = prcRoot;
    for depth = 1:4
        here = fileparts(here);
        if isempty(here), break; end
        candidate = fullfile(here, 'nirs-toolbox');
        if isfolder(fullfile(candidate, '+nirs', '+modules'))
            root = candidate; return
        end
    end

    parts = strsplit(path, pathsep);
    keep  = cellfun(@(d) ~isempty(d) && isfolder(fullfile(d, '+nirs', '+modules')), parts);
    found = parts(keep);
    if ~isempty(found), root = found{1}; end
end

function addToolboxPath(root)
% genpath, minus hidden folders. .git alone is a few hundred entries and makes
% every subsequent path lookup slower for no benefit.
    p = strsplit(genpath(root), pathsep);
    p = p(~cellfun(@isempty, p));
    p = p(~contains(p, [filesep '.']));
    addpath(strjoin(p, pathsep));
end
