function results = temperature_compensation_analysis(dataDir, varargin)
%TEMPERATURE_COMPENSATION_ANALYSIS  Build thermal compensation models.
%   RESULTS = TEMPERATURE_COMPENSATION_ANALYSIS(DATADIR) loads all CSV files
%   in DATADIR whose names start with "platformtest_" and contain the
%   columns `test_level`, `temperature`, and one or more `laser*` channels.
%   It fits a stacked-material thermal expansion + sensor drift model for
%   each laser channel, reports the residual statistics, and (when no output
%   argument is requested) plots the fit.
%
%   The model assumes the measured displacement y can be decomposed into:
%       y = b(level)                                        ... height offset
%           + Sum_i (alpha_i * L_i(level) * (T - T_ref))    ... mechanics
%           + Sum_k c_k * (T - T_ref)^k                     ... sensor drift
%           + epsilon
%   where alpha_i are thermal expansion coefficients and L_i are the
%   effective path lengths of steel, zirconia, aluminium, etc.  The
%   mechanical term is linear in temperature, while the laser sensor drift
%   is represented by a polynomial of configurable order.
%
%   Optional name-value arguments:
%     'ReferenceTemperature'  Scalar reference temperature in °C.  Default: mean(T).
%     'SensorDriftOrder'      Non-negative integer polynomial order (default 2).
%     'ExpansionCoefficients' Struct with fields `steel`, `zirconia`, `aluminum`.
%                             Units: 1/°C. Default values (from materials data):
%                               steel    = 11.5e-6
%                               zirconia = 10.5e-6
%                               aluminum = 23e-6
%     'MaterialStack'         Struct describing path lengths in metres. Fields:
%                               steelFcn(level)  -> steel length (m), default level*1e-3
%                               zirconiaLength   -> 22e-3 (22 mm)
%                               aluminumLength   -> 0.052 (52 mm, adjustable)
%                             Any unspecified field defaults to zero contribution.
%
%   The function returns a struct with entries for each laser channel:
%     results.(channel).model           Fitted LinearModel object
%     results.(channel).residualStats   Table with RMS and peak residuals (in mm)
%     results.summary                   Overall table of residual metrics
%
%   Example:
%     results = temperature_compensation_analysis('.', ...
%         'ReferenceTemperature', 31.0, ...
%         'SensorDriftOrder', 3, ...
%         'MaterialStack', struct('aluminumLength', 0.06));
%

parser = inputParser;
parser.FunctionName = mfilename;
addRequired(parser, 'dataDir', @(x) ischar(x) || isstring(x));
addParameter(parser, 'ReferenceTemperature', [], @(x) isempty(x) || isscalar(x));
addParameter(parser, 'SensorDriftOrder', 2, @(x) isscalar(x) && x >= 0 && round(x) == x);
addParameter(parser, 'ExpansionCoefficients', struct(), @isstruct);
addParameter(parser, 'MaterialStack', struct(), @isstruct);
parse(parser, dataDir, varargin{:});
args = parser.Results;

% Default coefficients of thermal expansion (CTE) in 1/°C
defaultCTE = struct('steel', 11.5e-6, 'zirconia', 10.5e-6, 'aluminum', 23e-6);
cte = merge_struct(defaultCTE, args.ExpansionCoefficients);

% Default stack lengths in metres
defaultStack = struct( ...
    'steelFcn', @(level) level(:) * 1e-3, ... % interpret test_level as mm thickness
    'zirconiaLength', 22e-3, ...             % 22 mm zirconia clamp
    'aluminumLength', 0.0);                  % allow user to override
stack = merge_struct(defaultStack, args.MaterialStack);

% Collect data
files = dir(fullfile(dataDir, 'platformtest_*.csv'));
if isempty(files)
    error('No CSV files matching platformtest_*.csv found in %s', dataDir);
end

tbls = cell(numel(files), 1);
for k = 1:numel(files)
    tbls{k} = readtable(fullfile(files(k).folder, files(k).name));
end
data = vertcat(tbls{:});

