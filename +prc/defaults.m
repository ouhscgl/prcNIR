function cfg = defaults()
% PRC.DEFAULTS - Canonical default profile for prcNIR.
%
% Usage:
%   cfg = prc.defaults()
%
% This is the single source of truth for every default in the toolchain.
% prc.loadSettings overlays a user's JSON on top of it, prc.validateSettings
% checks unknown keys against it, and the app populates its controls from it.
% Nothing else should carry a hard-coded default.
%
% The returned struct is in NORMALISED form, meaning:
%    - every list-of-things field is a cell array (never a struct array)
%    - every string list is a cellstr
%    - numeric ranges are row vectors
%    - "use the recording's own value" is NaN, never empty
%
% See docs/settings-schema.md for the JSON shape this mirrors.

cfg = struct();
cfg.label = 'Untitled profile';
cfg.notes = '';

%% ========================================================================
%  Paths
%  ========================================================================
cfg.paths = struct( ...
    'data_root',  '', ...
    'output_dir', '', ...
    'clean_dir',  '');

%% ========================================================================
%  Montage & dataset discovery
%  ========================================================================
cfg.montage = 'nirsport';
cfg.dataset = struct('folder_structure', {{'group','subject'}});

%% ========================================================================
%  Stimulus
%  ========================================================================
%-- names are applied in SORTED marker order; onset/duration NaN keeps
%   whatever the recording already carries.
cfg.stimulus = struct( ...
    'names',    {{'nback0a','nback1a','nback0b','nback2a'}}, ...
    'onset',    NaN, ...
    'duration', 72);

%% ========================================================================
%  Pipeline
%  ========================================================================
%-- Preprocessing: mirrors the fixed chain fNIRS_Process has always run, so
%   a profile that omits this block behaves exactly like the old code.
cfg.pipeline = struct();
cfg.pipeline.preprocess = { ...
    mkstep('TrimBaseline',         'preBaseline', 10, 'postBaseline', 10), ...
    mkstep('LabelShortSeperation', 'max_distance', 10), ...
    mkstep('LabeltooLongDistance', 'min_distance', 50), ...
    mkstep('RemovetooLongDistance'), ...
    mkstep('OpticalDensity'), ...
    mkstep('TDDR'), ...
    mkstep('BeerLambertLaw') };

%-- GLM: 'trend' is sugar for a function handle, which JSON cannot hold.
cfg.pipeline.glm = struct( ...
    'module',                   'GLM', ...
    'enabled',                  true, ...
    'trend',                    struct('type','dct','value',0.009), ...
    'add_short_sep_regressors', true, ...
    'remove_short_seperations', true);

%-- Group: each model is fitted separately and keeps its name. Contrasts
%   reference a model BY NAME, which is what stops a contrast built for one
%   formula being silently applied to another.
cfg.pipeline.group = struct('module', 'MixedEffects', 'enabled', true);
cfg.pipeline.group.models = { ...
    struct('name','group_main',    'formula','beta ~ -1 + group + (1|subject)'), ...
    struct('name','group_by_cond', 'formula','beta ~ -1 + group:cond + (1|subject)') };

%-- Post: modules applied to the fitted stats, not the time series. HbT
%   belongs here -- CalculateTotalHb takes the sum in beta space rather than
%   summing the signal before the model sees it.
cfg.pipeline.post = { mkstep('CalculateTotalHb', 'enabled', false) };

%% ========================================================================
%  Visualisation
%  ========================================================================
cfg.visualize = struct( ...
    'model',         'group_by_cond', ...
    'significance',  {{'p'}}, ...
    'threshold',     0.05, ...
    'tstat_range',   [-8 8], ...
    'chromophores',  {{'hbo'}}, ...
    'save_table',    true, ...
    'draw_method',   '10-20 map', ...
    'fig_format',    'svg', ...
    'output_prefix', '');
cfg.visualize.contrasts = {};
% _________________________________________________________________________
end

%% ========================================================================
%  Auxilliary Functions
%  ========================================================================
function s = mkstep(moduleName, varargin)
    s = struct('module', moduleName, 'enabled', true);
    for k = 1:2:numel(varargin)
        s.(varargin{k}) = varargin{k+1};
    end
end
