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
        viobj       (:,1)                                = []   % 1-by-1 videoinput object
        vsobj       (:,1)                                = []   % 1-by-1 videosource object
        fr_target   (1,1)   double      {mustBePositive} = 25   % 1-by-1 target frame rate, Hz
        cap_agent   (1,1)   timer                               % 1-by-1 timer object
        abs_start_t (1,1)   uint64                              % 1-by-1 absolute acquire time, given by tic
    end

    properties (Access=public)
        ROIAutoScale    (1,1)   logical  = true    % 1-by-1 logical, true as default
    end

    properties (SetAccess=private, GetAccess=public)
        VideoBuffer     (1,1)   Video   % handle, not deep copy
    end

    properties (Access=public, Dependent)
        AcquireFrameRate        % set/get, 1-by-1 double positive, in [1, 100], 25 as default
        BinningHorizontal       % set/get, 1-by-1 double positive integer in [1,2,3,4]
        BinningVertical         % set/get, 1-by-1 double positive integer in [1,2,3,4]
        BitDepth                % ___/get, 1-by-1 double positive integer in [8,12]
        DeviceModelName         % ___/get, 1-by-1 string
        ExposureTime            % set/get, 1-ny-1 double positive integer in [100, 1000000], unit as us
        Gamma                   % set/get, 1-by-1 double positive in (0, 4)
        IsConnected             % ___/get, 1-by-1 logical, false as default
        IsLiving                % ___/get, 1-by-1 logical, indicate camera living status
        IsRunning               % ___/get, 1-by-1 logical, false as default
        LineInverter            % set/get, 1-by-1 logical, true as default
        LineMode                % ___/get, 1-by-1 string, in ["input", "output"]
        LineSelector            % set/get, 1-by-1 string, in ["Line1", ..., "Line4"], "Line2" as default
        LineSource              % set/get, 1-by-1 string, in ["Exposure Active", "Frame Trigger Wait", "Frame Burst Trigger Wait"]
        MaxAcquireFrameRate     % ___/get, 1-by-1 double positive
        MaxFrameRate            % ___/get, 1-by-1 double positive
        OffsetX                 % set/get, 1-by-1 double nonnegtive integer
        OffsetY                 % set/get, 1-by-1 double nonnegtive integer
        ReadoutTime             % ___/get, 1-by-1 double positive integer
        ROIWidth                % set/get, 1-by-1 double positive integer
        ROIHeight               % set/get, 1-by-1 double positive integer
        VideoResolution         % ___/get, 1-by-2 double positive integer
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
            
            % set immutable variables
            this.Adapter = adapter_;
            this.Identity = identity_;
            this.Format = format_;

            % initialize video buffer
            this.VideoBuffer = Video.empty();

            % initialize capture agent
            this.cap_agent = timer("Name",          "EBCamera_Agent", ...
                                   "BusyMode",      "drop", ...
                                   "ExecutionMode", "fixedRate", ...
                                   "Period",        1/25,  ...          modified
                                   "TasksToExecute",inf, ...            modified
                                   "StartFcn",      @this.capture_begin, ...
                                   "StopFcn",       @this.capture_end, ...
                                   "TimerFcn",      @this.capture_one_frame);

            % disable raw devices warning
            EBCamera.ManageWarnings("off");
        end

        function delete(this)
            % remove capture agent timer
            if this.IsConnected
                % if running, stop
                if this.IsRunning, stop(this.cap_agent); end

                % disconnect camera
                this.Disconnect();
            end
            delete(this.cap_agent);

            % clear buffer
            delete(this.VideoBuffer);

            EBCamera.ManageWarnings("on");

            % free memory
            clear("this");
        end

        %% AcquireFrameRate Getter & Setter
        function value = get.AcquireFrameRate(this)
            if this.IsConnected
                if ~this.IsRunning
                    throw(MException("EBCamera:invalidAccess", "Camera is not acquiring, " + ...
                        "current frame rate is ungetable."))
                else
                    if this.VideoBuffer.IsEmpty
                        % there is no frame in the queue
                        value = 1/this.fr_target;     % replace by target frame rate
                    elseif this.VideoBuffer.Size == 1
                        frame = this.VideoBuffer.GetLastFrame();    % {image, time}
                        value = 1/frame{2};
                    else
                        n = this.VideoBuffer.Size;
                        frame_last = this.VideoBuffer.GetFrame(n);
                        frame_prev = this.VideoBuffer.GetFrame(n-1);
                        value = 1/(frame_last{2} - frame_prev{2});
                    end
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        function set.AcquireFrameRate(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive, mustBeInRange(value, 1, 100)}
            end
            if this.IsConnected
                if this.IsRunning
                    throw(MException("EBCamera:invalidAccess", "Running camera " + ...
                        "frame rate is unsetable."))
                else
                    this.fr_target = value;
                    this.cap_agent.Period = 1/value;    % unit as seconds
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% BinningHorizontal Getter & Setter
        function value = get.BinningHorizontal(this)
            if this.IsConnected
                value = this.vsobj.BinningHorizontal;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end
        
        function set.BinningHorizontal(this, value)
            arguments
                this
                value   (1,1)   {mustBeInRange(value, 1, 4), mustBeInteger}
            end

            if this.IsConnected
                if isrunning(this.viobj)|| this.IsLiving
                    throw(MException("EBCamera:invalidAccess", "Running camera " + ...
                        "binning is unsetable."));
                else
                    pre_value = this.vsobj.BinningHorizontal;
                    this.vsobj.BinningHorizontal = value;

                    if this.ROIAutoScale == true
                        this.OffsetX = round(this.OffsetX * pre_value/value);
                        this.ROIWidth = round(this.ROIWidth * pre_value/value - 1);
                    else
                        rpos = this.VideoResolution;
                        if this.OffsetX + this.ROIWidth > rpos(3)
                            % reset ROI area on X
                            this.OffsetX = 0;
                            this.ROIWidth = rpos(3);
                        end
                    end
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% BinningVertical Getter & Setter
        function value = get.BinningVertical(this)
            if this.IsConnected
                value = this.vsobj.BinningVertical;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.BinningVertical(this, value)
            arguments
                this
                value   (1,1)   {mustBeInRange(value, 1, 4), mustBeInteger}
            end

            if this.IsConnected
                if isrunning(this.viobj) || this.IsLiving
                    throw(MException("EBCamera:invalidAccess", "Running camera " + ...
                        "binning is unsetable."));
                else
                    pre_value = this.vsobj.BinningVertical;
                    this.vsobj.BinningVertical = value;

                    if this.ROIAutoScale == true
                        this.OffsetY = round(this.OffsetY * pre_value/value);
                        this.ROIHeight = round(this.ROIHeight * pre_value/value);
                    else
                        rpos = this.VideoResolution;
                        if this.OffsetY + this.ROIHeight > rpos(4)
                            % reset ROI area on Y
                            this.OffsetY = 0;
                            this.ROIHeight = rpos(4);
                        end
                    end
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% BitDepth Getter
        function value = get.BitDepth(this)
            switch this.Adapter
                case "gentl"
                    switch this.Format
                        case "Mono8"
                            value = 8;
                        case "Mono12"
                            value = 12;
                        otherwise
                            throw(MException("EBCamera:invalidFormat", ...
                                "Only 'Mono8' and 'Mono12' are supported."));
                    end
                case "winvideo"
                    value = 8;  % test
                otherwise
                    %
                    value = 8;
            end
        end

        %% DeviceName Getter
        function value = get.DeviceModelName(this)
            if this.IsConnected
                value = this.vsobj.DeviceModelName;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        %% ExposureTime Getter & Setter
        function value = get.ExposureTime(this)
            if this.IsConnected
                value = this.vsobj.ExposureTime;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.ExposureTime(this, value)
            arguments
                this
                value   (1,1)   double  {mustBeInteger, mustBeInRange(value, 100, 1000000)}
            end

            if this.IsConnected
                this.vsobj.ExposureTime = value;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% Gamma Getter && Setter
        function value = get.Gamma(this)
            if this.IsConnected
                value = this.vsobj.Gamma;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.Gamma(this, value)
            arguments
                this
                value   (1,1)   double  {mustBeInRange(value, 0, 4)}
            end

            if this.IsConnected
                this.vsobj.Gamma = value;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% IsConnected Getter
        function value = get.IsConnected(this)
            value = (~isempty(this.viobj) && isvalid(this.viobj));
        end

        %% IsLiving Getter
        function value = get.IsLiving(this)
            if this.IsConnected
                value = isequal(this.viobj.Previewing, "on");
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get status."));
            end
        end

        %% IsRunning Getter
        function value = get.IsRunning(this)
            if this.IsConnected
                % mark the agent running status
                value = isequal(this.cap_agent.Running, "on");
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get status."));
            end
        end

        %% LineInverter Getter & Setter
        function value = get.LineInverter(this)
            if this.IsConnected
                value = isequal(this.vsobj.LineInverter, "True");
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.LineInverter(this, value)
            arguments
                this
                value   (1,1)   logical
            end

            if this.IsConnected
                if value
                    this.vsobj.LineInverter = "True";
                else
                    this.vsobj.LineInverter = "False";
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% LineMode Getter
        function value = get.LineMode(this)
            if this.IsConnected
                value = this.vsobj.LineMode;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        %% LineSelector Getter
        function value = get.LineSelector(this)
            if this.IsConnected
                value = this.vsobj.LineSelector;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.LineSelector(this, value)
            arguments
                this
                value   (1,1)   string  {mustBeMember(value, ["Line1", "Line2", ...
                                                              "Line3", "Line4"])}
            end

            if this.IsConnected
                this.vsobj.LineSelector = value;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% LineSource Getter & Setter
        function value = get.LineSource(this)
            if this.IsConnected
                value = this.vsobj.LineSource;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.LineSource(this, value)
            arguments
                this
                value   (1,1)   string  {mustBeMember(value, ["ExposureActive", ...
                                                              "FrameTriggerWait", ...
                                                              "FrameBurstTriggerWait"])}
            end

            if this.IsConnected
                this.vsobj.LineSource = value;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% MaxAcquireFrameRate Getter
        function value = get.MaxAcquireFrameRate(this)
            if this.IsConnected
                value = (3-sqrt(5))/2 * this.MaxFrameRate;  % 0.618 as experimental value
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        %% MaxFrameRate Getter
        function value = get.MaxFrameRate(this)
            if this.IsConnected
                value = 1e6/this.vsobj.SensorReadoutTime;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        %% OffsetX Getter & Setter
        function value = get.OffsetX(this)
            if this.IsConnected
                rpos = this.viobj.ROIPosition;
                value = rpos(1);
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.OffsetX(this, value)
            arguments
                this
                value   (1,1)   double  {mustBeNonnegative, mustBeInteger}
            end
            if this.IsConnected
                try
                    rpos = this.viobj.ROIPosition; rpos(1) = value;
                    this.viobj.ROIPosition= rpos;
                catch ME
                    throw(ME);
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% OffsetY Getter & Setter
        function value = get.OffsetY(this)
            if this.IsConnected
                rpos = this.viobj.ROIPosition;
                value = rpos(2);
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.OffsetY(this, value)
            arguments
                this
                value   (1,1)   double  {mustBeNonnegative, mustBeInteger}
            end
            if this.IsConnected
                try
                    rpos = this.viobj.ROIPosition; rpos(2) = value;
                    this.viobj.ROIPosition = rpos;
                catch ME
                    throw(ME);
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% ReadoutTime Getter
        function value = get.ReadoutTime(this)
            if this.IsConnected
                value = this.vsobj.SensorReadoutTime;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        %% ROIWidth Getter & Setter
        function value = get.ROIWidth(this)
            if this.IsConnected
                rpos = this.viobj.ROIPosition;
                value = rpos(3);
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.ROIWidth(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive, mustBeInteger}
            end
            if this.IsConnected
                try
                    rpos = this.viobj.ROIPosition; rpos(3) = value;
                    this.viobj.ROIPosition = rpos;
                catch ME
                    throw(ME);
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% ROIHeight Getter & Setter
        function value = get.ROIHeight(this)
            if this.IsConnected
                rpos = this.viobj.ROIPosition;
                value = rpos(4);
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.ROIHeight(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive, mustBeInteger}
            end
            if this.IsConnected
                try
                    rpos = this.viobj.ROIPosition; rpos(4) = value;
                    this.viobj.ROIPosition = rpos;
                catch ME
                    throw(ME);
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% VideoResolution Getter
        function value = get.VideoResolution(this)
            if this.IsConnected
                value = this.viobj.VideoResolution;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

    end

    methods (Access = public)
        function Connect(this)
            if ~this.IsConnected
                try
                    % new object
                    this.viobj = videoinput(this.Adapter, ...
                                            this.Identity, ...
                                            this.Format);
                    this.vsobj = getselectedsource(this.viobj);

                    % set trigger parameters
                    triggerconfig(this.viobj, 'manual');
                    this.viobj.TriggerRepeat = inf;
                    this.viobj.FramesPerTrigger = 1;
                catch ME
                    throw(ME);
                end
            else
                warning("EBCamera:connectedInstance", "An EBCamera instance is already " + ...
                        "connected. You can create other EBCameras for multi-recording.");
            end
        end

        function Disconnect(this)
            if this.IsConnected
                % delete video control obejct
                delete(this.viobj); 
                this.viobj = [];
                this.vsobj = [];        % garbage collector auto clear

                % clear buffer (in memory)
                this.VideoBuffer.Clear();
            else
                warning("EBCamera:invalidAccess", "No connected EBCamera device.");
            end
        end

        function Live(this, state, hImage, fbd)
            % call inner function: preview
            arguments
                this
                state   (1,1)   string  {mustBeMember(state, ["on", "off"])} = "on"
                hImage  (1,:)                                                = []
                fbd     (1,1)   string  {mustBeMember(fbd, ["on", "off"])}   = "off"
            end

            if this.IsConnected
                switch state
                    case "on"
                        if this.IsLiving
                            warning("EBCamera:livingInstance", "An EBCamera " + ...
                                "instance is already living.");
                        else
                            this.viobj.PreviewFullBitDepth = fbd;

                            if isempty(hImage) || ~isvalid(hImage)
                                preview(this.viobj);
                            else
                                if isa(hImage, 'matlab.graphics.primitive.Image')
                                    preview(this.viobj, hImage);
                                else
                                    throw(MException("EBCamera:invalidArgument", ...
                                        "Unsupported image handle: hImage."));
                                end
                            end
                        end
                    case "off"
                        closepreview(this.viobj);
                    otherwise
                end
            else
                throw(MException("EBCamera:invalidAction", "Disconnected camera " + ...
                    "can not live."));
            end
        end

        function Acquire(this, time)
            arguments
                this
                time    (1,1)   double  {mustBePositive} = 10   % unit as seconds, 10 s as default
            end
            
            if this.IsConnected
                if this.IsRunning
                    warning("EBCamera:runningInstance", "An EBCamera instance is already " + ...
                        "running. You can create other EBCameras for multi-recording.");
                else
                    % calculate and set running times
                    ntasks = ceil(time*this.fr_target);
                    this.cap_agent.TasksToExecute = ntasks;

                    % clear buffer for initializing
                    this.VideoBuffer.Clear();

                    % start timer
                    this.abs_start_t = tic;
                    start(this.cap_agent);
                end
            else
                throw(MException("EBCamera:invalidAction", "Disconnected camera " + ...
                    "can not capture video."));
            end
            
        end

        function value = GetCurrentFrame(this)
            if this.IsConnected
                if this.IsRunning
                    [frame, time] = this.VideoBuffer.GetLastFrame();
                    value = {frame, time};
                else
                    warning("EBCamera:invalidAccess", "No image is captured " + ...
                        "because EBCamera is not running.");
                    value = {[], []};
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get images."));
            end
        end

        function Abort(this)
            % stop recording
            stop(this.cap_agent);

            % give up buffer
            this.VideoBuffer.Clear();
        end

        function Stop(this)
            % stop recording only
            stop(this.cap_agent);
        end
    end

    methods (Access = private)
        function capture_one_frame(this, src, evt)
            src; %#ok<VUNUS>
            evt; %#ok<VUNUS>

            trigger(this.viobj);
            img = getdata(this.viobj);

            % input to video buffer
            this.VideoBuffer.AddFrame(img, toc(this.abs_start_t));
        end

        function capture_begin(this, src, evt)
            src; %#ok<VUNUS>
            evt; %#ok<VUNUS>

            start(this.viobj);
        end

        function capture_end(this, src, evt)
            src; %#ok<VUNUS>
            evt; %#ok<VUNUS>

            stop(this.viobj);
        end
    end

    methods (Static)
        function ManageWarnings(state)
            arguments
                state    (1,1)   string  {mustBeMember(state, ["on","off"])} = "off"
            end

            warning(state, 'imaq:gige:adaptorPropertyHealed');
            warning(state, 'imaq:preview:typeBiggerThanUINT8');
        end
    end
end
