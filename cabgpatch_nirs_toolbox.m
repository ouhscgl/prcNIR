% Variable definition
%-- Path to nirs-toolbox folder
root_folder = uigetdir('','Select nirs-toolbox folder.');
%-- Patches to be applied
patches = [
    struct('filename', 'loadNIRx.m', ...
           'original', 'info.S_D_Mask(:,info.Detectors-info.ShortDetectors+1:end)=eye(info.ShortDetectors);', ...
           'replaced', ''), ...
    struct('filename', 'LabeltooLongDistance.m', ...
           'original', 'LabeltooLongSeperation', ...
           'replaced', 'LabeltooLongDistance'), ...
    struct('filename', 'loadSNIRF.m', ...
           'original', 'snirf = array2struct(array);', ...
           'replaced', ['array = loadSNIRF_repairStructFields(array);' newline ...
                          'snirf = array2struct(array) ;' newline ...
                          '[snirf.nirs.data.measurementList, mask] = loadSNIRF_filterStructArray(snirf.nirs.data.measurementList);' newline ...
                          'snirf.nirs.data.dataTimeSeries = snirf.nirs.data.dataTimeSeries(mask, :);']), ...
    struct('filename', 'ChangeStimulusInfo.m', ...
           'original', 'oldstiminfo = nirs.createStimulusTable(data);', ...
           'replaced', '')
];
% Main execution loop
disp('-------------------------------------------------------------------')
disp('Patching nirs-toolbox')
disp('-------------------------------------------------------------------')
for i = 1:length(patches)
    disp(['[' num2str(i) '/' num2str(length(patches)) '] Loading ' ...
          patches(i).filename ' ...'])
    patch_function(root_folder, patches(i).filename, ...
                   patches(i).original, patches(i).replaced)
end
disp('-------------------------------------------------------------------')

% Auxilliary functions
function patch_function(folder, filename, pattern, replacement)
    success = false;
    if ~exist(folder, 'dir')
        warning('Root folder does not exist: %s', folder);
        return;
    end
    allfiles = dir(fullfile(folder, '**', filename));
    if ~isempty(allfiles)
        filePath = fullfile(allfiles(1).folder, allfiles(1).name);
    else
        warning('File not found: %s', filename);
        return;
    end

    fileText = fileread(filePath);
    newText = strrep(fileText, pattern, replacement);
    if ~strcmp(newText, fileText)
        success = true;
    end
    
    % Write the modified text back to the file
    fid = fopen(filePath, 'w');
    if fid == -1
        error('Could not open file for writing');
    end
    fprintf(fid, '%s', newText);
    fclose(fid);
    
    if success
        disp(['Modified file: ' filePath]);
    else
        disp('File is already patched.');
    end

    
end