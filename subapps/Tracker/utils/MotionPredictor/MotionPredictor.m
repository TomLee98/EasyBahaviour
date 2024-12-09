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
        KFPredictedObjects  % ___/get, n-by-1 string vector, identity of objects predicted by KF
        KFWindowSize        % ___/get, 1-by-1 positive integer, indicate Kalman Filter Initialized Window Size
        Objects             % ___/get, m-by-1 string vector, identity of total objects
        SmoothMethod        % set/get, 1-by-1 string, could be ["EWMA", "UWMA"]
        SmoothWindowSize    % set/get, 1-by-1 positive integer, indicate smoothing window size
    end
    
    properties(SetAccess = immutable, GetAccess = private)
        kf_enable   (1,1)   logical     % auto loading KF if condition satisfied
        kf_win      (1,1)   double      % indicate the lookback window size for Kalman Filter Q,R estimation
    end

    properties(Access = private)
        isInit  (1,1)   dictionary  % <string> -> <logical>, mark if the object could use Kalman
        KFs     (1,1)   dictionary  % <string> -> <cell>, trackingKF objects, cell with 2-by-1 trackingKF objects, track (x,y) and (w,h) use "constant acceleration" model
        M       (1,1)   dictionary  % <string> -> <cell>, observed history, cell with D-by-T double matrix, dict with S samples
        P       (1,1)   dictionary  % <string> -> <cell>, posterior error, cell with D-by-D double matrix, dict with S samples
        Q       (1,1)   dictionary  % <string> -> <cell>, system noise covarance, cell with D-by-D double matrix, dict with S samples
        R       (1,1)   dictionary  % <string> -> <cell>, observation covariance, cell with D-by-D double matrix, dict with S samples
        sa      (1,1)   string      % smoothing algorithm, in ["EWMA", "UWMA"]
        sw      (1,1)   double      % smoothing window size
        X       (1,1)   dictionary  % <string> -> <cell>, filtered system state, cell with D-by-1 double vector, dict with S samples
    end
    
    methods
        function this = MotionPredictor(N_, EnableKF_)
            %MOTIONPREDICTOR A Constructor
            arguments
                N_          (1,1)   double  {mustBePositive, mustBeInteger} = 15
                EnableKF_   (1,1)   logical = true
            end

            this.kf_win = N_;
            this.kf_enable = EnableKF_;
            this.sa = "UWMA";
            this.sw = ceil(N_/3);

            % iteration variables
            this.isInit = configureDictionary("string", "logical");
            this.M = configureDictionary("string", "cell");
            this.Q = configureDictionary("string", "cell");
            this.R = configureDictionary("string", "cell");
            this.X = configureDictionary("string", "cell");
            this.P = configureDictionary("string", "cell");
            this.KFs = configureDictionary("string", "cell");
        end

        %% AutoKF Getter
        function value = get.AutoKF(this)
            value = this.kf_enable;
        end

        %% KFPredictedObjects Getter
        function value = get.KFPredictedObjects(this)
            if (this.kf_enable == false) ...
                    || ~this.isInit.isConfigured
                value = strings().empty(0,1);
            else
                value = this.isInit.keys("uniform");
                value = value(this.isInit.values);
            end
        end

        %% KFWindowSize Getter
        function value = get.KFWindowSize(this)
            value = this.kf_win;
        end

        %% Objects Getter
        function value = get.Objects(this)
            value = this.isInit.keys("uniform");
        end

        %% SmoothMethod Getter & Setter
        function value = get.SmoothMethod(this)
            value = this.sa;
        end

        function set.SmoothMethod(this, value)
            arguments
                this
                value   (1,1)   string  {mustBeMember(value, ["EWMA", "UWMA"])}
            end

            this.sa = value;
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
        function X = predict(this, A, Y, Mode)
            % This function use observed data Y and history to estimate 
            % current system status
            % Input:
            %   - this:
            %   - A: n-by-n transformation matrix
            %   - Y: 1-by-1 dictionary, identity(string) -> box
            %       feature(n-by-1 vector), current observation
            % Output:
            %   - X: 1-by-1 dictionary, identity(string) -> box 
            %       feature(n-by-1 vector), predicted current location
            arguments
                this
                A       (:,:)   double
                Y       (1,1)   dictionary
                Mode    (1,1)   string      {mustBeMember(Mode, ["append", "drop"])} = "append"
            end

            %% Output Prediction by Selected Predictor
            % [1] if Kalman filter enabled, update history length
            % automatically, before history is enough, naive predictor only
            % [2] if Kalman filter disabled, naive predictor only

            if this.kf_enable == true
                % enable Kalman filter if history is enough, or use
                % naive predictor only
                for key = Y.keys("uniform")'
                    if this.isInit.isKey(key)
                        if this.isInit(key) == true
                            %% run with Kalman Filter

                            if Mode == "append"
                                % update history, push and pop
                                this.M{key} = [this.M{key}, Y{key}];
                                this.M{key}(:,1) = [];
                            end

                            % update X, P
                            [this.X{key}, this.P{key}] = OneStepKalmanFilter(A, ...
                                this.Q{key}, this.R{key}, Y{key}, this.X{key}, this.P{key});

                            % update Q, R by M
                            this.updateQR(key);
                        else
                            %% update kalman running status automatically

                            if Mode == "append"
                                % update history, push only
                                this.M{key} = [this.M{key}, Y{key}];
                            end

                            % update kalman initial status if possible
                            if size(this.M{key}, 2) == this.kf_win
                                % initialize kalman filter X, P
                                this.initXP(key);

                                % initialize Q and R
                                this.updateQR(key);

                                % modify flag
                                this.isInit(key) = true;
                            else
                                % control equation only
                                this.X{key} = A*Y{key};
                            end
                        end
                    else
                        if Mode == "append"
                            % append new record
                            this.isInit(key) = false;
                            this.M{key} = Y{key};
                        end
                        this.X{key} = Y{key};     % no prediction, just current observation
                    end
                end

                X = this.X;
            else
                X = dictionary();

                for key = Y.keys("uniform")'
                    % use naive predictor only
                    X{key} = A*Y{key};
                end
            end
        end

        function remove(this, keys)
            arguments
                this
                keys     (:,1)   string
            end

            % remove all data corresponds to key
            for key = keys'
                if this.isInit.isKey(key)
                    this.isInit(key) = [];
                    this.Q(key) = [];
                    this.R(key) = [];
                    this.X(key) = [];
                    this.P(key) = [];
                    this.M(key) = [];
                else
                    warning("MotionPredictor:invalidKey", ...
                        "No such a key [%s] in predictor.", key);
                end
            end

        end
    end

    methods(Access = private)

        function updateQR(this, key)
            data = this.M{key};

            % use smooth algorithm for rough estimation
             switch this.sa
                 case "EWMA"
                     smy = MotionPredictor.EWMA(data, this.sw);
                 case "UWMA"
                     smy = MotionPredictor.UWMA(data, this.sw);
                 otherwise
             end

             % estimate Q and R then append
             this.Q(key) = {cov(smy')};
             this.R(key) = {cov((data-smy)')};
        end

        function initXP(this, key)
            this.X(key) = {mean(this.M{key}, 2)};
            this.P(key) = {cov(this.M{key}')};
        end
    end

    methods(Static)
        function Y = EWMA(Y, L)
            lambda = 1 - 2/(L+1);

            for n = 2:size(Y,2)
                Y(:,n) = lambda*Y(:,n-1) + (1-lambda)*Y(:,n);
            end
        end

        function Y = UWMA(Y, L)
            Y = smoothdata(Y, 2, "movmean", L, "omitmissing");
        end
    end
end

