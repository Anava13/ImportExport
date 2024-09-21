%Works perfectly for every struct except nested structs
clear
clc

% Specify the path to your HDF5 file
hdf5FilePath = 'C:\Users\aleja\Desktop\HDF5_mat_Toy_Example\toy_example.h5';

% Call the function to recreate all structures
recreateAllStructuresFromMap(hdf5FilePath);


hdf5FilePath = 'C:\Users\aleja\Desktop\HDF5_mat_Toy_Example\toy_example.h5';

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
                recreateStructureFromMap(hdf5FilePath, structMap, structName);
            catch ME
                fprintf('Error processing struct %s: %s\n', structName, ME.message);
            end
        end

    catch ME
        fprintf('Error reading StructList: %s\n', ME.message);
    end
end


function recreateStructureFromMap(hdf5FilePath, structMap, structName)
    % Function to recreate a single structure from its map
    % Inputs: 
    %   hdf5FilePath - path to the HDF5 file
    %   structMap - the map of the structure
    %   structName - name of the structure

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
                % Extract field name
                [~, fieldName] = strtok(line, ':');
                currentField = strtrim(fieldName(2:end));
            elseif startsWith(line, '            Element')
                % Extract element number, data type, and path
                elementNum = str2double(regexp(line, 'Element(\d+):', 'tokens', 'once'));
                dataTypeMatch = regexp(line, '\((\w+):', 'tokens');
                if ~isempty(dataTypeMatch)
                    dataType = dataTypeMatch{1}{1};
                else
                    dataType = 'double';  % Default to double if not specified
                end
                path = regexp(line, '/\S+$', 'match', 'once');

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