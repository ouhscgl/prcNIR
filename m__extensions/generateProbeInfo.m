function probeInfo = generateProbeInfo(links, geoms, options)
% GENERATEPROBEINFO - Generate probeInfo structure from optode data
%
% Usage:
%   probeInfo = generateProbeInfo(linksCSV, geomsCSV)
%   probeInfo = generateProbeInfo(..., 'nDet', 20)
%   probeInfo = generateProbeInfo(..., 'OutputFile', path)
%
% The master CSVs describe the full montage (all possible optodes).
% This function clips to the actual detector count in the recording:
%   - Links referencing detectors > nDet are dropped
%   - Links referencing sources > nSrc are dropped  
%   - Geometry rows beyond nDet / nSrc are dropped
%   - Detectors > 16 are always short-separation
%
% Short detectors (> 16) without explicit geometry entries are placed
% at a small 3D offset (~8mm) from their paired source along the scalp
% surface. 2D coordinates are computed via azimuthal equidistant
% projection from the apex of a best-fit sphere.
%
% Inputs:
%   links      - CSV with columns: source, detector
%   geoms      - CSV with columns: name, X, Y, Z, normal_x, normal_y, normal_z
%   nDet       - Actual detector count from HDR (default: from geometry)
%   nSrc       - Actual source count from HDR (default: 16)
%   OutputFile - If provided, saves probeInfo.mat to this path

arguments
    links              (1,1) string
    geoms              (1,1) string
    options.nDet       (1,1) double = 0
    options.nSrc       (1,1) double = 16
    options.OutputFile (1,1) string = ""
end

SHORT_BOUNDARY = 16;   % detectors > this are always short
SHORT_OFFSET   = 0.8;  % cm — physical short-sep distance on the scalp

%% Load data
L = readtable(links);
T = readtable(geoms);

%% Parse geometry by category (name-based)
sources   = T(contains(T.name, 'Source'),   :);
detectors = T(contains(T.name, 'Detector'), :);
anchors   = T(~contains(T.name,'Detector') & ~contains(T.name,'Source'), :);

nSrc     = options.nSrc;
nDetGeom = height(detectors);
nDetData = options.nDet;
if nDetData == 0, nDetData = nDetGeom; end

%% Filter links to valid optode range
validRows = L.source   <= nSrc & ...
            L.detector <= nDetData;
validLinks = L(validRows, :);

nDropped = height(L) - height(validLinks);
if nDropped > 0
    fprintf('       ℹ Filtered %d/%d links (nSrc=%d, nDet=%d)\n', ...
            nDropped, height(L), nSrc, nDetData);
end

nChan = height(validLinks);
if nChan == 0
    warning('generateProbeInfo:noChannels', ...
        'No valid channels after filtering (nSrc=%d, nDet=%d)', ...
        nSrc, nDetData);
    probeInfo = [];
    return;
end

%% Clip source geometry to nSrc
nSrcGeom = min(height(sources), nSrc);
sources  = sources(1:nSrcGeom, :);

%% Build detector 3D coordinate arrays (handle variable count)
nDetCoords = min(nDetGeom, nDetData);

coords_d3 = [detectors.X(1:nDetCoords), ...
             detectors.Y(1:nDetCoords), ...
             detectors.Z(1:nDetCoords)];
normals_d = [detectors.normal_x(1:nDetCoords), ...
             detectors.normal_y(1:nDetCoords), ...
             detectors.normal_z(1:nDetCoords)];
labels_d  = detectors.name(1:nDetCoords)';

%% Place short detectors beyond geometry at offset from paired source
if nDetData > nDetCoords
    nExtra = nDetData - nDetCoords;
    fprintf(['       ℹ %d detectors beyond geometry (%d). ' ...
             'Placing at %.1fmm offset from paired source.\n'], ...
            nExtra, nDetCoords, SHORT_OFFSET * 10);

    src3 = [sources.X, sources.Y, sources.Z];
    srcN = [sources.normal_x, sources.normal_y, sources.normal_z];

    extraDets = (nDetCoords+1):nDetData;
    for k = 1:nExtra
        dIdx = extraDets(k);
        pairedSrc = validLinks.source(validLinks.detector == dIdx);
        if ~isempty(pairedSrc) && pairedSrc(1) <= nSrcGeom
            s = pairedSrc(1);
            [pos, nrm] = short_det_offset(src3(s,:), srcN(s,:), ...
                                           SHORT_OFFSET);
            coords_d3(end+1, :) = pos;
            normals_d(end+1, :) = nrm;
        else
            coords_d3(end+1, :) = 0;
            normals_d(end+1, :) = [0 0 1];
        end
        labels_d{1, end+1} = sprintf('Detector %d', dIdx);
    end
end

%% Short channel classification
isShort  = validLinks.detector > SHORT_BOUNDARY;
nLong    = sum(~isShort);
nShort   = sum(isShort);

%% Compute 2D coordinates via azimuthal equidistant projection
coords_s3 = [sources.X, sources.Y, sources.Z];
normals_s = [sources.normal_x, sources.normal_y, sources.normal_z];
coords_o3 = [anchors.X, anchors.Y, anchors.Z];

% Project S, D, and anchors using a shared sphere fit (fit on S+D only)
sdPts3 = [coords_s3; coords_d3];
[sdPts2, projCenter] = azimuthal_equidist_proj(sdPts3);

coords_s2 = sdPts2(1:nSrcGeom, :);
coords_d2 = sdPts2(nSrcGeom+1:end, :);

