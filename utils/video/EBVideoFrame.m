classdef EBVideoFrame < handle
    %VIDEOFRAME This is video frame object, with basic properties could be
    % illstruated on VideoPlayer
    % generate as value object

    properties(GetAccess = public, Dependent)
        DetectBoxes         % ___/get, k-by-6 double, [Identity, OffsetX, OffsetY, Width, Height, Angle]
        GeometricCenters    % ___/get, k-by-3 double, [Identity, PositionX, PositionY]
        ImageData           % ___/get, m-by-n uint8/uint16 image data
        MetaData            % ___/get, 1-by-1 string, command code, such as "A&B"
        Scale               % ___/get, 1-by-1 struct, [xRes, yRes, resUnit], resolution for pixel size
        TimeStamp           % ___/get, 1-by-1 double, current frame relative captured time
    end

    
    properties(SetAccess = immutable, GetAccess = private)
        detect_boxes        (:,6)   double  % [Identity, OffsetX, OffsetY, Width, Height, Angle]
        geometric_centers   (:,3)   double  % [Identity, PositionX, PositionY]
        image_data          (:,:)           % image data
        meta_data           (1,1)   string  % command code, such as "A&B"
        scale               (1,1)   struct  % field: [xRes, yRes, resUnit]
        time_stamp          (1,1)   double  % second
    end
    
    methods
        function this = EBVideoFrame(image_, time_, meta_, scale_, boxes_, pos_)
            arguments
                image_  (:,:)         
                time_   (1,1)   double
                meta_   (1,1)   string  = ""
                scale_  (1,1)   struct  = struct("xRes",1, "yRes",1, "resUnit","mm")
                boxes_  (:,6)   double  = double.empty(0, 6)
                pos_    (:,3)   double  = double.empty(0, 3)
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

    methods(Access = public)
        function value = isempty(this)
            value = isempty(this.image_data);
        end

        function value = isequal(this, rhs_)
            arguments
                this
                rhs_    (1,1)   EBVideoFrame
            end

            value = isequal(this.image_data, rhs_.image_data) ...
                && isequal(this.meta_data, rhs_.meta_data) ...
                && isequal(this.scale, rhs_.scale) ...
                && isequal(this.time_stamp, rhs_.time_stamp) ...
                && isequal(this.detect_boxes, rhs_.detect_boxes) ...
                && isequal(this.geometric_centers, rhs_.geometric_centers);
        end
    end
end