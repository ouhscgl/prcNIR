function [GroupStatsGA, GroupStatsCE, demograph, stimulus] ...
    = fNIRS_Process(load_path, nirstoolbox_path, user_vars,save_snirf_flag)
% Data loading ____________________________________________________________
%-- Adding nirs-toolbox to path
addpath(genpath(fullfile(nirstoolbox_path,'nirs-toolbox')))
%-- Adding default user variables if not present
if ~isa(user_vars,'struct')
    user_vars = struct();
    user_vars.folder_structure  = {'group','subject'};
    user_vars.dct_value         = 0.009;
    user_vars.stim_names={'nback0a','nback1a','nback0b','nback2a'};
    user_vars.stim_onset=NaN;
    user_vars.stim_dur = 72;
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
job.max_distance = 10;
%-- Long channel identification and removal
job = nirs.modules.LabeltooLongDistance (job);
job.min_distance = 50;
job = nirs.modules.RemovetooLongDistance(job);
% _________________________________________________________________________

% Transform to physiological data _________________________________________
job = nirs.modules.OpticalDensity       (job);
job = nirs.modules.BeerLambertLaw       (job);
data_prps = job.run(data_raws);
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
job = nirs.modules.MixedEffects;
% Group analysis
job.formula = 'beta ~ -1 + group + (1|subject)';
GroupStatsGA = job.run(data_stat);
disp(GroupStatsGA.conditions);
% Group condition analysis
job.formula='beta ~ -1  + group:cond + (1|subject)';
GroupStatsCE=job.run(data_stat);
disp(GroupStatsCE.conditions);
%% Individual analysis
% job.formula='beta ~ -1  + group:cond';
% for i=1:length(SubjStats)
%     IndieStatsCE = job.run(SubjStats(i));
%     disp(IndieStatsCE.conditions);
%     c = [-1  0  0  1];
%     ContrastStatsCE = IndieStatsCE.ttest(c);
% 
%     ContrastStatsCE.probe=ContrastStatsCE.probe.SetFiducialsVisibility(false);
%     ContrastStatsCE.probe.defaultdrawfcn='10-20 map';
%     ContrastStatsCE.probe.optodes_registered = optode_map;
%     ContrastStatsCE.draw('tstat',[-8 8], 'p<0.05');
% 
%     compfig = figure;
%     a = findobj('Type','axes');
%     horz = floor(length(a)/2);
%     vert = 2;
%     fig_size = 0.25;
%     for p=1:length(a)
%         pos = [fig_size * (p-1), 1 - fig_size * (p-1),...
%                fig_size,         fig_size            ];
%         ax(p) = copyobj(a(p), compfig);
%         set(ax(p), 'Position', pos)
%     end
% 
% ContrastStatsCE.printAll('tstat',[-8 8], 'q<0.05', [save_figs,'1/'], 'fig');
% end
% fileList = dir(fullfile(save_figs,'**','*.fig'));
% for q=1:8
%     subplot(2,4,q)
%     img = imread(fullfile(fileList(q).folder,fileList(q).name));
%     imshow(img)
% end

% _________________________________________________________________________

% Save preprocessed data as .snirf ________________________________________
if save_snirf_flag == true
    for i=1:length(data_prps)
        visitID = '';
        if ismember('Visit',demograph.Properties.VariableNames)
            visitID = strcat('_V',demograph.Visit(i));
        end
        save_name = fullfile(load_path,[demograph.Name{i},visitID{:},...
                                '.snirf']);
        if isfile(save_name)
            validate =input('File already exists. Overwrite? [[y]/n]',"s");
            if isequal(lower(validate),'y') | isempty(validate)
                delete(save_name)
                nirs.io.saveSNIRF(data_prps(i,1),save_name)
                disp(['Saved ',save_name,'.']);
            else
                disp(['Discarded ',demograph.Name{i},'.snirf.']);
            end
        else
            nirs.io.saveSNIRF(data_prps(i,1),save_name)
            disp(['[',num2str(i),']',' Saved ',save_name,'.']);
        end
    end
end
% _________________________________________________________________________

% Auxillary functions _____________________________________________________
function [stim_table] = stimTableMapper(stim_table, ...
                            new_names, new_onsets, new_durs)
    for table=1:height(stim_table)
        len = width(stim_table);
        if length(new_names)  == 1
            new_names = arrayfun(@(n) sprintf('channel_%d', n), 1:len, ...
                'UniformOutput', false); 
        end
        new_names = [{''} new_names];
        
        if length(new_onsets) == 1
            new_onsets = ones(1,len)*new_onsets;
        end
        
        if length(new_durs)   == 1
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