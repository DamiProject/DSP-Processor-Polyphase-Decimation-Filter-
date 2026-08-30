classdef TestFloatingVsFixedDecimator < matlab.unittest.TestCase
    %% =========================================================
    %% FLOATING-VERSUS-FIXED POLYPHASE DECIMATOR INTEGRATION
    %% =========================================================
    % It generates its own deterministic real-valued stimulus and does not
    
    methods (Test)
        function testFixedDecimatorApproximatesFloatingReference(testCase)
            %% Verifies framed fixed-point DSP against floating-point DSP

            P = testCase.createPolyphaseParameters();
            DcF = P.getValue("DcF");
            InputSignal = testCase.createDeterministicInput(P);
            NumberInputSamples = numel(InputSignal);

            % The one-sample frame forces the streaming implementations to
            % preserve an incomplete decimation block across a boundary.
            FrameLengths = [3, 17, 1, 64, 5, 91, 76];
            testCase.verifyEqual(sum(FrameLengths), NumberInputSamples);

            %% Signed Fixed-Point Input Representation

            InputFormat.WL = 16;
            InputFormat.IWL = 2;
            InputFormat.FWL = 14;

            InputScale = 2^InputFormat.FWL;
            InputCodes = int64(round(InputSignal * InputScale));
            QuantizedInput = ...
                double(InputCodes) / InputScale;

            MinimumInputCode = ...
                -bitshift(int64(1), InputFormat.WL - 1);
            MaximumInputCode = ...
                bitshift(int64(1), InputFormat.WL - 1) - int64(1);

            testCase.verifyGreaterThanOrEqual( ...
                InputCodes, MinimumInputCode);
            testCase.verifyLessThanOrEqual( ...
                InputCodes, MaximumInputCode);
            testCase.verifyLessThanOrEqual( ...
                max(abs(InputSignal - QuantizedInput)), ...
                0.5 / InputScale + eps);

            %% Whole-Vector Floating-Point Reference

            WholeFloating = DSP(P);
            [ExpectedFloatingOutput, ExpectedFloatingInfo] = ...
                WholeFloating.ProcessFrame(InputSignal, true);

            %% Characterize the Fixed MAC and Select a Safe Format

            ReferenceFixed = FixedDSPDecimator(P);

            CoefficientFormat.WL = ReferenceFixed.CoeffWL;
            CoefficientFormat.IWL = ReferenceFixed.CoeffIWL;
            CoefficientFormat.FWL = ReferenceFixed.CoeffFWL;

            [PaddedInputCodes, NumberBlocks] = ...
                ReferenceFixed.FixedPrepareInput(InputCodes);

            [ReferenceFixedCodes, ReferenceMACData] = ...
                ReferenceFixed.FixedDecimator( ...
                PaddedInputCodes, NumberBlocks, ...
                InputFormat, CoefficientFormat);

            MACFormat = FindMACFormat( ...
                InputFormat, ...
                CoefficientFormat, ...
                ReferenceFixed.BranchCoefficients, ...
                ReferenceMACData, ...
                1);

            testCase.verifyEqual( ...
                MACFormat.FWL, MACFormat.ProductFWL);
            testCase.verifyEqual( ...
                MACFormat.RoundingMethod, 'Nearest');
            testCase.verifyEqual( ...
                MACFormat.OverflowAction, 'Saturate');

            % A one-frame bounded fixed execution supplies the expected
            % codes, cumulative MAC data, final state, and padding metadata.
            WholeFixed = FixedDSPDecimator(P);
            [ExpectedFixedCodes, ExpectedFixedMACData, ...
                ExpectedFixedInfo] = WholeFixed.ProcessFrame( ...
                InputCodes, true, ...
                InputFormat, CoefficientFormat, MACFormat);

            testCase.verifyEqual( ...
                ExpectedFixedCodes, ReferenceFixedCodes);

            %% Irregular Frame Processing of Both Implementations

            FrameFloating = DSP(P);
            [ActualFloatingOutput, FloatingOutputIndex, ...
                FinalFloatingInfo] = ...
                testCase.processFloatingFrames( ...
                FrameFloating, InputSignal, FrameLengths);

            FrameFixed = FixedDSPDecimator(P);
            [ActualFixedCodes, ActualFixedMACData, ...
                FixedOutputIndex, FinalFixedInfo] = ...
                testCase.processFixedFrames( ...
                FrameFixed, InputCodes, FrameLengths, ...
                InputFormat, CoefficientFormat, MACFormat);

            %% First Prove Frame Partition Invariance

            ExpectedOutputIndex = (0:NumberBlocks-1)';

            testCase.verifyEqual( ...
                ActualFloatingOutput, ExpectedFloatingOutput, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                FloatingOutputIndex, ExpectedOutputIndex);
            testCase.verifyEqual( ...
                FrameFloating.DelayLines, WholeFloating.DelayLines, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual( ...
                ActualFixedCodes, ExpectedFixedCodes);
            testCase.verifyEqual( ...
                ActualFixedMACData, ExpectedFixedMACData);
            testCase.verifyEqual( ...
                FixedOutputIndex, ExpectedOutputIndex);
            testCase.verifyEqual( ...
                FrameFixed.DelayLines, WholeFixed.DelayLines);

            %% Convert Fixed MAC Codes Back to Real Values

            [FixedRealOutput, ConvertedMACData] = ...
                FixedToRealConverter( ...
                ActualFixedCodes, ActualFixedMACData);
            FixedRealOutput = FixedRealOutput(:);

            testCase.verifySize( ...
                FixedRealOutput, size(ExpectedFloatingOutput));

            %% Derive an Objective Floating-Versus-Fixed Error Bound

            FloatingCoefficients = ...
                WholeFloating.FilterCoefficients(:);
            QuantizedCoefficients = ...
                double(ReferenceFixed.FixedFilterCoefficients(:)) / ...
                ReferenceFixed.CoeffScale;

            testCase.verifyEqual( ...
                ReferenceFixed.FilterCoefficients(:), ...
                FloatingCoefficients, "AbsTol", 1e-15);
            testCase.verifySize( ...
                QuantizedCoefficients, size(FloatingCoefficients));

            InputQuantizationBound = ...
                max(abs(InputSignal - QuantizedInput)) * ...
                sum(abs(FloatingCoefficients));

            CoefficientQuantizationBound = ...
                max(abs(QuantizedInput)) * ...
                sum(abs( ...
                FloatingCoefficients - QuantizedCoefficients));

            RemovedFractionBits = ...
                MACFormat.ProductFWL - MACFormat.FWL;

            if RemovedFractionBits > 0
                % Nearest rounding contributes at most half of one MAC LSB
                % per nonzero product in one complete FIR output.
                MACRoundingBound = ...
                    ReferenceMACData.NumberProducts * ...
                    0.5 * 2^(-MACFormat.FWL);
            else
                MACRoundingBound = 0;
            end

            NumericalTolerance = ...
                64 * eps(max(1, max(abs(ExpectedFloatingOutput))));

            TotalErrorBound = ...
                InputQuantizationBound + ...
                CoefficientQuantizationBound + ...
                MACRoundingBound + ...
                NumericalTolerance;

            OutputError = ...
                FixedRealOutput - ExpectedFloatingOutput;
            MaximumAbsoluteError = max(abs(OutputError));
            RMSError = sqrt(mean(OutputError.^2));

            testCase.verifyLessThanOrEqual( ...
                MaximumAbsoluteError, TotalErrorBound);
            testCase.verifyLessThanOrEqual( ...
                RMSError, TotalErrorBound);

            %% Verify Counts, Padding, Finalization, and Overflow Safety

            ExpectedOutputCount = ...
                ceil(NumberInputSamples / DcF);
            ExpectedPadding = ...
                mod(DcF - mod(NumberInputSamples, DcF), DcF);

            testCase.verifyEqual(NumberBlocks, ExpectedOutputCount);
            testCase.verifyEqual( ...
                numel(ExpectedFloatingOutput), ExpectedOutputCount);
            testCase.verifyEqual( ...
                numel(ActualFixedCodes), ExpectedOutputCount);
            testCase.verifyEqual( ...
                ExpectedFloatingInfo.NumPaddingSamples, ExpectedPadding);
            testCase.verifyEqual( ...
                ExpectedFixedInfo.NumPaddingSamples, ExpectedPadding);
            testCase.verifyEqual( ...
                FinalFloatingInfo.NumPaddingSamples, ExpectedPadding);
            testCase.verifyEqual( ...
                FinalFixedInfo.NumPaddingSamples, ExpectedPadding);

            testCase.verifyEqual( ...
                FrameFloating.InputSamplesReceived, NumberInputSamples);
            testCase.verifyEqual( ...
                FrameFloating.OutputSamplesProduced, ExpectedOutputCount);
            testCase.verifyEqual( ...
                FrameFloating.FramesProcessed, numel(FrameLengths));
            testCase.verifyEqual( ...
                FrameFixed.InputSamplesReceived, NumberInputSamples);
            testCase.verifyEqual( ...
                FrameFixed.OutputSamplesProduced, ExpectedOutputCount);
            testCase.verifyEqual( ...
                FrameFixed.FramesProcessed, numel(FrameLengths));

            testCase.verifyEqual( ...
                ConvertedMACData.ProductCastOverflowCount, 0);
            testCase.verifyEqual( ...
                ConvertedMACData.BranchAccumulatorOverflowCount, 0);
            testCase.verifyEqual( ...
                ConvertedMACData.FinalAccumulatorOverflowCount, 0);
            testCase.verifyEqual( ...
                ConvertedMACData.TotalAccumulatorOverflowCount, 0);
            testCase.verifyTrue(FrameFloating.StreamFinalized);
            testCase.verifyTrue(FrameFixed.StreamFinalized);
        end
    end

    methods (Access = private)

        function P = createPolyphaseParameters(~)
            %% Shared Floating and Fixed Decimator Specifications

            P = DSPParameters();
            P.setValue("DcF", 4);
            P.setValue("Fs_DSP", 5000);
            P.setValue("Fpass", 400);
            P.setValue("Fstop", 600);
            P.setValue("Astop", 60);
            P.setValue("Apass", 1);
            P.setValue("B", 25);
        end

        function InputSignal = createDeterministicInput(~, P)
            %% Multitone and Transient Stimulus With No ADC Dependency

            Fs = P.getValue("Fs_DSP");
            NumberSamples = 257;
            n = (0:NumberSamples-1)';

            % Two passband tones and one stopband tone exercise both the
            % desired response and anti-alias rejection. The isolated pulse
            % also exercises the complete FIR delay-line transient.
            InputSignal = ...
                0.55 * sin(2*pi*175*n/Fs) + ...
                0.23 * cos(2*pi*325*n/Fs) + ...
                0.08 * sin(2*pi*950*n/Fs);
            InputSignal(83) = InputSignal(83) + 0.06;
        end

        function [Output, OutputSampleIndex, FinalFrameInfo] = ...
                processFloatingFrames( ...
                testCase, D, InputSignal, FrameLengths)
            %% Processes One Floating Stream Using an Explicit Partition

            if sum(FrameLengths) ~= numel(InputSignal)
                error('TestFloatingVsFixedDecimator:FrameLengthMismatch', ...
                    ['FrameLengths must contain every floating-point ', ...
                     'input sample exactly once.']);
            end

            Output = zeros(0, 1);
            OutputSampleIndex = zeros(0, 1);
            FinalFrameInfo = [];
            StartIndex = 1;

            for k = 1:numel(FrameLengths)
                EndIndex = StartIndex + FrameLengths(k) - 1;
                InputFrame = InputSignal(StartIndex:EndIndex);
                IsLastFrame = k == numel(FrameLengths);

                [OutputFrame, FinalFrameInfo] = ...
                    D.ProcessFrame(InputFrame, IsLastFrame);

                Output = [Output; OutputFrame]; %#ok<AGROW>
                OutputSampleIndex = [ ...
                    OutputSampleIndex; ...
                    FinalFrameInfo.OutputSampleIndex]; %#ok<AGROW>

                StartIndex = EndIndex + 1;
            end

            testCase.verifyTrue(D.StreamFinalized);
        end

        function [OutputCodes, FinalMACData, OutputSampleIndex, ...
                FinalFrameInfo] = processFixedFrames( ...
                testCase, D, InputCodes, FrameLengths, ...
                InputFormat, CoefficientFormat, MACFormat)
            %% Processes One Integer-Code Stream Using the Same Partition

            if sum(FrameLengths) ~= numel(InputCodes)
                error('TestFloatingVsFixedDecimator:FrameLengthMismatch', ...
                    ['FrameLengths must contain every fixed-point input ', ...
                     'code exactly once.']);
            end

            OutputCodes = zeros(1, 0, 'int64');
            FinalMACData = [];
            OutputSampleIndex = zeros(0, 1);
            FinalFrameInfo = [];
            StartIndex = 1;

            for k = 1:numel(FrameLengths)
                EndIndex = StartIndex + FrameLengths(k) - 1;
                InputFrame = InputCodes(StartIndex:EndIndex);
                IsLastFrame = k == numel(FrameLengths);

                [OutputFrame, FinalMACData, FinalFrameInfo] = ...
                    D.ProcessFrame( ...
                    InputFrame, IsLastFrame, ...
                    InputFormat, CoefficientFormat, MACFormat);

                OutputCodes = ...
                    [OutputCodes, OutputFrame]; %#ok<AGROW>
                OutputSampleIndex = [ ...
                    OutputSampleIndex; ...
                    FinalFrameInfo.OutputSampleIndex]; %#ok<AGROW>

                StartIndex = EndIndex + 1;
            end

            testCase.verifyTrue(D.StreamFinalized);
        end
    end
end
