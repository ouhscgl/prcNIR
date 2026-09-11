function [checks, allOk] = checkEnvironment(options)
% PRC.CHECKENVIRONMENT - Everything that has to be true before prcNIR can run.
%
% Usage:
%   prc.checkEnvironment()                          % prints a report
%   [checks, allOk] = prc.checkEnvironment(...)
%   checks = prc.checkEnvironment('OutputDir', d)   % also test writability
%
% Every check here is fatal. There is no degraded mode: a missing toolbox or an
% unpatched nirs-toolbox does not produce slightly worse output, it produces
% wrong output or a stack trace forty minutes in. The app's status strip renders
% this struct directly, one row per entry.
%
% Outputs:
%   checks - struct array: .id .label .state ('ok'|'fail') .detail .action
%            .action names what a UI button could do about it, '' when nothing
%            can be done automatically.
%   allOk  - true when every check passed
%
% See also PRCNIR_SETUP, PATCH_NIRS_TOOLBOX

arguments
    options.ToolboxRoot (1,:) char = ''
    options.OutputDir   (1,:) char = ''
end

checks = struct('id', {}, 'label', {}, 'state', {}, 'detail', {}, 'action', {});

%% ========================================================================
%  MATLAB itself
%  ========================================================================
%-- R2020b (9.9) is the floor: `arguments` blocks, uigridlayout, and uitable
%   editing all behave from there on.
rel = version('-release');
if verLessThan('matlab', '9.9')
    add('matlab', 'MATLAB R2020b or newer', 'fail', ...
        sprintf('found R%s; prcNIR needs R2020b or newer', rel), '');
else
    add('matlab', 'MATLAB R2020b or newer', 'ok', sprintf('R%s', rel), '');
end

%% ========================================================================
%  MathWorks toolboxes
%  ========================================================================
%-- Statistics: MixedEffects is fitlme.
addToolbox('stats', 'Statistics and Machine Learning Toolbox', 'stats', ...
           {'fitlme'}, 'nirs.modules.MixedEffects needs fitlme');

%-- Signal Processing: TDDR is butter + filtfilt.
addToolbox('signal', 'Signal Processing Toolbox', 'signal', ...
           {'butter','filtfilt'}, 'nirs.math.tddr needs butter and filtfilt');

%% ========================================================================
%  prcNIR on the path
%  ========================================================================
%-- loadSNIRF_repairStructFields and loadSNIRF_filterStructArray are injected
%   INTO nirs-toolbox by the patch, so if m__extensions is missing, loading a
%   SNIRF file dies inside the toolbox rather than anywhere obvious.
missing = {};
for fn = {'getLeafs','generateProbeInfo','loadSNIRF_repairStructFields', ...
          'loadSNIRF_filterStructArray'}
    if exist(fn{1}, 'file') ~= 2, missing{end+1} = fn{1}; end %#ok<AGROW>
end
if exist('prc.defaults', 'file') ~= 2, missing{end+1} = 'prc.defaults'; end
if isempty(missing)
    add('prcnir', 'prcNIR on the path', 'ok', '', '');
else
    add('prcnir', 'prcNIR on the path', 'fail', ...
        sprintf('cannot find: %s — run prcNIR_setup', strjoin(missing, ', ')), 'setup');
end

%% ========================================================================
%  nirs-toolbox
%  ========================================================================
roots = toolboxRoots();
if ~isempty(options.ToolboxRoot)
    root = options.ToolboxRoot;
    if ~isfolder(fullfile(root, '+nirs', '+modules'))
        add('toolbox', 'nirs-toolbox on the path', 'fail', ...
            sprintf('%s does not contain +nirs/+modules', root), '');
        root = '';
    else
        add('toolbox', 'nirs-toolbox on the path', 'ok', root, '');
    end
elseif isempty(roots)
    root = '';
    add('toolbox', 'nirs-toolbox on the path', 'fail', ...
        'not found — add it with prcNIR_setup', 'setup');
elseif numel(roots) > 1
    %-- two copies shadow each other unpredictably; which one wins depends on
    %   path order, and the patched one is not necessarily first.
    root = roots{1};
    add('toolbox', 'nirs-toolbox on the path', 'fail', ...
        sprintf('%d copies are on the path: %s', numel(roots), strjoin(roots, '  |  ')), '');
else
    root = roots{1};
    add('toolbox', 'nirs-toolbox on the path', 'ok', root, '');
end

