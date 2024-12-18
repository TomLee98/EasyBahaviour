classdef Tracker < handle
    %TRACKER This class implements a tracker, which could track little 
    % moving objects in a complex scene

    properties(Constant, Hidden)
        AVERAGE_TARGET_RECALL = 0.8
        % MODE = "_DEBUG_"
        MODE = "_RELEASE_"
    end
    
    properties(Access = private)
        hBMC        (1,1)   BayesianMotionClassifier    % BayesianMotionClassifier object handle
        hLOD        (1,1)   LittleObjectDetector        % LittleObjectDetector object handle
        hMP         (1,1)   MotionPredictor             % MotionPredictor object handle
        hOM         (1,1)   ObjectMatcher               % ObjectMatcher object handle
        keys_lost   (1,1)   dictionary                  % string -> double, indicate lost keys continue number
        keys_stay   (1,1)   dictionary                  % mark the keep stayed objects identity -> target posterior
        obj_prev    (1,1)   dictionary                  % previous observed objects
        opts        (1,1)   struct                      % Track object options struct
        time_prev   (1,1)   double                      % previous time stamps, for calculating v, unit as seconds
    end

    properties(Access = private, Hidden)
        isTrackingInit  (1,1)   logical = true          % tracking initialize flag
    end
    
    methods
        function this = Tracker(options_)
            arguments
                options_    (1,1)   struct  = struct("lodopts", struct("classifier", "E:\si lab\Matlab Projects\EasyBehaviour\subapps\Tracker\utils\ObjectDetector\SVM\classifier_svm.bin", ...
                                                                       "alg",        "svm", ...
                                                                       "options",    struct()), ...
                                                     "mpopts",  struct("KFEnable", false, ...
                                                                       "KFWin",    9), ...
                                                     "omopts",  struct("cost", "Jaccard", ...
                                                                       "dist", "Euclidean"), ...
                                                     "tkopts",  struct("target",   "larva", ...
                                                                       "mmdl",  MotionModel("Brownian-Gaussian"), ...
                                                                       "pth",   0.35, ...
                                                                       "memlen", 10, ...
                                                                       "xRes", 0.1, ... % mm/pixel
                                                                       "yRes", 0.1));
            end

            % initialize variables
            this.obj_prev = configureDictionary("string", "cell");
            this.keys_lost = configureDictionary("string", "double");
            this.keys_stay = configureDictionary("string", "double");
            this.time_prev = 0;

            % initialize components handle
            refreshComponents(this, options_);
        end

        function delete(this)
            % ~
        end
    end

    methods(Access = public)
        function boxes = track_(this, frame)
            arguments
                this
                frame   (1, 2)  cell    % {image:m-by-n matrix, time:1-by-1 scalar}
            end

            boxes = dictionary();

            pause(0.4);
        end

        function boxes = track(this, frame)
            % This function implements "SORT" algorithm for object tracking
            % Input:
            %   - frame: 1-by-2 cell array, with {image, time}
            % Output:
            %   - boxes: 1-by-1 dictionary, identity(string) -> locatedprob(1-by-5 double, [x,y,w,h,p])
            arguments
                this
                frame   (1, 2)  cell    % {image:m-by-n matrix, time:1-by-1 scalar}
            end       

            %% Detect Objects from Current Frame
            t_cur = frame{2};

            duration_sec = [this.time_prev, t_cur];
            this.time_prev = t_cur;

            % note that posterior as prior when moving detection
            obj_observed = this.hLOD.detect(frame{1});  % {boxes, posterior}

            %% Predict Current Object Locations by MotionPredictor
            A = Tracker.MakeA(diff(duration_sec));

            if this.isTrackingInit
                % use observed replaced previous at initialized
                this.obj_prev = Tracker.TransFromObserved(obj_observed);    % {[boxes; velocity_boxes]}
                this.isTrackingInit = false;
            else
                % updated previously
            end

            % predict current locations by KF filter and obj_prev
            obj_predicted = this.hMP.predict(A, this.obj_prev);         % {[boxes; velocity_boxes]}
            obj_pdt_prior = Tracker.ExtractLocationsIn(obj_predicted);  % [boxes]
            obj_obs_prior = Tracker.ExtractLocationsIn(obj_observed);   % [boxes]

            %% Match Observed and Predicted Objects by ObjectMatcher
            [id_matched, id_new, id_lost, ~] = this.hOM.match(obj_pdt_prior, obj_obs_prior);

            %% Distribute 'Target' (Dynamic) Posterior on each object
            [boxes, this.obj_prev] = this.hBMC.reEstimate(this.obj_prev, ...
                                                          obj_pdt_prior, ...
                                                          obj_observed, ...
                                                          id_matched, ...
                                                          id_new, ...
                                                          id_lost, ...
                                                          diff(duration_sec));

            %% Remove 'Targets' with Posterior Lower than Threshold
            boxkeys = boxes.keys("uniform")';
            switch this.MODE
                case "_DEBUG_"
                    for key = boxkeys
                        % append v for debugging
                        vvec = this.obj_prev{key}(BayesianMotionClassifier.LOCFEATURES_N+1:end);
                        boxes{key} = [boxes{key}, sqrt(sum(vvec.^2))];
                    end
                otherwise
                    for key = boxkeys
                        % remove objects in boxes
                        if boxes{key}(end) < this.opts.tkopts.pth
                            boxes(key) = [];
                            % this.obj_prev(key) = [];    %! keep obj_prev to avoid erase-flush
                        end
                    end
            end
        end

        function status = refreshComponents(this, options)
            arguments
                this
                options     (1,1)   struct
            end

            this.opts = options;

            try
                this.hLOD = LittleObjectDetector(this.opts.lodopts.classifier, ...
                    this.opts.lodopts.alg);
                this.hMP = MotionPredictor(this.opts.mpopts.KFWin, ...
                    this.opts.mpopts.KFEnable);
                this.hOM = ObjectMatcher(this.opts.omopts.cost, ...
                    this.opts.omopts.dist);

                mdl = this.opts.tkopts.mmdl;
                scale = struct("xRes", this.opts.tkopts.xRes, ...
                    "yRes", this.opts.tkopts.yRes);
                lambda = this.opts.tkopts.pth^(1/(this.opts.tkopts.memlen+1));

                if this.hLOD.Loaded
                    target = find(this.hLOD.LabelsOrder==this.opts.tkopts.target);
                    this.hBMC = BayesianMotionClassifier(mdl, scale, target, lambda);
                    status = 0;
                else
                    status = -1;
                end
            catch ME
                rethrow(ME);
            end
        end
    end

    methods(Static)
        function value = noneTrack()
            value = configureDictionary("string", "cell");
        end
    end

    methods(Static, Hidden)
        function A = MakeA(dt)
            arguments
                dt    (1,1)   double    {mustBePositive}
            end

            A = [1, 0, 0, 0, dt,  0,  0,  0;    % [x]
                 0, 1, 0, 0,  0, dt,  0,  0;    % [y]
                 0, 0, 1, 0,  0,  0, dt,  0;    % [w]
                 0, 0, 0, 1,  0,  0,  0, dt;    % [h]
                 0, 0, 0, 0,  1,  0,  0,  0;    % [vx]
                 0, 0, 0, 0,  0,  1,  0,  0;    % [vy]
                 0, 0, 0, 0,  0,  0,  1,  0;    % [vw]
                 0, 0, 0, 0,  0,  0,  0,  1];   % [vh]
        end

        function Y = TransFromObserved(obj_cur)
            arguments
                obj_cur (1,1)   dictionary
            end

            Y = configureDictionary("string", "cell");

            for key = obj_cur.keys("uniform")'
                Y{key}= [obj_cur{key}{1}'; zeros(4, 1)];
            end
        end

        function r = ExtractLocationsIn(obj)
            arguments
                obj     (1,1)   dictionary
            end

            r = configureDictionary("string", "cell");
            for key = obj.keys("uniform")'
                if iscell(obj{key})
                    r{key} = obj{key}{1}';
                else
                    r{key} = obj{key}(1:4); % extract [x;y;w;h]
                end
            end
        end
    end
end

