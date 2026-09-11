function [v, name] = contrastVector(c, conditions)
% PRC.CONTRASTVECTOR - Turn a config contrast into a weight vector.
%
% Usage:
%   [v, name] = prc.contrastVector(cfg.visualize.contrasts{k}, stats.conditions)
%
% Named weights are matched against the model's real condition list, so the
% contrast does not care what order MixedEffects happens to emit conditions in.
% A name that does not match is an error listing every condition that exists --
% the alternative is a positional vector quietly lining up against the wrong
% column, which produces a plausible figure of the wrong thing.
%
% The positional "vector" form is still accepted for old configs. It is checked
% for length and nothing else, because nothing else can be checked.

arguments
    c          (1,1) struct
    conditions
end

conditions = cellstr(conditions);
conditions = conditions(:)';
n          = numel(conditions);

if isfield(c, 'name'), name = c.name; else, name = 'contrast'; end

%% -- positional form ------------------------------------------------------
if isfield(c, 'vector') && ~isempty(c.vector)
    v = asrow(c.vector);
    if numel(v) ~= n
        error('prc:contrastVector:WrongLength', ...
             ['Contrast "%s" has %d weights but the model has %d conditions.\n' ...
              '  Conditions: %s'], name, numel(v), n, strjoin(conditions, ', '));
    end
    return
end

%% -- named form -----------------------------------------------------------
if ~isfield(c, 'weights') || isempty(c.weights)
    error('prc:contrastVector:Empty', ...
          'Contrast "%s" has neither weights nor a vector.', name);
end

v = zeros(1, n);
for k = 1:numel(c.weights)
    w = c.weights{k};

    ix = find(strcmp(w.condition, conditions), 1);
    if isempty(ix)
        %-- be forgiving about case and stray whitespace before giving up
        ix = find(strcmpi(strtrim(w.condition), strtrim(conditions)), 1);
    end
    if isempty(ix)
        error('prc:contrastVector:NoSuchCondition', ...
             ['Contrast "%s" weights a condition called "%s", which this model ' ...
              'does not have.\n  Conditions: %s'], ...
              name, w.condition, strjoin(conditions, ', '));
    end

    %-- accumulate, so listing a condition twice sums rather than overwrites
    v(ix) = v(ix) + w.value;
end
end
