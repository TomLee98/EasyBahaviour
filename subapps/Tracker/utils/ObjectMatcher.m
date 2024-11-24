classdef ObjectMatcher
    %OBJECTMATCHER This class uses Hungarian algorithm to solve the object
    % matching problem
    % We have Predictor given current frame objects position prediction 
    % and Detector given the current observation
    
    properties
        Property1
    end
    
    methods
        function obj = ObjectMatcher(inputArg1,inputArg2)
            %OBJECTMATCHER 构造此类的实例
            %   此处显示详细说明
            obj.Property1 = inputArg1 + inputArg2;
        end
        
        function outputArg = method1(obj,inputArg)
            %METHOD1 此处显示有关此方法的摘要
            %   此处显示详细说明
            outputArg = obj.Property1 + inputArg;
        end
    end
end

