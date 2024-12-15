classdef Parameterizer
    %PARAMETERIZER This
    
    properties(Access = private)
        options
    end
    
    methods
        function this = Parameterizer(options_)
            arguments
                options_    (1,1)   struct  = struct("backbone_curvature",     {{@bc, {}}}, ...
                                                     "center_acceleration",    {{@ca, {}}}, ...
                                                     "center_position",        {{@cp, {}}}, ...
                                                     "center_velocity",        {{@cv, {}}}, ...
                                                     "head_direction",         {{@hd, {}}}, ...
                                                     "segment_acceleration",   {{@sa, {}}}, ...
                                                     "segment_velocity",       {{@sv, {}}}, ...
                                                     "tail_direction",         {{@td, {}}});
            end

            this.options = options_;
        end

        function delete(this)
            % ~
        end
    end

    methods (Access = public)
        function params = gather(this, frames, boxes, ops)
            % This function call operators for extract parameters(features)
            % from frames
            % Input:
            %   - frames:
            %   - ops:
            % Output:
            %   - params:

            arguments
                this    (1,1)
                frames  (:,2)   cell        % t-by-1 frames, local temporary frames, 
                                            % with [{image_1, timestamp_1};
                                            % ...
                                            % {image_n, timestamp_n}]
                boxes   (:,1)   cell        % t-by-1 boxes, boxes from tracker as 1-by-1 dictionary
                ops     (1,:)   string      = ["ba","cp","cv","hd"]
            end

            % calculate maximum possible set, others parameters could be nan
            params = struct();
            for k = 1:numel(ops)
                %% Calculate by operator
                oprfunc = str2func(ops(k));
                [frame, box] = Parameterizer.dataAdaptor(frames, boxes, ops(k));
                params.(ops(k)) = oprfunc(frame, box);
            end
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

        function [frame, boxes] = dataAdaptor(frame, boxes, op)
            arguments
                frame   (:,2)   cell
                boxes   (:,1)   cell
                op      (1,1)   string  {mustBeMember(op, ["bc","ca","cp","cv","hd","sa","sv","td"])} = "cp"
            end

            switch op
                case "bc"

                case "ca"

                case "cp"
                    frame = frame(end, :);
                    boxes  = boxes{end};
                case "cv"

                case "hd"

                case "sa"

                case "sv"

                case "td"

                otherwise
            end
        end
    end
end

