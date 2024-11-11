classdef VideoFrame
    %VIDEOFRAME This is video frame object, with basic properties could be
    % illstruated on VideoPlayer
    % generate as value object

    properties(GetAccess = public, Dependent)
        DetectBoxes         % ___/get, k-by-5 double, [OffsetX, OffsetY, Width, Height, Angle]
        GeometricCenters    % ___/get, k-by-2 double, [PositionX, PositionY]
        ImageData           % ___/get, m-by-n uint8/uint16 image data
        MetaData            % ___/get, 1-by-1 string, command code, such as "A&B"
        Scale               % ___/get, 1-by-1 struct, [xRes, yRes, resUnit], resolution for pixel size
        TimeStamp           % ___/get, 1-by-1 double, current frame relative captured time
    end

    
    properties(SetAccess = immutable, GetAccess = private)
        detect_boxes        (:,5)   double  % [OffsetX, OffsetY, Width, Height, Angle]
        geometric_centers   (:,2)   double  % [PositionX, PositionY]
        image_data          (:,:)           % image data
        meta_data           (1,1)   string  % command code, such as "A&B"
        scale               (1,1)   struct  % field: [xRes, yRes, resUnit]
        time_stamp          (1,1)   double  % second
    end
    
    methods
        function this = VideoFrame(image_, time_, meta_, scale_, boxes_, pos_)
            arguments
                image_  (:,:)           {mustBeNonnegative}
                time_   (1,1)   double  {mustBeNonnegative}
                meta_   (1,1)   string
                scale_  (1,1)   struct
                boxes_  (:,5)   double  {mustBeNonnegative}
                pos_    (:,2)   double  {mustBeNonnegative}
            end

            % immutable properties
            this.image_data = image_;
            this.time_stamp = time_;
            this.meta_data = meta_;
            this.scale = scale_;
            this.detect_boxes = boxes_;
            this.geometric_centers = pos_;
        end

        %% DetectBoxes Getter
        function value = get.DetectBoxes(this)
            value = this.detect_boxes;
        end

        %% GeometricCenters Getter
        function value = get.GeometricCenters(this)
            value = this.geometric_centers;
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

        %% TimeStamp Getter
        function value = get.TimeStamp(this)
            value = this.time_stamp;
        end
    end
end