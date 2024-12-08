classdef ObjectMatcher < handle
    %OBJECTMATCHER This class uses Hungarian algorithm to solve the object
    % matching problem
    % We have Predictor given current frame objects position prediction 
    % and Detector given the current observation
    
    properties(Access = private)
        % cost and dist looks like "cluster distance" and "sample distance"
        cost        % 1-by-1 string, indicate cost between two objects
        dist        % 1-by-1 string, indicate distance between two pixels
    end
    
    methods
        function this = ObjectMatcher(cost_, dist_)
            %OBJECTMATCHER A Constructor
            arguments
                cost_   (1,1)   string  {mustBeMember(cost_, ...
                    ["Jaccard", "Average", "CornerMin", "CornerMax"])} = "Jaccard"
                dist_   (1,1)   string  {mustBeMember(dist_, ...
                    ["Euclidean", "Manhattan"])} = "Euclidean"

            end

            this.cost = cost_;
            this.dist = dist_;
        end
    end

    methods(Access = public)
        function [matched, new, lost, cost] = match(this, predicted, observed)
            % This function match predicted objects and observed objects
            % Input:
            %   - predicted: 1-by-1 dictionary, ideneity(string) ->
            %                location(1-by-4 double, [x,y,w,h])
            %   - observed: 1-by-1 dictionary, ideneity(string) ->
            %                location(1-by-4 double, [x,y,w,h])
            % Output:
            %   - matched: p-by-2 table with keys(string), [predicted, observed]
            %   - new: q-by-1 table with keys(string), [observed]
            %   - lost: r-by-1 table with keys(string), [predicted]
            %   - cost: 1-by-1 nonnegtive double, matching cost
            arguments
                this
                predicted   (1,1)   dictionary
                observed    (1,1)   dictionary
            end

            if ~predicted.isConfigured || ~observed.isConfigured
                throw(MException("ObjectMatcher:invalidInput", ...
                    "Input dictionary must be configured."));
            end

            matched = strings(0, 2);    % [predicted, observed]
            new = strings(0, 1);        % [observed]
            lost = strings(0, 1);       % [predicted]

            %% calculate IOU as cost matrix
            % COST:
            % ================ predicted ============= %
            % ||        a11   a12    a13    a14     ||
            % observed  a21   a22    a23    a24     ||
            % ||        a31   a32    a33    a34     ||
            % ======================================== %
            [CostMat, DistMax] = ObjectMatcher.getCostMatrix(predicted, ...
                observed, this.cost);

            if isempty(CostMat), return; end    % no object need to match

            %% simple matching all 1 rows and columns
            keys_observed = observed.keys("uniform");
            keys_predicted = predicted.keys("uniform");

            % [case 1: new object detected]
            % =========== predicted ========= %
            % ||        a11   a12   a13    ||
            % observed  a21   a22   a23    ||
            % ||        a31   a32   a33    ||
            % ||   (*)   Q     Q     Q     ||
            % =============================== %
            for m = 1:observed.numEntries
                if all(CostMat(m, :) == DistMax)
                    % [CASE: Unmatched Detection]
                    new = [new; keys_observed(m)]; %#ok<AGROW>
                end
            end
            % remove all new keys in observed
            observed(new) = [];
            [~, newloc] = ismember(new, keys_observed);
            CostMat(newloc, :) = [];
            keys_observed(newloc) = [];

            % [case 2: previous object lost]
            % ================ predicted ============= %
            % ||             (*)                ||
            % ||        a11   Q   a13   a14     ||
            % observed  a21   Q   a23   a24     ||
            % ||        a31   Q   a33   a34     ||
            % ======================================== %
            for n = 1:predicted.numEntries
                if all(CostMat(:, n) == DistMax)
                    % [CASE: Unmatched Tracks]
                    lost = [lost; keys_predicted(n)]; %#ok<AGROW>
                end
            end
            % remove all lost keys in predicted
            predicted(lost) = [];
            [~, lostloc] = ismember(lost, keys_predicted);
            CostMat(:, lostloc) = [];
            keys_predicted(lostloc) = [];

            % keep intersection consostancy
            if observed.numEntries ~= predicted.numEntries
                throw(MException("ObjectMatcher:innerError", ...
                    "Unknown error caused."));
            end

            % [case 3: complete matching by Hungarian algorithm]
            % ============ predicted ========= %
            % ||        a11   a13   a14     ||
            % observed  a21   a23   a24     ||
            % ||        a31   a33   a34     ||
            % ================================ %
            if ~isempty(CostMat)
                [ids, cost] = Hungarian(CostMat);
                for k = 1:numel(ids)
                    matched = [matched; [keys_predicted(ids(k)), keys_observed(k)]]; %#ok<AGROW>
                end
            else
                cost = DistMax*(numel(new) + numel(lost));
            end

            % format output as table
            matched = array2table(matched, "VariableNames", {'predicted', 'observed'});
            new = array2table(new, "VariableNames",{'observed'});
            lost = array2table(lost, "VariableNames", {'predicted'});
        end
    end

    methods(Static)
        function [CostMat, DistMax] = getCostMatrix(predicted, observed, cost, dist)
            arguments
                predicted   (1,1)   dictionary
                observed    (1,1)   dictionary
                cost        (1,1)   string      {mustBeMember(cost, ...
                                    ["Jaccard", "Average", "CornerMin", "CornerMax"])} = "Jaccard"
                dist        (1,1)   string  {mustBeMember(dist, ["Euclidean", "Manhattan"])} = "Euclidean"
            end

            keys_obs = observed.keys("uniform");
            keys_pdt = predicted.keys("uniform");

            switch cost
                case "Jaccard"
                    CostMat = ones(observed.numEntries, predicted.numEntries);

                    for m = 1:observed.numEntries
                        for n = 1:predicted.numEntries
                            obsrt = observed{keys_obs(m)};
                            pdtrt = predicted{keys_pdt(n)};
                            w_itt = max(0, min(obsrt(1)+obsrt(3), pdtrt(1)+pdtrt(3)) ...
                                - max(obsrt(1), pdtrt(1)));
                            h_itt = max(0, min(obsrt(2)+obsrt(4), pdtrt(2)+pdtrt(4)) ...
                                - max(obsrt(2), pdtrt(2)));
                            IOU = (w_itt*h_itt) ...
                                /(obsrt(3)*obsrt(4) + pdtrt(3)*pdtrt(4) - w_itt*h_itt);

                            CostMat(m, n) = 1 - IOU;    % Jaccard Index
                        end
                    end

                    DistMax = 1;
                case "Average"
                    CostMat = inf(observed.numEntries, predicted.numEntries);

                    for m = 1:observed.numEntries
                        for n = 1:predicted.numEntries
                            obsrt = observed{keys_obs(m)};
                            pdtrt = predicted{keys_pdt(n)};
                            obs_c = [obsrt(1)+obsrt(3)/2, obsrt(2)+obsrt(4)/2];
                            pdt_c = [pdtrt(1)+pdtrt(3)/2, pdtrt(2)+pdtrt(4)/2];

                            switch dist
                                case "Euclidean"
                                    CostMat(m, n) = sqrt(sum((pdt_c - obs_c).^2));  % Euclidean Distance of Center
                                case "Manhattan"
                                    CostMat(m, n) = sum(abs(pdt_c - obs_c));        % Manhattan Distance of Center
                                otherwise
                                    throw(MException("ObjectMatcher:invalidDistance", ...
                                        "Only Euclidean and Manhattan distance are supported."));
                            end
                        end
                    end

                    DistMax = inf;
                case "CornerMin"
                    CostMat = inf(observed.numEntries, predicted.numEntries);

                    for m = 1:observed.numEntries
                        for n = 1:predicted.numEntries
                            obsrt = observed{keys_obs(m)};
                            pdtrt = predicted{keys_pdt(n)};
                            obsrtp4 = [obsrt(1:2) + [0, 0]; ...         % left top
                                       obsrt(1:2) + [0, obsrt(4)]; ...  % left bottom
                                       obsrt(1:2) + [obsrt(3),0]; ...   % right top
                                       obsrt(1:2) + obsrt(3:4)];        % right bottom
                            pdtrtp4 = [pdtrt(1:2) + [0, 0]; ...
                                       pdtrt(1:2) + [0, pdtrt(4)]; ...
                                       pdtrt(1:2) + [pdtrt(3),0]; ...
                                       pdtrt(1:2) + pdtrt(3:4)];

                            switch dist
                                case "Euclidean"
                                    D = pdist2(obsrtp4, pdtrtp4, "euclidean");
                                case "Manhattan"
                                    D = pdist2(obsrtp4, pdtrtp4, "cityblock");
                                otherwise
                                    throw(MException("ObjectMatcher:invalidDistance", ...
                                        "Only Euclidean and Manhattan distance are supported."));
                            end

                            CostMat(m, n) = min(D, [], "all");  % Minimum Distance
                        end
                    end

                    DistMax = inf;
                case "CornerMax"
                    CostMat = inf(observed.numEntries, predicted.numEntries);

                    for m = 1:observed.numEntries
                        for n = 1:predicted.numEntries
                            obsrt = observed{keys_obs(m)};
                            pdtrt = predicted{keys_pdt(n)};
                            obsrtp4 = [obsrt(1:2) + [0, 0]; ...         % left top
                                obsrt(1:2) + [0, obsrt(4)]; ...  % left bottom
                                obsrt(1:2) + [obsrt(3),0]; ...   % right top
                                obsrt(1:2) + obsrt(3:4)];        % right bottom
                            pdtrtp4 = [pdtrt(1:2) + [0, 0]; ...
                                pdtrt(1:2) + [0, pdtrt(4)]; ...
                                pdtrt(1:2) + [pdtrt(3),0]; ...
                                pdtrt(1:2) + pdtrt(3:4)];

                            switch dist
                                case "Euclidean"
                                    D = pdist2(obsrtp4, pdtrtp4, "euclidean");
                                case "Manhattan"
                                    D = pdist2(obsrtp4, pdtrtp4, "cityblock");
                                otherwise
                                    throw(MException("ObjectMatcher:invalidDistance", ...
                                        "Only Euclidean and Manhattan distance are supported."));
                            end

                            CostMat(m, n) = max(D, [], "all");  % Minimum Euclidean Distance
                        end
                    end

                    DistMax = inf;
                otherwise
                    throw(MException("ObjectMatcher:invalidCost", ...
                        "Only 'Average', 'Jaccard', 'Min' and 'Max' are supported cost."));
            end
        end
    end
end

