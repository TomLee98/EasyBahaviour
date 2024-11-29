classdef Tracker < handle
    %TRACKER This class implements a tracker, which could track little 
    % moving objects in a complex scene
    
    properties(Access = private)
        tracker_opts    (1,1)   struct                  % Track object options struct
        hLOD            (1,1)   LittleObjectDetector    % LittleObjectDetector object handle
        hMP             (1,1)   MotionPredictor         % MotionPredictor object handle
        hOM             (1,1)   ObjectMatcher           % ObjectMatcher object handle
        obj_pprev       (1,1)   dictionary              % pre-previous observed objects
        timestamps      (1,2)   double                  % previous time stamps, for calculating v, unit as seconds
    end
    
    methods
        function this = Tracker(options_)
            arguments
                options_    (1,1)   struct  = struct("feature",      ["SURF","HOG"], ...
                                                     "mix_model",    "augment", ...
                                                     "sampling",     10, ...
                                                     "classifter",   "SVM", ...
                                                     "predictor",    "KF", ...
                                                     "matcher",      "KM");
            end

            this.tracker_opts = options_;

            this.timestamps = [0, 0];
        end

        function delete(this)
            % ~
        end
    end

    methods(Access = public)
        function [boxes, gcs] = Track(this, frame)
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
            obj_observed = this.hLOD.detect(frame{1});

            %% Predict current objects location by previous observed
            dt = [this.timestamps, t_cur];
            % update time stamps
            this.timestamps(1) = this.timestamps(2);
            this.timestamps(2) = t_cur;
            % generate variables for prediction
            % update objects observed format
            [A, Y, obj_observed] = Tracker.GeneratePredictedVars(this.obj_pprev, obj_observed, dt);
            obj_predicted = this.hMP.predict(A, Y);

            %% Match observed and predicted
            obj_predicted = Tracker.ExtractLocationsIn(obj_predicted);
            obj_observed = Tracker.ExtractLocationsIn(obj_observed);
            % match
            [matched, new, lost, cost] = this.hOM.match(obj_predicted, obj_observed);

            boxes = dictionary();
            gcs = dictionary();

            pause(0.5);
        end
    end

    methods(Static)
        function [A, Y, obj_cur] = GeneratePredictedVars(obj_pprev, obj_cur, dt)
            arguments
                obj_pprev   (1,1)   dictionary      % id -> [x,y,w,h,vx,vy,vw,vh]'
                obj_cur     (1,1)   dictionary      % id -> {[x,y,w,h], posterior}
                dt          (1,3)   double      {mustBePositive}
            end

            % output the most possible larva object by posterior

        end

        function r = ExtractLocationsIn(obj)
            arguments
                obj     (1,1)   dictionary
            end


        end
    end
end

