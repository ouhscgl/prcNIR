function user_vars = toUserVars(cfg)
% PRC.TOUSERVARS - Config profile -> the user_vars struct fNIRS_Process takes.
%
% Usage:
%   user_vars = prc.toUserVars(cfg);
%   stats     = fNIRS_Process(dataPath, user_vars);
%
% A bridge, not a destination. fNIRS_Process still runs its own fixed module
% chain, so the parts of a profile it cannot express are reported rather than
% silently dropped -- if a profile reorders the pipeline or enables a post
% module, you hear about it here instead of wondering why the output looks the
% same as last time.
%
% When fNIRS_Process is split into stages this becomes its compatibility shim
% and nothing that calls it has to change.

arguments
    cfg (1,1) struct
end

user_vars = struct();

%% ========================================================================
%  Straightforward mappings
%  ========================================================================
user_vars.folder_structure   = cfg.dataset.folder_structure;
user_vars.stim_names         = cfg.stimulus.names;
user_vars.stim_onset         = cfg.stimulus.onset;
user_vars.stim_dur           = cfg.stimulus.duration;
user_vars.regression_formula = cellfun(@(m) m.formula, cfg.pipeline.group.models, ...
                                       'UniformOutput', false);

%% ========================================================================
%  Values fNIRS_Process reads as scalars but the profile keeps on the module
%  ========================================================================
user_vars.max_short_distance = stepProp(cfg, 'LabelShortSeperation', 'max_distance', 10);
user_vars.max_regul_distance = stepProp(cfg, 'LabeltooLongDistance', 'min_distance', 50);

if isfield(cfg.pipeline,'glm') && isfield(cfg.pipeline.glm,'trend')
    t = cfg.pipeline.glm.trend;
    if strcmpi(t.type, 'dct') && isfield(t, 'value')
        user_vars.dct_value = t.value;
    else
        warning('prc:toUserVars:TrendIgnored', ...
               ['fNIRS_Process only knows how to build a DCT trend, so the ' ...
                '"%s" trend in this profile is not applied.'], t.type);
        user_vars.dct_value = 0.009;
    end
end

%% ========================================================================
%  Things the legacy entry point cannot express
%  ========================================================================
enabled = @(s) ~isfield(s,'enabled') || s.enabled;

%-- preprocessing is all-or-nothing over there
pre = cfg.pipeline.preprocess;
user_vars.do_preprocessing = ~isempty(pre) && any(cellfun(enabled, pre));


defaultChain = {'TrimBaseline','LabelShortSeperation','LabeltooLongDistance', ...
                'RemovetooLongDistance','OpticalDensity','TDDR','BeerLambertLaw'};
if isempty(pre), chain = {};
else, chain = cellfun(@(s) s.module, pre(cellfun(enabled, pre)), 'UniformOutput', false);
end
if ~isequal(chain, defaultChain)
    warning('prc:toUserVars:PipelineIgnored', ...
           ['This profile changes the preprocessing chain, but fNIRS_Process ' ...
            'runs a fixed one. Expected:\n    %s\n  Profile has:\n    %s'], ...
            strjoin(defaultChain, ' -> '), strjoin(chain, ' -> '));
end

%-- post modules act on fitted stats; the legacy path has no step for them
if isfield(cfg.pipeline, 'post')
    post = cfg.pipeline.post(cellfun(enabled, cfg.pipeline.post));
    if ~isempty(post)
        warning('prc:toUserVars:PostIgnored', ...
               ['fNIRS_Process does not apply post modules, so %s will not run. ' ...
                'Apply it to the returned stats yourself for now.'], ...
                strjoin(cellfun(@(s) s.module, post, 'UniformOutput', false), ', '));
    end
end

%-- the old in-place HbT hack stays off: it overwrites the HbO column rather
%   than adding an hbt type, which is what the post module exists to fix
user_vars.calculate_HbT = false;
end

%% ========================================================================
%  Auxilliary Functions
%  ========================================================================
function v = stepProp(cfg, moduleName, propName, fallback)
    v = fallback;
    steps = cfg.pipeline.preprocess;
    for k = 1:numel(steps)
        if strcmp(steps{k}.module, moduleName) && isfield(steps{k}, propName)
            v = steps{k}.(propName); return
        end
    end
end
