classdef Tracker < handle
    %TRACKER This class implements a tracker, which could track little 
    % moving objects in a complex scene

    properties(Constant, Hidden)
        AVERAGE_TARGET_RECALL = 0.8
    end
    
    properties(Access = private)
        hLOD            (1,1)   LittleObjectDetector    % LittleObjectDetector object handle
        hMP             (1,1)   MotionPredictor         % MotionPredictor object handle
        hOM             (1,1)   ObjectMatcher           % ObjectMatcher object handle
        keys_lost       (1,1)   dictionary              % string -> double, indicate lost keys continue number
        keys_stay       (1,1)   dictionary              % mark the keep stayed objects identity -> target posterior
        obj_prev        (1,1)   dictionary              % previous observed objects
        time_prev       (1,1)   double                  % previous time stamps, for calculating v, unit as seconds
        opts            (1,1)   struct                  % Track object options struct
    end

    properties(Access = private, Hidden)
        isTrackingInit  (1,1)   logical = true          % tracking initialize flag
    end
    
    methods
        function this = Tracker(options_)
            arguments
                options_    (1,1)   struct  = struct("lodopts", struct("classifier", "E:\si lab\Matlab Projects\EasyBehaviour\subapps\Tracker\utils\SVM\classifier_svm.bin", ...
                                                                       "alg",        "svm", ...
                                                                       "options",    struct()), ...
                                                     "mpopts",  struct("KFEnable", true, ...
                                                                       "KFWin",    9), ...
                                                     "omopts",  struct("cost", "Jaccard", ...
                                                                       "dist", "Euclidean"), ...
                                                     "tkopts",  struct("target",   "larva", ...
                                                                       "keeplost", 3, ...
                                                                       "lastw", 0.618, ...
                                                                       "xRes", 0.1, ... % mm/pixel
                                                                       "yRes", 0.1));
            end

            this.opts = options_;

            this.obj_prev = configureDictionary("string", "cell");
            this.keys_lost = configureDictionary("string", "double");
            this.keys_stay = configureDictionary("string", "double");
            this.time_prev = 0;

            % initialize components handle
            this.hLOD = LittleObjectDetector(this.opts.lodopts.classifier, ...
                                             this.opts.lodopts.alg);
            this.hMP = MotionPredictor(this.opts.mpopts.KFWin, ...
                                       this.opts.mpopts.KFEnable);
            this.hOM = ObjectMatcher(this.opts.omopts.cost, ...
                                     this.opts.omopts.dist);
        end

        function delete(this)
            % ~
        end
    end

    methods(Access = public)
        function [boxes, gcs] = track(this, frame)
            % This function implements "SORT" algorithm for object tracking
            % Input:
            %   - frame: 1-by-2 cell array, with {image, time}
            % Output:
            %   - boxes: 1-by-1 dictionary, identity(string) -> location(1-by-4 double, [x,y,w,h])
            %   - gcs: 1-by-1 dictionary, identity(string) -> mass center(1-by-2 double, [x,y])
            arguments
                this
                frame   (1, 2)  cell    % {image:m-by-n matrix, time:1-by-1 scalar}
            end       

            %% Detect Objects from Current Frame
            t_cur = frame{2};
            obj_observed = this.hLOD.detect(frame{1});  % {boxes, posterior}

            duration_sec = [this.time_prev, t_cur];
            
            %% Match observed and predicted
            A = Tracker.MakeA(duration_sec);

            if this.isTrackingInit
                % use observed replaced previous at initialized
                Y = Tracker.TransFromObserved(obj_observed);
            else
                Y = Tracker.TransFromObserved(this.obj_prev);
            end

            obj_predicted = this.hMP.predict(A, Y);     % {[boxes, velocity_boxes]}
            obj_predicted = Tracker.ExtractLocationsIn(obj_predicted);  % [boxes]
            obj_obs_prior = Tracker.ExtractLocationsIn(obj_observed);

            % match predicted and observed
            [id_matched, id_new, id_lost, ~] = this.hOM.match(obj_predicted, obj_obs_prior);

            %% Pre-Filtered the objects may not be moving
            if ~this.isTrackingInit
                % validate objects in id_matched set, modify obj_predicted set
                obj_pdt_post = configureDictionary("string", "cell");
                for k = 1:numel(id_matched.predicted)
                    % rename for compared with observed
                    obj_pdt_post(id_matched.predicted(k)) ...
                        = obj_predicted(id_matched.predicted(k));
                end

                obj_predicted = generatePredictedVars(this, ...
                                                      obj_pdt_post, ...
                                                      obj_observed, ...
                                                      id_matched, ...
                                                      duration_sec);
            else
                % do nothing
            end

            obj_obs_prior = Tracker.ExtractLocationsIn(obj_observed);        % [boxes]
            %% Predict current objects location by previous observed
            % handle the cost in memory, until overflow memory size
            for k = 1:numel(id_lost.predicted)
                key = id_lost.predicted(k);
                if this.keys_lost.isKey(key)
                    this.keys_lost(key) = this.keys_lost(key) + 1;

                    % over memory capacity, may lost forever
                    if this.keys_lost(key) > this.opts.tkopts.keeplost
                        this.keys_lost(key) = [];
                        obj_predicted(key) = [];    % also remove from predicted set
                    end
                else
                    this.keys_lost(key) = 1;    % init lost
                end
            end

            % boxes with matched, new and lost
            % replace matched observed identities with predicted identities
            boxes = configureDictionary("string", "cell");
            for k = 1:numel(id_matched.predicted)
                boxes(id_matched.predicted(k)) = obj_obs_prior(id_matched.observed(k));
            end

            % insert new identities
            for k = 1:numel(id_new)
                boxes(id_new.observed(k)) = obj_obs_prior(id_new.observed(k));
            end

            % keep some losted boxes
            for key = this.keys_lost.keys("uniform")'
                boxes(key) = obj_predicted(key);
            end

            gcs = Parameterizer.GetGeometricCenters(frame{1}, boxes);

            % update memory
            updateMemory(this, boxes, t_cur);
        end
    end

    methods (Access = private)
        function obj_pdt = generatePredictedVars(this, obj_prev, obj_cur, id_mapping, timev, pth)
            arguments
                this    
                obj_prev    (1,1)   dictionary      % id -> [x,y,w,h]'
                obj_cur     (1,1)   dictionary      % id -> {{[x,y,w,h]}, {[posterior]}}
                id_mapping  (:,2)   table           % [predicted, observed]
                timev       (1,2)   double      {mustBeNonnegative}    % [tprev, tcur]
                pth         (1,1)   double      {mustBeInRange(pth, 0, 1)} = 0.5
            end

            prior_index = (this.hLOD.LabelsOrder==this.opts.tkopts.target);

            % estimate previous objects velocity
            prev_keys = obj_prev.keys("uniform")';
            obj_pdt = configureDictionary("string", "cell");

            for key = prev_keys

                bbox_prev = obj_prev{key};
                bbox_prev(1) = bbox_prev(1)+bbox_prev(3)/2; bbox_prev(2) = bbox_prev(2)+bbox_prev(4)/2;

                % estimate the object previous speed
                key_obs = id_mapping.observed(id_mapping.predicted==key);
                if obj_cur.isKey(key_obs)
                    % use 1st-order back difference estimate velocity
                    bbox_cur = obj_cur{key_obs}{1}';
                    bbox_cur(1) = bbox_cur(1) + bbox_cur(3)/2; bbox_cur(2) = bbox_cur(2) + bbox_cur(4)/2;
                    obj_prior = obj_cur{key_obs}{2}(prior_index);    % use classified results as prior
                    vobs = (bbox_cur - bbox_prev)/diff(timev) ...
                        .*  sqrt(this.opts.tkopts.xRes*this.opts.tkopts.yRes);  % average fluctuation speed;
                else
                    % nothing could estimate the objct speed at previous
                    % time stamp, set as zero
                    obj_prior = this.AVERAGE_TARGET_RECALL;
                    vobs = zeros(size(bbox_prev));
                end

                % detect target is moving as default, otherwise,
                % another posterior = 1 - posterior
                rvobs = sqrt(sum(vobs.^2));
                posterior = Tracker.BayesianEstimateMoving(rvobs, obj_prior);

                if this.keys_stay.isKey(key)
                    posterior = this.opts.tkopts.lastw*this.keys_stay(key) ...
                        + (1-this.opts.tkopts.lastw)*posterior;
                else
                    posterior = this.opts.tkopts.lastw*obj_prior ...
                        + (1-this.opts.tkopts.lastw)*posterior;
                end
                this.keys_stay(key) = posterior;

                if posterior > pth
                    % decide as moving target, output target
                    obj_pdt{key} = {bbox_prev, vobs};
                else
                    % skip this object
                end
            end
        end

        function updateMemory(this, observed_post, t)
            arguments
                this
                observed_post   (1,1)   dictionary
                t               (1,1)   double      {mustBeNonnegative}
            end

            this.obj_prev = configureDictionary("string", "cell");

            for key = observed_post.keys("uniform")'
                if (this.keys_stay.numEntries > 0) && this.keys_stay.isKey(key)
                    posterior_est = zeros(1, numel(this.hLOD.LabelsOrder));
                    typei = regexp(key, "[a-z]*", "match");
                    posterior_est(this.hLOD.LabelsOrder==typei) = this.keys_stay(key);
                    posterior_est(this.hLOD.LabelsOrder~=this.opts.tkopts.target) ...
                        = (1 - this.keys_stay(key))/sum(this.hLOD.LabelsOrder~=this.opts.tkopts.target);
                else
                    posterior_est = zeros(1, numel(this.hLOD.LabelsOrder));
                    typei = regexp(key, "[a-z]*", "match");
                    posterior_est(this.hLOD.LabelsOrder==typei) = 1;
                end
                this.obj_prev{key} = {observed_post{key}', posterior_est};
            end

            this.time_prev = t;

            this.isTrackingInit = false;
        end
    end

    methods(Static, Hidden)
        function A = MakeA(timev)
            arguments
                timev    (1,2)   double
            end

            dt = diff(timev);       % seconds

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

        function pp = BayesianEstimateMoving(vobs, pm, s0, v1, s1)
            % This function use bayesian estimate posterior prabability for
            % object is moving
            % Input:
            %   - s0:
            %   - v1:
            %   - s1:
            %   - pm:
            %   - vobs
            % Output:
            %   - pp:
            arguments
                vobs    (1,1)   double  {mustBeNonnegative}
                pm      (1,1)   double  {mustBeInRange(pm, 0, 1)}
                s0      (1,1)   double  {mustBePositive}            = 0.15  % prior, mm/s
                v1      (1,1)   double  {mustBeNonnegative}         = 0.5   % prior, mm/s
                s1      (1,1)   double  {mustBePositive}            = 0.1  % prior, mm/s
            end

            % 1-D cutoff gaussian distribution
            p_v_moving = (normpdf(vobs, v1, s1) - normpdf(0, v1, s1)) ...
                /(1/sqrt(2*pi*s1^2) - normpdf(0, v1, s1));

            % 4-D Maxwell-Boltzmann distribution
            p_v_shift = vobs^3/(3*pi*s0^4)*exp(-vobs^2/(2*s0^2));   

            % Bayesian continues formation
            pp = p_v_moving*pm/(p_v_moving*pm + p_v_shift*(1-pm) + eps);
        end
        
    end
end

