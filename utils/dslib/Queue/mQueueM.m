classdef mQueueM < matlab.mixin.Copyable
    %MQUEUEM This class provide a basic queue and some operator
    
properties (Access=private, Hidden)
        length;
    end

    properties(Access=private, Hidden, NonCopyable)
        data_v; % cell array is better choice
    end
    
    methods
        function this = mQueueM()
            %MQUEUE Initialize an empty queue
            this.length = 0;
            this.data_v = {};
        end

        function enqueue(this, d)
            this.data_v = [this.data_v, {d}];
            this.length = this.length + 1;
        end

        function item = dequeue(this)
            if ~this.isempty()
                item = this.head();
                this.data_v(1) = [];
                this.length = this.length - 1;
            else
                item = [];
            end
        end

        function item = head(this)
            if ~this.isempty()
                item = this.data_v{1};
            else
                item = [];
            end
        end

        function item = tail(this)
            if ~this.isempty()
                item = this.data_v{end};
            else
                item = [];
            end
        end

        function tf = isempty(this)
            if this.size() == 0
                tf = true;
            else
                tf = false;
            end
        end

        function len = numel(this)
            len = this.length;
        end

        function clear(this)
            % clean data but keep this
            this.cleanup();
            
        end

        function delete(this)
            % deconstructor
            this.cleanup();

            % ~
            clear("this");
        end
    end

    methods(Access = public, Hidden)
        function value = get(this, index)
            arguments
                this
                index   (1, 1)  double  {mustBePositive, mustBeInteger}
            end
            
            if index <= this.length
                value = this.data_v{index};
            else
                throw(MException("mQueue:OutOfBoundary", "Index out of array " + ...
                    "boundary."));
            end
        end
    end

    methods(Access = private, Hidden)
        function cleanup(this)
            % call object delete for memory free
            cellfun(@free, this.data_v);

            % clear built-in value classes
            this.data_v = {};
            
            this.length = 0;

            function free(x)
                if isobject(x) && isvalid(x) && ...
                        ismember("delete", string(methods(x)))
                    x.delete();     % call overloaded 'delete'
                end
            end
        end
    end

    methods(Access = protected)
        function cpt = copyElement(this)
            cpt = copyElement@matlab.mixin.Copyable(this);
            cpt.data_v = this.data_v;   % cell copy
        end
    end
end

