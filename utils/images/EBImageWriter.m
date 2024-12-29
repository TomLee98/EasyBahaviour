classdef EBImageWriter < handle
    %IMAGEWRITER This is image writer class, which support write files as
    %defined format
    properties (Constant, Hidden)
        IMAGE_FORMAT_DEFAULT = "jpg"
        IMAGE_SUFFIX = "AAAAA"
    end

    properties(SetAccess=immutable)
        dataset
        info
    end

    properties(Access=public, Dependent)
        WrittingProgress        % ___/get, 1-by-1 nonnegtive double in (0, 1)
    end

    properties(Access=private)
        prgs    (1,1)   double  = 0
    end
    
    methods
        function this = EBImageWriter(dataset, info)
            %IMAGEWRITER 
            arguments
                dataset     (1,1)   EBImages
                info        (1,13)  table
            end

            this.dataset = dataset;
            this.info = info;
        end

        function value = get.WrittingProgress(this)
            value = this.prgs;
        end

        function delete(this)
            % ~
        end
   end

   methods (Access = public)
       function write(this, fmt)
           arguments
               this
               fmt  (1,1)   string  {mustBeMember(fmt, ["IMAGE", "IMAGE_STACK"])} = "IMAGE_STACK"
           end

           if this.dataset.IsEmpty
               warning("EBImageWriter:noImagestoWrite", ...
                   "No images could be written.");
               return;
           end

           switch fmt
               case "IMAGE"
                   fdir = uigetdir(userpath, "选择文件夹");
                   if ~isnumeric(fdir)
                       this.saveToFolder(fdir);
                   end
               case "IMAGE_STACK"
                   [file, path] = uiputfile({'*.tif', 'Tiff Files (*.tif)'; ...
                       '*.hdf5', 'HDF5 Files (*.tif)'; ...
                       '*.mat',  'MATLAB Files (*.mat)'}, ...
                       "保存图像", "captured.tif");
                   if ~isnumeric(file)
                       file = fullfile(path, file);
                       [~, ~, ext] = fileparts(file);

                       switch ext
                           case ".tif"
                               this.saveAsTIFF(file);
                           case ".hdf5"
                               this.saveAsHDF5(file);
                           case ".mat"
                               this.saveAsMAT(file);
                           otherwise
                       end
                   end
               otherwise
           end
       end
   end

   methods (Access = private)
       %% IMAGE_STACK FILE FORMAT IMPLEMENT
       function saveAsTIFF(this, file)
           % call Tiff library built in MATLAB
           % save no compressed raw data
           try
               dt = this.info.dateTime;
               dt.Format = "MM-dd HH:mm:ss.SSS";
               np = this.dataset.Size;

               %% open tiff file to write
               tifobj = Tiff(file, "w8");   % save as BigTiff to avoid >4GB file error IO

               %% tag struct with image information
               tagstruct.ImageWidth = this.info.width;
               tagstruct.ImageLength = this.info.height;
               tagstruct.XPosition = this.info.xOffset;
               tagstruct.YPosition = this.info.yOffset;
               tagstruct.ImageDescription = ...
                   sprintf("BinningHorizontal=%d, BinningVertical=%d, " + ...
                   "FrameRate=%.2f, DeviceModel=%s", this.info.xBinning, ...
                   this.info.yBinning, this.info.frameRate, this.info.deviceModel);
               if this.info.bitDepth == 8
                   tagstruct.BitsPerSample = 8;
               else
                   tagstruct.BitsPerSample = 16;
               end
               tagstruct.Photometric = 1;
               tagstruct.SampleFormat = 1;
               tagstruct.ResolutionUnit = 3;
               switch this.info.resolutionUnit
                   case "mm"
                       expand_ratio = 10;
                   case "um"
                       expand_ratio = 1e4;
                   otherwise
                       expand_ratio = 1;
               end
               tagstruct.XResolution = 1/this.info.xResolution*expand_ratio;
               tagstruct.YResolution = 1/this.info.yResolution*expand_ratio;

               %% tag struct with environment information
               tagstruct.Artist = "behaviour3";
               tagstruct.Software = sprintf("MATLAB(R%s):EasyBehaviour:ImageWriter", ...
                   version('-release'));
               [~, hostname] = system('hostname');
               tagstruct.HostComputer = sprintf("Windows / %s", hostname);

               % write the first image
               [imageData, time] = this.dataset.GetFrame(1);
               tagstruct.PageNumber = [0, np];
               tagstruct.DateTime = char(dt+seconds(time));
               setTag(tifobj, tagstruct);
               write(tifobj, imageData);

               % others
               for k = 2:np
                   % read data
                   [imageData, time] = this.dataset.GetFrame(k);

                   % create new directory
                   writeDirectory(tifobj);

                   % update tag
                   tagstruct.PageNumber = [k-1, np];
                   tagstruct.DateTime = char(dt+seconds(time));

                   % save data
                   setTag(tifobj, tagstruct);
                   write(tifobj, imageData);

                   this.prgs = k/np;
               end

               %% close tiff file
               close(tifobj);

           catch ME
               rethrow(ME);
           end
       end

       function saveAsHDF5(this, file)

       end

       function saveAsMAT(this, file)
           
       end

       %% IMAGE FILE FORMAT IMPLEMENT
       function saveToFolder(this, folder)
           % save to folder as *.jpg format
           np = this.dataset.Size;
           fmt = sprintf("%s%%0%dd.%s", this.IMAGE_SUFFIX, ...
               ceil(log10(np-1)), this.IMAGE_FORMAT_DEFAULT);

           for k = 1:np
               file = fullfile(folder, sprintf(fmt, k-1));
               [img, ~] = this.dataset.GetFrame(k);
               img = uint8(double(img)/4095*255);
               imwrite(img, file, this.IMAGE_FORMAT_DEFAULT, "Quality",100, ...
                   "Comment","EBImage", "BitDepth",8);
               this.prgs = k/np;
           end
       end
   end
end

