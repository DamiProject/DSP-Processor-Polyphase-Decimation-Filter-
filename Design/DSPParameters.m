classdef DSPParameters < handle & matlab.mixin.CustomDisplay
    %% =============================================
    %% CONTAINER OF META OBJECTS FOR ADC PARAMETERS
    %% ==============================================
    properties (SetAccess = private)
        Params struct
    end

    methods
        %% ==================================================
        %% Constructor of the Meta Objects For ADC Parameters
        %% ==================================================
        function obj = DSPParameters()
            Schema = obj.GetSchema();
            obj.Params = struct();

            for k = 1:numel(Schema)
                S = Schema{k}; 

                if isfield(S, 'Unit') && ~isempty(S.Unit) && ...
                    ~ismissing(S.Unit) && S.Unit ~= ""
                    obj.Params.(S.Key) = DSPMeta( ...
                        S.Name, ...
                        S.Validator, ...
                        S.DataType, ...
                        S.Unit);
                else
                    obj.Params.(S.Key) = DSPMeta( ...
                        S.Name, ...
                        S.Validator, ...
                        S.DataType);
                end
            end
        end
        %% Retrieves The Stored Value Of A Parameter Using Its Key
        function value = getValue(obj,key)

            key = char(key);

            if ~isfield(obj.Params,key)
                error('Parameters:UnknownKey', ...
                    'Parameter "%s" does not exist.', key);
            end

            value = obj.Params.(key).Value;
        end
        
        %% Assigns A New Value To A Parameter Using Its Key
        function setValue(obj,key,val)

            key = char(key);

            if ~isfield(obj.Params,key)
                error('Parameters:UnknownKey', ...
                    'Parameter "%s" does not exist.', key);
            end

            obj.Params.(key).Value = val;
        end
        %% Retrieves The Metadata Associated With A Parameter Key
        function metaObj = getDSPMeta(obj,key)

            key = char(key);

            if ~isfield(obj.Params,key)
                error('Parameters:UnknownKey', ...
                    'Parameter "%s" does not exist.', key);
            end

            metaObj = obj.Params.(key);
        end
   
        %% User Input Request
        function PromptUser(obj)
            names = fieldnames(obj.Params);
            for k = 1:numel(names)
                param = obj.Params.(names{k});
                while true
                    try
                        if isprop(param, 'Unit') && ...
                            ~ismissing(param.Unit) && param.Unit ~= ""
                            promptStr = sprintf("Enter %s (%s): ", ...
                                param.Name, param.Unit);
                        else
                            promptStr = sprintf("Enter %s: ", param.Name);
                        end
                        
                        value = input(promptStr);
                        param.Value = value;
                        break
                    catch ME
                        fprintf(2, "Error: %s\n", ME.message);
                    end
                end
            end
        end
    end

    %% =============================================
    %% CUSTOM DISPLAY PATTERNS IN THE COMMAND WINDOW
    %% =============================================
    methods (Access = protected)
        function displayScalarObject(obj)
            %% Print the default class header line
            header = getHeader(obj);
            disp(header);
            
            %% Extract keys and preallocate data arrays for table display
            keys = fieldnames(obj.Params);
            nParams = numel(keys);
            
            Names = strings(nParams, 1);
            Values = zeros(nParams, 1); 
            DataTypes = strings(nParams, 1);
            Units = strings(nParams, 1);
            
            for k = 1:nParams
                metaObj = obj.Params.(keys{k});
                Names(k) = metaObj.Name;
                Values(k) = double(metaObj.Value);     
                DataTypes(k) = metaObj.DataType;
                
                %% Safely Parse Unassigned Or Empty Strings
                if ismissing(metaObj.Unit) || metaObj.Unit == ""
                    Units(k) = "-";
                else
                    Units(k) = metaObj.Unit;
                end
            end
            
            %% Readable Overview Table
            T = table(Names, Values, DataTypes, Units, 'RowNames', keys);
            T.Properties.VariableNames = {'Parameter Name', 'Value', ...
                'Data Type', 'Unit'};
            
           %% Display the Table Block Directly Into the Command Line Window
            disp(T);
        end
    end   
    
    %% Parameters Configuration
    methods (Static, Access = private)
        function Schema = GetSchema()
            Schema = {
               
                struct( ...
                'Key', "DcF", ...
                'Name', "Decimation Factor", ...
                'Validator', @mustBePositive, ...
                'DataType', "double" ...
                )

                struct( ...
                'Key', "FrameLength", ...
                'Name', "Frame Length", ...
                'Validator', @(x) validateattributes( ...
                    x, {'numeric'}, {'positive', 'integer', 'finite'}), ...
                'DataType', "double", ...
                'Unit', "Samples" ...
                )

                struct( ...
                'Key', "Fstop", ...
                'Name', "Kaiser Stopband Frequecy", ...
                'Validator', @mustBePositive, ...
                'DataType', "double", ...
                'Unit', "Hz" ...
                ) 
                
                struct( ...
                'Key', "Fpass", ...
                'Name', "Kaiser Passband Frequecy", ...
                'Validator', @mustBePositive, ...
                'DataType', "double", ...
                'Unit', "Hz" ...
                ) 

                struct( ...
                'Key', "Astop", ...
                'Name', "Target Stopband Attenuation", ...
                'Validator', @mustBePositive, ...
                'DataType', "double", ...
                'Unit', "dB" ...
                ) 

                struct( ...
                'Key', "Apass", ...
                'Name', "Target Passband Ripple", ...
                'Validator', @mustBePositive, ...
                'DataType', "double", ...
                'Unit', "dB" ...
                ) 
                
                struct( ...
                'Key', "Fs_DSP", ...
                'Name', "DSP Sampling Frequency", ...
                'Validator', @mustBePositive, ...
                'DataType', "double", ...
                'Unit', "Hz" ...
                ) 

                struct( ...
                'Key', "B", ...
                'Name', "Bessel Power Series Factor", ...
                'Validator', @mustBePositive, ...
                'DataType', "double" ...
                ) 
            };
        end
    end
end
