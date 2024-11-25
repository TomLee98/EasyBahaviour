classdef Tracker < handle
    %TRACKER This class implements a tracker, which could track little 
    % moving objects in a complex scene
    
    properties(Access = private)
        tracker_opts    (1,1)   struct                      % Track object options struct
        lod_obj         (1,1)   LittleObjectDetector        % LittleObjectDetector object handle
        mp_obj          (1,1)   MotionPredictor             % MotionPredictor object handle
        om_obj          (1,1)                               % ObjectMatcher object handle
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
            this.lod_obj.detect(frame{1});

            boxes = dictionary();
            gcs = dictionary();

            pause(0.5);
        end
    end
end