% Project anchors through the same sphere (reuse center)
[coords_o2, ~] = azimuthal_equidist_proj(coords_o3, projCenter);

%% Build probes structure
probes = struct();
probes.nSource0   = nSrcGeom;
probes.nDetector0 = nDetData;
probes.nChannel0  = nChan;
probes.index_c    = [validLinks.source, validLinks.detector];

% -- sources
probes.coords_s2 = coords_s2;
probes.coords_s3 = coords_s3;
probes.normals_s = normals_s;
probes.labels_s  = sources.name';

% -- detectors
probes.coords_d2 = coords_d2;
probes.coords_d3 = coords_d3;
probes.normals_d = normals_d;
probes.labels_d  = labels_d;

% -- anchors / fiducials
probes.coords_o2 = coords_o2;
probes.coords_o3 = coords_o3;
probes.normals_o = [anchors.normal_x, anchors.normal_y, anchors.normal_z];
probes.labels_o  = anchors.name';

% -- short channel metadata
probes.nChannel0_long  = nLong;
probes.nChannel0_short = nShort;
probes.isShort         = isShort;

% -- channel midpoints
[probes.coords_c2, probes.coords_c3, probes.normals_c] = ...
    calculate_midpoints(probes);

%% Output
probeInfo = struct('headmodel', 'ICBM152', 'probes', probes);

if options.OutputFile ~= ""
    save(options.OutputFile, 'probeInfo');
end

fprintf(['       ✓ probeInfo: %d ch (%d long + %d short), ' ...
         '%d src, %d det\n'], ...
         nChan, nLong, nShort, nSrcGeom, nDetData);
end

% =========================================================================
%  2D projection
% =========================================================================

function [pts2d, center] = azimuthal_equidist_proj(pts3d, center)
%AZIMUTHAL_EQUIDIST_PROJ  Project 3D scalp points to 2D.
%   Fits a sphere to the input points via algebraic least-squares, then
%   projects via azimuthal equidistant projection from the apex (+Z pole).
%   If 'center' is provided, skips the sphere fit and uses that center.
%
%   Formula:
%     theta  = angle from +Z pole (radians)
%     phi    = azimuthal angle: atan2(x, y)
%     rho_2d = SCALE * R * theta
%     x_2d   = rho * sin(phi)
%     y_2d   = rho * cos(phi)
%
%   SCALE ≈ 4.82 matches nirs-toolbox ICBM152 output to ~3 units on
%   an ~80 unit scale. Residual comes from mesh vs sphere geometry.

    % -- Algebraic sphere fit (linear least-squares, no iteration needed)
    %    ||p - c||^2 = R^2  →  2*x*cx + 2*y*cy + 2*z*cz + k = x^2+y^2+z^2
    if nargin < 2 || isempty(center)
        A = [2 * pts3d, ones(size(pts3d, 1), 1)];
        b = sum(pts3d.^2, 2);
        params = A \ b;
        center = params(1:3)';
        R = sqrt(params(4) + sum(center.^2));
    else
        R = mean(vecnorm(pts3d - center, 2, 2));
    end

    % -- Azimuthal equidistant projection
    SCALE = 4.82;   % empirical fit to nirs-toolbox ICBM152 registration

    shifted = pts3d - center;
    n = size(pts3d, 1);
    pts2d = zeros(n, 2);

    for i = 1:n
        p = shifted(i, :);
        r = norm(p);
        if r < 1e-10, continue; end
        theta = acos(max(-1, min(1, p(3) / r)));
        phi   = atan2(p(1), p(2));
        rho   = SCALE * R * theta;
        pts2d(i, :) = [rho * sin(phi), rho * cos(phi)];
    end
end

% =========================================================================
%  Short detector placement
% =========================================================================

function [pos, nrm] = short_det_offset(srcPos, srcNormal, offset)
%SHORT_DET_OFFSET  Place a short detector near its paired source.
%   Offsets along the scalp tangent plane by 'offset' cm.
%   Direction: perpendicular to the normal, toward the head center
%   (i.e. roughly "inward" along the scalp surface).

    nrm = srcNormal / norm(srcNormal);
    
    % Build a tangent vector: cross normal with a reference axis
    % Use whichever reference axis is least parallel to the normal
    ref = [0, 0, 1];
    if abs(dot(nrm, ref)) > 0.9
        ref = [1, 0, 0];
    end
    tangent = cross(nrm, ref);
    tangent = tangent / norm(tangent);
    
    % Offset along tangent, staying on the sphere surface
    % (first-order: just shift along tangent, then re-project)
    pos = srcPos + offset * tangent;
    
    % Re-project onto the sphere: normalize to same radius
    r_src = norm(srcPos);
    if r_src > 1e-10
        pos = pos * (r_src / norm(pos));
    end
end

% =========================================================================
%  Channel midpoints
% =========================================================================

function [c2, c3, nc] = calculate_midpoints(probes)
    nCh = probes.nChannel0;
    idx = probes.index_c;
    c2  = zeros(nCh, 2);
    c3  = zeros(nCh, 3);
    nc  = zeros(nCh, 3);

    for i = 1:nCh
        s = idx(i, 1);
        d = idx(i, 2);

        c2(i, :) = (probes.coords_s2(s, :) + probes.coords_d2(d, :)) / 2;
        c3(i, :) = (probes.coords_s3(s, :) + probes.coords_d3(d, :)) / 2;

        vec = probes.normals_s(s, :) + probes.normals_d(d, :);
        n   = norm(vec);
        if n > 0
            nc(i, :) = vec / n;
        else
            nc(i, :) = [0 0 1];
        end
    end
end