%% ========================================================================
%  Patch state
%  ========================================================================
if isempty(root)
    add('patch', 'nirs-toolbox patched', 'fail', 'no toolbox to check', '');
elseif exist('patch_nirs_toolbox', 'file') ~= 2
    add('patch', 'nirs-toolbox patched', 'fail', ...
        'patch_nirs_toolbox is not on the path', 'setup');
else
    [st, ok] = patch_nirs_toolbox(root, 'CheckOnly', true, 'Verbose', false);
    if ok
        add('patch', 'nirs-toolbox patched', 'ok', ...
            sprintf('%d/%d', numel(st), numel(st)), '');
    else
        bad = st(~strcmp({st.state}, 'ok'));
        add('patch', 'nirs-toolbox patched', 'fail', ...
            sprintf('%d/%d — %s', sum(strcmp({st.state},'ok')), numel(st), ...
                    strjoin(arrayfun(@(x) sprintf('%s (%s)', x.file, x.state), ...
                                     bad, 'UniformOutput', false), ', ')), ...
            'patch');
    end
end

%% ========================================================================
%  Dictionary shadowing
%  ========================================================================
%-- nirs-toolbox ships its own Dictionary in external/. If anything else on the
%   path answers to that name first, every stimulus operation silently uses the
%   wrong class.
if ~isempty(root)
    d = which('Dictionary');
    if isempty(d)
        add('dictionary', 'Dictionary resolves to nirs-toolbox', 'fail', ...
            'not found — is external/ on the path?', 'setup');
    elseif ~startsWith(lower(d), lower(root))
        add('dictionary', 'Dictionary resolves to nirs-toolbox', 'fail', ...
            sprintf('shadowed by %s', d), '');
    else
        add('dictionary', 'Dictionary resolves to nirs-toolbox', 'ok', '', '');
    end
end

%% ========================================================================
%  Output directory
%  ========================================================================
if ~isempty(options.OutputDir)
    [wok, why] = isWritable(options.OutputDir);
    if wok
        add('output', 'Output folder writable', 'ok', options.OutputDir, '');
    else
        add('output', 'Output folder writable', 'fail', why, '');
    end
end

%% ========================================================================
%  Verdict
%  ========================================================================
allOk = all(strcmp({checks.state}, 'ok'));

if nargout == 0
    fprintf('\n');
    for k = 1:numel(checks)
        if strcmp(checks(k).state, 'ok'), mark = '  ✓'; else, mark = '  ✗'; end
        if isempty(checks(k).detail)
            fprintf('%s  %s\n', mark, checks(k).label);
        else
            fprintf('%s  %-38s %s\n', mark, checks(k).label, checks(k).detail);
        end
    end
    fprintf('\n');
    clear checks allOk
end
% _________________________________________________________________________

%% ========================================================================
%  Nested helpers (share `checks`)
%  ========================================================================
function add(id, label, state, detail, action)
    checks(end+1) = struct('id', id, 'label', label, 'state', state, ...
                           'detail', detail, 'action', action); %#ok<AGROW>
end

function addToolbox(id, label, verTag, fns, why)
    have = ~isempty(ver(verTag));
    for ii = 1:numel(fns)
        have = have && exist(fns{ii}, 'file') > 0;
    end
    if have
        v = ver(verTag);
        add(id, label, 'ok', sprintf('v%s', v(1).Version), '');
    else
        add(id, label, 'fail', ['not installed — ' why], '');
    end
end
end

%% ========================================================================
%  Auxilliary Functions
%  ========================================================================
function roots = toolboxRoots()
% Every folder on the MATLAB path that is the parent of a +nirs/+modules
% package -- i.e. every nirs-toolbox root currently visible.
    parts = strsplit(path, pathsep);
    keep  = cellfun(@(d) ~isempty(d) && isfolder(fullfile(d, '+nirs', '+modules')), parts);
    roots = unique(parts(keep), 'stable');
end

function [ok, why] = isWritable(d)
    ok = false;
    if ~isfolder(d)
        [ok, msg] = mkdir(d);
        if ~ok, why = sprintf('cannot create %s (%s)', d, msg); return; end
    end
    [~, nm] = fileparts(tempname);
    probe   = fullfile(d, ['.prcnir_' nm]);
    fid     = fopen(probe, 'w');
    if fid == -1
        ok  = false;
        why = sprintf('%s is not writable', d);
        return
    end
    fclose(fid); delete(probe);
    ok = true; why = '';
end
