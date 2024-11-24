function feature = extractFeatures(BW, optr, option)
arguments
    BW      (:,:)
    optr    (1,:)   string  {mustBeMember(optr, ["HOG","LBP","GLCM","ALL"])} = "ALL"
    option  (1,1)   struct  = struct("NormalSize",      [24, 24], ...
                                     "HOG_CellSize",    [8, 8], ...
                                     "LBP_CellSize",    [8, 8], ...
                                     "LBP_RadiusNum",   2, ...
                                     "GLCM_OffsetNum",  8, ...
                                     "GLCM_StatOrder",  2)
end

%% Squared Image BW
[height, width] = size(BW);

% keep HW ratio scaling
if height > width
    pdL = floor((height - width)/2);
    % add border both left and right
    BW = padarray(BW, [0, pdL],"replicate","pre");
    BW = padarray(BW, [0, height-width-pdL], "replicate","post");
else
    pdT = floor((width-height)/2);
    % add border both top and bottom
    BW = padarray(BW, [pdT, 0],"replicate","pre");
    BW = padarray(BW, [width-height-pdT, 0], "replicate","post");
end

%% Resize BW to HOG Normal Size
BW = imresize(BW, option.NormalSize, "bilinear");

%% Do Features Extraction
if isscalar(optr)&&isequal(optr, "ALL"), optr = ["HOG","LBP","GLCM"]; end

feature = [];       % dynamic increase as 1-by-n vector

% combine features
for n = 1:numel(optr)
    switch optr(n)
        case "HOG"
            feature_hog = extractFeatureHOG(BW, option.HOG_CellSize);
            feature = [feature, feature_hog]; %#ok<AGROW>
        case "LBP"
            feature_lbp = extractFeatureLBP(BW, option.LBP_CellSize, option.LBP_RadiusNum);
            feature = [feature, feature_lbp]; %#ok<AGROW>
        case "GLCM"
            feature_glcm = extractFeatureGLCM(BW, option.GLCM_OffsetNum, option.GLCM_StatOrder);
            feature = [feature, feature_glcm]; %#ok<AGROW>
        otherwise
    end
end
end

function feature = extractFeatureHOG(BW, CellSize)
arguments
    BW          (:,:)
    CellSize    (1,2)   double  {mustBePositive, mustBeInteger} = [8, 8]
end

feature = extractHOGFeatures(BW,'CellSize',CellSize);
end

function feature = extractFeatureLBP(BW, CellSize, RadiusNum)
arguments
    BW          (:,:)
    CellSize    (1,2)   double  {mustBePositive, mustBeInteger} = [8, 8]
    RadiusNum   (1,1)   double  {mustBePositive, mustBeInteger} = 2
end

feature = [];
rmax = ceil(sqrt(prod(CellSize))/2);
for k = 1:RadiusNum
    feature = [feature, extractLBPFeatures(BW, "Radius",rmax-k, ...
        "Upright",false, "CellSize", CellSize)]; %#ok<AGROW>
end
end

function feature = extractFeatureGLCM(BW, OffsetNum, StatOrder)
arguments
    BW          (:,:)
    OffsetNum   (1,1)   double  {mustBePositive, mustBeInteger} = 8
    StatOrder   (1,1)   double  {mustBeInRange(StatOrder, 1, 2)} = 2
end

feature = [];

ThetaDVec = [0, 1; ...
    -1, 1; ...
    -1, 0; ...
    -1,-1];

for n = 1:OffsetNum
    sv = [];
    for m = 1:size(ThetaDVec, 1)
        offset = n*ThetaDVec(m, :);
        glcm = graycomatrix(BW, "Offset", offset);
        stats = graycoprops(glcm, "all");
        sv = [sv; [stats.Contrast, stats.Correlation, stats.Energy, stats.Homogeneity]]; %#ok<AGROW>
    end
    switch StatOrder
        case 1
            feature = [feature, mean(sv, 1)]; %#ok<AGROW>
        case 2
            feature = [feature, mean(sv), std(sv)]; %#ok<AGROW>
        otherwise
    end
end
end