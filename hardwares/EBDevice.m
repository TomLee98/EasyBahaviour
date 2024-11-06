classdef (Abstract) EBDevice
    %EBPLUS 此处显示有关此类的摘要
    %   此处显示详细说明
    
    properties (Abstract, Access=public, Dependent)
        IsConnected
        IsRunning
    end
    
    methods(Abstract)
        function this = EBDevice(inputArg1,inputArg2)
            %EBPLUS 构造此类的实例
            %   此处显示详细说明
            this.Property1 = inputArg1 + inputArg2;
        end

        function Connect(this)

        end

        function Disconnect(this)
            
        end
    end
end

