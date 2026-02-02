function conditionmap = fNIRS_Mapper(groupStats, savePath)
    % fNIRS_Mapper creates a dictionary mapping conditions to 
    % user-specified values. Facilitates easier file management when used
    % in conjunction with fNIRS_ControlPanel().
    %
    %   Input:
    %       GroupStats - Calculated using nirs-toolbox.
    %       savePath   - (Optional) String specifying the save path.
    %
    %   Output:
    %       fnirsmap - Dictionary mapping condition names to custom values.
    %
    %   Example:
    %       GroupStats.conditions = {'condition1', 'condition2'};
    %       fnirsmap = fNIRS_Mapper(GroupStats, 'path_to_save/map.mat');
    %       - no save:    fnirsmap = fNIRS_Mapper(GroupStats);
    
conditionmap = dictionary();
for i=1:length(groupStats.conditions)
    value = input([groupStats.conditions{i},' >> '],'s');
    conditionmap(groupStats.conditions{i}) = {value};
end
    if ~isempty(savePath)
        save(savePath, 'conditionmap');
        disp(['Saved at ', savePath])
    end
end