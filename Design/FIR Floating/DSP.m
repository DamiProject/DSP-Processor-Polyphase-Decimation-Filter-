classdef DSP < handle
    %% ===============================
    %% POLYPHASE DECIMATION OPERATIONS
    %% ===============================

    properties
        Parameters
        DcF 
        FilterCoefficients
        BranchCoefficients    
    end

    properties (SetAccess = private)
        %% ==============================================
        %% FRAME-BASED POLYPHASE DECIMATOR STREAM STATE
        %% ==============================================
        % Valid samples waiting for enough inputs to form one DcF block.
        PendingInput = zeros(0, 1)

        % One FIR delay line for every polyphase branch.
        DelayLines = zeros(0, 0)

        % Streaming counters exclude end-of-stream padding samples.
        InputSamplesReceived = 0
        OutputSamplesProduced = 0
        FramesProcessed = 0

        % Prevents accidental input after final-frame padding is applied.
        StreamFinalized = false
    end

    methods
        function obj = DSP(P)
            %% =========================
            %% DSP INSTANCE CONSTRUCTOR
            %% =========================
            obj.Parameters = P;
            DcFValue = P.getValue("DcF");
            obj.ValidateDecimationFactor(DcFValue);
            obj.DcF = double(DcFValue);
            obj.FilterCoefficients = obj.WindowLPF();
            obj.BranchCoefficients = obj.Decompose(obj.FilterCoefficients);
            obj.ResetDecimator();

        end

        function [DecimatedFrame, FrameInfo] = ...
                ProcessFrame(obj, InputFrame, IsLastFrame)
            %% ==========================================
            %% FRAME-BASED POLYPHASE FIR DECIMATION
            %% ==========================================
            % Incomplete DcF-sample groups are retained in PendingInput.
            % Zero padding is applied only when IsLastFrame is true.

            ValidFrame = isnumeric(InputFrame) && ...
                isreal(InputFrame) && ...
                (isvector(InputFrame) || isempty(InputFrame)) && ...
                all(isfinite(InputFrame(:)));

            if ~ValidFrame
                error('DSP:InvalidInputFrame', ...
                    ['InputFrame must be a finite, real-valued ', ...
                     'numeric vector.']);
            end

            ValidLastFrameFlag = ...
                (islogical(IsLastFrame) || isnumeric(IsLastFrame)) && ...
                isscalar(IsLastFrame) && isreal(IsLastFrame) && ...
                isfinite(IsLastFrame) && ...
                (IsLastFrame == 0 || IsLastFrame == 1);

            if ~ValidLastFrameFlag
                error('DSP:InvalidLastFrameFlag', ...
                    'IsLastFrame must be a logical scalar.');
            end

            if obj.StreamFinalized
                error('DSP:StreamAlreadyFinalized', ...
                    ['The decimator stream is already finalized. ', ...
                     'Call ResetDecimator before processing a new stream.']);
            end

            Input = double(InputFrame(:));
            IsLastFrame = logical(IsLastFrame);
            NumValidInputSamples = numel(Input);

            FirstInputSampleIndex = obj.InputSamplesReceived;
            FirstOutputSampleIndex = obj.OutputSamplesProduced;

            CombinedInput = [obj.PendingInput; Input];
            NumPaddingSamples = 0;

            if IsLastFrame
                NumPaddingSamples = mod( ...
                    obj.DcF - mod(numel(CombinedInput), obj.DcF), ...
                    obj.DcF);

                CompleteInput = [ ...
                    CombinedInput; ...
                    zeros(NumPaddingSamples, 1)];
                NewPendingInput = zeros(0, 1);
            else
                CompleteLength = ...
                    floor(numel(CombinedInput) / obj.DcF) * obj.DcF;
                CompleteInput = CombinedInput(1:CompleteLength);
                NewPendingInput = ...
                    CombinedInput(CompleteLength + 1:end);
            end

            NumBlocks = numel(CompleteInput) / obj.DcF;

            if NumBlocks > 0
                DecimatedFrame = ...
                    obj.Decimator(CompleteInput, NumBlocks);
            else
                DecimatedFrame = zeros(0, 1);
            end

            % Commit frame bookkeeping only after block processing succeeds.
            obj.PendingInput = NewPendingInput;
            obj.InputSamplesReceived = ...
                FirstInputSampleIndex + NumValidInputSamples;

            if NumValidInputSamples > 0
                obj.FramesProcessed = obj.FramesProcessed + 1;
            end

            if IsLastFrame
                obj.StreamFinalized = true;
            end

            %% Frame Metadata
            FrameInfo.NumValidInputSamples = NumValidInputSamples;
            FrameInfo.NumBlocksProcessed = NumBlocks;
            FrameInfo.NumOutputSamples = numel(DecimatedFrame);
            FrameInfo.NumBufferedSamples = numel(obj.PendingInput);
            FrameInfo.NumPaddingSamples = NumPaddingSamples;
            FrameInfo.IsLastFrame = IsLastFrame;
            FrameInfo.StreamFinalized = obj.StreamFinalized;
            FrameInfo.TotalInputSamplesReceived = ...
                obj.InputSamplesReceived;
            FrameInfo.TotalOutputSamplesProduced = ...
                obj.OutputSamplesProduced;

            if NumValidInputSamples > 0
                FrameInfo.StartInputSampleIndex = ...
                    FirstInputSampleIndex;
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

        function [InPadded, NumBlocks] = PrepareInput(obj, Input)
            
            %% =====================================================
            %% INPUT SIGNAL PREPARATION BEFORE DECIMATION OPERATIONS
            %% =====================================================
            % Whole-vector compatibility helper. It treats Input as the
            % complete signal and pads immediately. Streaming code must use
            % ProcessFrame so intermediate frame boundaries are not padded.
            DcF = obj.DcF; % Decimation Factor
            
            Input = Input(:); % Input Signal Into The Decimator

            % Pad input to complete DcF-sample blocks
            PadLen = mod(DcF - mod(length(Input), DcF), DcF);

            if PadLen > 0
                Input(end+1:end+PadLen) = 0;
            end

            % Padded Input 
            InPadded = Input;

            % Number of decimator input blocks
            NumBlocks = length(InPadded) / DcF;
            
        end

        function DecimatedSignal  = Decimator(obj, InPadded, NumBlocks) 
            %% ===============================
            %% POLYPHASE DECIMATION FIR FILTER
            %% ===============================
            % Processes complete DcF-sample blocks. Polyphase delay-line
            % values persist after this call for the next block group.

             ValidInput = isnumeric(InPadded) && ...
                 isreal(InPadded) && ...
                 (isvector(InPadded) || isempty(InPadded)) && ...
                 all(isfinite(InPadded(:)));

             if ~ValidInput
                 error('DSP:InvalidDecimatorInput', ...
                     ['InPadded must be a finite, real-valued ', ...
                      'numeric vector.']);
             end

             ValidNumBlocks = isnumeric(NumBlocks) && ...
                 isscalar(NumBlocks) && isreal(NumBlocks) && ...
                 isfinite(NumBlocks) && NumBlocks >= 0 && ...
                 NumBlocks == floor(NumBlocks);

             if ~ValidNumBlocks
                 error('DSP:InvalidNumBlocks', ...
                     'NumBlocks must be a finite nonnegative integer.');
             end

             DcF = obj.DcF; % Decimation Factor

             InPadded = double(InPadded(:));

             if numel(InPadded) ~= NumBlocks * DcF
                 error('DSP:InputBlockLengthMismatch', ...
                     ['The input length must equal ', ...
                      'NumBlocks multiplied by DcF.']);
             end

             if NumBlocks == 0
                 DecimatedSignal = zeros(0, 1);
                 return
             end

             % Polyphase decomposition
             BranchCoefficients = obj.BranchCoefficients; 

             % Length of The Each Polyphase Branch
             L = size(BranchCoefficients, 2);

             obj.EnsureDecimatorState();

             % Local cache of the persistent branch delay-line state.
             DelayLines = obj.DelayLines;

             % Initializing Decimated Filtered Output
             DecimatedSignal = zeros(NumBlocks, 1);

             % Initializing Polyphase Branches MAC Output
             BranchOutput = zeros(DcF, 1);

             % Main Processing System (Pure Multiply-Accumulate Loops)
             for b = 1:NumBlocks

                 for k = 0:DcF-1
                     % Commutator maps samples chronologically 
                     % into the branches
                     CurrentSample =InPadded((b-1)*DcF + (DcF - k));

                     % Shift Register Operation
                     for i = L:-1:2
                         DelayLines(k+1, i) = DelayLines(k+1, i-1);
                     end
                     DelayLines(k+1, 1) = CurrentSample;

                     % Multiply-Accumulate (MAC) step
                     MacAccumulator = 0;
                     for i = 1:L
                         MacAccumulator = MacAccumulator +  ...
                         (BranchCoefficients(k+1, i) * DelayLines(k+1, i));
                     end
                     BranchOutput(k+1) = MacAccumulator;
                 end 

                 % Sum the parallel branches 
                 BranchSum = 0;
                 for k = 1:DcF
                     BranchSum = BranchSum + BranchOutput(k);
                 end
                 % Decimated Target Signal
                 DecimatedSignal(b) = BranchSum;
             end

             % The final delay values become the initial state of the next
             % complete block group, even when that group is in a new frame.
             obj.DelayLines = DelayLines;
             obj.OutputSamplesProduced = ...
                 obj.OutputSamplesProduced + NumBlocks;
        end

        function ResetDecimator(obj)
            %% =========================================
            %% RESET POLYPHASE FRAME AND FIR STATE
            %% =========================================
            L = size(obj.BranchCoefficients, 2);
            obj.PendingInput = zeros(0, 1);
            obj.DelayLines = zeros(obj.DcF, L);
            obj.InputSamplesReceived = 0;
            obj.OutputSamplesProduced = 0;
            obj.FramesProcessed = 0;
            obj.StreamFinalized = false;
        end
    end

    methods (Access = private)
        function EnsureDecimatorState(obj)
            %% Resizes State if Tests or Users Replace Branch Coefficients

            ExpectedSize = [ ...
                obj.DcF, size(obj.BranchCoefficients, 2)];

            if ~isequal(size(obj.DelayLines), ExpectedSize)
                obj.DelayLines = zeros(ExpectedSize);
            end
        end

        function FilterCoefficients = WindowLPF(obj)
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

        function BranchCoefficients = Decompose(obj, FilterCoefficients)
            %% ===========================
            %% FIR POLYPHASE DECOMPOSITION
            %% ===========================
            DcF = obj.DcF; % Decimation Factor

            L = ceil(length(FilterCoefficients) / DcF); % Branch Length

            % Initializing Polyphase Branches
            BranchCoefficients = zeros(DcF, L);

            for k = 0:DcF-1
                for m = 0:L-1
                    % Index into prototype FIR coefficient
                    index= k + m*DcF + 1;

                    % Only copy coefficients that actually exist
                    if index <= length(FilterCoefficients)
                        BranchCoefficients(k+1, m+1) = ...
                        FilterCoefficients(index);
                    end
                end
            end
        end
    end

    methods (Access = private, Static)
        function ValidateDecimationFactor(DcF)
            %% Validates the Number of Polyphase Branches

            ValidDcF = isnumeric(DcF) && isscalar(DcF) && ...
                isreal(DcF) && isfinite(DcF) && ...
                DcF > 0 && DcF == floor(DcF);

            if ~ValidDcF
                error('DSP:InvalidDecimationFactor', ...
                    ['DcF must be a finite positive integer scalar ', ...
                     'for polyphase decimation.']);
            end
        end
    end
end
