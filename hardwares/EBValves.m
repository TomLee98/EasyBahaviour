classdef EBValves < handle
    %VALVES This is general EBvalves defination

    properties(SetAccess=immutable, GetAccess=public)
        % Interpreter - Specifies the interpreter transform  VCSL code to
        % value control command
        % Read/Write Access - Read-only
        % Accepted Values - function_handle with <code, map> as input parameters
        % Default - vcsl
        Interpreter

        % AutoInterpret - Specifies the interpreter auto working flag
        % Read/Write Access - Read-only
        % Accepted Values - true/false
        % Default - true
        AutoInterpret
    end
    
    properties(Access = private)
        adjust_time     (1,1)   double              % 1-by-1 double for avoiding timer error accumulation, seconds
        code_file       (1,1)   string              % source code file full path
        commands        (:,2)   table               % n-by-2 table, [cmd, delay]
        cmd_pointer     (1,1)   double              % 1-by-1 double, positive integer
        cmd_sender      (1,1)   timer               % 1-by-1 timer, send command to hardware
        device_id       (1,1)   string              % 1-by-1 device identity
        port_mapping    (1,1)   dictionary          % the hardware port mapping 
        vendor          (1,1)   string              % 1-by-1 device vendor
        vvobj           (:,1)               = []    % 1-by-1 DataAcquisition object
    end

    properties (Access=public, Dependent)
        CodePath            % set/get, 1-by-1 string
        DeviceID            % set/get, 1-by-1 string
        IsCommandReady      % ___/get, 1-by-1 logical
        IsConnected         % ___/get, 1-by-1 logical
        IsRunning           % ___/get, 1-by-1 logical
        PortMapping         % set/get, 1-by-1 dictionary
        Vendor              % set/get, 1-by-1 string
    end
    
    methods
        function this = EBValves(itp_, auto_interpret)
            %VALVES A constructor
            arguments
                itp_            (1,1)   function_handle
                auto_interpret  (1,1)   logical             = true  % code file will interpreted after assigning
            end

            % init immutable variables
            this.Interpreter = itp_;
            this.AutoInterpret = auto_interpret;

            this.commands = table('Size', [0, 2], 'VariableTypes',{'double', 'double'}, ...
                                  'VariableNames',{'cmd', 'delay'});
            this.adjust_time = 0;

            this.vendor = "ni";
            this.device_id = "Dev1";

            % init timer
            this.cmd_sender = timer("BusyMode","error", "ExecutionMode","singleShot", ...
                "Name","EBValves_Agent", "Period",1, "TimerFcn", @this.send_one_command);
        end

        %% CodePath Getter & Setter
        function value = get.CodePath(this)
            if ~isempty(this.code_file) ...
                    && isfile(this.code_file)
                value = this.code_file;
            else
                warning("EBValve:noCodeAssigned", "Code file has not been assigned.");
            end
        end

        function set.CodePath(this, value)
            arguments
                this
                value   (1,1)  string   {mustBeFile}
            end

            if ~this.IsRunning
                [~, ~, ext] = fileparts(value);

                if ~isequal(ext, ".vcs")
                    throw(MException("EBValve:invalidCodeFile", "Unsupported " + ...
                        "VCSL code file."));
                else
                    this.code_file = value;
                end

                % auto interpret codes
                if this.AutoInterpret
                    interpret(this);
                end
            else
                throw(MException("EBValves:invalidAccess", "Running valves " + ...
                    "code file is unsetable."));
            end
        end

        %% DeviceID Getter & Setter
        function value = get.DeviceID(this)
            value = this.device_id;
        end

        function set.DeviceID(this, value)
            arguments
                this 
                value   (1,1)   string 
            end

            if ~this.IsConnected
                this.device_id = value;
            else
                throw(MException("EBValves:invalidAccess", "Connected valves " + ...
                    "device ID is unsetable."));
            end
        end

        %% IsCommandReady Getter
        function value = get.IsCommandReady(this)
            value = ~isempty(this.commands);
        end

        %% IsConnected Getter
        function value = get.IsConnected(this)
            value = (~isempty(this.vvobj) && isvalid(this.vvobj));
        end

        %% IsRunning Getter
        function value = get.IsRunning(this)
            if this.IsConnected
                % mark the agent running status
                value = isequal(this.cmd_sender.Running, "on");
            else
                throw(MException("EBValves:invalidAccess", "Disconnected valves " + ...
                    "can not get status."));
            end
        end

        %% PortMapping Getter & Setter
        function value = get.PortMapping(this)
            value = this.port_mapping;
        end

        function set.PortMapping(this, value)
            arguments
                this
                value   (1,1)   {EBValves.mustBePortMapping}
            end

            if ~this.IsRunning
                this.port_mapping = value;

                % auto interpret codes
                if this.AutoInterpret
                    interpret(this);
                end
            else
                throw(MException("EBValves:invalidAccess", "Running valves " + ...
                    "port mapping is unsetable."));
            end
        end

        %% Vendor Getter & Setter
        function value = get.Vendor(this)
            value = this.vendor;
        end

        function set.Vendor(this, value)
            arguments
                this
                value   (1,1)   string  {mustBeMember(value, ["ni"])}
            end

            if ~this.IsConnected
                this.vendor = value;
            else
                throw(MException("EBValves:invalidAccess", "Connected valves " + ...
                    "vendor is unsetable."));
            end
        end

    end

    methods(Access = public)
        function Connect(this)
            if ~this.IsConnected
                try
                    % set 
                    this.vvobj = daq(this.Vendor);

                catch ME
                    throw(ME);
                end
            else
                warning("EBValves:connectedInstance", "An EBValves instance is already " + ...
                    "connected. You can create other EBValves for multi-switching.");
            end
            
        end

        function Disconnect(this)

        end

        function Test(this)

        end

        function Run(this)

        end

        function value = GetCurrentValves(this)

        end

        function Abort(this)

        end

        function Stop(this)

        end
    end

    methods (Access=public, Hidden)
        function Interpret(this)
            % user hidden calling
            interpret(this);
        end
    end

    methods (Access = private)

        function interpret(this)
            try
                this.commands = this.Interpreter(this.code_file, ...
                                                 this.port_mapping);
            catch ME
                throwAsCaller(ME);
            end
        end

        function send_one_command(this, src, evt)
            src; %#ok<VUNUS>
            evt; %#ok<VUNUS>

        end
    end

    methods (Static)
        function ManageWarnings(state)
            arguments
                state    (1,1)   string  {mustBeMember(state, ["on","off"])} = "off"
            end

        end

        function mustBePortMapping(A)
            arguments
                A   (1,1)   dictionary
            end

            vv = cellfun(@(x)any((x~=1)&(x~=0)), A.values, "UniformOutput", true);

            if ~isequal("string", A.types) ...
                    || any(vv)
                throw(MException("EBValves:invalidPortMapping", ...
                    "Port Mapping: string -> cell(only 0 and 1 as element)"));
            end
        end
    end
end

