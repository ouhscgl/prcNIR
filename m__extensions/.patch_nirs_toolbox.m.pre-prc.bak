function patch_nirs_toolbox(root_folder)
% PATCH_NIRS_TOOLBOX  Apply patches to the nirs-toolbox.
%
%   patch_nirs_toolbox()              — prompts user to select the folder
%   patch_nirs_toolbox(root_folder)   — uses the provided path directly
%
%   Example (from setup script):
%       patch_nirs_toolbox(fullfile(target_dir, 'nirs-toolbox'))

%% Resolve root folder
if nargin < 1 || isempty(root_folder)
    root_folder = uigetdir('', 'Select nirs-toolbox folder.');
    if root_folder == 0
        fprintf('Patch cancelled.\n');
        return;
    end
end

if ~exist(root_folder, 'dir')
    error('patch_nirs_toolbox: folder not found: %s', root_folder);
end

%% Patches to be applied
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

%% Main execution loop
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

end % end of main function

%% ------------------------------------------------------------------------
function patch_function(folder, filename, pattern, replacement)
% -- check for root directory
success = false;
if ~exist(folder, 'dir'), warning('Root non existant: %s', folder); return; end

% -- check for files
allfiles = dir(fullfile(folder, '**', filename));
if isempty(allfiles), warning('File not found: %s', filename); return; end

% -- assign io variables
filePath = fullfile(allfiles(1).folder, allfiles(1).name);
fileText = fileread(filePath);

% -- rewrite section
newText = strrep(fileText, pattern, replacement);
if ~strcmp(newText, fileText), success = true; end

% -- write to file
fid = fopen(filePath, 'w');
if fid == -1, error('Could not open file for writing: %s', filePath); end
fprintf(fid, '%s', newText);
fclose(fid);

if success, disp(['Modified file: ' filePath]);
else,       disp('File is already patched.'); end
end