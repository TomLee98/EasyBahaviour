classdef BayesianMotionClassifier < handle
    %BAYESIANMOTIONCLASSIFIER This class defines a motion classifier based
    %on bayesian posterior probability

    properties(Constant, Hidden)
        LOCFEATURES_N = 4
        AVERAGE_TARGET_RECALL = 0.8
    end
    
    properties(Access = private)
        mmodel
        scale
        pidx
        lambda
        posterior
    end
    
    methods
        function this = BayesianMotionClassifier(mdl, scale, target, lambda)
            %BAYESIANESTIMATOR A Constructor
            % Input:
            %   - mdl: 1-by-1 motion model
            %   - opts:1-by-1 struct with estimator options
            arguments
                mdl     (1,1)   MotionModel = MotionModel("Brownian-Gaussian")
                scale   (1,1)   struct  = struct("xRes", 0.1, ...
                                                 "yRes", 0.1);
                target  (1,:)   double  {mustBePositive, mustBeInteger} = 3
                lambda  (1,1)   double  {mustBeInRange(lambda, 0, 1)} = 0.88
            end

            this.mmodel = mdl;
            this.scale = [scale.xRes; scale.yRes; scale.xRes; scale.yRes];
            this.pidx = target;
            this.lambda = lambda;

            this.posterior = configureDictionary("string", "double");
        end

    end

    methods (Access = public)
        function [boxes, observed] = reEstimate(this, observed_prev, predicted, observed, matched, new, lost, dt)
            % This function re-estimates the objects posterior prabability
            % and export modified observed as observed_previous for next
            % estimation after Tracker calling
            % Input:
            %   - observed_prev: 1-by-1 dictionary, id(string) -> {[x,y,w,h,vx,vy,vw,vh]'}
            %   - predicted: 1-by-1 dictionary, id(string) -> {[x,y,w,h]'}
            %   - observed: 1-by-1 dictionary, id(string) -> {{[x,y,w,h]}, {[p0,p1,...]}}
            %   - matched: m-by-2 table, with {predicted, observed}, id
            %               mapping between predicted and observed
            %   - new: n-by-1 table, with {observed}
            %   - lost: p-by-1 table, with {predicted}
            %   - dt: 1-by-1 positive double, indicate time delay between
            %       observed_prev and observed
            % Output:
            %   - boxes: 1-by-1 dictionary, id(string) -> {[x,y,w,h,p]}, p
            %           for posterior probability between 0 and 1
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

            %% update velocity on each objects
            observed_tot = configureDictionary("string", "cell");   % id -> [x,y,w,h,vx,vy,vw,vh]
            boxes = configureDictionary("string", "cell");
            
            % update matched objects
            for m = 1:numel(matched.predicted)
                % update velocity
                bbox_prev = observed_prev{matched.predicted(m)}(1:this.LOCFEATURES_N);
                bbox_prev(1) = bbox_prev(1)+bbox_prev(3)/2; bbox_prev(2) = bbox_prev(2)+bbox_prev(4)/2;
                bbox_cur = observed{matched.observed(m)}{1}';
                bbox_cur(1) = bbox_cur(1)+bbox_cur(3)/2; bbox_cur(2) = bbox_cur(2)+bbox_cur(4)/2;

                v = (bbox_cur - bbox_prev).*this.scale./dt;

                observed_tot{matched.predicted(m)} = ...
                    [observed{matched.observed(m)}{1}'; v];

                % update posterior probability
                rv = sqrt(sum(v.^2));
                prior = observed{matched.observed(m)}{2}(this.pidx);

                if this.posterior.isKey(matched.predicted(m))
                    ptior = bem(this, rv, prior);

                    % update weighted memory
                    this.posterior(matched.predicted(m)) = ...
                        this.lambda*this.posterior(matched.predicted(m)) ...
                        + (1-this.lambda)*ptior;
                else
                    this.posterior(matched.predicted(m)) = prior;
                end

                boxes{matched.predicted(m)} = [observed{matched.observed(m)}{1}, ...
                    this.posterior(matched.predicted(m))];
            end

            % update new objects
            for n = 1:numel(new.observed)
                % update velocity
                % v as 0 for initializing
                v = zeros(this.LOCFEATURES_N, 1);   

                observed_tot{new.observed(n)} = ...
                    [observed{new.observed(n)}{1}'; v];

                % update posterior probability
                % only prior as initial value
                this.posterior(new.observed(n)) ...
                    = observed{new.observed(n)}{2}(this.pidx);

                boxes{new.observed(n)} = [observed{new.observed(n)}{1}, ...
                    this.posterior(new.observed(n))];
            end

            % update lost objects
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

                boxes{lost.predicted(p)} = [predicted{lost.predicted(p)}', ...
                    this.posterior(lost.predicted(p))];
            end

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

