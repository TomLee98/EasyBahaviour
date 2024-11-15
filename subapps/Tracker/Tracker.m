classdef Tracker
    %TRACKER 此处显示有关此类的摘要
    %   此处显示详细说明
    
    properties(Access = private)
        options
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

            this.options = options_;
        end

        function delete(this)
            % ~
        end
    end

    methods(Access = public)
        function [boxes, gcs] = Track(this, prevprevboxes, prevboxes, frame)
            arguments
                this
                prevprevboxes   (:, 6)   double
                prevboxes       (:, 6)   double
                frame           (1, 2)   cell
            end

            boxes = double.empty(0, 6);
            gcs = double.empty(0, 3);

            pause(0.5);
        end
    end
end

