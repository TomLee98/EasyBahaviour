classdef LittleObjectDetector < handle
    %LITTLEOBJECTDETECTOR This class for little object detection based on 
    % frequency division feature extraction

    properties(Constant, Hidden)
        EXTEND_BORDER_RATIO = 0.1
    end
    
    properties(Access = private)
        classifier      % ClassificationECOC object, SVM multiclass model
        option          % struct with detector options
    end
    
    methods
        function this = LittleObjectDetector(classifier, option_)
            %OBJECTDETECTOR A Constructor
            arguments
                classifier  (1,1)   string  {mustBeFile}
                option_     (1,1)   struct = struct("nprange",  [20, 200], ...              % number of pixels range
                                                    "ivrange",  [100, 300], ...             % intensity value range
                                                    "weight",   [0.5, 0.5], ...             % weight balance pixels number and intensity
                                                    "nobjest",  30, ...                     % number of objects estimated
                                                    "binning",  2, ...                      % binning pixels on each direction
                                                    "gfsigma",  0.5, ...                    % gaussian filter sigma
                                                    "edgealg",  "sobel", ...                % edge detection operator, 
                                                    "fudgefac", 0.5, ...                    % gradient edge detection fudge factor
                                                    "feature", ["HOG","LBP","GLCM"], ...    % HOG, LBP and GLCM as feature detector, subset of them
                                                    "objtype", "larva", ...                 % object identity type (match to one of classifier prediction)
                                                    "blackmin", true)
            end

            this.option = option_;
            this.classifier = load(classifier, "svm");
        end
        
        function objects = Detect(this, image)
            %Detect This function detect objects in input image
            %% Previous Dectection for Coarse Detection
            bboxes = this.preDetect(image);

            %% Get Features for Fine-Tuned Detection
            feature = this.getFeatures(image, bboxes);

            %% Use Features to Generate Identity
            objects = this.makeIdentity(bboxes, feature);
        end
    end

    methods (Access = private)

        function objboxes = makeIdentity(this, bboxes, feature)
            % This function uses SVM for feature detection, select 
            % objects with true labels
            % Input:
            %   - this:
            %   - bboxes: n-by-4 bounding box, [x, y, w, h]
            %   - feature: n-by-p features matrix
            % Output:
            %   - objboxes: 1-by-1 dictionary, with <string> -> <cell>,
            %   identity |-> {[x, y, w, h]}

            if size(bboxes, 1) ~= size(feature, 1)
                throw(MException("LittleObjectDetector:unmatchedObjects", ...
                    "Inner error caused, unmatched bounding boxes and features."));
            end

            objboxes = dictionary();

            ids = predict(this.classifier, feature);
            nlabels = ones(1, numel(unique(ids)));
            for k = 1:numel(ids)
                [~, idpos] = ismember(ids, this.option.objtype);
                if idpos ~= 0
                    key = sprintf("%s%d", ids(k), nlabels(idpos));
                    objboxes(key) = {bboxes(k, :)};   % string -> [x,y,w,h]
                    nlabels(idpos) = nlabels(idpos) + 1;
                end
            end

        end

        function feature = getFeatures(this, image, bboxes)
            % This function uses image middle frequency information for
            % features detection
            % Input:
            %   - this:
            %   - image: m-by-n uint8/uint16 matrix
            %   - bboxes: k-by-4 double matrix, k for objects number, [x, y, w, h]
            % output:
            %   - feature: 

            feature = cell(size(bboxes), 1);

            %% Use gradient method for object edge extraction
            % pipeline see: https://ww2.mathworks.cn/help/images/detecting-a-cell-using-image-segmentation.html
            parfor k = 1:size(bboxes, 1)
                % crop image region
                bbox = bboxes(k, :);
                img = image(bbox(2):bbox(2)+bbox(4)-1, bbox(1):bb(1)+bbox(3)-1);

                % edge detection
                [~, th] = edge(img, this.option.edgealg);
                img_bw_pre = edge(img, this.option.edgealg, th * this.option.fudgefac);

                % dilate object
                % we keep holes inner object as one of detection features
                se90 = strel("line",3,90); se0 = strel("line",3,0); % minimal cross
                img_bw_pre = imdilate(img_bw_pre,[se90 se0]);

                % fill holes
                img_bw_post = imfill(img_bw_pre, "holes");

                % remove possible connected object at border
                img_bw_post = imclearborder(img_bw_post, 4);

                % smooth for better foreground
                seD = strel('diamond',1);
                img_bw_post = imerode(img_bw_post, seD);    % erode only once

                % cross for final mask(with inner holes)
                img_bw = img_bw_post.*img_bw_pre;

                % detect features
                feature{k} = LittleObjectDetector.extractFeature(img_bw, ...
                                                                 "ALL");
            end

            feature = cell2mat(feature);
        end

        function bboxes = preDetect(this, image)
            % This function uses morphology algorithm to do objects 
            % coarse detection
            % Input:
            %   - this:
            %   - image: m-by-n uint8/uint16 matrix
            %$ Output:
            %   - bboxes: k-by-4 double matrix, k for objects number, [x, y, w, h]

            %% Get Coarse Bounding Box
            % Binning images for fast detection objects
            img = imresize(image, 1/this.option.binning, "bilinear");

            % Get extended max region (binarize)
            % estimate background intensity range by 1% points in image
            npts = numel(img);
            nsmpl = max(10, round(0.01*npts));
            index = randi(npts, nsmpl, 1);
            bkgupb = mean(img(index)) + 3*std(img(index));  % cover 99.7% possible of background

            img_bw = imextendedmax(img, this.option.ivrange(1) - bkgupb, 8);
            
            % Measure regions bounding boxes
            bboxes = regionprops("table", img_bw, "BoundingBox");

            % Extend boxes on raw image
            bboxes.BoundingBox = this.option.binning * bboxes.BoundingBox;

            %% Filter boxes by criterias
            objs_cost = zeros(size(bboxes, 1), 1);     % [w1, w2]*[size; intensity]
            parfor k = 1:size(bboxes, 1)
                % select raw image in box
                bbox = ceil(bboxes.BoundingBox(k, :));
                img = image(bbox(2):bbox(2)+bbox(4)-1, bbox(1):bb(1)+bbox(3)-1);
                
                % gaussian lowpass filter for robust object power estimate
                img = imgaussfilt(img, this.option.gfsigma, "Padding","replicate");

                boxsz = bbox(3)*bbox(4);
                % size filter
                if (boxsz < this.option.nprange(1)) || (boxsz > this.option.nprange(2))
                    objs_cost(k) = inf;
                else
                    % intensity filter
                    p0 = 1 - this.option.nprange(1)/(bbox(3)*bbox(4));
                    vI = mean(img(img >= quantile(img, p0, "all")));
                    if (vI < this.option.ivrange(1)) || (vI > this.option.ivrange(2))
                        objs_cost(k) = inf;
                    else
                        cost_s = abs(tan(pi*(1/2-(boxsz-this.option.nprange(1))/diff(this.option.nprange))));
                        cost_v = abs(tan(pi*(1/2-(boxsz-this.option.ivrange(1))/diff(this.option.ivrange))));
                        objs_cost(k) = this.option.weight*[cost_s; cost_v];
                    end
                end
            end

            % refine box: center symmetric expansion, make sure true object
            % foreground must be in box
            bboxes = bboxes.BoundingBox;    % table -> matrix
            bboxes(:,[1,2]) = max(1, ceil(bboxes(:,[1,2]) - this.EXTEND_BORDER_RATIO/2*bboxes(:,[3,4])));
            bboxes(:,[3,4]) = min((1+this.EXTEND_BORDER_RATIO/2)*bboxes(:,[3,4]), size(image, [2,1]));

            % remove boxes with inf cost
            bboxes(isinf(objs_cost), :) = [];
            objs_cost(isinf(objs_cost)) = [];

            % sort by min cost
            if size(bboxes, 1) > this.option.nobjest
                [~, cost_pos] = sort(objs_cost, "ascend");
                % select first nobjest objects
                bboxes = bboxes(cost_pos(1:this.option.nobjest), :);
            end
        end
    end

    methods(Static)
        function feature = extractFeatureHOG(BW, CellSize)
            arguments
                BW          (:,:)
                CellSize    (1,2)   double  {mustBePositive, mustBeInteger} = [4, 4]
            end

            feature = extractHOGFeatures(BW,'CellSize',CellSize);
        end

        function feature = extractFeatureLBP(BW, CellSize, RadiusNum)
            arguments
                BW          (:,:)
                CellSize    (1,2)   double  {mustBePositive, mustBeInteger} = [4, 4]
                RadiusNum   (1,1)   double  {mustBePositive, mustBeInteger} = 2
            end

            feature = [];
            for k = 1:RadiusNum
                feature = [feature, extractLBPFeatures(BW, "Radius",k, ...
                    "Upright",true, "CellSize", CellSize)]; %#ok<AGROW>
            end
        end

        function feature = extractFeatureGLCM(BW, OffsetNum, StatOrder)
            arguments
                BW          (:,:)
                OffsetNum   (1,1)   double  {mustBePositive, mustBeInteger} = 4
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

        function feature = extractFeature(BW, optr, option)
            arguments
                BW      (:,:)
                optr    (1,:)   string  {mustBeMember(optr, ["HOG","LBP","GLCM","ALL"])} = "ALL"
                option  (1,1)   struct  = struct("NormalSize",      [32, 32], ...
                                                 "HOG_CellSize",    [4, 4], ...
                                                 "LBP_CellSize",    [4, 4], ...
                                                 "LBP_RadiusNum",   2, ...
                                                 "GLCM_OffsetNum",  4, ...
                                                 "GLCM_StatOrder",  2)
            end

            %% Squared Image BW
            [height, width] = size(BW);
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
            if isequal(optr, "ALL"), optr = ["HOG","LBP","GLCM"]; end

            feature = [];       % dynamic increase as 1-by-n vector

            % combine features
            for n = 1:numel(optr)
                switch optr(n)
                    case "HOG"
                        feature_hog = LittleObjectDetector.extractFeatureHOG(BW, ...
                            option.HOG_CellSize);
                        feature = [feature, feature_hog]; %#ok<AGROW>
                    case "LBP"
                        feature_lbp = LittleObjectDetector.extractFeatureLBP(BW, ...
                            option.LBP_CellSize, option.LBP_RadiusNum);
                        feature = [feature, feature_lbp]; %#ok<AGROW>
                    case "GLCM"
                        feature_glcm = LittleObjectDetector.extractFeatureGLCM(BW, ...
                            option.GLCM_OffsetNum, option.GLCM_StatOrder);
                        feature = [feature, feature_glcm]; %#ok<AGROW>
                    otherwise
                end
            end
        end
    end
end

