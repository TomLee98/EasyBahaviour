classdef BayesianMotionClassifier < handle
    %BAYESIANMOTIONCLASSIFIER This class defines a motion classifier based
    %on bayesian posterior probability

    properties(Constant, Hidden)
        LOCFEATURES_N = 4
        AVERAGE_TARGET_RECALL = 0.8
    end
    
    properties(Access = private)
        boundary        % 3-by-2 double, [xmin,xmax; ymin,ymax; bxmin,bxmax]
        lambda          % 1-by-1 double, memory weight on history
        mmodel          % 1-by-1 MotionModel, which split moving objects and shake/hold objects 
        obj_type        % 1-by-1 positive integer, tracking objects type inner representation
        obj_oblivion    % 1-by-1 dictionary, <string> -> <double>, indicate each invalid object continuous time
        posterior       % 1-by-1 dictionary, <string> -> <double>, indicate each object (@obj_type) posterior probability
        scale           % 4-by-1 double, [xr; yr; xr; yr]
        trcap           % 1-by-1 positive integer, maximum continuous invalid objects traces capacity
    end
    
    methods
        function this = BayesianMotionClassifier(mdl, scale, boundary, object, lambda, trcap)
            %BAYESIANESTIMATOR A Constructor
            % Input:
            %   - mdl: 1-by-1 motion model
            %   - opts:1-by-1 struct with estimator options
            arguments
                mdl     (1,1)   MotionModel = MotionModel("Brownian-Gaussian")
                scale   (1,1)   struct  = struct("xRes", 0.1, ...
                                                 "yRes", 0.1);
                boundary(3,2)   double  {mustBePositive} = [1, 2048; 1, 1088; 15, 225]
                object  (1,1)   double  {mustBePositive, mustBeInteger} = 2
                lambda  (1,1)   double  {mustBeInRange(lambda, 0, 1)} = 0.88
                trcap   (1,1)   double  {mustBePositive, mustBeInteger} = 8
            end

            this.trcap = trcap;
            this.mmodel = mdl;
            this.scale = [scale.xRes; scale.yRes; scale.xRes; scale.yRes];
            this.boundary = boundary;
            this.obj_type = object;
            this.lambda = lambda;

            this.obj_oblivion = configureDictionary("string", "double");
            this.posterior = configureDictionary("string", "double");
        end

    end

    methods (Access = public)
        function [boxes, observed] = reEstimate(this, observed_prev, predicted, observed, matched, new, lost, dt)
            % This function re-estimates the objects posterior prabability
            % and export modified observed_prev for next estimation after 
            % Tracker calling
            % (observed_prev, predicted, observed) --update-->
            % (observed_prev) as new (observed)
            % Input:
            %   - observed_prev: 1-by-1 dictionary, id(string) ->
            %   {[x,y,w,h,vx,vy,vw,vh]'}, total observed tracks previously
            %   - predicted: 1-by-1 dictionary, id(string) -> {[x,y,w,h]'}
            %   - observed: 1-by-1 dictionary, id(string) -> {{[x,y,w,h]},
            %               {[p0,p1,...]}}, current observed tracks
            %   - matched: m-by-2 table, with {predicted, observed}, id
            %               mapping between predicted and observed
            %   - new: n-by-1 table, with {observed}
            %   - lost: p-by-1 table, with {predicted}
            %   - dt: 1-by-1 positive double, indicate time delay between
            %       observed_prev and observed
            % Output:
            %   - boxes: 1-by-1 dictionary, id(string) ->
            %       {[x,y,w,h,pp,pf]}, pp for posterior probability between 
            %       0 and 1, pf as predict indicator by MotionPredictor, 
            %       true for a predicted box
            %   - observed: 1-by-1 dictionary, id(string) -> {[x,y,w,h,vx,vy,vw,vh]}

            arguments
                this
                observed_prev   (1,1)   dictionary
                predicted       (1,1)   dictionary
                observed        (1,1)   dictionary
                matched         (:,2)   table
                new             (:,1)   table
                lost            (:,1)   table
                dt              (1,1)   double      {mustBePositive}
            end

            % Update Observed History
            observed_tot = configureDictionary("string", "cell");   % id -> [x,y,w,h,vx,vy,vw,vh]
            boxes = configureDictionary("string", "cell");  % id -> [x,y,w,h,pp,pf]

            %% update matched objects (<==>updateAssignedTracks)
            for m = 1:numel(matched.predicted)
                % update velocity
                bbox_prev = observed_prev{matched.predicted(m)}(1:this.LOCFEATURES_N);
                bbox_prev(1) = bbox_prev(1)+bbox_prev(3)/2; bbox_prev(2) = bbox_prev(2)+bbox_prev(4)/2;
                bbox_cur = observed{matched.observed(m)}{1}';

                % transform to [center_x, center_y, width, height]
                bbox_cur(1) = bbox_cur(1)+bbox_cur(3)/2; bbox_cur(2) = bbox_cur(2)+bbox_cur(4)/2;

                v = (bbox_cur - bbox_prev).*this.scale./dt;

                observed_tot{matched.predicted(m)} = ...
                    [observed{matched.observed(m)}{1}'; v];

                % update posterior probability
                rv = sqrt(sum(v.^2));
                prior = observed{matched.observed(m)}{2}(this.obj_type);

                if this.posterior.isKey(matched.predicted(m))
                    ptior = bem(this, rv, prior);

                    % update weighted memory
                    this.posterior(matched.predicted(m)) = ...
                        this.lambda*this.posterior(matched.predicted(m)) ...
                        + (1-this.lambda)*ptior;
                else
                    this.posterior(matched.predicted(m)) = prior;
                end
            end

            %% update new objects (<==>updateUnassignedTracks)
            new_objs = configureDictionary("string", "double");
            new_keys = strings(numel(new.observed), 1);
            obsvname_prev = observed_prev.keys("uniform");
            for n = 1:numel(new.observed)
                % update velocity
                % v as 0 for initializing
                v = zeros(this.LOCFEATURES_N, 1);   

                % regenerate new identities which will be added to
                % tracks history: observed_tot
                group = regexp(new.observed(n), "[a-zA-Z]*", "match");

                if ~new_objs.isKey(group)
                    new_objs(group) = 1;
                else
                    new_objs(group) = new_objs(group) + 1;
                end

                id_group = obsvname_prev(observed_prev.keys("uniform").contains(group));
                nmax_group = max(str2double(id_group.extractAfter(group)));
                n_next = nmax_group + new_objs(group);
                id_next = sprintf("%s%d", group, n_next);
                new_keys(n) = id_next;

                observed_tot{id_next} = ...
                    [observed{new.observed(n)}{1}'; v];

                % update posterior probability
                % only prior as initial value
                this.posterior(id_next) ...
                    = observed{new.observed(n)}{2}(this.obj_type);
            end

            %% update lost objects(<==>deleteLostTracks)
            for p = 1:numel(lost.predicted)
                % update velocity
                % keep v as previous observed
                v = observed_prev{lost.predicted(p)}(this.LOCFEATURES_N+1:end);

                observed_tot{lost.predicted(p)} = ...
                    [predicted{lost.predicted(p)}; v];

                % update posterior probability
                % exponential decay
                if this.posterior.isKey(lost.predicted(p))
                    this.posterior(lost.predicted(p)) = ...
                        this.lambda * this.posterior(lost.predicted(p));
                else
                    this.posterior(lost.predicted(p)) = this.AVERAGE_TARGET_RECALL;
                end
            end

            %% update valid object (with box filter: isValidBBox)
            invalid_objs = strings([]);
            for key = observed_tot.keys("uniform")'
                if this.isValidBBox(observed_tot{key}(1:this.LOCFEATURES_N))
                    predict_flag = ...
                        ~isempty(new_keys) && ismember(key, new_keys);

                    boxes{key} = [observed_tot{key}(1:this.LOCFEATURES_N)', ...
                            this.posterior(key), predict_flag];

                    % clear oblivion marker
                    if this.obj_oblivion.isKey(key)
                        this.obj_oblivion(key) = [];
                    end
                else
                    if this.obj_oblivion.isKey(key)
                        this.obj_oblivion(key) = this.obj_oblivion(key) + 1;
                        % mark invalid objects
                        if this.obj_oblivion(key) > this.trcap
                            invalid_objs = [invalid_objs, key]; %#ok<AGROW>
                        end
                    else
                        % initialized object marker
                        this.obj_oblivion(key) = 1;
                    end
                end
            end

            % remove object with invalid box over traces capacity
            for key = invalid_objs
                observed_tot(key) = [];
                this.obj_oblivion(key) = [];
            end

            %
            observed = observed_tot;
        end
    end

    methods(Access = private)
        function pp = bem(this, vobs, pm)
            d = this.mmodel.Args.d;
            s0 = this.mmodel.Args.s0;
            v1 = this.mmodel.Args.v1;
            s1 = this.mmodel.Args.s1;

            switch this.mmodel.Vmdl
                case "Brownian-Gaussian"
                    pp = BayesianMotionClassifier.bem_bg(vobs, pm, s0, d, v1, s1);
                case "Gamma-Gaussian"
                    pp = BayesianMotionClassifier.bem_gg(vobs, pm, d, s0, v1, s1);
                otherwise
                    throw(MException("BayesianMotionClassifier:invalidModel", ...
                        "Unsupported motion model."));
            end
        end

        function TF = isValidBBox(this, bbox)
            bbox = floor(bbox);
            TF = (bbox(1) >=this.boundary(1,1) && bbox(1)+bbox(3)-1<=this.boundary(1,2)) ...
                && (bbox(2) >=this.boundary(2,1) && bbox(2)+bbox(4)-1<= this.boundary(2,2)) ... 
                && (bbox(3) > 0) && (bbox(4) > 0) ...
                && (bbox(3)*bbox(4) >= this.boundary(3,1)) ...
                && (bbox(3)*bbox(4) <= this.boundary(3,2));
        end
    end

    methods(Static)
        function pp = bem_bg(vobs, pm, s0, d, v1, s1)
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
                s0      (1,1)   double  {mustBePositive}            = 0.25  % prior, mm/s
                d       (1,1)   double  {mustBeMember(d, 1:4)}      = 4     % 
                v1      (1,1)   double  {mustBeNonnegative}         = 1.40  % prior, mm/s
                s1      (1,1)   double  {mustBePositive}            = 0.45  % prior, mm/s
            end

            % 1-D cutoff gaussian distribution
            p_v_moving = (normpdf(vobs, v1, s1) - normpdf(0, v1, s1)) ...
                /(1/sqrt(2*pi*s1^2) - normpdf(0, v1, s1));
            if d ==1
                % degenerates into half-normal distribution
                p_v_shift = 2/(sqrt(2*pi)*s0)*exp(-vobs^2/(2*s0^2));
            elseif d == 2
                % 2-D Maxwell-Boltzmann distribution
                p_v_shift = vobs/s0^2*exp(-vobs^2/(2*s0^2));
            elseif d == 3
                % 3-D Maxwell-Boltzmann distribution
                p_v_shift = 2*vobs^2/(sqrt(2*pi)*s0^3)*exp(-vobs^2/(2*s0^2));
            elseif d == 4
                % 4-D Maxwell-Boltzmann distribution
                p_v_shift = vobs^3/(2*s0^4)*exp(-vobs^2/(2*s0^2));
            end

            % Bayesian continues formation
            pp = p_v_moving*pm/(p_v_moving*pm + p_v_shift*(1-pm) + 1e-10);
        end

        function pp = bem_gg(vobs, pm, n, s0, v1, s1)
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
                n       (1,1)   double  {mustBePositive}            = 1
                s0      (1,1)   double  {mustBePositive}            = 0.15  % prior, mm/s
                v1      (1,1)   double  {mustBeNonnegative}         = 1.25  % prior, mm/s
                s1      (1,1)   double  {mustBePositive}            = 0.2  % prior, mm/s
            end

            pp = 1;
        end
    end
end

