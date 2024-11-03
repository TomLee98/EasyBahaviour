classdef EBCamera < handle
    %CAMERA This class is camera defination for Easy Behaviour control
    %system, Which support basic camera settings and capturing images
    
    properties(SetAccess=immutable, GetAccess=public)
        % Adapter - Specifies the videoinput object hardware adapter
        % Read/Write Access - Read-only
        % Accepted Values - Member of ["winvideo", "kinect", "dalsasapera", 
        %                   "gige", "matrox", "dcam", "gentl", "pointgrey", 
        %                   "linuxvideo", "macvideo", "ni"]
        % Default - "gentl"
        Adapter

        % Identity - Specifies the device identity (device index)
        % Read/Write Access - Read-only
        % Accepted Values - Positive integer
        % Default - 1
        Identity

        % Format - Specifies the device pixel format
        % Read/Write Access - Read-only
        % Accepted Values - 1-by-1 string
        % Default - "Mono12"
        Format
    end

    properties(Access=private)
        viobj           % 1-by-1 videoinput object
        vsobj           % 1-by-1 videosource object
    end

    properties (Access=public)
        ROIAutoScale     (1,1)   logical  = true    % 1-by-1 logical, true as default
    end

    properties (Access=public, Dependent)
        BinningHorizontal       % set/get
        BinningVertical         % set/get
        BitDepth                % set/get
        ExposureTime            % set/get
        FrameRate               % set/get
        Gamma                   % set/get
        IsRunning               % ___/get
        IsConnected             % ___/get
        LineInverter            % set/get
        LineSource              % set/get
        MaxFrameRate            % ___/get
        OffsetX                 % set/get
        OffsetY                 % set/get
        ReadoutTime             % ___/get
        ROIWidth                % set/get
        ROIHeight               % set/get
        VideoResolution         % ___/get
    end

    methods
        function this = EBCamera(adapter_, identity_, format_)
            %EBCAMERA A constructor
            arguments
                adapter_     (1,1)   string  {mustBeMember(adapter_, ["winvideo", ...
                                            "kinect", "dalsasapera", "gige", ...
                                            "matrox", "dcam", "gentl", "pointgrey", ...
                                            "linuxvideo", "macvideo", "ni"])} = "gentl"
                identity_    (1,1)   double  {mustBePositive, mustBeInteger} = 1
                format_      (1,1)   string  = "Mono12"
            end
            
            this.Adapter = adapter_;
            this.Identity = identity_;
            this.Format = format_;
        end

        function value = get.IsConnected(this)
            value = (~isempty(this.viobj) && isvalid(this.viobj));
        end

        function value = get.VideoResolution(this)
            value = this.viobj.VideoResolution;
        end
        
        function set.BinningHorizontal(this, value)
            arguments
                this
                value   (1,1)   {mustBeInRange(value, 1, 4), mustBeInteger} = 1
            end

            if this.IsConnected
                if isrunning(this.viobj)
                    throw(MException("EBCamera:invalidAccess", "Running camera " + ...
                        "binning is unsetable."));
                else
                    pre_value = this.vsobj.BinningHorizontal;
                    this.vsobj.BinningHorizontal = value;

                    if this.ROIAutoScale == true
                        this.OffsetX = round(this.OffsetX * pre_value/value);
                        this.ROIWidth = round(this.ROIWidth * pre_value/value);
                    else
                        if this.OffsetX + this.ROIWidth > this.VideoResolution(1)
                            % reset ROI area on X
                            this.OffsetX = 0;
                            this.ROIWidth = this.VideoResolution(1);
                        end
                    end
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        function set.BinningVertical(this, value)
            arguments
                this
                value   (1,1)   {mustBeInRange(value, 1, 4), mustBeInteger} = 1
            end

            if this.IsConnected
                if isrunning(this.viobj)
                    throw(MException("EBCamera:invalidAccess", "Running camera " + ...
                        "binning is unsetable."));
                else
                    pre_value = this.vsobj.BinningVertical;
                    this.vsobj.BinningVertical = value;

                    if this.ROIAutoScale == true
                        this.OffsetY = round(this.OffsetY * pre_value/value);
                        this.ROIHeight = round(this.ROIHeight * pre_value/value);
                    else
                        if this.OffsetY + this.ROIHeight > this.VideoResolution(2)
                            % reset ROI area on Y
                            this.OffsetY = 0;
                            this.ROIHeight = this.VideoResolution(2);
                        end
                    end
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

    end

    methods (Access = public)
        function Connect(this)
            try
                this.viobj = videoinput(this.Adapter, ...
                                        this.Identity, ...
                                        this.Format);
                this.vsobj = getselectedsource(this.viobj);
            catch ME
                throw(ME);
            end
        end
    end

    methods (Static)
        function DisableWarnings(state)
            arguments
                state    (1,1)   string  {mustBeMember(state, ["on","off"])} = "off"
            end

            warning(state, '')
        end
    end
end

