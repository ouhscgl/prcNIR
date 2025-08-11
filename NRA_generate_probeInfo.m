function probeInfo = NRA_generate_probeInfo(links,geoms)
% Read data
if nargin == 0  % No inputs provided
    ROOT = '/Users/medicabg/Documents/Projects/023_fNIRS_ProbeInfo';
    L = readtable(fullfile(ROOT,'optode_data_links.csv'));
    T = readtable(fullfile(ROOT,'optode_data_symmetrical.csv'));
elseif nargin == 2
    L = readtable(links);
    T = readtable(geoms);
else,error('Must provide both links & geometry. Leave empty for default.');
end

probes = struct();

% Extract data categories and set counts
sources = T(contains(T.name, 'Source'), :);
detectors = T(contains(T.name, 'Detector'), :);
FID_anchors = T(~contains(T.name, 'Detector') ...
              & ~contains(T.name, 'Source'), :);

% Store counts and channel information
probes.nSource0 = height(sources);
probes.nDetector0 = height(detectors);
probes.nChannel0 = height(L);
probes.index_c = [L.source L.detector];

% Define categories to process
categories = {{sources, 's'}, {detectors, 'd'}, {FID_anchors, 'o'}};

% Extract coordinates, normals, and labels for each category
for i = 1:length(categories)
data = categories{i}{1};
prefix = categories{i}{2};
    
probes.(['coords_', prefix, '2']) = [data.X, data.Y];
probes.(['coords_', prefix, '3']) = [data.X, data.Y, data.Z];
probes.(['normals_', prefix])=[data.normal_x,data.normal_y,data.normal_z];
probes.(['labels_', prefix]) =data.name';
end

% Calculate midpoints
[probes.coords_c2, probes.coords_c3, probes.normals_c] = ...
    calculate_midpoints(probes);

% Create final structure
probeInfo = struct('headmodel', 'ICBM152', 'probes', probes);
% Function to calculate midpoints
function [c2, c3, nc] = calculate_midpoints(probes)
    % Initialize arrays
    nChannel0 = probes.nChannel0;
    index_c = probes.index_c;
    c2 = zeros(nChannel0, 2);
    c3 = zeros(nChannel0, 3);
    nc = zeros(nChannel0, 3);
    
    % Calculate midpoints for each channel
    for o = 1:nChannel0
        [src_idx, det_idx] = deal(index_c(o, 1), index_c(o, 2));
        
        % Calculate 2D and 3D midpoints and normals
        c2(o, :) = (probes.coords_s2(src_idx, :) ...
                    + probes.coords_d2(det_idx, :)) / 2;
        c3(o, :) = (probes.coords_s3(src_idx, :) ...
                    + probes.coords_d3(det_idx, :)) / 2;
        vector   = (probes.normals_s(src_idx, :) ...
                    + probes.normals_d(det_idx, :)) / 2;
        nc(o, :) = vector / norm(vector);
    end
end
end