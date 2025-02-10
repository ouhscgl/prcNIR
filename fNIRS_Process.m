function [GroupStats, demograph, stimulus] ...
    = fNIRS_Process(load_path, nirstoolbox_path, user_vars)
% Data loading ____________________________________________________________
%-- Adding nirs-toolbox to path
addpath(genpath(nirstoolbox_path))
%-- Adding default user variables if not present
if ~isa(user_vars,'struct')
    user_vars = struct();
    user_vars.folder_structure  = {'group','subject'};
    user_vars.dct_value         = 0.009;
    user_vars.stim_names={'nback0a','nback1a','nback0b','nback2a'};
    user_vars.stim_onset=NaN;
    user_vars.stim_dur = 72;
    user_vars.max_short_distance = 10;
    user_vars.max_regul_distance = 50;
    user_vars.regression_formula = ...
        {'beta ~ -1 + group + (1|subject)', ...
         'beta ~ -1  + group:cond + (1|subject)'};
    user_vars.save_as_snirf_flag = false;
    user_vars.overwrite_as_snirf = false;
    user_vars.calculate_total_hb = false;
end
%-- Solo or directory data loading ( data_raws.probe.draw )
if ~isempty(dir(fullfile(load_path, '*.wl1')))
    data_raws = nirs.io.loadNIRx(load_path);
else
    data_raws = nirs.io.loadDirectory(load_path, ...
        user_vars.folder_structure, @nirs.io.loadNIRx,{'.wl1'});
end
% _________________________________________________________________________

% Stimulus correction _____________________________________________________
% -- Change stimulus data ( nirs.getStimNames(data_raws) );
job = nirs.modules.ChangeStimulusInfo   ();
mod_stimTable = stimTableMapper(nirs.createStimulusTable(data_raws),...
    user_vars.stim_names, user_vars.stim_onset, user_vars.stim_dur);
job.ChangeTable = mod_stimTable;
%-- Rename stimuli
job = nirs.modules.RenameStims          (job);
job.listOfChanges = cat(2, nirs.getStimNames(data_raws(1)), ...
                           user_vars.stim_names');
% _________________________________________________________________________

% Identify short channels and exclude faux channels _______________________
%-- Short channel identification
job = nirs.modules.LabelShortSeperation (job);
job.max_distance = user_vars.max_short_distance;
%-- Long channel identification and removal
job = nirs.modules.LabeltooLongDistance (job);
job.min_distance = user_vars.max_regul_distance;
job = nirs.modules.RemovetooLongDistance(job);
% _________________________________________________________________________

% Transform to physiological data _________________________________________
job = nirs.modules.OpticalDensity       (job);
job = nirs.modules.BeerLambertLaw       (job);
data_prps = job.run(data_raws);
% Calculate total hemoglobin - INDEV
if user_vars.calculate_total_hb
    temp = data_prps.data;
    for row=1:2:size(temp,2)
        data_prps.data(:,row) = temp(:,row) + temp(:,row+1);
    end
end
% _________________________________________________________________________

% Motion correction (Auto-regressive Iteratively Reweighted Least Squares)_
% Barker, J. W., Aarabi, A., & Huppert, T. J. (2013). 
% Autoregressive model based algorithm for correcting motion and serially 
% correlated errors in fNIRS. Biomedical optics express, 4(8), 1366–1379. 
% https://doi.org/10.1364/BOE.4.001366
job = nirs.modules.GLM                  ();
if any(data_prps(1).probe.link.ShortSeperation == 1)
    job.AddShortSepRegressors = true;
end
job.trend_func=@(t)nirs.design.trend.dctmtx(t, user_vars.dct_value);
data_stat = job.run(data_prps);
% _________________________________________________________________________

% Extract data from the preprocessing pipeline ____________________________
demograph = nirs.createDemographicsTable(data_prps);
stimulus  = nirs.createStimulusTable(data_prps);
% _________________________________________________________________________

% Statistical analysis (Mixed Effects Model, Wilkinson notation) __________
job = nirs.modules.MixedEffects();
for iter = 1:length(user_vars.regression_formula)
    job.formula = user_vars.regression_formula{iter};
    GroupStats(iter) = job.run(data_stat);
    disp(['Conditions for formula: ', user_vars.regression_formula{iter}])
    disp(GroupStats(iter).conditions)
end
% _________________________________________________________________________

% Save preprocessed data as .snirf ________________________________________
if user_vars.save_as_snirf_flag == true
    saveAsSNIRF(data_prps, demograph, load_path, ...
        user_vars.overwrite_as_snirf)
end
disp('Finished processing data.')
% _________________________________________________________________________

% Auxillary functions _____________________________________________________
function saveAsSNIRF(data, demo, load_path, overwrite)
    for i=1:length(data)
    visitID = '';
    if ismember('Visit',demo.Properties.VariableNames)
        visitID = strcat('_V',demo.Visit(i));
    end
    save_name = fullfile(load_path,[demo.Name{i},visitID{:},...
                            '.snirf']);
    if isfile(save_name) && ~overwrite
        validate =input('File already exists. Overwrite? [[y]/n]',"s");
        if isequal(lower(validate),'y') | isempty(validate)
            delete(save_name)
            nirs.io.saveSNIRF(data(i,1),save_name)
            disp(['Saved ',save_name,'.']);
        else
            disp(['Discarded ',demo.Name{i},'.snirf.']);
        end
    else
        nirs.io.saveSNIRF(data(i,1),save_name)
        disp(['[',num2str(i),']',' Saved ',save_name,'.']);
    end
    end
end
    
function [stim_table] = stimTableMapper(stim_table, ...
                            new_names, new_onsets, new_durs)
    for table=1:height(stim_table)
        len = width(stim_table);
        if isscalar(new_names)
            new_names = arrayfun(@(n) sprintf('channel_%d', n), 1:len, ...
                'UniformOutput', false); 
        end
        new_names = [{''} new_names];
        
        if isscalar(new_onsets)
            new_onsets = ones(1,len)*new_onsets;
        end
        
        if isscalar(new_durs)
            new_durs = ones(1,len)*new_durs;
        end

        for c=2:len
            stim_table(table,:).(c).name   = new_names{c};
            stim_table(table,:).(c).onset  = new_onsets(c);
            stim_table(table,:).(c).dur    = new_durs(c);
        end
    end
end
end