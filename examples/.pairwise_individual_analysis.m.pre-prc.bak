%% ========================================================================
%  Load data, paths
%  ========================================================================
DATA_PATH         = 'SET THIS TO WHERE YOUR RAW DATA IS';
PROGRAMPATH       = 'SET THIS TO WHERE YOUR SOFTWARE`S PARENT FOLDER IS';

NIRS_PATH         = fullfile(PROGRAMPATH,'prcNIR');
NIRS_TOOLBOX_PATH = fullfile(PROGRAMPATH,'nirs-toolbox');
addpath(genpath(NIRS_TOOLBOX_PATH),genpath(NIRS_PATH));
fprintf('\nPaths loaded in successfully.\n');

%% ========================================================================
%  Clean dataset
%  ========================================================================
%% General cleaning -> changing pinfo
clean_dir = fullfile(pwd,'clean_dataset');
NRA_cleanFNIRSData(DATA_PATH, ...
    'nirscout_optode_data_link_traditional.csv', ...
    'nirscout_optode_data_geom_traditional.csv', [], clean_dir)

%% ========================================================================
%  Process dataset
%  ========================================================================
%% Apply settings
settings=load_settings('example_settings.json');
prc             = settings.nir.processing.nback_pairwise;
viz             = settings.nir.visualizing.nback_pairwise; 
viz.contrasts   = settings.contrasts.nback_pairwise;

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
resultsdir = fullfile(pwd,'results'); tmpdir = fullfile(pwd,'temp');
for i = 1:size(pairs, 2)
    pairname = strrep(pairs{1,i}, 'V1', '');
    viz.output_dir = fullfile(resultsdir, pairname);
    
    if exist(tmpdir, 'dir'), rmdir(tmpdir, 's'); end
    mkdir(fullfile(tmpdir, 'V1')); mkdir(fullfile(tmpdir, 'V2'));
    copyfile(fullfile(clean_dir, pairs{1,i}), ...
             fullfile(tmpdir, 'V1', pairs{1,i}));
    copyfile(fullfile(clean_dir, pairs{2,i}), ...
             fullfile(tmpdir, 'V2', pairs{2,i}));
    
    [PairStats,~,~] = fNIRS_Process(tmpdir, prc);
    fNIRS_ControlPanel(PairStats, 0, 'auto', viz);
    writetable(PairStats.table(),fullfile(viz.output_dir,'raw_betas.csv'));
end
rmdir(tmpdir, 's');


