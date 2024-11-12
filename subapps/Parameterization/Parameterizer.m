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

        function delete(this)
            % ~
        end
    end
end

