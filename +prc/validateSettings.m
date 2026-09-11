function [ok, problems] = validateSettings(cfg)
% PRC.VALIDATESETTINGS - Check a profile before anything expensive runs.
%
% Usage:
%   prc.validateSettings(cfg)                % prints a report
%   [ok, problems] = prc.validateSettings(cfg)
%
% Two severities. An 'error' means the profile cannot run and prc.loadSettings
% will refuse it. A 'warning' means it will run but probably not as intended --
% an unknown key is the usual case, and silently ignoring those is how a typo'd
% setting costs someone an afternoon.
%
% The module checks are the valuable ones: every step's class and every property
% name is verified against the real nirs.modules class, so a misspelled
% property fails here rather than after the GLM.
%
% Outputs:
%   ok       - true when there are no errors (warnings do not clear it)
%   problems - struct array: .severity, .path, .message
%
% See also PRC.DEFAULTS, PRC.LOADSETTINGS

arguments
    cfg (1,1) struct
end

problems = struct('severity', {}, 'path', {}, 'message', {});
D        = prc.defaults();

TREND_TYPES   = {'dct','legendre','constant','none'};
SIG_TYPES     = {'p','q'};
CHROMOPHORES  = {'hbo','hbr','hbt','sto2'};
FIG_FORMATS   = {'svg','png','jpg','jpeg','tif','tiff','pdf','eps','epsc','bmp','fig'};

haveToolbox = exist('nirs.modules.GLM', 'class') == 8;
if ~haveToolbox
    add('warning', 'pipeline', ...
        'nirs-toolbox is not on the path, so module and property names were not checked.');
end

%% ========================================================================
%  Top level
%  ========================================================================
unknownKeys(cfg, D, '');

for fn = {'label','notes','montage'}
    if isfield(cfg, fn{1}) && ~ischar(cfg.(fn{1}))
        add('error', fn{1}, 'must be a string.');
    end
end
if isfield(cfg,'montage') && isempty(cfg.montage)
    add('error', 'montage', 'must name a montage in configs/montages/.');
end

%% ========================================================================
%  Paths
%  ========================================================================
if isfield(cfg, 'paths')
    unknownKeys(cfg.paths, D.paths, 'paths');
    pf = fieldnames(cfg.paths);
    for i = 1:numel(pf)
        if ~ischar(cfg.paths.(pf{i}))
            add('error', ['paths.' pf{i}], 'must be a string (use "" for unset).');
        end
    end
end

%% ========================================================================
%  Dataset
%  ========================================================================
if isfield(cfg, 'dataset') && isfield(cfg.dataset, 'folder_structure')
    unknownKeys(cfg.dataset, D.dataset, 'dataset');
    fs = cfg.dataset.folder_structure;
    if ~iscellstr(fs) %#ok<ISCLSTR>
        add('error', 'dataset.folder_structure', 'must be a list of strings.');
    else
        bad = fs(~cellfun(@isvarname, fs));
        if ~isempty(bad)
            add('error', 'dataset.folder_structure', ...
                sprintf(['%s cannot be a demographics field name. Use letters, ', ...
                         'digits and underscores, not starting with a digit.'], ...
                        strjoin(strcat('"', bad, '"'), ', ')));
        end
    end
end

%% ========================================================================
%  Stimulus
%  ========================================================================
if isfield(cfg, 'stimulus') && isfield(cfg.stimulus, 'names')
    unknownKeys(cfg.stimulus, D.stimulus, 'stimulus');
    if ~iscellstr(cfg.stimulus.names) %#ok<ISCLSTR>
        add('error', 'stimulus.names', 'must be a list of strings.');
    elseif isempty(cfg.stimulus.names)
        add('warning', 'stimulus.names', ...
            'is empty, so markers keep their generic marker01.. names.');
    end
    for fn = {'onset','duration'}
        if ~isfield(cfg.stimulus, fn{1}), continue; end
        v = cfg.stimulus.(fn{1});
        if ~isnumeric(v)
            add('error', ['stimulus.' fn{1}], 'must be a number, a list of numbers, or null.');
        elseif numel(v) > 1 && iscellstr(cfg.stimulus.names) ... %#ok<ISCLSTR>
                && numel(v) ~= numel(cfg.stimulus.names)
            add('error', ['stimulus.' fn{1}], ...
                sprintf('has %d values but there are %d stimulus names.', ...
                        numel(v), numel(cfg.stimulus.names)));
        end
    end
