classdef MotionPredictor < handle
    %MOTIONPREDICTOR This class uses Kalman filter to predict objects motion
    % in current frame by previous frame
    
    properties(Access = private)
        Q   (1,1)   dictionary  % <string> -> <cell>, system noise covarance, cell with N-by-N double matrix, dict with S samples
        R   (1,1)   dictionary  % <string> -> <cell>, observation covariance, cell with N-by-N double matrix, dict with S samples
        X   (1,1)   dictionary  % <string> -> <cell>, filtered system state, cell with N-by-1 double vector, dict with S samples
        P   (1,1)   dictionary  % <string> -> <cell>, posterior error, cell with N-by-N double matrix, dict with S samples
        M   (1,1)   dictionary  % <string> -> <cell>, observed history, cell with N-by-T double matrix, dict with S samples
        sa  (1,1)   string      % smoothing algorithm, in ["EWMA", "UWMA"]
        sw  (1,1)   double      % smoothing window size
    end
    
    methods
        function this = MotionPredictor(Q_, R_)
            %MOTIONPREDICTOR A Constructor
            arguments
                Q_  (1,1)   dictionary = dictionary()
                R_  (1,1)   dictionary = dictionary()
            end

            if ~Q_.isConfigured && ~R_.isConfigured
                %
            elseif Q_.isConfigured && R_.isConfigured
                if ~isempty(setdiff(Q_.keys("uniform"), R_.keys("uniform")))
                    throw(MException("MotionPredictor:invalidNoiseCovarance", ...
                        "Noise covarance matrix with inconsistant labels."));
                end

                for ky = Q_.keys("uniform")'
                    if any(size(Q_{ky})~=size(R_{ky}))
                        throw(MException("MotionPredictor:invalidNoiseCovarance", ...
                            "Noise covarance matrix with inconsistant size"));
                    end
                    if ~issymmetric(Q_{ky}) || ~all(eig(Q_{ky})>size(Q_{ky},1)*eps(max(eig(Q_{ky})))) ...
                            || ~issymmetric(R_{ky}) || ~all(eig(R_{ky})>size(R_{ky},1)*eps(max(eig(R_{ky}))))
                        throw(MException("MotionPredictor:invalidNoiseCovarance", ...
                            "Noise covarance matrix must be positive finate"));
                    end
                end
            else
                throw(MException("MotionPredictor:invalidNoiseCovarance", ...
                            "Noise dictionary configuration not consistant."));
            end

            this.Q = Q_;
            this.R = R_;
            this.X = dictionary();
            this.P = dictionary();
            this.M = dictionary();

            this.sa = "EWMA";
            this.sw = 5;
        end
        
        function InitKalmanFilter(this, Y, Sa, Sw)
            %INITKALMANFILTER This function initializes Kalman filter
            % parameters X0, P0
            arguments
                this
                Y       (1,1)   dictionary
                Sa      (1,1)   string  {mustBeMember(Sa, ["EWMA", "UWMA"])} = "EWMA"
                Sw      (1,1)   double  {mustBePositive} = 5
            end

            ysize = cellfun(@size, Y.values, "UniformOutput", false);
            try
                ysize = cell2mat(ysize);
                if numel(unique(ysize(:,2))) ~= 1
                    throw(MException("MotionPredictor:invalidTime", ...
                        "Sampling time stamps are not consistant."));
                end
                if ysize(1,2) <= Sw
                    throw(MException("MotionPredictor:invalidTime", ...
                        "Sampling time stamps are not enough."));
                end
            catch ME
                rethrow(ME);
            end
            
            % init basic parameters
            this.M = Y;
            this.sa= Sa;
            this.sw = Sw;

            % use smooth algorithm for rough estimation
            this.update_QR();

            % initialize X0 and P0
            kys = Y.keys("uniform");
            this.X(kys) = cellfun(@(x)mean(x,2), Y.values, "UniformOutput",false);
            this.P(kys) = cellfun(@(x)cov(x'), Y.values, "UniformOutput",false);
        end

        function X = Predict(this, A, Y)
            % This function use observed data Y and history to estimate 
            % current system status
            arguments
                this
                A       (:,:)   double
                Y       (1,1)   dictionary
            end

            if ~this.M.isConfigured
                throw(MException("MotionPredictor:uninitializedFilter", ...
                    "Kalman filter has not initialized yet."));
            else
                if ~isempty(setdiff(Y.keys("uniform"), X_.keys("uniform")))
                    throw(MException("MotionPredictor:invalidSample", ...
                        "Samples number is not consistant."));
                end

                % call Kalman filter on samples
                for ky = Y.keys("uniform")'
                    [this.X{ky}, this.P{ky}] = OneStepKalmanFilter(A, ...
                        this.Q{ky}, this.R{ky}, Y{ky}, this.X{ky}, this.P{ky});
                end

                % update Q and R dynamically
                this.update_history();
                this.update_QR();

                X = this.X;
            end
        end

        function RemoveSample(this, key)
            arguments
                this
                key     (1,1)   string
            end

            % remove all data corresponds to key
            if this.X.isKey(key)
                this.Q(key) = [];
                this.R(key) = [];
                this.X(key) = [];
                this.P(key) = [];
                this.M(key) = [];
            end
        end

        function AppendSample(this, key, value)

        end
    end

    methods(Access = private)
        function update_history(this, Y)
            % use Y update M
            for ky = this.M.keys("uniform")'
                this.M{ky}(:,1) = [];               % remove oldest record
                this.M{ky} = [this.M{ky}, Y{ky}];   % append new record
            end
        end

        function update_QR(this)
            % use smooth algorithm for rough estimation
            switch this.sa
                case "EWMA"
                    smy = MotionPredictor.EWMA(this.M, this.sw);
                case "UWMA"
                    smy = MotionPredictor.UWMA(this.M, this.sw);
                otherwise
            end

            % estimate Q and R one by one
            for ky = this.M.keys("uniform")'
                this.Q{ky} = cov(smy{ky}');
                this.R{ky} = cov((this.M{ky}-smy{ky})');
            end
        end
    end

    methods(Static)
        function sy = EWMA(Y, L)
            lambda = 1 - 2/(L+1);
            sy = Y;
            sy.values = cellfun(@(x)smt(x, lambda), Y.values, "UniformOutput",false);

            function s = smt(x, w)
                s = x;
                for n = 2:numel(x)
                    s(n) = w*s(:,n-1,:) + (1-w)*x(:,n,:);
                end
            end
        end

        function sy = UWMA(Y, L)
            sy = Y;
            sy.values = cellfun(@(x)smoothdata(x, 2, "movmean", L, "omitmissing"), ...
                Y.values, "UniformOutput",false);
        end
    end
end

