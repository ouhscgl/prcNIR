function repairedArray = loadSNIRF_repairStructFields(array)
    for i = 1:size(array, 1)
        if ischar(array{i, 1}) || isstring(array{i, 1})
            if contains(array{i, 1}, ' ')
                array{i, 1} = strrep(array{i, 1}, ' ', '');
            end
        end
    end
    repairedArray = array;
end