end

%% ========================================================================
%  Pipeline
%  ========================================================================
modelNames = {};
if isfield(cfg, 'pipeline')
    P = cfg.pipeline;
    unknownKeys(P, D.pipeline, 'pipeline');

    %-- preprocess / post: module + property checks
    for fn = {'preprocess','post'}
        if ~isfield(P, fn{1}), continue; end
        steps = P.(fn{1});
        for k = 1:numel(steps)
            checkModule(steps{k}, sprintf('pipeline.%s(%d)', fn{1}, k));
        end
    end

    %-- glm
    if isfield(P, 'glm')
        %-- a GLM block carries both schema sugar (trend, the short-sep flags)
        %   and real module properties such as type or basis, so both sets are
        %   legal and anything outside them is a typo worth naming.
        unknownKeys(P.glm, D.pipeline.glm, 'pipeline.glm', moduleProps(P.glm));
        checkModuleClass(P.glm, 'pipeline.glm');
        if isfield(P.glm, 'trend')
            t = P.glm.trend;
            if ~isstruct(t) || ~isfield(t, 'type')
                add('error', 'pipeline.glm.trend', 'needs a "type".');
            elseif ~any(strcmpi(t.type, TREND_TYPES))
                add('error', 'pipeline.glm.trend.type', ...
                    sprintf('"%s" is not one of: %s.', t.type, strjoin(TREND_TYPES, ', ')));
            elseif any(strcmpi(t.type, {'dct','legendre'}))
                if ~isfield(t,'value') || ~isnumeric(t.value) || ~isscalar(t.value)
                    add('error', 'pipeline.glm.trend.value', ...
                        sprintf('a "%s" trend needs a numeric value.', t.type));
                end
            end
        end
    end

    %-- group models
    if isfield(P, 'group') && isfield(P.group, 'models')
        unknownKeys(P.group, D.pipeline.group, 'pipeline.group', moduleProps(P.group));
        checkModuleClass(P.group, 'pipeline.group');
        models = P.group.models;
        if isempty(models)
            add('error', 'pipeline.group.models', 'at least one model is required.');
        end
        for k = 1:numel(models)
            m = models{k}; pth = sprintf('pipeline.group.models(%d)', k);
            if ~isfield(m,'name') || ~ischar(m.name) || isempty(m.name)
                add('error', pth, 'needs a "name".');
            elseif ~isvarname(m.name)
                add('error', [pth '.name'], ...
                    sprintf('"%s" must be a plain identifier so contrasts can reference it.', m.name));
            else
                if any(strcmp(m.name, modelNames))
                    add('error', [pth '.name'], sprintf('"%s" is used twice.', m.name));
                end
                modelNames{end+1} = m.name; %#ok<AGROW>
            end
            if ~isfield(m,'formula') || ~ischar(m.formula) || isempty(m.formula)
                add('error', pth, 'needs a "formula".');
            elseif ~contains(m.formula, '~')
                add('error', [pth '.formula'], ...
                    sprintf('"%s" is not Wilkinson notation -- it needs a ~.', m.formula));
            end
        end
    end
end

