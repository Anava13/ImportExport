%Works perfectly for every struct except nested structs
clear
clc

% Specify the path to your HDF5 file
hdf5FilePath = 'C:\Users\aleja\Desktop\HDF5_mat_Toy_Example\toy_example.h5';

% Call the function to recreate all structures
recreateAllStructuresFromMap(hdf5FilePath);


% Read the HDF5 file
fileInfo = h5info(hdf5FilePath);

% Read the StructList and reconstruct structs
structList = h5read(hdf5FilePath, '/metadata/StructList');



% Read the list of char variable names
charVarNames = {};
if h5exists(hdf5FilePath, '/metadata/char_variables')
    charVarNamesStr = h5read(hdf5FilePath, '/metadata/char_variables');
    charVarNames = strsplit(char(charVarNamesStr), ',');
end

% Process remaining datasets (those not part of reconstructed structs)
% Process remaining datasets (those not part of reconstructed structs)
for i = 1:length(fileInfo.Datasets)
    datasetName = fileInfo.Datasets(i).Name;
    if ~strcmp(datasetName, '/metadata') && ~startsWith(datasetName, '/metadata/')
        % Ensure datasetName starts with a slash for reading
        if ~startsWith(datasetName, '/')
            datasetName = ['/' datasetName];
        end
        
        % Remove leading slash for variable name
        varName = datasetName(2:end);
        
        if ~any(strcmp(varName, structList))
            try
                data = readData(hdf5FilePath, datasetName);
                assignin('base', varName, data);
            catch ME
                warning('Failed to read dataset %s: %s', datasetName, ME.message);
            end
        end
    end
