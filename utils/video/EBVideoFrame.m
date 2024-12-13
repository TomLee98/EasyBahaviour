classdef EBVideoFrame < handle
    %VIDEOFRAME This is video frame object, with basic properties could be
    % illstruated on VideoPlayer
    % generate as value object

    properties(GetAccess = public, Dependent)
        DetectBoxes         % ___/get, 1-by-1 dictionary, identity |-> location, [OffsetX, OffsetY, Width, Height, PostPrab]
        CenterTraces        % ___/get, 1-by-1 dictionary, identity |-> location, [PositionX, PositionY, TimeStamp]
        ImageData           % ___/get, m-by-n uint8/uint16 image data
        MetaData            % ___/get, 1-by-1 string, command code, such as "A&B"
        Scale               % ___/get, 1-by-1 struct, [XRes, YRes, ResUnit, BarLength], resolution for pixel size
        Tag                 % ___/get, 1-by-1 double, current frame tag, positive integer
        TimeStamp           % ___/get, 1-by-1 double, current frame relative captured time
    end

    properties(SetAccess = immutable, GetAccess = private)
        detect_boxes        (1,1)   dictionary  % [OffsetX, OffsetY, Width, Height, PostPrab]
        center_traces       (1,1)   dictionary  % [PositionX, PositionY, TimeStamp]
        image_data          (:,:)               % image data
        meta_data           (1,1)   string      % command code, such as "A&B"
        scale               (1,1)   struct      % field: [xRes, yRes, resUnit]
        tag                 (1,1)   double      % indicate current frame index
        time_stamp          (1,1)   double      % second
    end
    
    methods
        function this = EBVideoFrame(image_, time_, tag_, meta_, scale_, boxes_, traces_)
            arguments
                image_  (:,:)         
                time_   (1,1)   double
                tag_    (1,1)   double
                meta_   (1,1)   string  = ""
                scale_  (1,1)   struct  = struct("XRes",0.1, "YRes",0.1, "ResUnit","mm", "BarLength",10)
                boxes_  (1,1)   dictionary  = configureDictionary("string", "cell")
                traces_ (1,1)   dictionary  = configureDictionary("string", "cell")
            end

            % immutable properties
            this.image_data = image_;
            this.time_stamp = time_;
            this.tag = tag_;
            this.meta_data = meta_;
            this.scale = scale_;
            this.detect_boxes = boxes_;
            this.center_traces = traces_;
        end

        %% DetectBoxes Getter
        function value = get.DetectBoxes(this)
            value = this.detect_boxes;
        end

        %% GeometricCenters Getter
        function value = get.CenterTraces(this)
            value = this.center_traces;
        end

        %% ImageData Getter
        function value = get.ImageData(this)
            value = this.image_data;
        end

        %% MetaData Getter
        function value = get.MetaData(this)
            value = this.meta_data;
        end

        %% Scale Getter
        function value = get.Scale(this)
            value = this.scale;
        end

        %% Tag Getter
        function value = get.Tag(this)
            value = this.tag;
        end

        %% TimeStamp Getter
        function value = get.TimeStamp(this)
            value = this.time_stamp;
        end
    end

    methods(Access = public)
        function value = isempty(this)
            value = isempty(this.image_data);
        end

        function value = isequal(this, rhs_)
            arguments
                this
                rhs_    (1,1)   EBVideoFrame
            end

            value = (this.tag == rhs_.tag);
        end
    end
end