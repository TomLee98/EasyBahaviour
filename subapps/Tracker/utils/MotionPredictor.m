classdef MotionPredictor < handle
    %MOTIONPREDICTOR This class uses Kalman filter to predict objects motion
    % in current frame by previous frame
    % if there are no enough frames, predictor use naive prediction: assume
    % that no error in observation, motion is determined by movement-equation

    properties (Access=public, Dependent)
        KFStatus            % ___/get, 1-by-1 string, in ["off","on","ready"]
        AutoKF              % set/get, 1-by-1 logical, true for running KF autometically
        KFWindowSize        % set/get, 1-by-1 positive integer, indicate Kalman Filter Initialized Window Size
    end
    
    properties(Access = private)
        autokf  (1,1)   logical     % auto loading KF if condition satisfied
        M       (1,1)   dictionary  % <string> -> <cell>, observed history, cell with N-by-T double matrix, dict with S samples
        P       (1,1)   dictionary  % <string> -> <cell>, posterior error, cell with N-by-N double matrix, dict with S samples
        Q       (1,1)   dictionary  % <string> -> <cell>, system noise covarance, cell with N-by-N double matrix, dict with S samples
        R       (1,1)   dictionary  % <string> -> <cell>, observation covariance, cell with N-by-N double matrix, dict with S samples
        sa      (1,1)   string      % smoothing algorithm, in ["EWMA", "UWMA"]
        sw      (1,1)   double      % smoothing window size
        X       (1,1)   dictionary  % <string> -> <cell>, filtered system state, cell with N-by-1 double vector, dict with S samples
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

            this.M = dictionary();
            this.Q = Q_;
            this.R = R_;
            this.X = dictionary();
            this.P = dictionary();

            % init
            this.sa = "EWMA";
            this.sw = 5;
        end

        function X = Predict(this, A, Y, F)
            % This function use observed data Y and history to estimate 
            % current system status
            arguments
                this
                A       (:,:)   double
                Y       (1,1)   dictionary
                F       (1,1)   string  {mustBeMember(F,["Kalman", "Naive"])} = "Naive"
            end

            %% Output Prediction by Selected Predictor
            

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
                this.updateQR(Y);

                X = this.X;
            end
        end

        function RemoveSamples(this, keys)
            arguments
                this
                keys     (:,1)   string
            end

            % remove all data corresponds to key
            for ky = keys'
                if this.X.isKey(ky)
                    this.Q(ky) = [];
                    this.R(ky) = [];
                    this.X(ky) = [];
                    this.P(ky) = [];
                    this.M(ky) = [];
                else
                    warning("MotionPredictor:invalidKey", ...
                        "No such a key [%s] in predictor.", ky);
                end
            end

        end

        function AppendSample(this, Y)
            arguments
                this
                Y       (1,1)   dictionary
            end

            % validate at first
            MotionPredictor.validatedata(Y, this.sw);

            % append new sample by given data Y
            for ky = Y.keys("uniform")'
                if this.X.isKey(ky)
                    warning("MotionPredictor:invalidKey", ...
                        "There exist a same key [%s] in predictor.", ky);
                else
                    % append M, Q, R
                    this.appendQR(ky, Y{ky});

                    % append X, P
                    this.appendXP(ky, Y{ky});
                end
            end
        end
    end

    methods(Access = private)

        function initKalmanFilter(this, Y, Sa, Sw)
            %INITKALMANFILTER This function initializes Kalman filter
            % parameters X0, P0
            arguments
                this
                Y       (1,1)   dictionary
                Sa      (1,1)   string  {mustBeMember(Sa, ["EWMA", "UWMA"])} = "EWMA"
                Sw      (1,1)   double  {mustBePositive} = 5
            end

            % validate input data
            MotionPredictor.validatedata(Y, Sw);

            % init basic parameters
            this.updateSmoothParameters(Sa, Sw);
            
            % use smooth algorithm for rough estimation
            this.updateQR(Y);

            % initialize X0 and P0
            this.updateXP(Y);
        end

        function updateQR(this, Y)
            % use Y update M
            if ~this.M.isConfigured
                this.M = Y;
            else
                % append history
                for ky = this.M.keys("uniform")'
                    this.M{ky}(:,1) = [];               % remove oldest record
                    this.M{ky} = [this.M{ky}, Y{ky}];   % append new record
                end
            end

            % use smooth algorithm for rough estimation
            switch this.sa
                case "EWMA"
                    smy = MotionPredictor.EWMA(this.M, this.sw, "all");
                case "UWMA"
                    smy = MotionPredictor.UWMA(this.M, this.sw, "all");
                otherwise
            end

            % estimate Q and R one by one
            for ky = this.M.keys("uniform")'
                this.Q{ky} = cov(smy{ky}');
                this.R{ky} = cov((this.M{ky}-smy{ky})');
            end
        end

        function updateSmoothParameters(this, Sa, Sw)
            this.sa= Sa;
            this.sw = Sw;
        end

        function appendQR(this, key, value)
             % use key-value pair update M
             % note that key is string, value is N-by-T double matrix
             this.M(key) = {value};

             % use smooth algorithm for rough estimation
             switch this.sa
                 case "EWMA"
                     smy = MotionPredictor.EWMA(this.M, this.sw, key);
                 case "UWMA"
                     smy = MotionPredictor.UWMA(this.M, this.sw, key);
                 otherwise
             end

             % estimate Q and R then append
             this.Q(ky) = {cov(smy{ky}')};
             this.R(ky) = {cov((this.M{ky}-smy{ky})')};
        end

        function updateXP(this, Y)
            kys = Y.keys("uniform");
            this.X(kys) = cellfun(@(x)mean(x,2), Y.values, "UniformOutput",false);
            this.P(kys) = cellfun(@(x)cov(x'), Y.values, "UniformOutput",false);
        end

        function appendXP(this, key, value)
            this.X(key) = {mean(value, 2)};
            this.P(key) = {cov(value')};
        end
    end

    methods(Static)
        function sy = EWMA(Y, L, key)
            lambda = 1 - 2/(L+1);

            if isequal(key, "all")
                sy = Y;
                sy.values = cellfun(@(x)smt(x, lambda), Y.values, "UniformOutput",false);
            elseif Y.isKey(key)
                sy = dictionary(key, {smt(Y{key}, lambda)});
            else
                throw(MException("MotionPredictor:invalidKey", ...
                    "No such a key exist."));
            end

            function s = smt(x, w)
                s = x;
                for n = 2:numel(x)
                    s(n) = w*s(:,n-1,:) + (1-w)*x(:,n,:);
                end
            end
        end

        function sy = UWMA(Y, L, key)
            if isequal(key, "all")
                sy = Y;
                sy.values = cellfun(@(x)smoothdata(x, 2, "movmean", L, "omitmissing"), ...
                    Y.values, "UniformOutput",false);
            elseif Y.isKey(key)
                sy = dictionary(key, {smoothdata(Y{key}, 2, "movmean", L, "omitmissing")});
            else
                throw(MException("MotionPredictor:invalidKey", ...
                    "No such a key exist."));
            end
            
        end

        function validatedata(Y, Sw)
            arguments
                Y   (1,1)   dictionary
                Sw  (1,1)   double      = 5
            end

            if ~Y.isConfigured
                throw(MException("MotionPredictor:invalidSample", ...
                        "Data Y has not been configured."));
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
        end
    end
end

