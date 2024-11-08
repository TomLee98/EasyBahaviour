classdef EBPressureController < handle
    %PRESSURECONTROLLER 此处显示有关此类的摘要
    %   此处显示详细说明
    
    properties(Access = public, Dependent)
        IsConnected
    end
    
    methods
        function this = EBPressureController()
            %PRESSURECONTROLLER 构造此类的实例
        end

        function delete(this)
            % ~
        end

        function value = get.IsConnected(this)
            value = true;
        end
    end
end

