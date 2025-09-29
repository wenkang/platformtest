%% analyze_laser_temperature2
% 计算激光读值与温度之间的统计关系，并给出温度补偿指标。
%
% 使用 index.json 中的索引依次读取所有 CSV 数据文件，汇总后输出以下
% 指标：
%   1. 每个批次(文件)对应的平均激光读值与批次温度。
%   2. 在每个 test_level 下，激光读值随温度的线性拟合斜率、截距以及
%      皮尔逊相关系数。
% 脚本执行完毕后将在工作区中生成 `results` 结构体，并打印关键结果。

%% 初始化
scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;
end
indexPath = fullfile(scriptDir, 'index.json');
if ~isfile(indexPath)
    error('索引文件 %s 不存在。', indexPath);
end

indexData = jsondecode(fileread(indexPath));
if isempty(indexData)
    error('索引文件 %s 为空。', indexPath);
end

laserVars = {'laser0', 'laser1', 'laser2'};
allData = table();

%% 读取并汇总所有批次数据
for iEntry = 1:numel(indexData)
    entry = indexData(iEntry);
    csvPath = fullfile(scriptDir, char(entry.filename));
    if ~isfile(csvPath)
        warning('跳过不存在的文件: %s', csvPath);
        continue;
    end

    batchTable = readtable(csvPath);

    if ~ismember('temperature', batchTable.Properties.VariableNames)
        batchTable.temperature = repmat(entry.temperature, height(batchTable), 1);
    else
        missingMask = isnan(batchTable.temperature);
        batchTable.temperature(missingMask) = entry.temperature;
    end

    batchTable.batchTemperature = repmat(entry.temperature, height(batchTable), 1);
    batchLabels = strings(height(batchTable), 1);
    batchLabels(:) = string(entry.filename);
    batchTable.batchFile = batchLabels;

    allData = [allData; batchTable]; %#ok<AGROW>
end

if isempty(allData)
    error('未从索引文件中加载到任何数据。');
end

%% 按批次计算平均激光读值
[batchGroup, batchNames] = findgroups(allData.batchFile);
batchMeanTemperature = splitapply(@mean, allData.batchTemperature, batchGroup);

batchMeans = table(string(batchNames), batchMeanTemperature, ...
    'VariableNames', {'BatchFile', 'BatchTemperature'});

for iLaser = 1:numel(laserVars)
    varName = laserVars{iLaser};
    meanValues = splitapply(@mean, allData.(varName), batchGroup);
    batchMeans.(sprintf('%sMean', varName)) = meanValues;
end

%% 计算温度-激光线性拟合及相关系数
uniqueLevels = unique(allData.test_level);
fitResults = table('Size', [0, 5], ...
    'VariableTypes', {'double', 'string', 'double', 'double', 'double'}, ...
    'VariableNames', {'TestLevel', 'LaserChannel', 'Slope', 'Intercept', 'Correlation'});

for iLevel = 1:numel(uniqueLevels)
    level = uniqueLevels(iLevel);
    levelMask = allData.test_level == level;
    levelData = allData(levelMask, :);
    temps = levelData.temperature;

    for iLaser = 1:numel(laserVars)
        varName = laserVars{iLaser};
        readings = levelData.(varName);

        coeffs = polyfit(temps, readings, 1);
        slope = coeffs(1);
        intercept = coeffs(2);

        corrMatrix = corrcoef(temps, readings);
        corrValue = corrMatrix(1, 2);

        newRow = {level, string(varName), slope, intercept, corrValue};
        fitResults = [fitResults; newRow]; %#ok<AGROW>
    end
end

%% 整理输出结果
results = struct();
results.allData = allData;
results.batchMeans = sortrows(batchMeans, 'BatchTemperature');
results.temperatureFits = sortrows(fitResults, {'TestLevel', 'LaserChannel'});
results.laserVariables = laserVars;

%% 打印汇总
fprintf('\n===== 批次平均激光读值 =====\n');
disp(results.batchMeans);

fprintf('\n===== 温度线性拟合结果 =====\n');
disp(results.temperatureFits);

fprintf('\n已在工作区变量 results 中保存详细结果。\n');
