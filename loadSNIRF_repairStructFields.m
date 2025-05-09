function repairedArray = loadSNIRF_repairStructFields(array)
% loadSNIRF_repairStructFields - Auxilliary function to bridge between 
%                                SATORI and nirs-toolbox by removing 0x20
%                                from .snirf fieldnames added to metadata.
%
% Usage:
%   You really shouldn't manually use it, but alas:
%      array = loadSNIRF_repairStructFields(array);
%
% Inputs:
%   array              - .snirf array datastream loaded via hdf5read
%
% Description:
%   This function repairs .snirf fieldnames maliciously set by SATORI to be
%   MATLAB compatible.
% @zkaposzt

% .. iterate through every field
for i = 1:size(array, 1)
% -- if its a string or character array and contains 0x20
if ischar(array{i, 1}) || isstring(array{i, 1})
if contains(array{i,1},' '), array{i, 1}=strrep(array{i,1},' ', '');end;end
end; repairedArray = array;
end