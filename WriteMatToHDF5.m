
global datasetPaths;
datasetPaths = {};


matFilePath = 'C:\Users\aleja\Desktop\Workspace Backup\CombinationA\Workspace\DataManagerState_CombinationA_20240828_164820.mat';

hdf5FilePath = 'C:\Users\aleja\Desktop\HDF5_mat_Toy_Example\toy_example.h5';
% Load the MAT file
matData = load(matFilePath);

% Create or open the HDF5 file
if exist(hdf5FilePath, 'file')
    delete(hdf5FilePath); % Remove existing file
end

% Generate and write maps
writeMapsToHdf5(hdf5FilePath, matData);

% Write metadata
h5create(hdf5FilePath, '/metadata/filename', [1 1], 'Datatype', 'string');
h5write(hdf5FilePath, '/metadata/filename', string(matFilePath));

varNames = fieldnames(matData);

% Initialize list for char variables
charVarNames = {};

% Write each variable to the HDF5 file
for i = 1:length(varNames)
    varName = varNames{i};
    varData = matData.(varName);
    
    % Check if the variable is a char and add to the list
    if ischar(varData)
        charVarNames{end+1} = varName;
    end
    
    try
        createAndWriteData(hdf5FilePath, ['/' varName], varData, i);
    catch ME
        warning('Failed to write variable %s: %s', varName, ME.message);
    end
end

% Write the list of char variable names
h5create(hdf5FilePath, '/metadata/char_variables', [1 1], 'Datatype', 'string');
h5write(hdf5FilePath, '/metadata/char_variables', join(string(charVarNames), ','));



function createDataset(filePath, datasetPath, data, index)
    if isempty(data)
        h5create(filePath, [datasetPath '/isEmpty'], [1], 'Datatype', 'uint8');
        h5write(filePath, [datasetPath '/isEmpty'], uint8(1));
    elseif isstruct(data)
        h5create(filePath, [datasetPath '/type'], [1], 'Datatype', 'string');
        h5write(filePath, [datasetPath '/type'], "struct");
        h5create(filePath, [datasetPath '/size'], [1 ndims(data)], 'Datatype', 'uint64');
        h5write(filePath, [datasetPath '/size'], uint64(size(data)));
    elseif ischar(data)
        if ismatrix(data) && size(data, 1) > 1
            h5create(filePath, datasetPath, size(data), 'Datatype', 'uint16');
        else
            h5create(filePath, datasetPath, [1 1], 'Datatype', 'string');
        end
    elseif isa(data, 'string')
        h5create(filePath, datasetPath, size(data), 'Datatype', 'string');
    elseif iscell(data)
        h5create(filePath, [datasetPath '/type'], [1], 'Datatype', 'string');
        h5write(filePath, [datasetPath '/type'], "cell");
        h5create(filePath, [datasetPath '/size'], [1 ndims(data)], 'Datatype', 'uint64');
        h5write(filePath, [datasetPath '/size'], uint64(size(data)));
    elseif isa(data, 'strel')
        h5create(filePath, [datasetPath '/type'], [1], 'Datatype', 'string');
        h5write(filePath, [datasetPath '/type'], "strel");
        h5create(filePath, [datasetPath '/Neighborhood'], size(data.Neighborhood), 'Datatype', 'uint8');
        h5write(filePath, [datasetPath '/Neighborhood'], uint8(data.Neighborhood));
        h5create(filePath, [datasetPath '/Dimensionality'], [1], 'Datatype', 'uint8');
        h5write(filePath, [datasetPath '/Dimensionality'], uint8(data.Dimensionality));
    elseif islogical(data)
        h5create(filePath, datasetPath, size(data), 'Datatype', 'uint8');
    elseif isnumeric(data)
        chunkSize = min(size(data), 1000); % Limit chunk size
        h5create(filePath, datasetPath, size(data), 'Datatype', class(data), 'ChunkSize', chunkSize, 'Deflate', 5);
    elseif isobject(data)
        warning('Skipping object of class %s at %s', class(data), datasetPath);
    else
        warning('Unsupported data type %s at %s', class(data), datasetPath);
    end
end

function writeData(filePath, datasetPath, data, index)
    global k
    k = k + 1;
    
    if isempty(data)
        % Already handled in createDataset
    elseif isstruct(data)
        fields = fieldnames(data);
        for i = 1:length(fields)
            fieldPath = [datasetPath '/' fields{i}];
            if numel(data) == 1
                fieldData = data.(fields{i});
            else
                fieldData = {data.(fields{i})};
            end
            createAndWriteData(filePath, fieldPath, fieldData, index);
        end
    elseif ischar(data)
        if ismatrix(data) && size(data, 1) > 1
            h5write(filePath, datasetPath, uint16(data));
        else
            h5write(filePath, datasetPath, string(data));
        end
    elseif isa(data, 'string')
        h5write(filePath, datasetPath, data);
    elseif iscell(data)
        for i = 1:numel(data)
            cellPath = [datasetPath '/cell_' num2str(i)];
            createAndWriteData(filePath, cellPath, data{i}, index);
        end
    elseif isa(data, 'strel')
        % Strel data is written in createDataset
    elseif islogical(data)
        h5write(filePath, datasetPath, uint8(data));
    elseif isnumeric(data)
        h5write(filePath, datasetPath, data);
    elseif isobject(data)
        % Objects are handled in createDataset (skipped with warning)
    else
        warning('Unsupported data type %s at %s', class(data), datasetPath);
    end
end











