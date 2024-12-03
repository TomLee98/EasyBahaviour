classdef Parameterizer
    %PARAMETERIZER 此处显示有关此类的摘要
    %   此处显示详细说明
    
    properties(Access = private)
        options
    end
    
    methods
        function this = Parameterizer(options_)
            arguments
                options_    (1,1)   struct  = struct("backbone_curvature",     {{@bc, {}}}, ...
                                                     "center_acceleration",    {{@ca, {}}}, ...
                                                     "center_velocity",        {{@cv, {}}}, ...
                                                     "head_direction",         {{@hd, {}}}, ...
                                                     "segment_acceleration",   {{@sa, {}}}, ...
                                                     "segment_velocity",       {{@sv, {}}}, ...
                                                     "tail_direction",         {{@td, {}}});
            end

            this.options = options_;
        end

        function params = collect(frames, ops)
            % This function call operators for extract parameters(features)
            % from frames
            % Input:
            %   - frames:
            %   - ops:
            % Output:
            %   - params:

            arguments
                frames  (:,1)   cell        % t-by-1 frames, local temporary frames, 
                                            % with {{image_1, timestamp_1};
                                            % ...
                                            % {image_n, timestamp_n}}
                ops     (1,:)   string  {mustBeMember(ops, ["bc","ca","cv","hd","sa","sv","td"])} = ["ba","cv","hd"]
            end


        end

        function delete(this)
            % ~
        end
    end

    methods(Static)
        function gcs = GetGeometricCenters(image, boxes)
            arguments
                image   (:,:)
                boxes   (1,1)   dictionary
            end

            gcs = configureDictionary("string", "cell");

            % simple computation, omit image fine tuned object
            for key = boxes.keys("uniform")'
                bbox = boxes{key};
                xpos = bbox(1)+bbox(3)/2;
                ypos = bbox(2)+bbox(4)/2;
                gcs(key) = {[xpos, ypos]};
            end
        end

    end
end

