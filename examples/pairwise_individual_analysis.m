%% ========================================================================
%  Load data, paths
%  ========================================================================
DATA_PATH         = 'SET THIS TO WHERE YOUR RAW DATA IS';
PROGRAMPATH       = 'SET THIS TO WHERE YOUR SOFTWARE`S PARENT FOLDER IS';

%-- prcNIR_setup puts both prcNIR and nirs-toolbox on the path and then checks
%   that everything it needs is actually there: MATLAB version, the two
%   MathWorks toolboxes, and whether nirs-toolbox is patched. All of those are
%   fatal, so it is worth failing here rather than an hour into a run.
%   First time on a machine, run it once as:  prcNIR_setup('Patch', true)
addpath(fullfile(PROGRAMPATH, 'prcNIR'));
[~, ready] = prcNIR_setup('ToolboxRoot', fullfile(PROGRAMPATH, 'nirs-toolbox'));
if ~ready, error('Environment is not ready -- see the failures above.'); end

%% ========================================================================
%  Clean dataset
%  ========================================================================
%% General cleaning -> changing pinfo
clean_dir = fullfile(pwd,'clean_dataset');   % overridden below if the profile sets one
fNIRS_cleanRawData( ...
    'InputDir',   DATA_PATH, ...
    'OptodeLink', fullfile(PROGRAMPATH,'prcNIR','configs', ...
                           'nirscout_optode_data_link_traditional.csv'), ...
    'OptodeGeom', fullfile(PROGRAMPATH,'prcNIR','configs', ...
                           'nirscout_optode_data_geom_traditional.csv'), ...
    'OutputDir',  clean_dir);

%% ========================================================================
%  Process dataset
%  ========================================================================
%% Apply settings
%-- One profile holds the whole analysis: stimulus naming, the pipeline, the
%   models and the contrasts. Edit configs/profiles/example.json by hand or in
%   the app; both write the same file.
settingsFile = fullfile(PROGRAMPATH,'prcNIR','configs','profiles','example.json');
[cfg, meta]  = prc.loadSettings(settingsFile, 'nback_pairwise');
user_vars    = prc.toUserVars(cfg);

%% Create analysis framework
% Requirments: 
% (1) All files in individual folders, folders named the same except visit
% number (e.g.: FIL001_V1_NBK and FIL001_V2_NBK or CC00001_nback_V1 and
% CC00001_nback_V2 will be paired, but LAT002_v1_nback and LAT002_nback_V2
% will not.
% (2) Folders should have V1 and V2 within them.
folders =dir(clean_dir);
folders ={folders([folders.isdir] & ~startsWith({folders.name},'.')).name};
v1 = folders(contains(folders, 'V1'));
v2 = cellfun(@(x) strrep(x, 'V1', 'V2'), v1, 'UniformOutput', false);
valid = ismember(v2, folders);
pairs = [v1(valid); v2(valid)];
fprintf('Found %d pairs.\n', size(pairs, 2));

%% Analyze dataset (pairwise)
%-- paths in a profile are relative to the profile file; unset means "here"
resultsdir = prc.abspath(cfg.paths.output_dir, meta.root);
if isempty(resultsdir), resultsdir = fullfile(pwd,'results'); end
tmpdir     = fullfile(pwd,'temp');

for i = 1:size(pairs, 2)
    pairname = strrep(pairs{1,i}, 'V1', '');
    outdir   = fullfile(resultsdir, pairname);
    if ~isfolder(outdir), mkdir(outdir); end
    
    if exist(tmpdir, 'dir'), rmdir(tmpdir, 's'); end
    mkdir(fullfile(tmpdir, 'V1')); mkdir(fullfile(tmpdir, 'V2'));
    copyfile(fullfile(clean_dir, pairs{1,i}), ...
             fullfile(tmpdir, 'V1', pairs{1,i}));
    copyfile(fullfile(clean_dir, pairs{2,i}), ...
             fullfile(tmpdir, 'V2', pairs{2,i}));
    
    [PairStats,~,~] = fNIRS_Process(tmpdir, user_vars);
    
    %-- PairStats carries one fitted model per formula, in profile order, so a
    %   contrast is drawn against the model it names rather than whichever one
    %   happened to come out first.
    for m = 1:numel(cfg.pipeline.group.models)
        modelName = cfg.pipeline.group.models{m}.name;
        modelCfg  = cfg;
        modelCfg.visualize.contrasts = contrastsFor(cfg, modelName);
        if isempty(modelCfg.visualize.contrasts), continue; end
        
        viz = prc.toVizParams(modelCfg, PairStats(m), outdir);
        fNIRS_Visualize(PairStats(m), 0, viz);
        writetable(PairStats(m).table(), ...
                   fullfile(outdir, ['raw_betas_' modelName '.csv']));
    end
end
rmdir(tmpdir, 's');

%% ========================================================================
%  Auxilliary Functions
%  ========================================================================
function out = contrastsFor(cfg, modelName)
% The contrasts in this profile that belong to one model. A contrast without a
% model of its own falls back to visualize.model.
    out = {};
    for k = 1:numel(cfg.visualize.contrasts)
        c = cfg.visualize.contrasts{k};
        if isfield(c,'model') && ~isempty(c.model), owner = c.model;
        else,                                      owner = cfg.visualize.model;
        end
        if strcmp(owner, modelName), out{end+1} = c; end %#ok<AGROW>
    end
end
