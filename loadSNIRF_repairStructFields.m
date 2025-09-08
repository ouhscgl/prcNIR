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

% -- specific rows to keep, default = all
keepRows = true(size(array, 1), 1);

% .. iterate through every field
for i = 1:size(array, 1)

if ischar(array{i, 1}) || isstring(array{i, 1})

% -- remove 0x20 from fieldname
if contains(array{i,1},' '), array{i, 1}=strrep(array{i,1},' ', '');    end

% -- remove 'dataUnit' fields
if endsWith(array{i,1}, 'dataUnit'), keepRows(i) = false; continue;     end

% -- transpose malformed dataTimeSeries
f = 'dataTimeSeries'; txVal = diff(size(array{i,2})) < 0;
if contains(array{i,1},f) && txVal, array{i,2} = array{i,2}';           end
end

% -- modify un-resolvable fieldtype format
f = 'hdf5.h5string';
if contains(array{i,3},f), array{i, 3} = strrep(array{i,3},f, 'char');  end

% -- return array
repairedArray = array(keepRows, :);
end