function mapContent = mapStructRecursive(s, level, path, currentDepth, maxDepth)
    global datasetPaths;
    mapContent = {};
    if currentDepth > maxDepth
        mapContent{end+1} = sprintf('%s[Max depth reached]', repmat('    ', 1, level));
        return;
    end

    fields = fieldnames(s);
    for i = 1:length(fields)
        fieldName = fields{i};
        datasetPath = [path '/' fieldName];
        mapContent{end+1} = sprintf('%sField: %s', repmat('    ', 1, level), fieldName);
        
        for j = 1:numel(s)
            value = s(j).(fieldName);
            elementPath = sprintf('%s/cell_%d', datasetPath, j);
            
            % Find the matching path in datasetPaths
            matchingPath = findMatchingPath(elementPath, datasetPaths);
            
            if isstruct(value)
                mapContent{end+1} = sprintf('%s    Element%d: (Struct) %s Nesting Level %d', repmat('    ', 1, level), j, matchingPath, currentDepth+1);
                mapContent = [mapContent, mapStructRecursive(value, level+2, matchingPath, currentDepth+1, maxDepth)];
            elseif iscell(value)
                mapContent = [mapContent, mapCell(value, level+1, matchingPath, currentDepth, maxDepth)];
            else
                mapContent = [mapContent, mapElement(value, j, level+1, matchingPath)];
            end
        end
        
        mapContent{end+1} = ''; % Add a blank line between fields
    end
end

function matchingPath = findMatchingPath(partialPath, allPaths)
    matchIndex = find(startsWith(allPaths, partialPath), 1, 'first');
    if ~isempty(matchIndex)
        matchingPath = allPaths{matchIndex};
    else
        matchingPath = partialPath; % Use the original path if no match found
    end
end

function mapContent = mapElement(value, elementNumber, level, datasetPath)
    global datasetPaths;
    matchingPath = findMatchingPath(datasetPath, datasetPaths);
    if isnumeric(value) || islogical(value)
        mapContent = {sprintf('%s    Element%d: (%s: %s) %s', repmat('    ', 1, level), elementNumber, class(value), mat2str(size(value)), matchingPath)};
    elseif ischar(value)
        mapContent = {sprintf('%s    Element%d: (char: %s) %s', repmat('    ', 1, level), elementNumber, mat2str(size(value)), matchingPath)};
    elseif iscell(value)
        mapContent = {sprintf('%s    Element%d: (cell: %s) %s', repmat('    ', 1, level), elementNumber, mat2str(size(value)), matchingPath)};
    else
        mapContent = {sprintf('%s    Element%d: (%s) %s', repmat('    ', 1, level), elementNumber, class(value), matchingPath)};
    end
end

function mapContent = mapCell(c, level, path, currentDepth, maxDepth)
    global datasetPaths;
    mapContent = {};
    matchingPath = findMatchingPath(path, datasetPaths);
    mapContent{end+1} = sprintf('%s%s (Cell: %s)', repmat('    ', 1, level), matchingPath, mat2str(size(c)));
    for i = 1:numel(c)
        value = c{i};
        elementPath = sprintf('%s/cell_%d', matchingPath, i);
        if isstruct(value)
            mapContent{end+1} = sprintf('%sElement%d: %s (Struct) Nesting Level %d', repmat('    ', 1, level+1), i, elementPath, currentDepth);
            mapContent = [mapContent, mapStructRecursive(value, level+2, elementPath, currentDepth+1, maxDepth)];
        else
            mapContent = [mapContent, mapElement(value, i, level+1, elementPath)];
        end
    end
end















function createAndWriteData(filePath, datasetPath, data, index)
    global datasetPaths;
    datasetPaths{end+1} = datasetPath;
    createDataset(filePath, datasetPath, data, index);
    writeData(filePath, datasetPath, data, index);
    
    % Update the map
    updateMap(datasetPath);
end
% Add a new function to update the map:
function updateMap(datasetPath)
    global mapContent;
    parts = strsplit(datasetPath, '/');
    currentPath = '';
    for i = 1:length(parts)
        currentPath = [currentPath '/' parts{i}];
        if ~any(strcmp(mapContent, currentPath))
            mapContent{end+1} = currentPath;
        end
    end
end
% Modify the mapStructRecursive function:

function mapContent = generateStructMap(structData, structName)
    MAX_DEPTH = 5; % Adjust this value as needed
    mapContent = {};
    mapContent{end+1} = sprintf('%s (Struct Array[1x%d]) Nesting Level 0', structName, numel(structData));
    mapContent = [mapContent, mapStructRecursive(structData, 1, ['/' structName], 1, MAX_DEPTH)];
end
function writeMapsToHdf5(hdf5FilePath, matData)
    mapNames = {};
    for varName = fieldnames(matData)'
        if isstruct(matData.(varName{1}))
            mapName = [varName{1} 'Map'];
            mapContent = generateStructMap(matData.(varName{1}), varName{1});
            
            % Write map to HDF5 file
            h5create(hdf5FilePath, ['/metadata/structure_maps/' mapName], size(mapContent), 'Datatype', 'string');
            h5write(hdf5FilePath, ['/metadata/structure_maps/' mapName], mapContent);
            
            % Write map to text file
            writeMapToTextFile(mapContent, [mapName '.txt']);
            
            mapNames{end+1} = mapName;
        end
    end
    
    % Write StructList
    h5create(hdf5FilePath, '/metadata/StructList', size(mapNames), 'Datatype', 'string');
    h5write(hdf5FilePath, '/metadata/StructList', mapNames);
end
function writeMapToTextFile(mapContent, fileName)
    fid = fopen(fileName, 'w');
    if fid == -1
        error('Unable to create map file: %s', fileName);
    end
    for i = 1:length(mapContent)
        fprintf(fid, '%s\n', mapContent{i});
    end
    fclose(fid);
end
% Function to create dataset with proper chunking and compression
% Function to write data, handling empty cases
