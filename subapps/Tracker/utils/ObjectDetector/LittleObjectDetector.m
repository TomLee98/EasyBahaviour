classdef LittleObjectDetector < handle
    %LITTLEOBJECTDETECTOR This class for little object detection based on 
    % frequency division feature extraction
    % Note that detector combines static and dynamic features to predict if
    % the objects are target

    properties(Constant, Hidden)
        EXTEND_RATIO = 1.25
        MINIMAL_OBJECT_PIXNUM = 15
    end

    properties(Access = public, Dependent)
        BWImage         % ___/get, m-by-n logical matrix indicates binarized scene image
        FeatureSize     % ___/get, 1-by-1 positive integer, the feature dimension
        LabelsOrder     % ___/get, 1-by-n string vector, consistant with posterior probability
        Loaded          % ___/get, 1-by-1 logical, indicate if classifier is loaded
    end
    
    properties(Access = private)
        algorithm       % key technique branch
        classifier      % ClassificationECOC object, SVM multiclass model
        detector_opts   % struct with detector combined SVM options
        bimg            % binarized final processed image
        prop_opts       % struct for preprocess options
    end
    
    methods
        function this = LittleObjectDetector(file_classifier_, alg, option_)
            %OBJECTDETECTOR A Constructor
            arguments
                file_classifier_    (1,1)   string =  ""
                alg                 (1,1)   string  {mustBeMember(alg,["svm", "yolov4", "unet"])} = "svm"
                option_             (1,1)   struct = struct("npobj",        [120, 30], ...  % number of pixels distribution(normal) of object, [mu, sigma]
                                                            "nprange",      [15, 225], ...  % number of pixels range of all detection
                                                            "robustness",   0.99, ...       % adaptive sensitivity for foreground objects detection
                                                            "nobjmax",      30, ...         % number of objects estimated
                                                            "object",       "larva")            
            end

            this.algorithm = alg;

            this.prop_opts = option_;

            if ~isequal(file_classifier_, "") && isfile(file_classifier_)
                % load immediatelly
                this.load_classifier(file_classifier_);
            else
                % skip, caller uses load_classifier
            end
        end

        %% BWImage Getter & Setter
        function value = get.BWImage(this)
            value = this.bimg;
        end
        
        %% FeatureDimension Getter
        function value = get.FeatureSize(this)
            % feature dimension can be calculated by extracted options
            value = [1, 0];
            if isscalar(this.detector_opts.feature)&&isequal(this.detector_opts.feature,"ALL")
                feature = ["HOG","LBP","GLCM"];
            else
                feature = this.detector_opts.feature;
            end

            % plus feature dimension by options calculation
            for fea = feature
                switch fea
                    case "HOG"

                    case "LBP"

                    case "GLCM"

                    otherwise
                end
            end
        end

        %% LabelsOrder Getter
        function value = get.LabelsOrder(this)
            value = reshape(string(this.classifier.ClassNames), 1, []);
        end

        %% Loaded Getter
        function value = get.Loaded(this)
            value = (~isempty(this.classifier) && isobject(this.classifier));
        end
    end

    methods (Access = public)
        function objects = detect(this, image)
            arguments
                this
                image   (:,:)   {mustBeNumeric}
            end

            %Detect This function detect objects in input image
            %% Previous Dectection for Coarse Detection
            bboxes = this.preDetect(image);

            %% Get Features for Fine-Tuned Detection
            features = this.getFeatures(image, bboxes);

            %% Use Features to Generate Identity
            objects = this.makeIdentity(bboxes, features);
        end

        function load_classifier(this, file)
            arguments
                this
                file    (1,1)   string  {mustBeFile}
            end

            [~, ~, ext] = fileparts(file);
            if ~ismember(ext, [".bin", ".mat"])
                throw(MException("LittleObjectDetector:invalidFile", ...
                    "Unsupported predictor file."));
            else
                try
                    S = load(file, "-mat");
                    switch this.algorithm
                        case "svm"
                            this.classifier = S.SVM;
                            this.detector_opts = S.option;
                        case "yolov4"
                            % TODO
                        case "unet"
                            % TODO
                        otherwise
                            throw(MException("LittleObjectDetector", ...
                                "Unsupported object detection algorithm."));
                    end
                catch ME
                    rethrow(ME);
                end
            end
        end
    end

    methods (Access = private)

        function objs = makeIdentity(this, bboxes, features)
            % This function uses SVM for features detection, use Bayesian 
            % method to calculate the object identity posterior probability,
            % select objects with target labels
            % Input:
            %   - this:
            %   - bboxes: n-by-4 bounding box, [x, y, w, h]
            %   - preobjs: 1-by-1 dictionary, comes from object matcher
            %   - features: n-by-1 cell array with features vector
            % Output:
            %   - objboxes: 1-by-1 dictionary, with <string> -> <cell>,
            %   identity |-> {[x, y, w, h], [p1,p2,p3, ...]}

            if size(bboxes, 1) ~= size(features, 1)
                throw(MException("LittleObjectDetector:unmatchedObjects", ...
                    "Inner error caused, unmatched bounding boxes and features."));
            end

            objs = configureDictionary("string", "cell");

            % remove invalid features
            rmfidx = cellfun(@isempty, features, "UniformOutput",true);
            bboxes(rmfidx, :) = [];
            features(rmfidx, :) = [];

            % SVM makes classification by using features
            features = cell2mat(features);
            [ids, ~, ~, posterior] = predict(this.classifier, features);

            % omit other labels, only object (&posterior)
            for k = 1:numel(ids)
                key = sprintf("%s%d", this.prop_opts.object, k);
                objs{key} = {bboxes(k, :), posterior(k,:)};
            end
        end

        function features = getFeatures(this, image, bboxes)
            % This function uses image middle frequency information for
            % features detection
            % Input:
            %   - this:
            %   - image: m-by-n uint8/uint16 matrix
            %   - bboxes: k-by-4 double matrix, k for objects number, [x, y, w, h]
            %   - prebboxes: k-by-4 double
            % output:
            %   - features: k-by-1 cell with feature vector

            features = cell(size(bboxes, 1), 1);
            opts = this.detector_opts;

            %% Use gradient method for object edge extraction
            parfor k = 1:size(bboxes, 1)
                % crop image region
                bbox = bboxes(k, :);
                img = image(bbox(2):bbox(2)+bbox(4)-1, bbox(1):bbox(1)+bbox(3)-1); %#ok<PFBNS>

                % extract feature in boxed image
                features{k} = LittleObjectDetector.getBoxedFeaturesIn(img, opts);
            end
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

            % remove artifact in white field
            DoS = 2*std2(imresize(image, [32,32], "box"))^2;
            image = imbilatfilt(image, DoS);

            % use adaptive threshold for foreground detection
            img_bw = imbinarize(image, "adaptive", "Sensitivity", 1-this.prop_opts.robustness);

            % imclose for covered foreground estimation
            img_bw = imclose(img_bw, strel("diamond", 2));

            % remove border objects (omit true objects, treat as lost)
            img_bw = imclearborder(img_bw, 4);

            % remove too small objects by absolute pixels number
            img_bw = bwareaopen(img_bw, this.prop_opts.nprange(1), 4);
            this.bimg = img_bw;
            
            % Measure regions bounding boxes
            bboxes = regionprops("table", img_bw, "BoundingBox").BoundingBox;

            %% Filter boxes by size
            boxsz = bboxes(:,3).*bboxes(:,4);

            % Mahalanobis distance for outlier removing
            objs_cost = abs(boxsz - this.prop_opts.npobj(1))./this.prop_opts.npobj(2);

            % sort by min cost
            if size(bboxes, 1) > this.prop_opts.nobjmax
                [~, cost_pos] = sort(objs_cost, "ascend");
                bboxes = bboxes(cost_pos(1:this.prop_opts.nobjmax), :);
            end

            % post process: box extension, make sure true object 
            % foreground must be in box
            % dw = dh = d
            half_p = bboxes(:,3)+bboxes(:,4);
            area_sz = bboxes(:,3).*bboxes(:,4);
            pd = ceil((sqrt(half_p.^2+4*this.EXTEND_RATIO*area_sz)-half_p) / 2);
            wh_max = size(image, [2,1]);
            for k = 1:size(bboxes, 1)
                bboxes(k,[1,2]) = max(1, floor(bboxes(k,[1,2]) - pd(k)/2));
                bboxes(k,[3,4]) = min(bboxes(k,[3,4]) + pd(k), ...
                                      wh_max - bboxes(k,[1,2]));
            end
            % final shrink
            bboxes = floor(bboxes);
        end
    end 

    methods(Static)
        function [features, img_bw] = getBoxedFeaturesIn(img, option)
            %GETFEATURES This function get features in one boxed image (image block)
            % and call LittleObjectDetector static function: extractFeature
            % This function works look like LittleObjectDetector private function: getFeatures
            % pipeline see: https://ww2.mathworks.cn/help/images/detecting-a-cell-using-image-segmentation.html
            % Input:
            %   - img: m-by-n uint8/uint16 blocked image, contains only one object
            %   - option: 1-by-1 struct, with features extraction options
            % Output:
            %   - feature: 1-by-s feature vector
            arguments
                img     (:,:)   {mustBeNonnegative}
                option  (1,1)   struct
            end

            % edge detection
            [~, th] = edge(img, option.edgealg);
            img_bw_pre = edge(img, option.edgealg, th * option.fudgefac);

            % dilate object
            % we keep holes inner object as one of detection features
            se90 = strel("line",3,90); se0 = strel("line",3,0); % minimal cross
            img_bw_pre = imdilate(img_bw_pre,[se90 se0]);

            % fill holes
            img_bw_post = imfill(img_bw_pre, "holes");

            % remove possible connected object at border
            img_bw_post_rmbd = imclearborder(img_bw_post, 4);

            % check if object has been removed
            if ~any(img_bw_post_rmbd, "all")
                img_bw_post(1,:) = false;
                img_bw_post(end,:) = false;
                img_bw_post(:,1) = false;
                img_bw_post(:,end) = false;

                img_bw_post_rmbd = img_bw_post;
            end

            % smooth for better foreground
            seD = strel('diamond',1);
            img_bw_post_rmbd = imerode(img_bw_post_rmbd, seD);    % erode only once

            % cross for final mask(with inner holes)
            img_bw = img_bw_post_rmbd.*img_bw_pre;

            % detect features
            features = extractFeatures(img_bw, option.feature, option.feaopt);
        end
    end
end