function params = toVizParams(cfg, stats, outputDir)
% PRC.TOVIZPARAMS - Config profile -> the params struct fNIRS_Visualize takes.
%
% Usage:
%   params = prc.toVizParams(cfg, groupStats)
%   params = prc.toVizParams(cfg, groupStats, outDir)
%   fNIRS_Visualize(groupStats, 0, params)
%
% `stats` is needed because contrasts are stored by condition NAME and only the
% fitted model knows what the conditions ended up being called. That resolution
% is the whole point: it is what lets a profile outlive a change in condition
% ordering.

arguments
    cfg       (1,1) struct
    stats
    outputDir (1,:) char = ''
end

V = cfg.visualize;

%% ========================================================================
%  Resolve contrasts against the model's real condition list
%  ========================================================================
conditions = stats(1).conditions;

contrasts = cell(1, numel(V.contrasts));
names     = cell(1, numel(V.contrasts));
for k = 1:numel(V.contrasts)
    [contrasts{k}, names{k}] = prc.contrastVector(V.contrasts{k}, conditions);
end

params = struct();
params.contrasts     = contrasts;
params.contrastNames = names;

%% ========================================================================
%  Output options
%  ========================================================================
params.significance = V.significance;
params.saveHbo      = any(strcmpi('hbo', V.chromophores));
params.saveHbr      = any(strcmpi('hbr', V.chromophores));
params.saveCoeff    = V.save_table;
params.visMethod    = V.draw_method;
params.figFormat    = V.fig_format;
params.output_prefix = V.output_prefix;

if ~isempty(outputDir)
    params.output_dir = outputDir;
else
    params.output_dir = cfg.paths.output_dir;
end

if any(strcmpi('hbt', V.chromophores))
    warning('prc:toVizParams:NoHbT', ...
           ['fNIRS_Visualize only saves hbo and hbr figures, so the hbt ' ...
            'request is ignored. The beta table still carries it.']);
end
end
