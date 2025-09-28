% ANALYZE_LASER_TEMPERATURE Compute 6 mm vs 10 mm laser differences across temperatures.
%
%   This script scans all platform test CSV files in the current folder,
%   calculates the mean laser reading difference between the 6 mm and 10 mm
%   calibration blocks for each laser channel, and fits a linear trend with
%   respect to the mean temperature of each dataset.
%
%   The reusable logic for computing the differences lives in the helper
%   function COMPUTE_LASER_LEVEL_DIFFERENCE.

% Configuration
lowLevel = 6;
highLevel = 10;
channelNames = ["laser0", "laser1", "laser2"];
filePattern = 'platformtest_*C.csv';

% Discover relevant CSV files (ignore backups ending with .bck)
files = dir(filePattern);
files = files(~contains({files.name}, '.bck'));
if isempty(files)
    error('analyze_laser_temperature:NoFiles', ...
          'No CSV files matching %s were found.', filePattern);
end

% Preallocate results container
nFiles = numel(files);
results = table('Size', [nFiles, 5], ...
                'VariableTypes', {'string', 'double', 'double', 'double', 'double'}, ...
                'VariableNames', {'filename', 'temperature', 'laser0_diff', 'laser1_diff', 'laser2_diff'});

for idx = 1:nFiles
    fileName = files(idx).name;
    tbl = readtable(fileName);

    diffs = compute_laser_level_difference(tbl, lowLevel, highLevel, channelNames);
    meanTemperature = mean(tbl.temperature, 'omitnan');

    results.filename(idx) = string(fileName);
    results.temperature(idx) = meanTemperature;
    for chIdx = 1:numel(channelNames)
        columnName = char(channelNames(chIdx) + "_diff");
        results.(columnName)(idx) = diffs(chIdx);
    end
end

% Sort by temperature for easier interpretation
results = sortrows(results, 'temperature');

% Display numeric results
disp('Laser difference (6 mm - 10 mm) versus temperature:');
disp(results);

% Fit and print linear models for each channel
fprintf('Linear fits (difference = slope * temperature + intercept):\n');
coefficients = struct();
for chIdx = 1:numel(channelNames)
    columnName = char(channelNames(chIdx) + "_diff");
    y = results.(columnName);
    x = results.temperature;
    p = polyfit(x, y, 1);
    coefficients.(columnName) = p;
    fprintf('  %s: slope = %.6f mm/°C, intercept = %.6f mm\n', columnName, p(1), p(2));
end

% Plot differences vs temperature
figure('Name', 'Laser difference vs temperature', 'NumberTitle', 'off');
hold on;
colors = lines(numel(channelNames));
for chIdx = 1:numel(channelNames)
    columnName = char(channelNames(chIdx) + "_diff");
    plot(results.temperature, results.(columnName), 'o-', 'Color', colors(chIdx,:), ...
         'DisplayName', sprintf('%s difference', channelNames(chIdx)));
end
xlabel('Temperature (°C)');
ylabel('Laser reading difference (6 mm - 10 mm) [mm]');
grid on;
legend('Location', 'best');
title('Laser channel differences between 6 mm and 10 mm blocks');

% Store the coefficients in the base workspace for further analysis if needed
assignin('base', 'laser_difference_results', results);
assignin('base', 'laser_difference_coefficients', coefficients);
