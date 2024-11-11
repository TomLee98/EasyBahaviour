classdef VideoFrame
    %VIDEOFRAME This is video frame object, with 
    


    properties(Access = private)
        time_stamp
        scale
        meta_data
        detect_box
        
    end
    
    methods
        function obj = VideoFrame(inputArg1,inputArg2)
            %VIDEOFRAME 构造此类的实例
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

