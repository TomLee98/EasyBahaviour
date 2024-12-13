function ax = updateComponentsOnNew(ax, vf, sw, opts)
%UPDATECOMPONENTSONNEW This function updates components on ax by frame vf,
% opts controls appearance
% Input:
%   - ax:
%   - vf:
%   - sw:
%   - opts:
% Output:
%   - ax
arguments
    ax      (1,1)
    vf      (1,1)   EBVideoFrame
    sw      (1,1)   struct
    opts    (1,1)   struct
end

% screen defination as followed:
%% ======================== Screen ============================
%  [TIME]                                        [Play Speed] %
%                                                             %
%                      [*]                                    %
%                      Video Frame Image Data                 %
%                                [>]                          %
%              [<]                         [*]                %
%                                                             %
%  [Scale]                                        [Meta Data] %
%% ============================================================

scrx = ax.XLim-0.5; scry = ax.YLim-0.5;

%% Update Time
hTime = findobj(ax.Children, "Tag", "time");
if sw.TimeStamp == true
    hTime.Visible = "on";
    hTime.String = ...
        string(duration(seconds(vf.TimeStamp),"Format","hh:mm:ss.S"));
else
    hTime.Visible = "off";
end

%% Update Scale Bar
hScaleTxt = findobj(ax.Children, "Tag", "scaletxt");
hScaleBar = findobj(ax.Children, "Tag", "scalebar");
if sw.ScaleBar == true
    if vf.Scale.resUnit == "um"
        sr = 1e4;
    elseif vf.Scale.resUnit == "mm"
        sr = 10;
    elseif vf.Scale.resUnit == "inch"
        sr = 1/2.54;
    else
        sr = 1;
    end
    DX = bl / vf.Scale.xRes * sr;  % in pixels
    hScaleBar.Visible = "on";
    hScaleBar.XData = [EBScreenLayout.SCALE_OFFSET_X.Value, ...
                       EBScreenLayout.SCALE_OFFSET_X.Value + DX];
    hScaleTxt.Visible = "on";
    hScaleTxt.String = sprintf("%.1f cm", bl);
    hScaleTxt.Position(1) = EBScreenLayout.SCALE_OFFSET_X.Value + DX/2;
else
    hScaleBar.Visible = "off";
    hScaleTxt.Visible = "off";
end

%% Update Play Speed
hSpeed = findobj(ax.Children, "Tag", "speed");
if sw.PlaySpeed == true
    hSpeed.Visible = "on";
    hSpeed.String = sprintf("Play@%.2f X", spr);
else
    hSpeed.Visible = "off";
end

%% Update Metadata
hMeta = findobj(ax.Children, "Tag", "meta");
if sw.Metadata == true
    hMeta.String = vf.MetaData;
    hMeta.Visible = "on";
else
    hMeta.Visible = "off";
end

%% Update Boxes
if sw.DetectBox == true
    boxes = vf.DetectBoxes;
    pos = cell2mat(boxes.values("uniform"));
    lbl = boxes.keys("uniform");
    color = getcmap(lbl, tgt);
    % draw
    createDetectBoxesOn(ax, pos, lbl, color);
else
    % empty
    createDetectBoxesOn(ax, [], [], []);
end

%% Update Trajectory
if sw.Trajectory == true

end

end

function c = getcmap(lbl, tgt)
c = strings(numel(lbl), 1);
c(string(regexp(lbl, "[a-zA-Z]*", "match"))==tgt) = "g";
c(string(regexp(lbl, "[a-zA-Z]*", "match"))==tgt) = "r";
end


