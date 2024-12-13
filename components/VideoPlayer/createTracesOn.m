function ax = createTracesOn(ax, trs, trscolor, trsalpha)
%CREATETRACEON This function create simple traces on ax
% Input:
%   - ax: 1-by-1 matlab.graphics.axis.Axes or matlab.ui.control.UIAxes
%       object handle
%   - trs: n-by-1 cell, each cell with [x1,y1; x2,y2; ...] as trace
%       sample position
%   - trscolor: n-by-3 RGB array, indicate each trace color

arguments
    ax          (1,1)
    trs         (1,1)   dictionary
    trscolor    (1,1)   dictionary
    trsalpha    (:,1)   double  {mustBeInRange(trsalpha, 0, 1)}
end

%% validate objects number
if ~all(ismember(trs.keys("uniform"), trscolor.keys("uniform")))
    throw(MException("createTracesOn:objectsNotMatch", ...
        "Some traces lost color information."));
end

%% remove exist traces
delete(findobj(ax.Children, "Tag", "traces"));

%% create new traces
hold(ax, "on");

for key = trs.keys("uniform")'
    % draw circles (as scatter)
    mkalpha = linspace(trsalpha, 0, size(trs{key}, 1));

    scatter(ax, trs{key}(:,1), trs{key}(:,2), 10, "filled", "o", ...
        "MarkerEdgeColor","none", "MarkerFaceColor",trscolor{key}, ...
        "AlphaData",mkalpha, "MarkerFaceAlpha","flat", ...
        "Tag", "traces");
end

hold(ax, "off");

end

