classdef EBImages < handle
    %VIDEO This class defines 2D Video

    properties(Access=public, Dependent)
        IsEmpty         % ___/get, 1-by-1 logical
        Size            % ___/get, 1-by-1 nonnegtive integer
        Mode            % ___/get, 1-by-1 string, "static" or "dynamic"
        Storage         % ___/get, 1-by-1 string, "memory","hard drive"
    end
    
    properties(Access = private, Hidden, NonCopyable)
        image_queue (1,1)   
        time        (:,1)   double
        mode        (1,1)   string
        storage     (1,1)   string
    end
    
    methods
        function this = EBImages(mode_, storage_, images_, time_)
            %EBIMAGES A Constructor
            arguments
                mode_       (1,1)   string  {mustBeMember(mode_, ["static", "dynamic"])} = "dynamic"
                storage_    (1,1)   string  {mustBeMember(storage_, ["memory","hard drive"])} = "memory"
                images_     (:,:,:)         {mustBeNonnegative}  = []
                time_       (:,1)   double  {mustBeNonnegative} = []
            end

            % set object mode and storage 
            this.mode = mode_;
            this.storage = storage_;

            % initialize data
            switch mode_
                case "static"
                    if isempty(images_)
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
                switch this.storage
                    case "memory"
                        this.image_queue = mQueueM();
                    case "hard drive"
                        this.image_queue = mQueueHD();
                    otherwise
                end
                
                for k = 1:size(images_, 3)
                    this.image_queue.enqueue(images_(:,:,k));
                end
            else
                if ~isempty(time_)
                    throw(MException("Video:invalidConstruction", ...
                        "Number of images and timestamps does not match."));
                else
                    switch this.storage
                        case "memory"
                            this.image_queue = mQueueM();
                        case "hard drive"
                            this.image_queue = mQueueHD();
                        otherwise
                    end
                    this.time = time_;
                end
            end
        end

        function delete(this)
            this.image_queue.delete();

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

        function value = get.Storage(this)
            value = this.storage;
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
        function hEBImage = empty(storage_)
            arguments
                storage_    (1,1)   string  {mustBeMember(storage_, ["memory","hard drive"])} = "memory"
            end

            hEBImage = EBImages("dynamic", storage_, [], []);
        end
    end
end
