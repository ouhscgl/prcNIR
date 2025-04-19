function result = avg_EEGStats(EEGStat, byField, groupID)
    if ~isempty(byField) && isfield(EEGStat, byField)
        types = unique({EEGStat.(byField)});
        for t = 1:length(types)
            temp = EEGStat(strcmp({EEGStat.(byField)}, types{t}));
            
            % Initialize result structure with the first element
            result(t) = temp(1);
            result(t).subject = groupID;
            
            % -- Average power fields
            if isfield(result(t), 'power') && ~isempty(result(t).power)
                pf = fieldnames(result(t).power);
                for p = 1:length(pf)
                    % Pre-allocate the 3D matrix
                    matrix = zeros([size(temp(1).power.(pf{p})), length(temp)]);
                    for l = 1:length(temp)
                        matrix(:,:,l) = temp(l).power.(pf{p});
                    end
                    result(t).power.(pf{p}) = mean(matrix, 3); % Simplified to mean for now
                end
            end
            
            % -- Average ERP fields
            if isfield(result(t), 'erp') && ~isempty(result(t).erp)
                pf = fieldnames(result(t).erp);
                for p = 1:length(pf)
                    % Pre-allocate the 3D matrix
                    matrix = zeros([size(temp(1).erp.(pf{p})), length(temp)]);
                    for l = 1:length(temp)
                        matrix(:,:,l) = temp(l).erp.(pf{p});
                    end
                    result(t).erp.(pf{p}) = mean(matrix, 3);
                end
            end
            
            % -- Average timefreq fields
            if isfield(result(t), 'timefreq') && ~isempty(result(t).timefreq)
                pf = fieldnames(result(t).timefreq);
                for p = 1:length(pf)
                    if isstruct(temp(1).timefreq.(pf{p}))
                        % Handle the case where timefreq contains a struct of fields
                        tf_fields = fieldnames(temp(1).timefreq.(pf{p}));
                        for tf = 1:length(tf_fields)
                            if iscell(temp(1).timefreq.(pf{p}).(tf_fields{tf}))
                                % Handle cell arrays (like per-channel data)
                                num_cells = length(temp(1).timefreq.(pf{p}).(tf_fields{tf}));
                                for c = 1:num_cells
                                    cell_data = zeros([size(temp(1).timefreq.(pf{p}).(tf_fields{tf}){c}), length(temp)]);
                                    for l = 1:length(temp)
                                        cell_data(:,:,l) = temp(l).timefreq.(pf{p}).(tf_fields{tf}){c};
                                    end
                                    result(t).timefreq.(pf{p}).(tf_fields{tf}){c} = mean(cell_data, 3);
                                end
                            else
                                % Handle numeric arrays
                                matrix = zeros([size(temp(1).timefreq.(pf{p}).(tf_fields{tf})), length(temp)]);
                                for l = 1:length(temp)
                                    matrix(:,:,l) = temp(l).timefreq.(pf{p}).(tf_fields{tf});
                                end
                                result(t).timefreq.(pf{p}).(tf_fields{tf}) = mean(matrix, 3);
                            end
                        end
                    else
                        % Direct array averaging
                        matrix = zeros([size(temp(1).timefreq.(pf{p})), length(temp)]);
                        for l = 1:length(temp)
                            matrix(:,:,l) = temp(l).timefreq.(pf{p});
                        end
                        result(t).timefreq.(pf{p}) = mean(matrix, 3);
                    end
                end
            end
            
            % -- Average connectivity fields
            if isfield(result(t), 'connectivity') && ~isempty(result(t).connectivity)
                pf = fieldnames(result(t).connectivity);
                for p = 1:length(pf)
                    % Handle .dccc field specifically
                    if isfield(temp(1).connectivity.(pf{p}), 'dccc')
                        matrix = zeros([size(temp(1).connectivity.(pf{p}).dccc), length(temp)]);
                        for l = 1:length(temp)
                            matrix(:,:,:,l) = temp(l).connectivity.(pf{p}).dccc;
                        end
                        result(t).connectivity.(pf{p}).dccc = mean(matrix, 4);
                        result(t).connectivity.(pf{p}).scales = temp(1).connectivity.(pf{p}).scales; % Keep scales unchanged
                    end
                end
            end
        end
    else
        result = EEGStat; % Return original if byField is empty or doesn't exist
    end
end