requiredColumns = {'test_level', 'temperature'};
for c = requiredColumns
    if ~ismember(c{1}, data.Properties.VariableNames)
        error('Input data must contain column "%s".', c{1});
    end
end

laserColumns = startsWith(data.Properties.VariableNames, 'laser');
laserNames = data.Properties.VariableNames(laserColumns);
if isempty(laserNames)
    error('No laser* columns found in the data.');
end

data = sortrows(data, {'test_level', 'temperature'});

T = data.temperature;
if isempty(args.ReferenceTemperature)
    Tref = mean(T, 'omitnan');
else
    Tref = args.ReferenceTemperature;
end
deltaT = T - Tref;

level = data.test_level;
steelLength = stack.steelFcn(level);

zirconiaLength = fetch_stack_value(stack, 'zirconiaLength', level);
alLength = fetch_stack_value(stack, 'aluminumLength', level);

mechanicalSlope_mm_per_deg = ...
    steelLength * cte.steel * 1e3 + ...
    zirconiaLength * cte.zirconia * 1e3 + ...
    alLength * cte.aluminum * 1e3;

mechanicalDelta_mm = mechanicalSlope_mm_per_deg .* deltaT;

catLevel = categorical(level);

uniqueLevels = unique(level);
numFiles = numel(files);
numRows = height(data);
temperatureRange = [min(T, [], 'omitnan'), max(T, [], 'omitnan')];
levelTemperatureTable = groupsummary(table(level, T), 'level', {'mean', 'std'}, 'T');

results = struct();
results.dataOverview = struct( ...
    'numFiles', numFiles, ...
    'numRows', numRows, ...
    'temperatureMin', temperatureRange(1), ...
    'temperatureMax', temperatureRange(2), ...
    'testLevels', uniqueLevels, ...
    'levelTemperature', levelTemperatureTable);

% Prepare polynomial terms for sensor drift
polyOrder = args.SensorDriftOrder;
driftTerms = zeros(height(data), polyOrder);
for p = 1:polyOrder
    driftTerms(:, p) = deltaT.^p;
end

perLevelVarNames = {'Channel', 'Level_mm', 'TempCorrelation', 'Slope_mm_per_deg', 'MeanReading_mm'};
summaryRows = cell(0, 3);
correlationSummaryRows = cell(0, 3);
perLevelSummaryRows = cell(0, numel(perLevelVarNames));

