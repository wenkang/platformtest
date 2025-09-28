function differences = compute_laser_level_difference(tbl, lowLevel, highLevel, channelNames)
%COMPUTE_LASER_LEVEL_DIFFERENCE Calculate mean reading differences between two levels.
%   DIFFERENCES = COMPUTE_LASER_LEVEL_DIFFERENCE(TBL, LOWLEVEL, HIGHLEVEL, CHANNELNAMES)
%   returns the mean reading at LOWLEVEL minus the mean reading at HIGHLEVEL
%   for each channel listed in CHANNELNAMES.
%
%   TBL           : MATLAB table that contains at least the variables
%                   'test_level' and every entry in CHANNELNAMES.
%   LOWLEVEL      : Numeric scalar representing the lower test level (e.g. 6).
%   HIGHLEVEL     : Numeric scalar representing the higher test level (e.g. 10).
%   CHANNELNAMES  : String array or cell array of character vectors containing
%                   the names of the laser channels to analyse.
%
%   The function validates that data is available for both levels and throws
%   an error when one of the levels is missing from the table.
%
%   Example
%       tbl = readtable('platformtest_29-60C.csv');
%       channelNames = ["laser0", "laser1", "laser2"];
%       differences = compute_laser_level_difference(tbl, 6, 10, channelNames);
%
%   See also READTABLE.

    arguments
        tbl table
        lowLevel (1,1) double
        highLevel (1,1) double
        channelNames {validateChannelNames(channelNames)}
    end

    % Ensure channelNames is a string row vector for consistent indexing
    if iscell(channelNames)
        channelNames = string(channelNames);
    else
        channelNames = channelNames(:)';
    end

    validateRequiredColumns(tbl, channelNames);

    % Extract rows for the requested levels
    lowMask = tbl.test_level == lowLevel;
    highMask = tbl.test_level == highLevel;

    if ~any(lowMask)
        error('compute_laser_level_difference:MissingLevel', ...
              'No observations found for level %.3f.', lowLevel);
    end

    if ~any(highMask)
        error('compute_laser_level_difference:MissingLevel', ...
              'No observations found for level %.3f.', highLevel);
    end

    lowValues = table2array(tbl(lowMask, channelNames));
    highValues = table2array(tbl(highMask, channelNames));

    lowMeans = mean(lowValues, 1, 'omitnan');
    highMeans = mean(highValues, 1, 'omitnan');

    differences = lowMeans - highMeans;
end

function validateRequiredColumns(tbl, channelNames)
    requiredColumns = ["test_level", channelNames];
    missing = setdiff(requiredColumns, string(tbl.Properties.VariableNames));
    if ~isempty(missing)
        error('compute_laser_level_difference:MissingColumns', ...
              'The table is missing required columns: %s', strjoin(missing, ', '));
    end
end

function validateChannelNames(value)
% Custom validator that accepts string/cellstr vectors.
    if ~(isstring(value) || iscellstr(value))
        error('compute_laser_level_difference:InvalidChannelNames', ...
              'Channel names must be provided as a string array or cell array of character vectors.');
    end
    if numel(value) == 0
        error('compute_laser_level_difference:EmptyChannelNames', ...
              'Channel names array must not be empty.');
    end
end