%% ========================================================================
%  Visualisation
%  ========================================================================
if isfield(cfg, 'visualize')
    V = cfg.visualize;
    unknownKeys(V, D.visualize, 'visualize');

    if ~isempty(modelNames) && isfield(V,'model') && ~isempty(V.model) ...
            && ~any(strcmp(V.model, modelNames))
        add('error', 'visualize.model', ...
            sprintf('"%s" is not a model. Defined: %s.', V.model, strjoin(modelNames, ', ')));
    end

    inSet(V, 'significance', SIG_TYPES,    'visualize.significance');
    inSet(V, 'chromophores', CHROMOPHORES, 'visualize.chromophores');

    if isfield(V,'threshold') && (~isnumeric(V.threshold) || ~isscalar(V.threshold) ...
            || V.threshold <= 0 || V.threshold > 1)
        add('error', 'visualize.threshold', 'must be a number in (0, 1].');
    end
    if isfield(V,'tstat_range') && (numel(V.tstat_range) ~= 2 ...
            || V.tstat_range(1) >= V.tstat_range(2))
        add('error', 'visualize.tstat_range', 'must be [low high] with low < high.');
    end
    if isfield(V,'fig_format') && ~any(strcmpi(V.fig_format, FIG_FORMATS))
        add('error', 'visualize.fig_format', ...
            sprintf('"%s" is not one of: %s.', V.fig_format, strjoin(FIG_FORMATS, ', ')));
    end
    if isfield(V,'draw_method') && (~ischar(V.draw_method) || isempty(V.draw_method))
        add('error', 'visualize.draw_method', 'must be a string, e.g. "10-20 map".');
    end

    %-- contrasts
    if isfield(V, 'contrasts')
        for k = 1:numel(V.contrasts)
            checkContrast(V.contrasts{k}, sprintf('visualize.contrasts(%d)', k), modelNames);
        end
        if isempty(V.contrasts)
            add('warning', 'visualize.contrasts', ...
                'is empty, so the run will fit models but draw nothing.');
        end
    end
end

%% ========================================================================
%  Verdict
%  ========================================================================
ok = ~any(strcmp({problems.severity}, 'error'));

if nargout == 0
    if isempty(problems)
        fprintf('  ✓ profile is valid.\n');
    else
        for k = 1:numel(problems)
            if strcmp(problems(k).severity,'error'), mark = '  ✗'; else, mark = '  !'; end
            fprintf('%s  %-34s %s\n', mark, problems(k).path, problems(k).message);
        end
    end
    clear ok
end
% _________________________________________________________________________

%% ========================================================================
%  Nested checks (share `problems`, `D`, `haveToolbox`)
%  ========================================================================
function add(sev, pth, msg)
    problems(end+1) = struct('severity', sev, 'path', pth, 'message', msg); %#ok<AGROW>
end

function unknownKeys(actual, expected, prefix, alsoAllowed)
    if ~isstruct(actual) || ~isstruct(expected), return; end
    if nargin < 4, alsoAllowed = {}; end
    known = [fieldnames(expected); alsoAllowed(:)];
    extra = setdiff(fieldnames(actual), known);
    for ii = 1:numel(extra)
        if isempty(prefix), pth = extra{ii}; else, pth = [prefix '.' extra{ii}]; end
        hint = suggest(extra{ii}, known);
        if isempty(hint)
            add('warning', pth, 'is not a setting prcNIR knows about; it will be ignored.');
        else
            add('warning', pth, sprintf('is not a setting prcNIR knows about. Did you mean "%s"?', hint));
        end
    end
end

function inSet(S, field, allowed, pth)
    if ~isfield(S, field), return; end
    v = S.(field);
    if ~iscellstr(v) %#ok<ISCLSTR>
        add('error', pth, 'must be a list of strings.'); return
    end
    bad = v(~ismember(lower(v), allowed));
    if ~isempty(bad)
        add('error', pth, sprintf('%s not one of: %s.', ...
            strjoin(strcat('"', bad, '"'), ', '), strjoin(allowed, ', ')));
    end
end

