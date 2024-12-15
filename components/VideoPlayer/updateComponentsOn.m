function updateComponentsOn(ax, vf, sw, bl, spr, tgt)
%UPDATECOMPONENTSON This function update components on ax by vf, sw as
%switch, control component repaint

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

persistent trscolor;

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
    if vf.Scale.ResUnit == "um"
        sr = 1e4;
    elseif vf.Scale.ResUnit == "mm"
        sr = 10;
    elseif vf.Scale.ResUnit == "inch"
        sr = 1/2.54;
    else
        sr = 1;
    end
    DX = bl / vf.Scale.XRes * sr;  % in pixels
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
    if boxes.numEntries ~= 0
        box = cell2mat(boxes.values("uniform"));
        pos = box(:, 1:4);
        class_ = boxes.keys("uniform");
        color = getcmap(class_, tgt);
        % draw
        sposteri = sprintf("%.2f,", box(:,end)).split(",");
        lbl = class_ + ": " + sposteri(1:end-1);
        createDetectBoxesOn(ax, pos, lbl, color);
    end
else
    % empty
    createDetectBoxesOn(ax, [], [], []);
end

%% Update Traces
if sw.Traces == true
    if isempty(trscolor), trscolor = configureDictionary("string", "cell"); end
    colors = jet(256);
    % use little transparency circle as traces
    % hold 10 circles
    traces = vf.Traces;

    % ! note that no color release process
    for key = traces.keys("uniform")'
        if ~trscolor.isKey(key)
            alloc_n = traces.numEntries;
            % push new color from left color set
            trscolor(key) = {colors(alloc_n+1, :)};
        end
    end

    createTracesOn(ax, traces, trscolor, 0.5);
else
    createTracesOn(ax, configureDictionary("string", "cell"), ...
        configureDictionary("string", "cell"), 0);
end

end

function c = getcmap(lbl, tgt)
c = strings(numel(lbl), 1);
c(string(regexp(lbl, "[a-zA-Z]*", "match"))==tgt) = "g";
c(string(regexp(lbl, "[a-zA-Z]*", "match"))~=tgt) = "r";
end