end
% Convert string variables back to char if they were originally char
for i = 1:length(charVarNames)
    varName = charVarNames{i};
    if evalin('base', ['exist(''' varName ''', ''var'')'])
        data = evalin('base', varName);
        if isstring(data)
            assignin('base', varName, char(data));
        end
    end
end

disp('HDF5 file contents loaded into MATLAB workspace successfully.');

clear charVarNames
clear charVarNamesStr
clear data
clear datasetName
clear fileInfo
clear hdf5FilePath
clear i
clear structlist
clear varName


%% General Data Functions
function data = readDataFromHDF5(hdf5FilePath, dataPath, dataType, dataSize)
    try
        data = h5read(hdf5FilePath, dataPath);
        
        % Convert data type if necessary
        switch dataType
            case 'char'
                data = char(data);
            case 'string'
                data = string(data);
            case 'logical'
                data = logical(data);
            case 'strel'
                % Reconstruct strel object
                neighborhood = logical(h5read(hdf5FilePath, [dataPath '/Neighborhood']));
                data = strel('arbitrary', neighborhood);
            case 'matlab.graphics.primitive.Image'
                % For Image objects, we might need to store additional properties
                % Here we're just creating a placeholder
                data = matlab.graphics.primitive.Image;
        end
        
        % Reshape data if size information is available
        if ~isempty(dataSize)
            data = reshape(data, dataSize);
        end
    catch ME
        warning('Failed to read data at %s: %s', dataPath, ME.message);
        data = [];
    end
end
function [dataType, dataSize, dataPath] = parseLeafNodeInfo(info)
    parts = strsplit(info, ')');
    typeAndSize = strtrim(parts{1});
    if length(parts) > 1
        dataPath = strtrim(parts{end});
    else
        dataPath = '';
    end
    
    [dataType, sizeStr] = strtok(typeAndSize, ':');
    dataType = strtrim(dataType);
    if ~isempty(sizeStr)
        sizeStr = strtrim(sizeStr(2:end));
        dataSize = str2num(sizeStr(2:end-1));
    else
        dataSize = [];
    end
end
function data = readData(filePath, dataPath)
    try
        % Check if the dataset has a 'type' attribute
        if h5exists(filePath, [dataPath '/type'])
            dataType = h5read(filePath, [dataPath '/type']);
            switch dataType
                case "struct"
                    error('Struct data should be handled by reconstructStructFromMap');
                case "cell"
                    data = readCell(filePath, dataPath);
                case "char"
                    data = readChar(filePath, dataPath);
                case "string"
                    data = readString(filePath, dataPath);
                case "strel"
                    data = readStrel(filePath, dataPath);
                otherwise
                    data = h5read(filePath, dataPath);
            end
        elseif h5exists(filePath, [dataPath '/isEmpty'])
            data = [];
        else
            % Read the data directly
            data = h5read(filePath, dataPath);
            % Check if it's a char array or string
            if ischar(data)
                data = readChar(filePath, dataPath);
            elseif isstring(data)
                data = readString(filePath, dataPath);
            elseif islogical(data)
                data = logical(data);
            end
        end
    catch ME
        warning('Failed to read data at %s: %s', dataPath, ME.message);
        data = [];
    end
end
function data = readCell(filePath, dataPath)
    try
        sizeData = h5read(filePath, [dataPath '/size']);
        data = cell(sizeData);
        
        % Read each cell element
        for i = 1:prod(sizeData)
            cellPath = [dataPath '/cell_' num2str(i)];
            if h5exists(filePath, cellPath)
                data{i} = readData(filePath, cellPath);
            else
                warning('Missing cell element %d at %s', i, dataPath);
                data{i} = [];
            end
        end
        
        % Reshape the cell array if necessary
        if ~isequal(size(data), sizeData)
            data = reshape(data, sizeData);
        end
    catch ME
        warning('Failed to read cell array at %s: %s', dataPath, ME.message);
        data = {};
    end
end
function data = readChar(filePath, dataPath)
    try
        charData = h5read(filePath, dataPath);
        if isstring(charData)
            data = char(charData);
        elseif ischar(charData)
            data = charData;
        else
            data = char(charData);
        end
    catch ME
        warning('Failed to read char data at %s: %s', dataPath, ME.message);
        data = '';
    end
end
function data = readStrel(filePath, dataPath)
    try
        neighborhood = logical(h5read(filePath, [dataPath '/Neighborhood']));
        dimensionality = h5read(filePath, [dataPath '/Dimensionality']);
        data = strel('arbitrary', neighborhood);
        data.Dimensionality = dimensionality;
    catch ME
        warning('Failed to read strel data at %s: %s', dataPath, ME.message);
        data = strel('arbitrary', true(3));
    end
end
function data = readString(filePath, dataPath)
    try
        stringData = h5read(filePath, dataPath);
        if ischar(stringData)
            data = string(stringData);
        else
            data = stringData;
        end
    catch ME
        warning('Failed to read string data at %s: %s', dataPath, ME.message);
        data = "";
    end
end
function result = h5exists(filename, path)
    try
        h5info(filename, path);
        result = true;
    catch
        result = false;
    end
end
function name = removeLeadingSlash(name)
    if startsWith(name, '/')
        name = name(2:end);
    end
end




function recreateAllStructuresFromMap(hdf5FilePath)
    % Function to recreate all structures from an HDF5 file based on their maps
    % Input: hdf5FilePath - path to the HDF5 file

    try
        % Read the StructList from the HDF5 file
        structList = h5read(hdf5FilePath, '/metadata/StructList');

        % Check if the structList is not empty
        if isempty(structList)
            error('The struct list is empty.');
        end

        % Process each structure in the list
        for structIdx = 1:length(structList)
            structMapName = structList{structIdx};
            structName = erase(structMapName, 'Map');
            fprintf('Processing structure: %s\n', structName);

            % Find and process the map of the current struct
            structMapPath = ['/metadata/structure_maps/' structMapName];
            try
                structMap = h5read(hdf5FilePath, structMapPath);
                
                % Check if the struct is nested
              isNested = any(cellfun(@(x) contains(x, 'Nesting Level') && ~contains(x, 'Nesting Level 1') && ~contains(x, 'Nesting Level 2'), structMap));

                if isNested
                    fprintf('%s is a nested struct. Calling recreateNestedStruct...\n', structName);
                    recreateNestedStruct(hdf5FilePath, structMap, structName);
                else
                    fprintf('%s is a simple struct. Processing with existing method...\n', structName);
                    recreateSimpleStruct(hdf5FilePath, structMap, structName);
                end
            catch ME
                fprintf('Error processing struct %s: %s\n', structName, ME.message);
            end
        end

    catch ME
        fprintf('Error reading StructList: %s\n', ME.message);
    end
end
function recreateSimpleStruct(hdf5FilePath, structMap, structName)
   

    try
        % Extract array size from the first line of the map
        firstLine = structMap{1};
        arraySize = regexp(firstLine, '\[(\d+x\d+)\]', 'tokens');
        if ~isempty(arraySize)
            arraySize = str2num(strrep(arraySize{1}{1}, 'x', ','));
        else
            arraySize = [1 1];  % Default to scalar if no size specified
        end

        % Initialize the structure array
        Structure = repmat(struct(), arraySize);

        % Process each line in the structMap
        currentField = '';
        for i = 2:length(structMap)  % Start from 2 to skip the first line
            line = structMap{i};
            if startsWith(line, '    Field:')
                % Extract field name and ignore nesting level
                [~, fieldInfo] = strtok(line, ':');
                fieldParts = strsplit(strtrim(fieldInfo(2:end)), ' ');
                currentField = fieldParts{1};  % Take only the field name, ignore nesting level
            elseif startsWith(line, '            Element')
                % Extract element number, data type, and path
                elementNum = str2double(regexp(line, 'Element(\d+):', 'tokens', 'once'));
                dataTypeMatch = regexp(line, '\((\w+):', 'tokens');
                if ~isempty(dataTypeMatch)
                    dataType = dataTypeMatch{1}{1};
                else
                    dataType = 'double';  % Default to double if not specified
                end
                
                % Extract path, ignoring the Nesting Level information
                pathMatch = regexp(line, '(/\S+)', 'tokens', 'once');
                if ~isempty(pathMatch)
                    path = pathMatch{1};
                else
                    warning('Path not found in line: %s', line);
                    continue;
                end

                % Try to read data from HDF5 file
                try
                    data = h5read(hdf5FilePath, path);
                    
                    % Handle different data types
                    switch dataType
                        case 'uint8'
                            % For uint8, assume it's an image and keep as is
                        case 'double'
                            % Ensure data is a column vector for double type
                            if size(data, 2) > 1 && size(data, 1) == 1
                                data = data';
                            end
                        otherwise
                            % For other types, convert to double
                            data = double(data);
                    end
                catch ME
                    warning('Error reading path %s: %s. Using empty array.', path, ME.message);
                    data = [];
                end

                % Store data in the appropriate element and field of the structure
                Structure(elementNum).(currentField) = data;
            end
        end

        % Assign the recreated structure to the base workspace
        assignin('base', structName, Structure);
        fprintf('Structure "%s" has been recreated and assigned to the base workspace.\n', structName);
    catch ME
        fprintf('Error recreating structure %s: %s\n', structName, ME.message);
    end
end







function recreateNestedStruct(hdf5FilePath, structMap, structName)
 
% Create the Level 1 Struct
createInitialStruct(structMap);
PopulateLevel1LeafNodes(hdf5FilePath, structMap);


% Create the Level 2 Struct
createAndPopulateLevel2Structs(structMap);
PopulateLevel2LeafNodes(hdf5FilePath, structMap);

% Create the Level 3 struct
createAndPopulateLevel3Structs(structMap);
PopulateLevel3LeafNodes(hdf5FilePath, structMap);

% Create the Level 4 struct
createAndPopulateLevel4Structs(structMap);
PopulateLevel4LeafNodes(hdf5FilePath, structMap);
end



%% Level 1 Struct
function structMap = readStructMapFromHDF5(hdf5FilePath)
    % Read the StructList
    structList = h5read(hdf5FilePath, '/metadata/StructList');
    
    % Find the map for LoadedProjects
    for i = 1:length(structList)
        structMapName = structList{i};
        if strcmp(structMapName, 'LoadedProjectsMap')
            structMapPath = ['/metadata/structure_maps/' structMapName];
            structMap = h5read(hdf5FilePath, structMapPath);
            return;
        end
    end
    error('LoadedProjectsMap not found in the HDF5 file');
end
function createInitialStruct(structMap)
    % Extract struct name and dimensions from the first line
    firstLine = structMap{1};
    [structName, dimensions] = extractStructInfo(firstLine);
    
    % Initialize the struct array
    structArray = repmat(struct(), dimensions);
    
    % Populate fields (at this stage, just creating empty placeholders)
    for i = 2:numel(structMap)
        line = structMap{i};
        if startsWith(line, '    Field: ')
            [fieldName, nestingLevel] = extractFieldInfo(line);
            if nestingLevel == 1
                % For level 1 fields, initialize with empty array
                [structArray.(fieldName)] = deal([]);
            elseif nestingLevel == 2
                % For level 2 fields, initialize with empty struct
                [structArray.(fieldName)] = deal(struct());
            end
        end
    end
    
    % Assign the struct array to a variable with the correct name in the base workspace
    assignin('base', structName, structArray);
end
function [structName, dimensions] = extractStructInfo(line)
    parts = strsplit(line);
    structName = parts{1};
    dimStr = regexp(line, '\[([^\]]+)\]', 'tokens');
    if ~isempty(dimStr)
        dimParts = strsplit(dimStr{1}{1}, 'x');
        if length(dimParts) == 2
            dimensions = [str2double(dimParts{1}), str2double(dimParts{2})];
        else
            dimensions = [1, 1]; % Default to scalar if parsing fails
        end
    else
        dimensions = [1, 1]; % Default to scalar if no dimensions found
    end
end

%% Level 1 Leaf Nodes
function PopulateLevel1LeafNodes(hdf5FilePath, structMap)
    % Extract struct name from the first line of structMap
    firstLine = structMap{1};
    structName = strtok(firstLine);
    
    % Get the struct from the base workspace
    structData = evalin('base', structName);
    
    % Extract field names and paths
    fields = {};
    paths = {};
    currentField = '';
    currentNestingLevel = 1;
    for i = 2:numel(structMap)
        line = structMap{i};
        if startsWith(line, '    Field: ')
            [currentField, currentNestingLevel] = extractFieldInfo(line);
        elseif startsWith(line, '            Element')
            [elementNum, path, nestingLevel] = extractElementInfo(line);
            if currentNestingLevel == 1
                fields{end+1} = currentField;
                paths{end+1} = path;
            end
        end
    end
    
    % Read and populate data for each element
    for i = 1:length(paths)
        try
            data = h5read(hdf5FilePath, paths{i});
            [fieldName, elementNum] = parseFieldAndElement(fields{i}, paths{i});
            structData(elementNum).(fieldName) = data;
        catch ME
            warning('Failed to read data for %s, Element%d: %s', fields{i}, elementNum, ME.message);
        end
    end
    
    % Assign the updated struct back to the base workspace
    assignin('base', structName, structData);
end
function [fieldName, nestingLevel] = extractFieldInfo(line)
    parts = strsplit(strtrim(line(length('    Field: ') + 1:end)));
    fieldName = parts{1};
    nestingLevel = str2double(regexp(line, 'Nesting Level (\d+)', 'tokens', 'once'));
    if isempty(nestingLevel)
        nestingLevel = 1; % Default to level 1 if not specified
    end
end
function [elementNum, path, nestingLevel] = extractElementInfo(line)
    elementNum = str2double(regexp(line, 'Element(\d+):', 'tokens', 'once'));
    pathMatch = regexp(line, '(/\S+)', 'tokens', 'once');
    if ~isempty(pathMatch)
        path = pathMatch{1};
    else
        path = '';
    end
    nestingLevel = str2double(regexp(line, 'Nesting Level (\d+)', 'tokens', 'once'));
    if isempty(nestingLevel)
        nestingLevel = 1; % Default to level 1 if not specified
    end
end
function [fieldName, elementNum] = parseFieldAndElement(field, path)
    fieldName = strtok(field); % Remove "Nesting Level X" from field name
    pathParts = strsplit(path, '/');
    elementNum = str2double(regexp(pathParts{end}, 'cell_(\d+)', 'tokens', 'once'));
end

%% Level 2 Structs
function createAndPopulateLevel2Structs(structMap)
    [structName, mainStruct] = extractMainStructInfo(structMap);
    fieldNames = fieldnames(mainStruct);
   
    
    for i = 1:numel(fieldNames)
        fieldName = fieldNames{i};
       
        level2Line = findLevel2Line(structMap, fieldName);
        if isempty(level2Line)
           
            continue;
        end
        
        [rows, cols, fieldCount] = extractLevel2Dimensions(level2Line, fieldName);
        if isempty(rows)
            continue;
        end
        
        level2Struct = createLevel2Struct(structMap, level2Line, fieldCount);
        
        mainStruct = assignLevel2StructToMain(mainStruct, fieldName, level2Struct);
    end
    
    finalizeAndDisplay(structName, mainStruct);
end
function [structName, mainStruct] = extractMainStructInfo(structMap)
    firstLine = structMap{1};
    structName = strtok(firstLine);

    
    mainStruct = evalin('base', structName);

end
function level2Line = findLevel2Line(structMap, fieldName)
    level2Line = '';
    for j = 1:numel(structMap)
        if contains(structMap{j}, [fieldName '/cell_']) && contains(structMap{j}, 'Nesting Level 2')
            level2Line = structMap{j};

            break;
        end
    end
end
function [rows, cols, fieldCount] = extractLevel2Dimensions(level2Line, fieldName)
    dimMatch = regexp(level2Line, 'Struct\[(\d+)x(\d+)\]<(\d+)>', 'tokens');
    if isempty(dimMatch)
        warning('Could not parse struct dimensions and field count for: %s', fieldName);
        rows = []; cols = []; fieldCount = [];
    else
        rows = str2double(dimMatch{1}{1});
        cols = str2double(dimMatch{1}{2});
        fieldCount = str2double(dimMatch{1}{3});

    end
end
function level2Struct = createLevel2Struct(structMap, level2Line, fieldCount)
    level2Struct = struct();
    fieldStart = find(strcmp(structMap, level2Line)) + 1;

    
    k = fieldStart;
    while k <= numel(structMap)
        line = structMap{k};
        if contains(line, 'Field:') && contains(line, 'Nesting Level 2')
            [level2Struct, k] = processLevel2Field(structMap, k, level2Struct);
        elseif contains(line, 'Nesting Level 1') || ...
               (contains(line, 'Nesting Level 2') && ~contains(line, 'Field:'))
   
            break;
        else
            % Move to the next line if it's not a new Level 2 field or the end
            k = k + 1;
        end
    end
    
    verifyFieldCount(level2Struct, fieldCount);
end
function [level2Struct, k] = processLevel2Field(structMap, k, level2Struct)
    line = structMap{k};
    fieldNameMatch = regexp(line, 'Field: (\w+)', 'tokens');
    if ~isempty(fieldNameMatch)
        newFieldName = fieldNameMatch{1}{1};
        
        % Create a new empty field in level2Struct
        level2Struct.(newFieldName) = [];

        
        % Move to the next line
        k = k + 1;
    end
end
function verifyFieldCount(level2Struct, fieldCount)
    actualFieldCount = numel(fieldnames(level2Struct));

    if actualFieldCount ~= fieldCount
        warning('Expected %d fields but found %d for struct', fieldCount, actualFieldCount);
    end
end
function mainStruct = assignLevel2StructToMain(mainStruct, fieldName, level2Struct)
    for j = 1:numel(mainStruct)
        mainStruct(j).(fieldName) = level2Struct;
    end

end
function finalizeAndDisplay(structName, mainStruct)
    assignin('base', structName, mainStruct);
    
end


%% Level 2 Leaf Nodes
function PopulateLevel2LeafNodes(hdf5FilePath, structMap)
    % Extract struct name from the first line of structMap
    firstLine = structMap{1};
    structName = strtok(firstLine);
    
    % Get the struct from the base workspace
    structData = evalin('base', structName);
    
  
    for i = 2:numel(structMap)
        line = strtrim(structMap{i});
        if startsWith(line, 'Element') && (contains(line, 'Nesting Level 2') || contains(line, 'Nesting Level 3'))
            [~, path, nestingLevel] = extractElementInfo3(line);
      
            try
                % Ensure path is a string
                if ~ischar(path) && ~isstring(path)
                    path = char(path);
                   
                end
                
              
              
                
                % Parse the path
               
                pathParts = strsplit(path, '/');
              
              

                % Try to find 'cell_X' in any part of the path
                cellPart = find(contains(pathParts, 'cell_'), 1);
                if ~isempty(cellPart)
                    mainStructIndex = str2double(regexp(pathParts{cellPart}, 'cell_(\d+)', 'tokens', 'once'));
                   
                else
                    error('Cannot find cell index in path');
                end

                level2Field = 'Data';  % This is always 'Data' in your structure
                level3Field = pathParts{end-1};  % The field before 'cell_1'
                
               
              
                
                % Remove '/cell_1' from the end
                trimmedPath = strjoin(pathParts(1:end-1), '/');
                
                % Read data from HDF5 file
                [data, dataInfo] = safeHDF5Read(hdf5FilePath, trimmedPath);
                
                if ~isempty(data)
                  
                    
                    % Ensure the nested structure exists
                    if ~isfield(structData(mainStructIndex), 'Data')
                       
                        structData(mainStructIndex).Data = struct();
                    end
                    if ~isfield(structData(mainStructIndex).Data, level3Field)
                      
                        structData(mainStructIndex).Data.(level3Field) = [];
                    end
                    
                    % Assign the data
                   
                    structData(mainStructIndex).Data.(level3Field) = data;
                    
                   
                else
             
                end
            catch ME
              
               
            end
        else

        end
    end
    
    % Assign the updated struct back to the base workspace
    assignin('base', structName, structData);
   
end
function [elementNum, path, nestingLevel] = extractElementInfo3(line)
    elementNum = str2double(regexp(line, 'Element(\d+):', 'tokens', 'once'));
    pathMatch = regexp(line, '(/\S+)', 'tokens', 'once');
    if ~isempty(pathMatch)
        path = pathMatch{1};
    else
        path = '';
    end
    nestingLevel = str2double(regexp(line, 'Nesting Level (\d+)', 'tokens', 'once'));
    if isempty(nestingLevel)
        nestingLevel = 1; % Default to level 1 if not specified
    end

end
function [data, info] = safeHDF5Read(filePath, dataPath)
    try
        data = h5read(filePath, dataPath);
        info = 'Data read successfully';
    catch ME
        data = [];
        if strcmp(ME.identifier, 'MATLAB:imagesci:h5read:libraryError')
            info = h5info(filePath, dataPath);
            info = sprintf('HDF5 read failed. DataSet Info: Size=%s, Type=%s', mat2str(info.Dataspace.Size), info.Datatype.Class);
        else
            info = sprintf('Error: %s', ME.message);
        end
    end
end

%% Level 3 Structs
function level2Struct = processLevel3Structs(structMap, level2Struct, level2Line, parentPath)
    level2FieldNames = fieldnames(level2Struct);
    
    for i = 1:numel(level2FieldNames)
        level2FieldName = level2FieldNames{i};
        level3Line = findLevel3Line(structMap, level2Line, level2FieldName);
        
        if isempty(level3Line)
       
            continue;
        end
        
        [rows, cols, fieldCount] = extractLevel3Dimensions(level3Line, level2FieldName);
        if isempty(rows)
           
            continue;
        end
        
       
        currentPath = [parentPath, '.', level2FieldName];
        
        if isstruct(level2Struct.(level2FieldName))
        
            level3Struct = level2Struct.(level2FieldName);
        else
           
            level3Struct = repmat(struct(), rows, cols);  % Create struct array with correct dimensions
            if ~isempty(level2Struct.(level2FieldName))
                [level3Struct.Data] = deal(level2Struct.(level2FieldName));
              
            end
        end
        
        level3Struct = createLevel3Fields(structMap, level3Line, fieldCount, level3Struct, currentPath, rows, cols);
        
        level2Struct.(level2FieldName) = level3Struct;
    end
end
function level3Struct = createLevel3Fields(structMap, level3Line, fieldCount, level3Struct, currentPath, rows, cols)
    fieldStart = find(strcmp(structMap, level3Line)) + 1;
    
    k = fieldStart;
    while k <= numel(structMap)
        line = structMap{k};
        if contains(line, 'Field:') && contains(line, 'Nesting Level 3')
            [level3Struct, k] = processLevel3Field(structMap, k, level3Struct, currentPath, rows, cols);
        elseif contains(line, 'Nesting Level 2') || ...
               (contains(line, 'Nesting Level 3') && ~contains(line, 'Field:'))
            break;
        else
            k = k + 1;
        end
    end
    
    verifyFieldCount3(level3Struct, fieldCount, currentPath);
end
function [level3Struct, k] = processLevel3Field(structMap, k, level3Struct, currentPath, rows, cols)
    line = structMap{k};
    fieldNameMatch = regexp(line, 'Field: (\w+)', 'tokens');
    if ~isempty(fieldNameMatch)
        newFieldName = fieldNameMatch{1}{1};
        if ~isfield(level3Struct, newFieldName)
            [level3Struct(1:rows, 1:cols).(newFieldName)] = deal([]);
         
        else
           
        end
        k = k + 1;
    end
end
function verifyFieldCount3(struct, expectedCount, path)
    actualCount = numel(fieldnames(struct));
    if actualCount ~= expectedCount
       
    else
       
    end
  
end
function createAndPopulateLevel3Structs(structMap)
    [structName, mainStruct] = extractMainStructInfo(structMap);
    fieldNames = fieldnames(mainStruct);
    
  
    for i = 1:numel(fieldNames)
        fieldName = fieldNames{i};
        level2Line = findLevel2Line(structMap, fieldName);
        
        if isempty(level2Line)
           
            continue;
        end
        
        [rows, cols, fieldCount] = extractLevel2Dimensions(level2Line, fieldName);
        if isempty(rows)
            ;
            continue;
        end
        
       
        for j = 1:numel(mainStruct)
            level2Struct = mainStruct(j).(fieldName);
           
            level2Struct = processLevel3Structs(structMap, level2Struct, level2Line, [fieldName, '_', num2str(j)]);
            
            mainStruct(j).(fieldName) = level2Struct;
        end
    end
    
    finalizeAndDisplay(structName, mainStruct);
end
function level3Line = findLevel3Line(structMap, level2Line, level2FieldName)
    level3Line = '';
    startIdx = find(strcmp(structMap, level2Line));
    
    for j = startIdx:numel(structMap)
        if contains(structMap{j}, [level2FieldName '/']) && contains(structMap{j}, 'Nesting Level 3')
            level3Line = structMap{j};
            break;
        end
    end
end
function [rows, cols, fieldCount] = extractLevel3Dimensions(level3Line, fieldName)
    dimMatch = regexp(level3Line, 'Struct\[(\d+)x(\d+)\]<(\d+)>', 'tokens');
    if isempty(dimMatch)
        warning('Could not parse struct dimensions and field count for Level 3: %s', fieldName);
        rows = []; cols = []; fieldCount = [];
    else
        rows = str2double(dimMatch{1}{1});
        cols = str2double(dimMatch{1}{2});
        fieldCount = str2double(dimMatch{1}{3});
    end
end
function level3Struct = createLevel3Struct(structMap, level3Line, fieldCount)
    level3Struct = struct();
    fieldStart = find(strcmp(structMap, level3Line)) + 1;
    
    k = fieldStart;
    while k <= numel(structMap)
        line = structMap{k};
        if contains(line, 'Field:') && contains(line, 'Nesting Level 3')
            [level3Struct, k] = processLevel3Field(structMap, k, level3Struct);
        elseif contains(line, 'Nesting Level 2') || ...
               (contains(line, 'Nesting Level 3') && ~contains(line, 'Field:'))
            break;
        else
            k = k + 1;
        end
    end
    
    verifyFieldCount(level3Struct, fieldCount);
end



%% Level 3 Leaf Nodes
function PopulateLevel3LeafNodes(hdf5FilePath, structMap)
    % Extract struct name from the first line of structMap
    firstLine = structMap{1};
    structName = strtok(firstLine);
    
    % Get the struct from the base workspace
    structData = evalin('base', structName);
    
    % Initialize debug log
    debugLog = {};
    
      for i = 2:numel(structMap)
        line = strtrim(structMap{i});
        if startsWith(line, 'Element') && contains(line, 'Nesting Level 4')
            [elementNum, path, nestingLevel] = extractElementInfo4(line);
            
            debugLog{end+1} = sprintf('Leaf Node Found - Line %d: %s', i, line);
            debugLog{end+1} = sprintf('Original Path: %s', path);
            
            try
                % Split the path by '/'
                pathParts = strsplit(path, '/');
                
                % Extract the main struct and indices
                mainstruct = pathParts{2}; % 'LoadedProjects'
                mainIndex = str2double(regexp(pathParts{4}, '\d+', 'match', 'once'));
                level2Field = pathParts{3}; % 'Data'
                level3Field = pathParts{5}; % 'AllQuadrants'
                level3Index = str2double(regexp(pathParts{8}, '\d+', 'match', 'once'));
                level4Field = pathParts{7}; % 'WT', 'Dbf4_1', etc.
                
                structPosition = sprintf('%s(%d).%s.%s(%d).%s', mainstruct, mainIndex, level2Field, level3Field, level3Index, level4Field);
                debugLog{end+1} = sprintf('Structure Position: %s', structPosition);
                
                % Create the corrected read path
                readPath = strjoin([pathParts(1:5), pathParts(7:end)], '/');
                debugLog{end+1} = sprintf('Corrected Read Path: %s', readPath);
                
                % Read data from HDF5 file
                data = h5read(hdf5FilePath, readPath);
                debugLog{end+1} = sprintf('Data successfully read from HDF5 file. Size: %s', mat2str(size(data)));
                
                % Navigate to the correct position in the structure and assign data
                structData(mainIndex).(level2Field).(level3Field)(level3Index).(level4Field) = data;
                debugLog{end+1} = 'Data successfully assigned to structure';
                
                % Debug: Print information about the assigned data
                debugLog{end+1} = sprintf('Assigned data type: %s', class(structData(mainIndex).(level2Field).(level3Field)(level3Index).(level4Field)));
                debugLog{end+1} = sprintf('Assigned data size: %s', mat2str(size(structData(mainIndex).(level2Field).(level3Field)(level3Index).(level4Field))));
                
            catch ME
                debugLog{end+1} = sprintf('Error processing path %s: %s', path, ME.message);
                debugLog{end+1} = sprintf('Error occurred at: %s', ME.stack(1).name);
                debugLog{end+1} = sprintf('Line: %d', ME.stack(1).line);
                debugLog{end+1} = getReport(ME, 'extended', 'hyperlinks', 'off');
            end
            
            debugLog{end+1} = '------------------------';
        end
    end
    % Assign the updated struct back to the base workspace
    assignin('base', structName, structData);
    
    % Save debug log to file
    logFile = 'PopulateLevel3LeafNodes_DebugLog.txt';
    fid = fopen(logFile, 'w');
    if fid ~= -1
      
    else
    
    end
end
function [elementNum, path, nestingLevel] = extractElementInfo4(line)
    elementNum = str2double(regexp(line, 'Element(\d+):', 'tokens', 'once'));
    pathMatch = regexp(line, '(/\S+)', 'tokens', 'once');
    if ~isempty(pathMatch)
        path = pathMatch{1};
    else
        path = '';
    end
    nestingLevel = str2double(regexp(line, 'Nesting Level (\d+)', 'tokens', 'once'));
    if isempty(nestingLevel)
        nestingLevel = 1; % Default to level 1 if not specified
    end
end




%% Level 4 Structs
function createAndPopulateLevel4Structs(structMap)
    [structName, mainStruct] = extractMainStructInfo(structMap);
    debugLog = {};
    
    for i = 1:numel(structMap)
        line = strtrim(structMap{i});
        if contains(line, 'Nesting Level 4') && contains(line, 'Struct')
            [fieldCount, fieldNames, elementCount, path, location] = parseLevel4Struct(line, structMap, i);
            debugLog{end+1} = sprintf('Nesting Level 4 Struct Identified:');
            debugLog{end+1} = sprintf('Field count: %d', fieldCount);
            debugLog{end+1} = sprintf('Field names: %s', strjoin(fieldNames, ', '));
            debugLog{end+1} = sprintf('Number of elements: %d', elementCount);
            debugLog{end+1} = sprintf('Path: %s', path);
            debugLog{end+1} = sprintf('Location: %s', location);
            
            % Create and assign the new struct directly in the base workspace
            command = sprintf('%s = struct(''%s'', cell(1,1), ''%s'', cell(1,1));', location, fieldNames{1}, fieldNames{2});
           
            debugLog{end+1} = sprintf('Executing command: %s', command);
            try
                evalin('base', command);
                debugLog{end+1} = sprintf('Successfully created struct at: %s', location);
            catch ME
                debugLog{end+1} = sprintf('Unexpected error at %s: %s', location, ME.message);
            end
            
            debugLog{end+1} = '-----------------------------------';
        end
    end
    
    % Write debug log to file
    writeDebugLogToFile(debugLog);
    
    % Retrieve the updated struct from the base workspace
    mainStruct = evalin('base', structName);
    
    % Assign the updated struct back to the base workspace
    assignin('base', structName, mainStruct);
end
function [success, message] = navigateAndAssign(struct, location, newStruct)
    parts = strsplit(location, '.');
    current = struct;
    
    for i = 2:length(parts)-1  % Start from 2 to skip the base struct name
        [fieldName, index] = parseFieldNameAndIndex(parts{i});
        if ~isfield(current, fieldName)
            success = false;
            message = sprintf('Field "%s" does not exist at level %d', fieldName, i-1);
            return;
        end
        if index > 0
            if numel(current.(fieldName)) < index
                success = false;
                message = sprintf('Invalid index %d for field "%s" at level %d', index, fieldName, i-1);
                return;
            end
            current = current.(fieldName)(index);
        else
            current = current.(fieldName);
        end
    end
    
    % Assign the new struct directly to the Centers field
    lastPart = parts{end};
    [fieldName, ~] = parseFieldNameAndIndex(lastPart);
    current.(fieldName) = newStruct;
    
    success = true;
    message = 'Struct assigned successfully';
end
function [fieldName, index] = parseFieldNameAndIndex(fieldString)
    matches = regexp(fieldString, '(\w+)(?:\((\d+)\))?', 'tokens', 'once');
    if ~isempty(matches)
        fieldName = matches{1};
        if length(matches) > 1 && ~isempty(matches{2})
            index = str2double(matches{2});
        else
            index = 0;
        end
    else
        fieldName = fieldString;
        index = 0;
    end
end
function [fieldCount, fieldNames, elementCount, path, location] = parseLevel4Struct(line, structMap, lineIndex)
    % Extract field count
    fieldCountMatch = regexp(line, 'Struct\[(\d+)x(\d+)\]<(\d+)>', 'tokens');
    if ~isempty(fieldCountMatch)
        fieldCount = str2double(fieldCountMatch{1}{3});
    else
        fieldCount = 0;
    end
    
    % Extract element count
    elementCountMatch = regexp(line, 'Struct\[(\d+)x(\d+)\]', 'tokens');
    if ~isempty(elementCountMatch)
        elementCount = 1;  % It's always 1x1
    else
        elementCount = 1;
    end
    
    % Extract path
    pathMatch = regexp(line, '(/\S+)', 'tokens');
    if ~isempty(pathMatch)
        path = pathMatch{1}{1};
    else
        path = '';
    end
    
    % Calculate location
    location = calculateLocation(path);
    
    % Extract field names
    fieldNames = {};
    fieldsFound = 0;
    for j = lineIndex+1:numel(structMap)
        nextLine = strtrim(structMap{j});
        if contains(nextLine, 'Field:') && contains(nextLine, 'Nesting Level 4')
            fieldNameMatch = regexp(nextLine, 'Field: (\w+)', 'tokens');
            if ~isempty(fieldNameMatch)
                fieldNames{end+1} = fieldNameMatch{1}{1};
                fieldsFound = fieldsFound + 1;
                if fieldsFound == fieldCount
                    break;
                end
            end
        elseif contains(nextLine, 'Nesting Level 3') || ...
               (contains(nextLine, 'Nesting Level 4') && ~contains(nextLine, 'Field:'))
            break;
        end
    end
end
function location = calculateLocation(path)
    pathParts = string(strsplit(path, '/'));
    BaseStruct = pathParts(2);
    BaseField = pathParts(3);
    baseindex = string(strcat('(', regexp(pathParts{4}, '\d+', 'match'), ')'));
    SecondField = pathParts(5);
    ThirdField = pathParts(7);
    NestIndex = string(strcat('(', regexp(pathParts{8}, '\d+', 'match'), ')'));  % Changed from 6 to 8
    
    location = strcat(BaseStruct, baseindex, '.', BaseField, '.', SecondField, NestIndex, '.', ThirdField);
end
function writeDebugLogToFile(debugLog)
    fid = fopen('Level4StructsDebugLog.txt', 'w');
    if fid ~= -1
        for i = 1:numel(debugLog)
            fprintf(fid, '%s\n', debugLog{i});
        end
        fclose(fid);
    else
        warning('Unable to open file for writing debug log.');
    end
end
function [success, current, message] = navigateStructPart(current, part)
    if ~isfield(current, part.field)
        success = false;
        message = sprintf('Field "%s" does not exist', part.field);
        return;
    end
    
    if part.index > 0
        if ~isstruct(current.(part.field)) || numel(current.(part.field)) < part.index
            success = false;
            message = sprintf('Invalid index %d for field "%s". Current size: %s', ...
                              part.index, part.field, mat2str(size(current.(part.field))));
            return;
        end
        current = current.(part.field)(part.index);
    else
        current = current.(part.field);
    end
    
    if ~isstruct(current)
        success = false;
        message = sprintf('Expected struct at field "%s", but found %s', part.field, class(current));
        return;
    end
    
    success = true;
    message = '';
end
function parts = parseLocation(location)
    parts = {};
    segments = strsplit(location, '.');
    for i = 2:length(segments)  % Start from 2 to skip the base struct name
        [field, index] = parseFieldAndIndex(segments{i});
        parts{end+1} = struct('field', field, 'index', index);
    end
end
function [field, index] = parseFieldAndIndex(segment)
    match = regexp(segment, '(\w+)(?:\((\d+)\))?', 'tokens');
    if ~isempty(match)
        field = match{1}{1};
        if length(match{1}) > 1 && ~isempty(match{1}{2})
            index = str2double(match{1}{2});
        else
            index = 0;
        end
    else
        field = segment;
        index = 0;
    end
end



%% Level 4 Leaf Nodes
function PopulateLevel4LeafNodes(hdf5FilePath, structMap)
    % Extract struct name from the first line of structMap
    firstLine = structMap{1};
    structName = strtok(firstLine);
    
    % Get the struct from the base workspace
    structData = evalin('base', structName);
    
    % Initialize debug log
    debugLog = {};
    
    for i = 2:numel(structMap)
        line = strtrim(structMap{i});
        if startsWith(line, 'Element') && contains(line, 'Nesting Level 5')
            [elementNum, path, nestingLevel] = extractElementInfo5(line);
            
            debugLog{end+1} = sprintf('Leaf Node Found - Line %d: %s', i, line);
            debugLog{end+1} = sprintf('Original Path: %s', path);
            
            try
                % Split the path by '/'
                pathParts = string(strsplit(path, '/'));
                
                % Extract the main struct and indices
                mainstruct = pathParts(2); % 'LoadedProjects'
                mainIndex = str2double(regexp(pathParts(4), '\d+', 'match', 'once'));
                level2Field = pathParts(3); % 'Data'
                level3Field = pathParts(5); % 'AllQuadrants'
                level3Index = str2double(regexp(pathParts(8), '\d+', 'match', 'once'));
                level4Field = pathParts(7); % e.g., 'WT', 'Dbf4_1', etc.
                level5Field = pathParts(9); % New field at level 5
                
                structPosition = sprintf('%s(%d).%s.%s(%d).%s.%s', mainstruct, mainIndex, level2Field, level3Field, level3Index, level4Field, level5Field);
                debugLog{end+1} = sprintf('Structure Position: %s', structPosition);
                
                % Create the corrected read path
                pathParts([6, 10]) = []; % Remove the 6th and 10th parts
                readPath = strjoin(pathParts, '/');
                debugLog{end+1} = sprintf('Corrected Read Path: %s', readPath);
                
                % Read data from HDF5 file
                data = h5read(hdf5FilePath, readPath);
                debugLog{end+1} = sprintf('Data successfully read from HDF5 file. Size: %s', mat2str(size(data)));
                
                % Navigate to the correct position in the structure and assign data
                structData(mainIndex).(level2Field).(level3Field)(level3Index).(level4Field).(level5Field) = data;
                debugLog{end+1} = 'Data successfully assigned to structure';
                
                % Debug: Print information about the assigned data
                debugLog{end+1} = sprintf('Assigned data type: %s', class(structData(mainIndex).(level2Field).(level3Field)(level3Index).(level4Field).(level5Field)));
                debugLog{end+1} = sprintf('Assigned data size: %s', mat2str(size(structData(mainIndex).(level2Field).(level3Field)(level3Index).(level4Field).(level5Field))));
                
            catch ME
                debugLog{end+1} = sprintf('Error processing path %s: %s', path, ME.message);
                debugLog{end+1} = sprintf('Error occurred at: %s', ME.stack(1).name);
                debugLog{end+1} = sprintf('Line: %d', ME.stack(1).line);
                debugLog{end+1} = getReport(ME, 'extended', 'hyperlinks', 'off');
            end
            
            debugLog{end+1} = '------------------------';
        end
    end
    
    % Assign the updated struct back to the base workspace
    assignin('base', structName, structData);
    
    % Save debug log to file
    logFile = 'PopulateLevel4LeafNodes_DebugLog.txt';
    fid = fopen(logFile, 'w');
    if fid ~= -1
        fprintf(fid, '%s\n', strjoin(debugLog, '\n'));
        fclose(fid);
      
    else
        warning('Unable to open file for writing debug log.');
    end
end
function [elementNum, path, nestingLevel] = extractElementInfo5(line)
    elementNum = str2double(regexp(line, 'Element(\d+):', 'tokens', 'once'));
    pathMatch = regexp(line, '(/\S+)', 'tokens', 'once');
    if ~isempty(pathMatch)
        path = pathMatch{1};
    else
        path = '';
    end
    nestingLevel = str2double(regexp(line, 'Nesting Level (\d+)', 'tokens', 'once'));
    if isempty(nestingLevel)
        nestingLevel = 1; % Default to level 1 if not specified
    end
end


