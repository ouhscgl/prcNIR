function probeInfo = generateProbeInfo(links, geoms, options)
% NRA_GENERATE_PROBEINFO - Generate probeInfo structure from optode data
%
% Usage:
%   probeInfo = NRA_generate_probeInfo()
%   probeInfo = NRA_generate_probeInfo(linksCSV, geomsCSV)
%   probeInfo = NRA_generate_probeInfo(..., 'nDetectors', 20)
%   probeInfo = NRA_generate_probeInfo(..., 'OutputFile', path)
%
% Inputs:
%   links      - CSV with columns: source, detector
%   geoms      - CSV with columns: name,X,Y,Z,normal_x,normal_y,normal_z
%   nDetectors - Actual detector count in data (default: from geometry)
%   OutputFile - If provided, saves probeInfo.mat to this path

arguments
    links      (1,1) string = ""
    geoms      (1,1) string = ""
    options.nDet (1,1) double {mustBeInRange(options.nDet,0,24)} = 0
    options.OutputFile (1,1) string = ""
end

%% Load data
if links == "" || geoms == ""
    ROOT = '/Users/medicabg/Documents/Projects/023_fNIRS_ProbeInfo';
    L = readtable(fullfile(ROOT, 'optode_data_links.csv'));
    T = readtable(fullfile(ROOT, 'optode_data_symmetrical.csv'));
else
    L = readtable(links);
    T = readtable(geoms);
end

%% Parse geometry by category
sources   = T(contains(T.name, 'Source'), :);
detectors = T(contains(T.name, 'Detector'), :);
anchors   = T(~contains(T.name,'Detector') & ~contains(T.name,'Source'),:);

%% Determine detector count
nDetGeom = height(detectors);
nDetData = options.nDet;
if nDetData == 0, nDetData = nDetGeom; end

%% Filter links to valid detectors only
validLinks = L(L.detector <= nDetData, :);

%% Build probes structure
probes = struct();
probes.nSource0   = height(sources);
probes.nDetector0 = nDetData;
probes.nChannel0  = height(validLinks);
probes.index_c    = [validLinks.source, validLinks.detector];

% -- sources
probes.coords_s2 = [sources.X, sources.Y];
probes.coords_s3 = [sources.X, sources.Y, sources.Z];
probes.normals_s = [sources.normal_x, sources.normal_y, sources.normal_z];
probes.labels_s  = sources.name';

% -- detectors (geometry defines up to 20, extend if data has more)
nDetCoords = min(nDetGeom, 20);  % coords capped at 20
probes.coords_d2 = [detectors.X(1:nDetCoords), ...
                    detectors.Y(1:nDetCoords)];
probes.coords_d3 = [detectors.X(1:nDetCoords), ...
                    detectors.Y(1:nDetCoords), ...
                    detectors.Z(1:nDetCoords)];
probes.normals_d = [detectors.normal_x(1:nDetCoords), ...
                    detectors.normal_y(1:nDetCoords), ...
                    detectors.normal_z(1:nDetCoords)];
probes.labels_d  = detectors.name(1:nDetCoords)';

% -- extend with placeholders if data has more detectors than coords
if nDetData > nDetCoords
    nExtra = nDetData - nDetCoords;
    probes.coords_d2(end+1:end+nExtra, :) = 0;
    probes.coords_d3(end+1:end+nExtra, :) = 0;
    probes.normals_d(end+1:end+nExtra, :) = 0;
    probes.labels_d(1, end+1:end+nExtra)  = {'Dx'};
end

% -- anchors/fiducials
probes.coords_o2 = [anchors.X, anchors.Y];
probes.coords_o3 = [anchors.X, anchors.Y, anchors.Z];
probes.normals_o = [anchors.normal_x, anchors.normal_y, anchors.normal_z];
probes.labels_o  = anchors.name';

% -- channel midpoints
[probes.coords_c2, probes.coords_c3, probes.normals_c] = ...
    calculate_midpoints(probes);

%-- output variable
probeInfo = struct('headmodel', 'ICBM152', 'probes', probes);

%-- save (optional)
if options.OutputFile ~= "", save(options.OutputFile, 'probeInfo'); end
end

%% Local function
function [c2, c3, nc] = calculate_midpoints(probes)
    nCh = probes.nChannel0;
    idx = probes.index_c;
    c2 = zeros(nCh, 2);
    c3 = zeros(nCh, 3);
    nc = zeros(nCh, 3);
    
    for i = 1:nCh
        s = idx(i, 1);
        d = idx(i, 2);
        
        c2(i, :) = (probes.coords_s2(s, :) + probes.coords_d2(d, :)) / 2;
        c3(i, :) = (probes.coords_s3(s, :) + probes.coords_d3(d, :)) / 2;
        
        vec = (probes.normals_s(s, :) + probes.normals_d(d, :)) / 2;
        nc(i, :) = vec / norm(vec);
    end
end