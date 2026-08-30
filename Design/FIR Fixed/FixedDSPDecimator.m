classdef FixedDSPDecimator < handle
    %% ===============================
    %% POLYPHASE DECIMATION OPERATIONS
    %% ===============================

    properties
        Parameters
        DcF
        FilterCoefficients % Floating-point prototype FIR coefficients
        BranchCoefficients % Fixed-point polyphase branch coefficients
        NPoint % Frequency-response verification resolution

        % Fixed-point FIR coefficient range and resolution representation
        FixedFilterCoefficients
        CoeffWL
        CoeffIWL
        CoeffFWL
        CoeffScale
    end

    properties (SetAccess = private)
        %% ====================================================
        %% FRAME-BASED FIXED-POINT DECIMATOR STREAM STATE
        %% ====================================================
        % Integer input codes waiting to complete one DcF-sample block.
        PendingInputCodes = zeros(0, 1, 'int64')

        % Persistent integer delay line for every polyphase branch.
        DelayLines = zeros(0, 0, 'int64')

        % Cumulative characterization for all completed blocks in a stream.
        CumulativeMACData = []

        % Streaming counters exclude end-of-stream padding samples.
        InputSamplesReceived = 0
        OutputSamplesProduced = 0
        FramesProcessed = 0

        % A stream uses one fixed-point format set from first to last frame.
        ActiveInputFormat = []
        ActiveCoefficientFormat = []
        ActiveMACFormat = []
        StreamFormatInitialized = false

        % Prevents accidental input after final-frame padding is applied.
        StreamFinalized = false
    end

    methods
        function obj =  FixedDSPDecimator (P)
            %% =========================
            %% DSP INSTANCE CONSTRUCTOR
            %% =========================
            obj.Parameters = P;
            obj.DcF = P.getValue("DcF");

            %% ---------------------------------------------------------
            %% Generate Floating-Point Prototype FIR Coefficients
            %% ---------------------------------------------------------
            obj.FilterCoefficients = obj.FixedWindowLPF();

            %% ---------------------------------------------------------
            %% Determine Frequency-Response Verification Resolution
            %% ---------------------------------------------------------

            obj.NPoint = FindResponseResolution( ...
                obj.FilterCoefficients, ...
                obj.Parameters);

            %% ---------------------------------------------------------
            %% Determine Fixed-Point Coefficient Representation
            %% ---------------------------------------------------------

            [obj.FixedFilterCoefficients, ...
                obj.CoeffWL, ...
                obj.CoeffIWL, ...
                obj.CoeffFWL, ...
                obj.CoeffScale] = ...
                FindCoefficientFormat( ...
                obj.FilterCoefficients, ...
                obj.Parameters, ...
                obj.NPoint);

            %% ---------------------------------------------------------
            %% Polyphase Decomposition Of Fixed-Point Coefficients
            %% ---------------------------------------------------------
            obj.BranchCoefficients = ...
                obj.FixedDecompose(obj.FixedFilterCoefficients);

            obj.ResetDecimator();

        end

        function [DecimatedFrame, MACData, FrameInfo] = ...
                ProcessFrame(obj, InputFrame, IsLastFrame, InputFormat, ...
                CoefficientFormat, MACFormat)
            %% ==================================================
            %% FRAME-BASED FIXED-POINT POLYPHASE FIR DECIMATION
            %% ==================================================
            % InputFrame contains signed integer codes. Incomplete
            % DcF-sample groups remain buffered between calls. Zero padding
            % is applied once, and only when IsLastFrame is true.

            if nargin < 6
                MACFormat = [];
            end

            ValidFrame = isnumeric(InputFrame) && ...
                isreal(InputFrame) && ...
                (isvector(InputFrame) || isempty(InputFrame)) && ...
                all(isfinite(InputFrame(:))) && ...
                (isinteger(InputFrame) || ...
                 all(InputFrame(:) == fix(InputFrame(:))));

            if ~ValidFrame
                error('FixedDSPDecimator:InvalidInputFrame', ...
                    ['InputFrame must be a finite, real-valued vector ', ...
                     'of integer codes.']);
            end

            ValidLastFrameFlag = ...
                (islogical(IsLastFrame) || isnumeric(IsLastFrame)) && ...
                isscalar(IsLastFrame) && isreal(IsLastFrame) && ...
                isfinite(IsLastFrame) && ...
                (IsLastFrame == 0 || IsLastFrame == 1);

            if ~ValidLastFrameFlag
                error('FixedDSPDecimator:InvalidLastFrameFlag', ...
                    'IsLastFrame must be a logical scalar.');
            end

            if obj.StreamFinalized
                error('FixedDSPDecimator:StreamAlreadyFinalized', ...
                    ['The fixed decimator stream is already finalized. ', ...
                     'Call ResetDecimator before processing a new stream.']);
            end

            obj.ValidateStreamFormatCompatibility( ...
                InputFormat, CoefficientFormat, MACFormat);

            InputCodes = int64(InputFrame(:));
            FixedDSPDecimator.ValidateFormat( ...
                InputFormat, 'InputFormat');
            FixedDSPDecimator.ValidateSignedCodes( ...
                InputCodes, InputFormat.WL, 'InputFrame');

            IsLastFrame = logical(IsLastFrame);
            NumValidInputSamples = numel(InputCodes);

            FirstInputSampleIndex = obj.InputSamplesReceived;
            FirstOutputSampleIndex = obj.OutputSamplesProduced;

            CombinedInput = [obj.PendingInputCodes; InputCodes];
            NumPaddingSamples = 0;

            if IsLastFrame
                NumPaddingSamples = mod( ...
                    obj.DcF - mod(numel(CombinedInput), obj.DcF), ...
                    obj.DcF);

                CompleteInput = [ ...
                    CombinedInput; ...
                    zeros(NumPaddingSamples, 1, 'int64')];
                NewPendingInput = zeros(0, 1, 'int64');
            else
                CompleteLength = ...
                    floor(numel(CombinedInput) / obj.DcF) * obj.DcF;
                CompleteInput = CombinedInput(1:CompleteLength);
                NewPendingInput = ...
                    CombinedInput(CompleteLength + 1:end);
            end

            NumBlocks = numel(CompleteInput) / obj.DcF;
            InitialDelayLines = obj.GetCurrentDelayLines();

            % FixedDecimator performs all format, code-range, and block-size
            % validation. Supplying InitialDelayLines selects its streaming
            % state path without changing its legacy stateless behaviour.
            [DecimatedFrame, FrameMACData, NewDelayLines] = ...
                obj.FixedDecimator( ...
                CompleteInput, ...
                NumBlocks, ...
                InputFormat, ...
                CoefficientFormat, ...
                MACFormat, ...
                InitialDelayLines);

            if NumBlocks > 0
                NewCumulativeMACData = ...
                    FixedDSPDecimator.MergeMACData( ...
                    obj.CumulativeMACData, FrameMACData);
            else
                NewCumulativeMACData = obj.CumulativeMACData;
            end

            % Commit stream state only after fixed-point processing succeeds.
            obj.PendingInputCodes = NewPendingInput;
            obj.DelayLines = NewDelayLines;
            obj.CumulativeMACData = NewCumulativeMACData;
            obj.InputSamplesReceived = ...
                FirstInputSampleIndex + NumValidInputSamples;
            obj.OutputSamplesProduced = ...
                FirstOutputSampleIndex + NumBlocks;

            if NumValidInputSamples > 0
                obj.FramesProcessed = obj.FramesProcessed + 1;
            end

            obj.ActiveInputFormat = InputFormat;
            obj.ActiveCoefficientFormat = CoefficientFormat;
            obj.ActiveMACFormat = MACFormat;
            obj.StreamFormatInitialized = true;

            if IsLastFrame
                obj.StreamFinalized = true;
            end

            if isempty(obj.CumulativeMACData)
                % No complete block has been processed yet. Return the valid
                % zero-block metadata generated by the unchanged MAC engine.
                MACData = FrameMACData;
            else
                MACData = obj.CumulativeMACData;
            end

            %% Frame Metadata
            FrameInfo.NumValidInputSamples = NumValidInputSamples;
            FrameInfo.NumBlocksProcessed = NumBlocks;
            FrameInfo.NumOutputSamples = numel(DecimatedFrame);
            FrameInfo.NumBufferedSamples = numel(obj.PendingInputCodes);
            FrameInfo.NumPaddingSamples = NumPaddingSamples;
            FrameInfo.IsLastFrame = IsLastFrame;
            FrameInfo.ReferenceMode = isempty(MACFormat);
            FrameInfo.MACDataIsCumulative = true;
            FrameInfo.StreamFinalized = obj.StreamFinalized;
            FrameInfo.TotalInputSamplesReceived = ...
                obj.InputSamplesReceived;
            FrameInfo.TotalOutputSamplesProduced = ...
                obj.OutputSamplesProduced;

            if NumValidInputSamples > 0
                FrameInfo.StartInputSampleIndex = FirstInputSampleIndex;
                FrameInfo.EndInputSampleIndex = ...
                    obj.InputSamplesReceived - 1;
            else
                FrameInfo.StartInputSampleIndex = NaN;
                FrameInfo.EndInputSampleIndex = NaN;
            end

            if isempty(DecimatedFrame)
                FrameInfo.OutputSampleIndex = zeros(0, 1);
            else
                FrameInfo.OutputSampleIndex = ...
                    (FirstOutputSampleIndex: ...
                     obj.OutputSamplesProduced - 1)';
            end
        end

        function [InPadded, NumBlocks] = FixedPrepareInput(obj, Input)

            %% =====================================================
            %% INPUT SIGNAL PREPARATION BEFORE DECIMATION OPERATIONS
            %% =====================================================
            % Whole-vector compatibility helper. It treats Input as the
            % complete signal and pads immediately. Streaming code must use
            % ProcessFrame so intermediate frame boundaries are not padded.
            DcF = obj.DcF; % Decimation Factor

            Input = Input(:); % Input Signal Into The Decimator

            % Determine required zero padding
            Remainder = mod(length(Input), DcF);

            % Pad input to complete DcF-sample blocks
            PadLen = mod(DcF - Remainder, DcF);

            if PadLen > 0
                Input(end+1:end+PadLen) = 0;
            end

            % Padded Input
            InPadded = Input;

            % Number of decimator input blocks
            NumBlocks = length(InPadded) / DcF;

        end

        function [DecimatedCodes, MACData, FinalDelayLines] = ...
            FixedDecimator(obj, InPadded, NumBlocks, InputFormat, ...
            CoefficientFormat, MACFormat, InitialDelayLines)
            %% ===============================
            %% POLYPHASE DECIMATION FIR FILTER
            %% ===============================

            if nargin < 6
                MACFormat = [];
            end

            if nargin < 7
                InitialDelayLines = [];
            end

            DcF = obj.DcF; % Decimation Factor

            % Polyphase decomposition
            BranchCoefficients = obj.BranchCoefficients;

            % Length of each polyphase branch
            L = size(BranchCoefficients, 2);

            % Validate fixed-point format descriptions used by the MAC.
            FixedDSPDecimator.ValidateFormat( ...
                InputFormat, 'InputFormat');

            FixedDSPDecimator.ValidateFormat( ...
                CoefficientFormat, 'CoefficientFormat');

            ValidInput = isnumeric(InPadded) && ...
                isreal(InPadded) && ...
                (isvector(InPadded) || isempty(InPadded)) && ...
                all(isfinite(InPadded(:))) && ...
                (isinteger(InPadded) || ...
                 all(InPadded(:) == fix(InPadded(:))));

            if ~ValidInput
                error('FixedDSPDecimator:InvalidDecimatorInput', ...
                    ['InPadded must be a finite, real-valued vector ', ...
                     'of integer codes.']);
            end

            ValidNumBlocks = isnumeric(NumBlocks) && ...
                isscalar(NumBlocks) && isreal(NumBlocks) && ...
                isfinite(NumBlocks) && NumBlocks >= 0 && ...
                NumBlocks == floor(NumBlocks);

            if ~ValidNumBlocks
                error('FixedDSPDecimator:InvalidNumBlocks', ...
                    'NumBlocks must be a finite nonnegative integer.');
            end

            InPadded = int64(InPadded(:));

            if numel(InPadded) ~= NumBlocks * DcF
                error('FixedDSPDecimator:InputBlockLengthMismatch', ...
                    ['The input length must equal ', ...
                     'NumBlocks multiplied by DcF.']);
            end

            FixedDSPDecimator.ValidateSignedCodes( ...
                InPadded, ...
                InputFormat.WL, ...
                'InPadded');

            FixedDSPDecimator.ValidateSignedCodes( ...
                BranchCoefficients, ...
                CoefficientFormat.WL, ...
                'BranchCoefficients');

            % Initializing decimated filtered output integer codes
            DecimatedCodes = zeros(1, NumBlocks, 'int64');

            % Legacy calls omit InitialDelayLines and therefore retain the
            % original stateless whole-vector behaviour. ProcessFrame passes
            % the persistent integer state explicitly.
            if isempty(InitialDelayLines)
                WorkingDelayLines = zeros(DcF, L, 'int64');
            else
                ValidDelayLines = isnumeric(InitialDelayLines) && ...
                    isreal(InitialDelayLines) && ...
                    all(isfinite(InitialDelayLines(:))) && ...
                    (isinteger(InitialDelayLines) || ...
                     all(InitialDelayLines(:) == ...
                         fix(InitialDelayLines(:)))) && ...
                    isequal(size(InitialDelayLines), [DcF, L]);

                if ~ValidDelayLines
                    error('FixedDSPDecimator:InvalidDelayLines', ...
                        ['InitialDelayLines must be a DcF-by-L array ', ...
                         'of finite integer codes.']);
                end

                WorkingDelayLines = int64(InitialDelayLines);
                FixedDSPDecimator.ValidateSignedCodes( ...
                    WorkingDelayLines, InputFormat.WL, 'InitialDelayLines');
            end

            % Initializing polyphase branch MAC outputs
            BranchOutput = zeros(1, DcF, 'int64');

            %% Pass 1:
            %%   Call without MACFormat
            %%   -> characterization/reference MAC
            ReferenceMode = isempty(MACFormat);

            %% =============================
            %% FULL-PRECISION PRODUCT FORMAT
            %% =============================

            ProductWL = ...
                InputFormat.WL + ...
                CoefficientFormat.WL;

            ProductFWL = ...
                InputFormat.FWL + ...
                CoefficientFormat.FWL;

            ProductIWL = ...
                ProductWL - ProductFWL;

            %% ============================
            %% INT64 CONTAINER SAFETY CHECK
            %% ============================

            if ProductWL > 63
                error(['Full product requires %d bits. ' ...
                    'The current toolbox-free int64 model ' ...
                    'supports product widths up to 63 bits.'], ...
                    ProductWL);
            end

            % Conservative full-precision accumulator check.
            %
            % ProductWL + ceil(log2(number of products))
            %
            % This is intentionally conservative and is only
            % checking whether int64 is large enough to perform
            % the reference characterization safely.

            NumberProducts = length(obj.FixedFilterCoefficients);

            % Conservative accumulator growth
            GuardBits = ...
                ceil(log2(NumberProducts));

            ReferenceContainerWL = ...
                ProductWL + GuardBits;

            if ReferenceContainerWL > 63
                error(['Reference MAC may require ' ...
                    'approximately %d bits. ' ...
                    'The current int64 reference container is ' ...
                    'insufficient.'], ...
                    ReferenceContainerWL);
            end
            % Store reference MAC width information
            MACData.NumberProducts = NumberProducts;
            MACData.GuardBits = GuardBits;
            MACData.ReferenceContainerWL = ReferenceContainerWL;
            MACData.NumBlocksProcessed = NumBlocks;

            %% ======================
            %% FIXED-MAC FORMAT CHECK
            %% ======================

            %% Pass 2:
            %%   Call with MACFormat
            %%   -> width-constrained fixed-point MAC
            if ~ReferenceMode

                FixedDSPDecimator.ValidateFormat( ...
                    MACFormat, 'MACFormat');

                if ~isfield(MACFormat, 'RoundingMethod')
                    error('MACFormat must contain RoundingMethod.');
                end

                if ~isfield(MACFormat, 'OverflowAction')
                    error('MACFormat must contain OverflowAction.');
                end

                if MACFormat.WL > 63
                    error(['MACFormat.WL must be <= 63 for the ' ...
                        'int64 model.']);
                end

                % Allowed preservation or reduction of product
                % fractional precision.
                if MACFormat.FWL > ProductFWL
                    error(['MAC FWL cannot currently exceed the ' ...
                        'full-precision product FWL.']);
                end

                [MACMinCode, MACMaxCode] = ...
                    FixedDSPDecimator.SignedCodeLimits( ...
                    MACFormat.WL);
            end

            %% ==========================================
            %% CHARACTERIZATION STORAGE
            %% ==========================================

            MACData.Product.MaxCode = intmin('int64');
            MACData.Product.MinCode = intmax('int64');
            MACData.Product.MaxAbsCode = int64(0);

            MACData.BranchAccumulator.MaxCode = intmin('int64');
            MACData.BranchAccumulator.MinCode = intmax('int64');
            MACData.BranchAccumulator.MaxAbsCode = int64(0);

            MACData.BranchAccumulator.GrowthByTapCode = ...
                zeros(1, L, 'int64');

            MACData.FinalAccumulator.MaxCode = intmin('int64');
            MACData.FinalAccumulator.MinCode = intmax('int64');
            MACData.FinalAccumulator.MaxAbsCode = int64(0);

            MACData.FinalAccumulator.GrowthByBranchCode = ...
                zeros(1, DcF, 'int64');

            % Overflow counters are only expected to increase during
            % the width-constrained pass, but are initialized for both.
            MACData.ProductCastOverflowCount = 0;
            MACData.BranchAccumulatorOverflowCount = 0;
            MACData.FinalAccumulatorOverflowCount = 0;

            % Integer-domain format metadata. This is not a conversion
            % back to real values; it describes how the codes are scaled.
            MACData.ProductFormat.WL = ProductWL;
            MACData.ProductFormat.IWL = ProductIWL;
            MACData.ProductFormat.FWL = ProductFWL;

            if ~ReferenceMode
                MACData.AccumulatorFormat = MACFormat;
            end

            %% =====================
            %% MAIN PROCESSING LOOP
            %% =====================

            % Main Processing System (Pure Multiply-Accumulate Loops)
            for b = 1:NumBlocks

                %% -----------------------------------------
                %% PROCESS EACH POLYPHASE BRANCH
                %% -----------------------------------------
                for k = 0:DcF-1

                    % Commutator maps samples chronologically
                    % into the branches.
                    CurrentSample = ...
                        InPadded((b-1)*DcF + (DcF-k));

                    % Shift Register Operation
                    for i = L:-1:2
                        WorkingDelayLines(k+1, i) = ...
                            WorkingDelayLines(k+1, i-1);
                    end
                    WorkingDelayLines(k+1, 1) = CurrentSample;

                    % Multiply-Accumulate (MAC) step
                    MacAccumulator = int64(0);

                    %% -------------------------------------
                    %% MAC ACROSS ALL TAPS OF THIS BRANCH
                    %% -------------------------------------
                    for i = 1:L

                        %% ------------------------------
                        %% FULL-PRECISION MULTIPLICATION
                        %% ------------------------------

                        ProductCode = ...
                            int64(BranchCoefficients(k+1, i)) * ...
                            int64(WorkingDelayLines(k+1, i));

                        %% ------------------------------
                        %% PRODUCT CHARACTERIZATION
                        %% ------------------------------

                        MACData.Product.MaxCode = ...
                            max( ...
                            MACData.Product.MaxCode, ...
                            ProductCode);

                        MACData.Product.MinCode = ...
                            min( ...
                            MACData.Product.MinCode, ...
                            ProductCode);

                        MACData.Product.MaxAbsCode = ...
                            max( ...
                            MACData.Product.MaxAbsCode, ...
                            abs(ProductCode));

                        %% ======================
                        %% PASS 1: REFERENCE MAC
                        %% ======================

                        if ReferenceMode

                            % No intentional wordlength restriction
                            % is imposed here.
                            MacAccumulator = ...
                                MacAccumulator + ...
                                ProductCode;

                        %% =============================
                        %% PASS 2: WIDTH-CONSTRAINED MAC
                        %% =============================

                        else

                            % Convert the product from ProductFWL
                            % to the selected accumulator FWL.
                            ProductForAccumulator = ...
                                FixedDSPDecimator.RequantizeCode( ...
                                ProductCode, ...
                                ProductFWL, ...
                                MACFormat.FWL, ...
                                MACFormat.RoundingMethod);

                            %% ------------------------------
                            %% PRODUCT -> ACCUMULATOR RANGE
                            %% ------------------------------

                            ProductOverflow = ...
                                ProductForAccumulator > MACMaxCode || ...
                                ProductForAccumulator < MACMinCode;

                            if ProductOverflow
                                MACData.ProductCastOverflowCount = ...
                                    MACData.ProductCastOverflowCount + 1;
                            end

                            ProductForAccumulator = ...
                                FixedDSPDecimator.ApplySignedOverflow( ...
                                ProductForAccumulator, ...
                                MACFormat.WL, ...
                                MACFormat.OverflowAction);

                            %% -------------
                            %% ACCUMULATION
                            %% -------------

                            RawAccumulator = ...
                                MacAccumulator + ...
                                ProductForAccumulator;

                            AccumulatorOverflow = ...
                                RawAccumulator > MACMaxCode || ...
                                RawAccumulator < MACMinCode;

                            if AccumulatorOverflow
                                MACData.BranchAccumulatorOverflowCount ...
                                = MACData.BranchAccumulatorOverflowCount...
                                + 1;
                            end

                            MacAccumulator = ...
                                FixedDSPDecimator.ApplySignedOverflow( ...
                                RawAccumulator, ...
                                MACFormat.WL, ...
                                MACFormat.OverflowAction);
                        end

                        %% ==================================
                        %% BRANCH ACCUMULATOR CHARACTERIZATION
                        %% ==================================

                        MACData.BranchAccumulator.MaxCode = ...
                            max( ...
                            MACData.BranchAccumulator.MaxCode, ...
                            MacAccumulator);

                        MACData.BranchAccumulator.MinCode = ...
                            min( ...
                            MACData.BranchAccumulator.MinCode, ...
                            MacAccumulator);

                        MACData.BranchAccumulator.MaxAbsCode = ...
                            max( ...
                            MACData.BranchAccumulator.MaxAbsCode, ...
                            abs(MacAccumulator));

                        MACData.BranchAccumulator.GrowthByTapCode(i) = ...
                            max( ...
                            MACData.BranchAccumulator.GrowthByTapCode(i), ...
                            abs(MacAccumulator));
                    end

                    % Store completed MAC result for this branch.
                    BranchOutput(k+1) = MacAccumulator;
                end

                %% -----------------------------------------
                %% SUM THE PARALLEL POLYPHASE BRANCH OUTPUTS
                %% -----------------------------------------

                FinalAccumulatorCode = int64(0);

                for k = 1:DcF

                    RawFinalAccumulator = ...
                        FinalAccumulatorCode + ...
                        BranchOutput(k);

                    if ReferenceMode

                        FinalAccumulatorCode = ...
                            RawFinalAccumulator;

                    else

                        FinalOverflow = ...
                            RawFinalAccumulator > MACMaxCode || ...
                            RawFinalAccumulator < MACMinCode;

                        if FinalOverflow
                            MACData.FinalAccumulatorOverflowCount = ...
                                MACData.FinalAccumulatorOverflowCount + 1;
                        end

                        FinalAccumulatorCode = ...
                            FixedDSPDecimator.ApplySignedOverflow( ...
                            RawFinalAccumulator, ...
                            MACFormat.WL, ...
                            MACFormat.OverflowAction);
                    end

                    %% ------------------
                    %% BRANCH-SUM GROWTH
                    %% ------------------

                    MACData.FinalAccumulator.GrowthByBranchCode(k) = ...
                        max( ...
                        MACData.FinalAccumulator.GrowthByBranchCode(k), ...
                        abs(FinalAccumulatorCode));
                end

                % Decimated target signal integer code
                DecimatedCodes(b) = FinalAccumulatorCode;

                %% ===================================
                %% FINAL ACCUMULATOR CHARACTERIZATION
                %% ===================================

                MACData.FinalAccumulator.MaxCode = ...
                    max( ...
                    MACData.FinalAccumulator.MaxCode, ...
                    FinalAccumulatorCode);

                MACData.FinalAccumulator.MinCode = ...
                    min( ...
                    MACData.FinalAccumulator.MinCode, ...
                    FinalAccumulatorCode);

                MACData.FinalAccumulator.MaxAbsCode = ...
                    max( ...
                    MACData.FinalAccumulator.MaxAbsCode, ...
                    abs(FinalAccumulatorCode));
            end

            FinalDelayLines = WorkingDelayLines;
        end

        function ResetDecimator(obj)
            %% ===============================================
            %% RESET FIXED-POINT FRAME, FORMAT, AND FIR STATE
            %% ===============================================
            L = size(obj.BranchCoefficients, 2);
            obj.PendingInputCodes = zeros(0, 1, 'int64');
            obj.DelayLines = zeros(obj.DcF, L, 'int64');
            obj.CumulativeMACData = [];
            obj.InputSamplesReceived = 0;
            obj.OutputSamplesProduced = 0;
            obj.FramesProcessed = 0;
            obj.ActiveInputFormat = [];
            obj.ActiveCoefficientFormat = [];
            obj.ActiveMACFormat = [];
            obj.StreamFormatInitialized = false;
            obj.StreamFinalized = false;
        end

    end

    methods (Static, Access = private)

        function Combined = MergeMACData(Previous, Current)
            %% =============================================
            %% MERGE PER-FRAME FIXED-MAC CHARACTERIZATION
            %% =============================================
            if isempty(Previous)
                Combined = Current;
                return
            end

            Combined = Previous;

            Combined.Product.MaxCode = max( ...
                Previous.Product.MaxCode, Current.Product.MaxCode);
            Combined.Product.MinCode = min( ...
                Previous.Product.MinCode, Current.Product.MinCode);
            Combined.Product.MaxAbsCode = max( ...
                Previous.Product.MaxAbsCode, Current.Product.MaxAbsCode);

            Combined.BranchAccumulator.MaxCode = max( ...
                Previous.BranchAccumulator.MaxCode, ...
                Current.BranchAccumulator.MaxCode);
            Combined.BranchAccumulator.MinCode = min( ...
                Previous.BranchAccumulator.MinCode, ...
                Current.BranchAccumulator.MinCode);
            Combined.BranchAccumulator.MaxAbsCode = max( ...
                Previous.BranchAccumulator.MaxAbsCode, ...
                Current.BranchAccumulator.MaxAbsCode);
            Combined.BranchAccumulator.GrowthByTapCode = max( ...
                Previous.BranchAccumulator.GrowthByTapCode, ...
                Current.BranchAccumulator.GrowthByTapCode);

            Combined.FinalAccumulator.MaxCode = max( ...
                Previous.FinalAccumulator.MaxCode, ...
                Current.FinalAccumulator.MaxCode);
            Combined.FinalAccumulator.MinCode = min( ...
                Previous.FinalAccumulator.MinCode, ...
                Current.FinalAccumulator.MinCode);
            Combined.FinalAccumulator.MaxAbsCode = max( ...
                Previous.FinalAccumulator.MaxAbsCode, ...
                Current.FinalAccumulator.MaxAbsCode);
            Combined.FinalAccumulator.GrowthByBranchCode = max( ...
                Previous.FinalAccumulator.GrowthByBranchCode, ...
                Current.FinalAccumulator.GrowthByBranchCode);

            Combined.ProductCastOverflowCount = ...
                Previous.ProductCastOverflowCount + ...
                Current.ProductCastOverflowCount;
            Combined.BranchAccumulatorOverflowCount = ...
                Previous.BranchAccumulatorOverflowCount + ...
                Current.BranchAccumulatorOverflowCount;
            Combined.FinalAccumulatorOverflowCount = ...
                Previous.FinalAccumulatorOverflowCount + ...
                Current.FinalAccumulatorOverflowCount;
            Combined.NumBlocksProcessed = ...
                Previous.NumBlocksProcessed + Current.NumBlocksProcessed;
        end

        %% ==================
        %% FORMAT VALIDATION
        %% ==================

        function ValidateFormat(Format, FormatName)
            RequiredFields = {'WL', 'IWL', 'FWL'};
            for i = 1:length(RequiredFields)
                if ~isfield(Format, RequiredFields{i})
                    error('%s must contain %s.', ...
                        FormatName, ...
                        RequiredFields{i});
                end
            end
            if Format.WL ~= ...
                    Format.IWL + Format.FWL
                error(['%s format is inconsistent: ' ...
                    'WL must equal IWL + FWL.'], ...
                    FormatName);
            end
            if Format.WL < 1 || ...
                    Format.FWL < 0 || ...
                    Format.IWL < 1

                error('%s contains an invalid fixed-point format.', ...
                    FormatName);
            end
        end

        %% ==================
        %% SIGNED CODE LIMITS
        %% ==================

        function [MinCode, MaxCode] = SignedCodeLimits(WL)
            if WL < 1 || WL > 63
                error('Signed integer-code WL must be between 1 and 63.');
            end
            Magnitude = ...
                bitshift(int64(1), WL - 1);
            MinCode = ...
                -Magnitude;
            MaxCode = ...
                Magnitude - 1;
        end

        %% ===================
        %% CHECK INTEGER CODES
        %% ===================
        function ValidateSignedCodes(Codes, WL, SignalName)
            [MinCode, MaxCode] = ...
                FixedDSPDecimator.SignedCodeLimits(WL);
            if any(Codes(:) < MinCode) || ...
                    any(Codes(:) > MaxCode)
                error('%s contains codes outside its declared WL.', ...
                    SignalName);
            end
        end

        %% =======================
        %% REQUANTIZE INTEGER CODE
        %% =======================

        function OutCode = RequantizeCode( ...
                InCode, ...
                FromFWL, ...
                ToFWL, ...
                RoundingMethod)
            FractionBitsRemoved = ...
                FromFWL - ToFWL;
            if FractionBitsRemoved < 0
                error(['This implementation currently supports ' ...
                    'preserving or reducing FWL only.']);
            end
            if FractionBitsRemoved == 0
                OutCode = InCode;
                return;
            end
            Divisor = ...
                bitshift(int64(1), ...
                FractionBitsRemoved);
            switch lower(RoundingMethod)
                case 'truncate'
                    % Round toward zero
                    OutCode = ...
                        idivide( ...
                        InCode, ...
                        Divisor, ...
                        'fix');
                case 'nearest'
                    HalfLSB = ...
                        bitshift( ...
                        int64(1), ...
                        FractionBitsRemoved - 1);
                    if InCode >= 0
                        OutCode = ...
                            idivide( ...
                            InCode + HalfLSB, ...
                            Divisor, ...
                            'fix');
                    else
                        OutCode = ...
                            -idivide( ...
                            (-InCode) + HalfLSB, ...
                            Divisor, ...
                            'fix');
                    end
                otherwise
                    error(['Unsupported rounding method: %s. ' ...
                        'Use ''Nearest'' or ''Truncate''.'], ...
                        RoundingMethod);
            end
        end

        %% =================
        %% MANUAL SATURATION
        %% ==================
        function OutCode = ApplySignedOverflow( ...
                InCode, ...
                WL, ...
                OverflowAction)
            [MinCode, MaxCode] = ...
                FixedDSPDecimator.SignedCodeLimits(WL);
            if InCode <= MaxCode && ...
                    InCode >= MinCode
                OutCode = InCode;
                return;
            end
            switch lower(OverflowAction)
                case 'saturate'
                    if InCode > MaxCode
                        OutCode = MaxCode;
                   else
                        OutCode = MinCode;
                    end
                case 'error'
                    error(['Fixed-point overflow occurred for ' ...
                        'a signed %d-bit value.'], ...
                        WL);
                otherwise
                    error(['Unsupported OverflowAction: %s. ' ...
                        'Use ''Saturate'' or ''Error''.'], ...
                        OverflowAction);
            end
        end
    end

    methods (Access = private)
        function DelayLines = GetCurrentDelayLines(obj)
            %% Resize Initial State if a Unit Test Replaces Coefficients
            ExpectedSize = [ ...
                obj.DcF, size(obj.BranchCoefficients, 2)];

            if isequal(size(obj.DelayLines), ExpectedSize)
                DelayLines = obj.DelayLines;
                return
            end

            if obj.StreamFormatInitialized
                error('FixedDSPDecimator:StateSizeChanged', ...
                    ['DcF or BranchCoefficients changed during an active ', ...
                     'stream. Call ResetDecimator before processing.']);
            end

            DelayLines = zeros(ExpectedSize, 'int64');
        end

        function ValidateStreamFormatCompatibility( ...
                obj, InputFormat, CoefficientFormat, MACFormat)
            %% One Stream Must Use One Code Scaling and MAC Configuration
            if ~obj.StreamFormatInitialized
                return
            end

            SameFormats = ...
                isequaln(InputFormat, obj.ActiveInputFormat) && ...
                isequaln(CoefficientFormat, ...
                    obj.ActiveCoefficientFormat) && ...
                isequaln(MACFormat, obj.ActiveMACFormat);

            if ~SameFormats
                error('FixedDSPDecimator:FormatChangedDuringStream', ...
                    ['InputFormat, CoefficientFormat, and MACFormat must ', ...
                     'remain unchanged until ResetDecimator is called.']);
            end
        end

        function FilterCoefficients = FixedWindowLPF(obj)
            %% ============================
            %% Kaiser Window Implementation
            %% ============================
            Fs_DSP = obj.Parameters.getValue("Fs_DSP");% Sampling Frequency
            Fstop = obj.Parameters.getValue("Fstop"); % Stopband frequency
            Fpass = obj.Parameters.getValue("Fpass"); % Passband frequency
            Astop = obj.Parameters.getValue("Astop"); %Stopband attenuation
            Apass = obj.Parameters.getValue("Apass"); % Passband Ripple
            B = obj.Parameters.getValue ("B"); % Bessel Function Factor

            % Transition Width
            delta_f = Fstop - Fpass;

            % Normalized Transition Width
            delta_f_norm = delta_f/Fs_DSP;

            % Passband Ripple dB Conversion to linear tolerances
            delta_p = (10^(Apass/20) - 1) / (10^(Apass/20) + 1);

            % Stopband Attenuation dB Conversion to linear tolerances
            delta_s = 10^(-Astop/20);

            % Maximum Passband/Stopband Allowable Filter Ripple
            delta = min(delta_p, delta_s);

            % Target Stopband Attenuation dB
            A = -20 * log10(delta);

            % Kaiser's Alpha (Shape Parameter).
            if A >= 50
                alpha = 0.1102 * (A - 8.7);
            elseif A > 21 && A < 50
                alpha = 0.5842 * (A - 21)^0.4 + 0.07886 * (A - 21);
            else
                alpha = 0.0;
            end

            % Stopband Attenuation Scaling Operation
            if A > 21
                D = (A - 7.95) / 14.36;
            else
                D = 0.922;
            end

            % Filter length (N) and round up
            Nkaiser = ceil(1 + (D / delta_f_norm));

            % Enforce Type-I FIR: Odd Number of Taps
            if mod(Nkaiser, 2) == 0
                Nlength = Nkaiser + 1;
            else
                Nlength = Nkaiser;
            end

            %% Low Pass Filter Coefficient Generation

            % Normalized Cutoff Frequency (Middle of transition band)
            Fc_norm = (Fpass + Fstop) / (2 * Fs_DSP);

            % FIR symmetry centre
            center = (Nlength - 1) / 2;

            % Initializing Window, Ideal LPF, and Windowed LPF
            w = zeros(1, Nlength);
            hideal = zeros(1, Nlength);
            FilterCoefficients = zeros(1, Nlength);

            for n = 0:Nlength-1

                % Ideal Lowpass Filter
                if n == center
                    hideal(n+1) = 2 * Fc_norm;
                else
                    hideal(n+1) = sin(2 * pi * Fc_norm * (n - center)) ...
                    / (pi * (n - center));
                end

                % Kaiser Window
                kaiser_arg = alpha * sqrt( n * (2 * center - n)) / center;
                w(n+1) = Bessel_I0(kaiser_arg) / Bessel_I0(alpha);

                % Final Windowed LPF Coefficient
                FilterCoefficients(n+1) = hideal(n+1) * w(n+1);
            end

            %% 1st Kind Bessel Function and 0th Order
            function BesselOutput = Bessel_I0(x)

               BesselOutput = 1.0; % 1st Bessel Function Output
               BesselSeries = 1.0; % 1st Bessel Power Series
               for k = 1:B
                   BesselSeries = BesselSeries * ((x / (2 * k))^2);
                   BesselOutput = BesselOutput + BesselSeries;
               end
            end
        end

        function BranchCoefficients = ...
            FixedDecompose (obj,  FixedFilterCoefficients)
            %% =========================================
            %% FIXED-POINT FIR COEFFICIENT DECOMPOSITION
            %% ===========================================

            % Decimation factor
            DcF = obj.DcF;

            %% -------------------------
            %% Polyphase Decomposition
            %% -------------------------

            % Length of each polyphase branch
            L = ceil(length(FixedFilterCoefficients) / DcF);

            % Integer coefficient matrix
            BranchCoefficients = ...
            zeros(DcF, L, 'like', FixedFilterCoefficients);

            for k = 0:DcF-1
                for m = 0:L-1

                    % Prototype FIR coefficient index
                    index = k + m*DcF + 1;

                    % Copy only coefficients that actually exist
                    if index <= length(FixedFilterCoefficients)

                        BranchCoefficients(k+1, m+1) = ...
                        FixedFilterCoefficients(index);
                    end
                end
            end
        end
    end
end