function checkModule(step, pth)
    if ~isstruct(step) || ~isfield(step, 'module') || ~ischar(step.module)
        add('error', pth, 'every step needs a "module" naming a nirs.modules class.');
        return
    end
    if isfield(step,'enabled') && ~islogical(step.enabled) && ~isnumeric(step.enabled)
        add('error', [pth '.enabled'], 'must be true or false.');
    end
    if ~haveToolbox, return; end

    cls = ['nirs.modules.' step.module];
    if exist(cls, 'class') ~= 8
        add('error', [pth '.module'], sprintf('"%s" is not a nirs-toolbox module.', step.module));
        return
    end
    props = properties(cls);
    keys  = setdiff(fieldnames(step), {'module','enabled'});
    for ii = 1:numel(keys)
        if ~any(strcmp(keys{ii}, props))
            hint = suggest(keys{ii}, props);
            if isempty(hint)
                add('error', [pth '.' keys{ii}], ...
                    sprintf('%s has no such property. It has: %s.', ...
                            step.module, strjoin(props(:)', ', ')));
            else
                add('error', [pth '.' keys{ii}], ...
                    sprintf('%s has no such property. Did you mean "%s"?', step.module, hint));
            end
        end
    end
end

function props = moduleProps(block)
% The public properties of the nirs.modules class a block names, or {} when the
% toolbox is not loaded and we cannot know.
    props = {};
    if ~haveToolbox || ~isstruct(block) || ~isfield(block,'module'), return; end
    cls = ['nirs.modules.' block.module];
    if exist(cls, 'class') == 8, props = properties(cls); end
end

function checkModuleClass(block, pth)
    if ~isstruct(block) || ~isfield(block,'module') || ~ischar(block.module)
        add('error', pth, 'needs a "module" naming a nirs.modules class.'); return
    end
    if ~haveToolbox, return; end
    if exist(['nirs.modules.' block.module], 'class') ~= 8
        add('error', [pth '.module'], ...
            sprintf('"%s" is not a nirs-toolbox module.', block.module));
    end
end

function checkContrast(c, pth, models)
    if ~isstruct(c)
        add('error', pth, 'must be an object.'); return
    end
    if ~isfield(c,'name') || ~ischar(c.name) || isempty(c.name)
        add('error', pth, 'needs a "name" -- it becomes the output filename.');
    end
    if isfield(c,'model') && ~isempty(c.model) && ~isempty(models) ...
            && ~any(strcmp(c.model, models))
        add('error', [pth '.model'], ...
            sprintf('"%s" is not a model. Defined: %s.', c.model, strjoin(models, ', ')));
    end

    hasW = isfield(c,'weights') && ~isempty(c.weights);
    hasV = isfield(c,'vector')  && ~isempty(c.vector);
    if hasW && hasV
        add('error', pth, 'has both "weights" and "vector"; keep one.');
    elseif ~hasW && ~hasV
        add('error', pth, 'needs either "weights" (preferred) or "vector".');
    end

    if hasW
        for ii = 1:numel(c.weights)
            w = c.weights{ii}; wp = sprintf('%s.weights(%d)', pth, ii);
            if ~isstruct(w) || ~isfield(w,'condition') || ~ischar(w.condition) || isempty(w.condition)
                add('error', wp, 'needs a "condition" naming a model condition.');
            end
            if ~isstruct(w) || ~isfield(w,'value') || ~isnumeric(w.value) || ~isscalar(w.value)
                add('error', wp, 'needs a numeric "value".');
            end
        end
    end
    if hasV && ~isnumeric(c.vector)
        add('error', [pth '.vector'], 'must be a list of numbers.');
    end
end
end

%% ========================================================================
%  Auxilliary Functions
%  ========================================================================
function hint = suggest(name, candidates)
% Cheap did-you-mean. Case differences and separator slips account for most
% real typos here (max_distance vs maxDistance), so those are all it chases.
    hint = '';
    candidates = candidates(:)';
    if isempty(candidates), return; end

    ix = find(strcmpi(name, candidates), 1);
    if ~isempty(ix), hint = candidates{ix}; return; end

    flat = @(s) lower(strrep(strrep(s, '_', ''), '-', ''));
    ix = find(strcmp(flat(name), cellfun(flat, candidates, 'UniformOutput', false)), 1);
    if ~isempty(ix), hint = candidates{ix}; return; end

    ix = find(contains(lower(candidates), lower(name)) | ...
              cellfun(@(c) contains(lower(name), lower(c)), candidates), 1);
    if ~isempty(ix), hint = candidates{ix}; end
end
