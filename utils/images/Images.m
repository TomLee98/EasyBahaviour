classdef Images < handle
    %VIDEO This class defines 2D Video

    properties(Access=public, Dependent)
        IsEmpty         % 1-by-1 logical
        Size            % 1-by-1 nonnegtive integer
        Mode            % 1-by-1 string, "static" or "dynamic"
    end
    
    properties(Access = private, Hidden, NonCopyable)
        image_queue (1,1)   mQueue
        time        (:,1)   double
        mode        (1,1)   string
    end
    
    methods
        function this = Images(mode_, images_, time_)
            %VIDEO A Constructor
            arguments
                mode_   (1,1)   string  {mustBeMember(mode_, ["static", "dynamic"])} = "dynamic"
                images_ (:,:,:)         {mustBeNonnegative}  = []
                time_   (:,1)   double  {mustBeNonnegative} = []
            end

            % set mode
            this.mode = mode_;

            % initialize data
            switch mode_
                case "static"
                    if isempty(images)
                        throw(MException("Video:invalidConstruction", ...
                            "Images can not be empty when instance generation."));
                    end
                case "dynamic"
                    %
                otherwise
            end

            if ~isempty(images_)
                % set timestamps
                if isempty(time_)
                    warning("Video:timeLost", "Timestamps lost, frame " + ...
                        "indices will replace it.");
                    this.time = (1:size(images_, 3))';
                else
                    if numel(time_) ~= size(images_, 3)
                        throw(MException("Video:invalidConstruction", ...
                            "Number of images and timestamps does not match."));
                    else
                        this.time = time_;
                    end
                end

                % set data
                this.image_queue = mQueue();
                for k = 1:size(images_, 3)
                    this.image_queue.enqueue(images_(:,:,k));
                end
            else
                if ~isempty(time_)
                    throw(MException("Video:invalidConstruction", ...
                        "Number of images and timestamps does not match."));
                else
                    this.image_queue = mQueue();
                    this.time = time_;
                end
            end
        end

        function delete(this)
            delete(this.image_queue);

            clear("this");
        end
       
        function value = get.IsEmpty(this)
            value = (numel(this.image_queue)==0);
        end

        function value = get.Mode(this)
            value = this.mode;
        end

        function value = get.Size(this)
            value = numel(this.image_queue);
        end
    end

    methods(Access = public)
        function AddFrame(this, image_, time_)
            arguments
                this
                image_  (:,:)
                time_   (1,1)   double  {mustBeNonnegative} = numel(this.time) + 1
            end

            switch this.mode
                case "static"
                    throw(MException("Video:invalidUse", ...
                        "Static Video is read-only object."));
                case "dynamic"
                    this.image_queue.enqueue(image_);
                    this.time = [this.time; time_];
            end
        end

        function [image, time] = GetLastFrame(this)
            n = numel(this.image_queue);
            if n > 0
                [image, time] = GetFrame(this, n);
            else
                warning("Video:emptyVideo", "No valid frames.");
                image = [];
                time = [];
            end
        end

        function Clear(this)
            % clean up image queue and time
            this.image_queue.clear();

            this.time = [];
        end
    end

    methods(Access=public, Hidden)
        function [image, time] = GetFrame(this, fIndex)
            arguments
                this
                fIndex  (1,1)   double  {mustBePositive, mustBeInteger}
            end

            image = this.get_image_at(fIndex);
            time = this.get_time_at(fIndex);
        end
    end

    methods(Access=private)
        function value = get_image_at(this, fIndex)
            if fIndex > numel(this.image_queue)
                warning("Video:outOfBoundary", "Index out of video frames.");
                value = [];
            else
                value = this.image_queue.get(fIndex);
            end
        end

        function value = get_time_at(this, fIndex)
            if fIndex > numel(this.time)
                warning("Video:outOfBoundary", "Index out of video frames.");
                value = [];
            else
                value = this.time(fIndex);
            end
        end
    end

    methods (Static)
        function e = empty()
            e = Images("dynamic", [], []);
        end
    end
end
