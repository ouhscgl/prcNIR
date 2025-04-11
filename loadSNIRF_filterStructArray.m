function [filteredStruct, mask] = loadSNIRF_filterStructArray(structArray)
    mask = false(size(structArray));
    for i = 1:length(structArray)
        if strcmp(structArray(i).dataTypeLabel, 'HbO') || strcmp(structArray(i).dataTypeLabel, 'HbR')
            mask(i) = true;
            structArray(i).dataTypeIndex = 1;
            if strcmp(structArray(i).dataTypeLabel, 'HbO')
                structArray(i).wavelengthIndex = 1;
            elseif strcmp(structArray(i).dataTypeLabel, 'HbR')
                structArray(i).wavelengthIndex = 2;
            end
        end
    end
    filteredStruct = structArray(mask);
end