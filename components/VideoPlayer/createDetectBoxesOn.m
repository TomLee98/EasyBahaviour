function ax = createDetectBoxesOn(ax, pos, lbl, color)
%CREATEDETECTBOX This function create simple detect boxes on ax
% Input:
%   - ax: 1-by-1 matlab.graphics.axis.Axes or matlab.ui.control.UIAxes
%       object handle
%   - pos: n-by-4 nonnegtive double, format as [x,y,w,h], n rectanges
%   - lbl: n-by-1 string, label for each rectange
%   - color: n-by-3 or 1-by-3 or RGB simple code for rectange

arguments
    ax      (1,1)
    pos     (:,4)   double  {mustBeNonnegative}
    lbl     (:,1)   string  
    color
end

%% validate objects number
if size(pos, 1) ~= numel(lbl)
    throw(MException("createDetectBoxOn:objectsNotMatch", ...
        "Boxes number must be equal to labels number."));
end

nobj = size(pos, 1);

%% validate color
if size(color, 1) == 1
    if isnumeric(color)
        if numel(color) == 3
            color = repmat(color, nobj, 1);
        else
            throw(MException("createDetectBox:invalidColorFormat", ...
                "Color should be [R,G,B] triple array."));
        end
    elseif ismember(string(color), ["red","green","blue","cyan","maganta","yellow","black","white", ...
                                    "r","g","b","c","m","y","k","w"])
        color = repmat(color, nobj, 1);
    else
        throw(MException("createDetectBox:invalidColorFormat", ...
                "Unsupported color representation."));
    end
else
    if size(color, 1) ~= nobj
        throw(MException("createDetectBox:invalidColorNumber", ...
                "Colors number mismatch."));
    end
end

%% remove exist rectangles and labels
delete(findobj(ax.Children, "Tag", "boxes"));
delete(findobj(ax.Children, "Tag", "labels"))

%% create new boxes and labels
for n = 1:nobj
    % draw rectangle
    rectangle(ax, "Position", pos(n, :), "EdgeColor",color(n, :), "LineWidth",1, ...
        "Tag", "boxes");

    % draw text
    text(ax, pos(n,1)+pos(n,3)/2, pos(n,2)-3, lbl(n), "Color",color(n, :), "FontSize",12, ...
        "HorizontalAlignment", "center", ...
        "VerticalAlignment", "bottom", ...
        "Tag", "labels");
end

end

