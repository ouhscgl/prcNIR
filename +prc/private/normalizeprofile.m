function p = normalizeprofile(p)
% NORMALIZEPROFILE - Fix the SHAPE of a decoded profile, never its values.
%
% jsondecode is ambiguous in ways that bite: a one-element string list may come
% back as a bare char, a list of objects becomes a struct array when the objects
% happen to share fields and a cell array when they do not, and numeric lists
% arrive as columns. This flattens all of that before anything else runs.
%
% Values are left alone on purpose -- filling in defaults is mergeinto's job,
% and doing it here would turn a JSON null into a real value and defeat it.

if ~isstruct(p) || ~isscalar(p), return; end

%-- dataset
if isfield(p,'dataset') && isstruct(p.dataset) && isfield(p.dataset,'folder_structure')
    p.dataset.folder_structure = ascellstr(p.dataset.folder_structure);
end

%-- stimulus
if isfield(p,'stimulus') && isstruct(p.stimulus)
    if isfield(p.stimulus,'names')
        p.stimulus.names = ascellstr(p.stimulus.names);
    end
    for fn = {'onset','duration'}
        if isfield(p.stimulus, fn{1})
            p.stimulus.(fn{1}) = asnanable(p.stimulus.(fn{1}));
        end
    end
end

%-- pipeline
if isfield(p,'pipeline') && isstruct(p.pipeline)
    for fn = {'preprocess','post'}
        if isfield(p.pipeline, fn{1})
            p.pipeline.(fn{1}) = ascellstruct(p.pipeline.(fn{1}));
        end
    end
    if isfield(p.pipeline,'group') && isstruct(p.pipeline.group) ...
            && isfield(p.pipeline.group,'models')
        p.pipeline.group.models = ascellstruct(p.pipeline.group.models);
    end
end

%-- visualize
if isfield(p,'visualize') && isstruct(p.visualize)
    v = p.visualize;
    if isfield(v,'significance'), v.significance = ascellstr(v.significance); end
    if isfield(v,'chromophores'), v.chromophores = ascellstr(v.chromophores); end
    if isfield(v,'tstat_range'),  v.tstat_range  = asrow(v.tstat_range);      end
    if isfield(v,'contrasts')
        v.contrasts = ascellstruct(v.contrasts);
        for k = 1:numel(v.contrasts)
            c = v.contrasts{k};
            if isfield(c,'weights'), c.weights = ascellstruct(c.weights); end
            if isfield(c,'vector'),  c.vector  = asrow(c.vector);         end
            v.contrasts{k} = c;
        end
    end
    p.visualize = v;
end
end

%% ------------------------------------------------------------------------
function v = asnanable(v)
% Accept the legacy "NaN" string spelling alongside a real JSON null.
    if ischar(v) || isstring(v)
        if strcmpi(char(v),'NaN'), v = NaN; end
        return
    end
    v = asrow(v);
end
