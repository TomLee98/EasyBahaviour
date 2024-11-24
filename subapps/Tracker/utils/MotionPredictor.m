classdef MotionPredictor < handle
    %MOTIONPREDICTOR This class uses Kalman filter to predict objects motion
    % in current frame by previous frame
    % if there are no enough frames, predictor use naive prediction: assume
    % that no error in observation, motion is determined by movement-equation

    properties (Constant, Hidden)
        SYSTEM_DIMENSION = 8        % simplify marked as D
    end

    properties (Access=public, Dependent)
        AutoKF              % ___/get, 1-by-1 logical, true for running KF autometically
        KFStatus            % ___/get, 1-by-1 string, in ["await", "ready"]
        KFWindowSize        % ___/get, 1-by-1 positive integer, indicate Kalman Filter Initialized Window Size
        SmoothWindowSize    % set/get, 1-by-1 positive integer, indicate smoothing window size
    end
    
    properties(SetAccess = immutable, GetAccess = private)
        autokf  (1,1)   logical     % auto loading KF if condition satisfied
        kf_win  (1,1)   double      % indicate the lookback window size for Kalman Filter Q,R estimation
    end

    properties(Access = private)
        M       (1,1)   dictionary  % <string> -> <cell>, observed history, cell with D-by-T double matrix, dict with S samples
        P       (1,1)   dictionary  % <string> -> <cell>, posterior error, cell with D-by-D double matrix, dict with S samples
        Q       (1,1)   dictionary  % <string> -> <cell>, system noise covarance, cell with D-by-D double matrix, dict with S samples
        R       (1,1)   dictionary  % <string> -> <cell>, observation covariance, cell with D-by-D double matrix, dict with S samples
        sa      (1,1)   string      % smoothing algorithm, in ["EWMA", "UWMA"]
        sw      (1,1)   double      % smoothing window size
        X       (1,1)   dictionary  % <string> -> <cell>, filtered system state, cell with D-by-1 double vector, dict with S samples
    end
    
    methods
        function this = MotionPredictor(N_, AutoKF_)
            %MOTIONPREDICTOR A Constructor
            arguments
                N_      (1,1)   double  {mustBePositive, mustBeInteger} = 15
                AutoKF_ (1,1)   logical = true
            end

            this.kf_win = N_;
            this.autokf = AutoKF_;
            this.sa = "EWMA";
            this.sw = ceil(N_/3);

            % iteration variables
            this.M = dictionary();
            this.Q = dictionary();
            this.R = dictionary();
            this.X = dictionary();
            this.P = dictionary();
        end

        %% AutoKF Getter
        function value = get.AutoKF(this)
            value = this.autokf;
        end

        %% KFWindowSize Getter
        function value = get.KFWindowSize(this)
            value = this.kf_win;
        end

        %% KFStatus Getter
        function value = get.KFStatus(this)
            if this.M.isConfigured
                value = "ready";
                kys = this.M.keys("uniform");
                for ky = this.M.keys("uniform")'
                    if size(this.M{kys(1)}, 2) < this.kf_win
                        value = "await";    % enough history size
                        return;
                    end
                end
            else
                value = "await";
            end
        end

        %% SmoothWindowSize Getter & Setter
        function value = get.SmoothWindowSize(this)
            value = this.sw;
        end

        function set.SmoothWindowSize(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive, mustBeInteger}
            end

            if value > this.kf_win
                warning("MotionPredictor:badSmoothingWindowSize", ...
                    "Window size has been modified by predictor automatically.");
            end

            this.sw = min(this.kf_win, value);
        end
    end

    methods(Access = public)
        function X = Predict(this, A, Y, F)
            % This function use observed data Y and history to estimate 
            % current system status
            % Input:
            %   - this:
            %   - A:
            %   - Y:
            %   - F:
            % Output:
            %   - X: 
            arguments
                this
                A       (:,:)   double
                Y       (1,1)   dictionary
                F       (1,1)   string  {mustBeMember(F,["Kalman", "Naive"])} = "Naive"
            end

            %% Output Prediction by Selected Predictor
            % [1] if select naive, naive predictor given next state estimation,
            % current observation put into KF history, 'add' or 'remove' to
            % keep the object identities consistant outer
            % [2] if select kalman, use Y update observed history M, estimation
            % X, and estimate Q and R

            if ~isempty(setdiff(Y.keys("uniform"), X_.keys("uniform")))
                throw(MException("MotionPredictor:invalidSample", ...
                    "Samples number is not consistant."));
            else
                if this.autokf
                    if isequal("ready", this.KFStatus)
                        F = "Kalman";           % change to Kalman algorithm
                    else
                        F = "Naive";
                    end
                end

                switch F
                    case "Naive"
                        % just use transformation matrix
                        for ky = Y.keys("uniform")'
                            this.X{ky} = A*Y{ky};
                            if size(this.M{ky}, 2) == this.kf_win
                                this.M{ky}(:,1)=[];
                            end
                            this.M{ky} = [this.M{ky}, Y{ky}];
                        end
                    case "Kalman"
                        % call Kalman filter on samples
                        for ky = Y.keys("uniform")'
                            [this.X{ky}, this.P{ky}] = OneStepKalmanFilter(A, ...
                                this.Q{ky}, this.R{ky}, Y{ky}, this.X{ky}, this.P{ky});
                        end

                        % update Q and R dynamically
                        this.updateQR(Y);
                    otherwise
                        throw(MException("MotionPredictor:invalidPredictor", ...
                            "Unsupported predictor."));
                end

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