for idx = 1:numel(laserNames)
    channel = laserNames{idx};
    y = data.(channel);

    tblModel = table(catLevel, mechanicalDelta_mm, 'VariableNames', {'Level', 'Mechanical'});
    for p = 1:polyOrder
        tblModel.(sprintf('Drift%d', p)) = driftTerms(:, p);
    end
    tblModel.Response = y;

    formulaTerms = ['-1 + Level + Mechanical'];
    for p = 1:polyOrder
        formulaTerms = sprintf('%s + Drift%d', formulaTerms, p);
    end

    mdl = fitlm(tblModel, sprintf('Response ~ %s', formulaTerms), ...
        'CategoricalVars', 'Level', 'DummyVarCoding', 'full');

    residuals = mdl.Residuals.Raw;
    rmsResidual = sqrt(mean(residuals.^2));
    peakResidual = max(abs(residuals));
    results.(channel).model = mdl;
    results.(channel).residualStats = table(rmsResidual, peakResidual, ...
        'VariableNames', {'RMS_mm', 'Peak_mm'});

    summaryRows(end+1, :) = {channel, rmsResidual, peakResidual};

    validAll = isfinite(T) & isfinite(y);
    if sum(validAll) >= 2
        overallCorrelation = corr(T(validAll), y(validAll));
        coeffsAll = polyfit(T(validAll), y(validAll), 1);
        overallSlope = coeffsAll(1);
    else
        overallCorrelation = NaN;
        overallSlope = NaN;
    end

    levelCorr = nan(numel(uniqueLevels), 1);
    levelSlope = nan(numel(uniqueLevels), 1);
    levelMean = nan(numel(uniqueLevels), 1);
    for lv = 1:numel(uniqueLevels)
        mask = level == uniqueLevels(lv);
        validMask = mask & isfinite(T) & isfinite(y);
        if sum(validMask) >= 2
            levelCorr(lv) = corr(T(validMask), y(validMask));
            coeffs = polyfit(T(validMask), y(validMask), 1);
            levelSlope(lv) = coeffs(1);
        end
        levelMean(lv) = mean(y(mask), 'omitnan');
    end

    perLevelTable = table(uniqueLevels, levelCorr, levelSlope, levelMean, ...
        'VariableNames', {'Level_mm', 'TempCorrelation', 'Slope_mm_per_deg', 'MeanReading_mm'});

    results.(channel).temperatureAnalysis = struct( ...
        'overallCorrelation', overallCorrelation, ...
        'overallSlope_mm_per_deg', overallSlope, ...
        'perLevel', perLevelTable);

    correlationSummaryRows(end+1, :) = {channel, overallCorrelation, overallSlope};

    channelColumn = repmat({channel}, height(perLevelTable), 1);
    perLevelSummaryRows = [perLevelSummaryRows; [channelColumn, table2cell(perLevelTable)]]; %#ok<AGROW>

    if nargout == 0
        figure('Name', sprintf('Channel %s', channel));
        subplot(2,1,1);
        plot(T, y, 'o'); hold on;
        plot(T, mdl.Fitted, '.-');
        xlabel('Temperature (°C)'); ylabel('Laser reading (mm)');
        title(sprintf('%s: Data vs Model', channel)); legend('Data', 'Model', 'Location', 'best');

        subplot(2,1,2);
        plot(T, residuals, 'o-'); yline(0, '--k');
        xlabel('Temperature (°C)'); ylabel('Residual (mm)');
        title(sprintf('%s: Residuals (RMS = %.4g mm)', channel, rmsResidual));
    end
end

results.summary = cell2table(summaryRows, 'VariableNames', {'Channel', 'RMS_mm', 'Peak_mm'});

if ~isempty(correlationSummaryRows)
    results.temperatureCorrelation = cell2table(correlationSummaryRows, ...
        'VariableNames', {'Channel', 'OverallCorrelation', 'OverallSlope_mm_per_deg'});
end

if ~isempty(perLevelSummaryRows)
    results.perLevelTemperature = cell2table(perLevelSummaryRows, ...
        'VariableNames', perLevelVarNames);
end

fprintf('\nThermal compensation summary (mm):\n');
disp(results.summary);

fprintf('Reference temperature: %.3f °C\n', Tref);
fprintf('Assumed mechanical slope: %.4g mm/°C\n', mean(mechanicalSlope_mm_per_deg, 'omitnan'));

fprintf('Data overview: %d rows from %d files spanning %.3f–%.3f °C.\n', ...
    numRows, numFiles, temperatureRange(1), temperatureRange(2));
levelLabels = arrayfun(@(x) sprintf('%.0f', x), uniqueLevels, 'UniformOutput', false);
fprintf('Test levels present: %s mm\n', strjoin(levelLabels, ', '));

if isfield(results, 'temperatureCorrelation')
    fprintf('\nRaw temperature vs. laser correlation (all levels combined):\n');
    disp(results.temperatureCorrelation);
end

if isfield(results, 'perLevelTemperature')
    fprintf('Per-level temperature slopes (mm/°C):\n');
    disp(results.perLevelTemperature);
end

if nargout == 0
    clear results;
end

end

function merged = merge_struct(base, override)
merged = base;
fields = fieldnames(override);
for k = 1:numel(fields)
    merged.(fields{k}) = override.(fields{k});
end
end

function values = fetch_stack_value(stack, fieldName, level)
if isfield(stack, fieldName)
    val = stack.(fieldName);
    if isa(val, 'function_handle')
        values = val(level);
    elseif isscalar(val)
        values = repmat(val, numel(level), 1);
    elseif numel(val) == numel(level)
        values = val(:);
    else
        error('Field %s must be scalar or length %d.', fieldName, numel(level));
    end
else
    values = zeros(numel(level), 1);
end
end
