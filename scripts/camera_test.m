%% This script test the camera: configure and capture

%% Create connection to the device using the specified adaptor with the specified format.
Format = "Mono12";
vid = videoinput("gentl", "1", Format);     % mono8, mono12

%% Configure properties that are specific to this device.
src = getselectedsource(vid);

% set screen parameters
src.BinningVertical = 2;            % determine resolution and light
src.BinningHorizontal = 2;          % determine resolution and light
fprintf("Width: %d,  Height: %d\n", vid.VideoResolution)
vid.ROIPosition = [50,50,800,450];  % limited by resolution, [X,Y,W,H]

% set exposure parameters
src.ExposureMode = "Timed";         % time control
src.ExposureAuto = "Off";           % fixed by exposure time
src.ExposureTime = 1e4;             % exposure time, us
MFPS = 0.65*1e6/(src.ExposureTime+src.SensorReadoutTime);    % 0.65 as experimental coefficient
fprintf("Readout Time: %d us\n", src.SensorReadoutTime);% readout time, determine by Binning, Decimation and ROI
fprintf("Max Stable Frame Rate: %.1f FPS\n", MFPS);
FrameRate = 30;                     % Hz, captured frame rate, user control, limited by 
                                    % exposure time, readout time and 

% output line parameters
src.LineInverter = "True";          % low voltage level as default
src.LineSelector = "Line2";         % output
src.LineSource = "ExposureActive";  % exposure trigger the 'inner switch'

% set trigger parameters
triggerconfig(vid, 'manual');
vid.TriggerRepeat = inf;
vid.FramesPerTrigger = 1;

%% Capture image as fast as possible and display
NF = 500;

start(vid);
trigger(vid);

img = getdata(vid);
switch Format
    case "Mono8"
        h = imshow(img, [0 255]);
    case "Mono12"
        h = imshow(img, [0 4095]);
end

t = zeros(NF,1);

fprintf("Start acquiring...");

for k = 1:NF
    tic;
    trigger(vid);
    img = getdata(vid);
    h.CData = img;
    t1 = toc;
    pause(1/FrameRate - t1);
    t(k) = toc;
end

stop(vid);

fprintf("Done.");

% Output Frame Rate Curve
t(1) = [];
fps = 1./t;
figure;
plot(fps);
xlabel("Frame","FontSize",12);
ylabel("FPS", "FontSize",12);
ylim([0 max(MFPS, FrameRate)]);
fprintf("Mean: %.2f FPS, Std: %.2f FPS, Prc1: %.2f FPS\n", ...
    mean(fps), std(fps), prctile(fps, 1));
%% Clean up

delete(vid)
clear
close all
clc