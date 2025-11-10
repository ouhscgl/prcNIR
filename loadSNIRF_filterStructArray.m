function [filteredStruct, mask] = loadSNIRF_filterStructArray(structArray)
% loadSNIRF_filterStructArray - Extracts CC data from pre-processed SATORI 
%                                datasets for importing into nirs-toolbox
%
% Usage:
%   You really shouldn't manually use it, but alas:
%       [snirf.nirs.data.measurementList, mask] = ...
%           loadSNIRF_filterStructArray(snirf.nirs.data.measurementList);
%       snirf.nirs.data.dataTimeSeries = ...
%           snirf.nirs.data.dataTimeSeries(mask, :);
%
% Inputs:
%   structArray               - .snirf array datastream loaded via hdf5read
%
% Description:
%   This function extracts CC values from pre-processed SATORI datasets for
%   importing into nirs-toolbox appropriately.
% @zkaposzt

% -- check if data is direct NIRx recording
if isfield(structArray, 'dataTypeLabel')
    % -- check if data is pre-processed
    if isscalar(unique({structArray(:).dataTypeLabel}))
        filteredStruct = structArray; 
        mask = true(size(structArray));
        return;
    end
% -- check if data went through mne
else
    [structArray.dataTypeLabel] = deal('raw-DC');

end

% .. iterate through array to create data mask
mask = false(size(structArray));
for i = 1:length(structArray)
% -- check for pre-processed labels (HbO, HbR)
if isfield(structArray, 'dataTypeLabel')
    label = structArray(i).dataTypeLabel;
    if strcmp(label, 'HbO') || strcmp(label, 'HbR')
        % -- select and activate data row
        mask(i) = true; structArray(i).dataTypeIndex = 1;
    end

% -- set wavelength idx according to data type
if strcmp(label, 'HbO'), structArray(i).wavelengthIndex = 1;
elseif strcmp(label, 'HbR'), structArray(i).wavelengthIndex = 2;end
end
end
filteredStruct = structArray(mask);
end