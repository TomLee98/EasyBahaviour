classdef LittleObjectDetector
    %LITTLEOBJECTDETECTOR This class for little object detection based on 
    % frequency division feature extraction
    
    properties
        Property1
    end
    
    methods
        function obj = LittleObjectDetector(inputArg1,inputArg2)
            %OBJECTDETECTOR 构造此类的实例
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

