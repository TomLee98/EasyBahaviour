classdef EBScreenLayout
    %EBSCREEN This is enumeric class to define screen
    
    properties (SetAccess = immutable, GetAccess=public, Hidden)
        Value
    end
    
    methods
        function this = EBScreenLayout(val)
            % A Constructor
            this.Value = val;
        end
    end

    enumeration
        INIT_SCREEN_SIZE    ([512, 272]) % initialized [width, height]
        TIMESTAMP_OFFSET_X  (10)         % relative to left border
        TIMESTAMP_OFFSET_Y  (10)         % relative to top border
        SCALE_OFFSET_X      (10)         % relative to left border
        SCALE_OFFSET_Y      (20)         % relative to bottom border
        SPEED_OFFSET_X      (10)         % relative to right border
        SPEED_OFFSET_Y      (10)         % relative to top border
        METADATA_OFFSET_X   (10)         % relative to right border
        METADATA_OFFSET_Y   (10)         % relative to bottom border
    end
end

