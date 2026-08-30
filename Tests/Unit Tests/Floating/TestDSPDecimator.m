classdef TestDSPDecimator < matlab.unittest.TestCase
    %% ===========================================
    %% UNIT TEST SUITE FOR DSP POLYPHASE DECIMATOR
    %% ===========================================

    methods (Test)
        function testKnownPolyphaseMACSequence(testCase)
            %% Validates Shift Registers, Branch MACs, and Branch Summation

            P = testCase.createDefaultParameters();
            P.setValue("DcF", 2);

            D = DSP(P);

            % Replace generated coefficients with a simple known
            % two-branch, two-tap polyphase filter.
            D.BranchCoefficients = [1 10; ...
                                    2 20];

            Input = [1 2 3 4];

            [InPadded, NumBlocks] = D.PrepareInput(Input);

            DecimatedSignal = D.Decimator(InPadded, NumBlocks);

            % Block 1:
            % Branch 0 -> 1*2 + 10*0 = 2
            % Branch 1 -> 2*1 + 20*0 = 2
            % Output = 4
            %
            % Block 2:
            % Branch 0 -> 1*4 + 10*2 = 24
            % Branch 1 -> 2*3 + 20*1 = 26
            % Output = 50
            expectedOutput = [4; 50];

            testCase.verifyEqual(DecimatedSignal, expectedOutput);
        end


        function testDecimatorMatchesDirectFIRReference(testCase)
            %% Validates Polyphase Output Against Direct FIR Then Downsample

            P = testCase.createDefaultParameters();
            D = DSP(P);

            DcF = P.getValue("DcF");

            Input = 1:40;

            [InPadded, NumBlocks] = D.PrepareInput(Input);

            DecimatedSignal = D.Decimator(InPadded, NumBlocks);

            % Independent direct-form reference.
            h = D.FilterCoefficients(:);
            FullFIR = conv(InPadded, h);

            % Current commutator alignment produces the FIR output at
            % input indices DcF, 2*DcF, 3*DcF, ...
            expectedOutput = ...
                FullFIR(DcF:DcF:length(InPadded));

            testCase.verifyEqual( ...
                DecimatedSignal, expectedOutput, ...
                "AbsTol", 1e-12);
        end

        function testDecimatedOutputLengthEqualsNumberOfBlocks(testCase)
            %% Validates One Output Sample Is Produced Per DcF Input Samples

            P = testCase.createDefaultParameters();
            D = DSP(P);

            Input = 1:13;

            [InPadded, NumBlocks] = D.PrepareInput(Input);

            DecimatedSignal = D.Decimator(InPadded, NumBlocks);

            testCase.verifyLength(DecimatedSignal, NumBlocks);
        end

        function testConstructorInitializesFrameState(testCase)
            %% Validates Initial Residual, Delay-Line, and Counter State

            P = testCase.createDefaultParameters();
            D = DSP(P);

            ExpectedL = size(D.BranchCoefficients, 2);

            testCase.verifySize(D.PendingInput, [0, 1]);
            testCase.verifySize( ...
                D.DelayLines, [D.DcF, ExpectedL]);
            testCase.verifyEqual( ...
                D.DelayLines, zeros(D.DcF, ExpectedL));
            testCase.verifyEqual(D.InputSamplesReceived, 0);
            testCase.verifyEqual(D.OutputSamplesProduced, 0);
            testCase.verifyEqual(D.FramesProcessed, 0);
            testCase.verifyFalse(D.StreamFinalized);
        end

        function testResidualAndDelayStatePersistAcrossFrames(testCase)
            %% Validates Input Blocking and Branch FIR State Continuity

            P = testCase.createDefaultParameters();
            P.setValue("DcF", 2);
            D = DSP(P);

            D.BranchCoefficients = [1, 10; 2, 20];
            D.ResetDecimator();

            [FirstOutput, FirstInfo] = ...
                D.ProcessFrame([1; 2; 3], false);
            [SecondOutput, SecondInfo] = ...
                D.ProcessFrame(4, true);

            testCase.verifyEqual(FirstOutput, 4);
            testCase.verifyEqual(SecondOutput, 50);
            testCase.verifyEqual(D.PendingInput, zeros(0, 1));
            testCase.verifyEqual(FirstInfo.NumBufferedSamples, 1);
            testCase.verifyEqual(FirstInfo.OutputSampleIndex, 0);
            testCase.verifyEqual(SecondInfo.NumBufferedSamples, 0);
            testCase.verifyEqual(SecondInfo.OutputSampleIndex, 1);
            testCase.verifyEqual(D.InputSamplesReceived, 4);
            testCase.verifyEqual(D.OutputSamplesProduced, 2);
            testCase.verifyEqual(D.FramesProcessed, 2);
            testCase.verifyTrue(D.StreamFinalized);
        end

        function testFinalFrameAlonePadsIncompleteBlock(testCase)
            %% Validates Residual Samples Are Not Padded Before End-of-Stream

            P = testCase.createDefaultParameters();
            D = DSP(P);

            D.BranchCoefficients = ones(D.DcF, 1);
            D.ResetDecimator();

            [FirstOutput, FirstInfo] = ...
                D.ProcessFrame([1; 2; 3], false);

            testCase.verifySize(FirstOutput, [0, 1]);
            testCase.verifyEqual(FirstInfo.NumBufferedSamples, 3);
            testCase.verifyEqual(FirstInfo.NumPaddingSamples, 0);

            [FinalOutput, FinalInfo] = ...
                D.ProcessFrame(zeros(0, 1), true);

            % The single result generated from the completed zero-padded
            % block is an intentional output sample and must be retained.
            ExpectedOutputCount = ceil(3 / D.DcF);
            testCase.verifyEqual(FinalOutput, 6);
            testCase.verifyEqual(numel(FinalOutput), ExpectedOutputCount);
            testCase.verifyEqual(FinalInfo.NumPaddingSamples, 1);
            testCase.verifyEqual(FinalInfo.NumBufferedSamples, 0);
            testCase.verifyEqual(D.InputSamplesReceived, 3);
            testCase.verifyEqual( ...
                D.OutputSamplesProduced, ExpectedOutputCount);
            testCase.verifyEqual(D.FramesProcessed, 1);
            testCase.verifyTrue(D.StreamFinalized);
        end

        function testImpulseTailCrossesDecimatorFrameBoundary(testCase)
            %% Validates FIR memory continues after a boundary impulse

            P = testCase.createDefaultParameters();
            N = 96;
            BoundarySample = 16;

            InputSignal = zeros(N, 1);
            InputSignal(BoundarySample) = 1;

            WholeD = DSP(P);
            ExpectedOutput = ...
                WholeD.ProcessFrame(InputSignal, true);

            FrameD = DSP(P);
            FrameLengths = [16, 3, 29, 48];
            [ActualOutput, ActualOutputIndex] = ...
                testCase.processInFrames( ...
                FrameD, InputSignal, FrameLengths);

            DirectReference = ...
                testCase.directFIRDecimatorReference( ...
                InputSignal, FrameD.FilterCoefficients, FrameD.DcF);

            testCase.verifyEqual( ...
                ActualOutput, ExpectedOutput, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualOutput, DirectReference, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualOutputIndex, (0:numel(ExpectedOutput)-1)');

            FirstFrameOutputCount = BoundarySample / FrameD.DcF;
            testCase.verifyGreaterThan( ...
                norm(ActualOutput(FirstFrameOutputCount + 1:end), inf), ...
                1e-15);
            testCase.verifyEqual( ...
                FrameD.DelayLines, WholeD.DelayLines, "AbsTol", 1e-12);
        end

        function testFramedDecimatorMatchesDirectFIRReference(testCase)
            %% Validates Arbitrary Frame Partitioning Against Direct FIR

            P = testCase.createDefaultParameters();
            D = DSP(P);
            N = 73;
            InputSignal = ...
                0.4 * sin(0.17 * (0:N-1)') + ...
                0.03 * cos(0.07 * (0:N-1)');

            FrameLengths = [7, 3, 19, 2, 42];
            [ActualOutput, ActualOutputIndex] = ...
                testCase.processInFrames( ...
                    D, InputSignal, FrameLengths);

            ExpectedOutput = ...
                testCase.directFIRDecimatorReference( ...
                    InputSignal, D.FilterCoefficients, D.DcF);

            testCase.verifyEqual( ...
                ActualOutput, ExpectedOutput, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualOutputIndex, ...
                (0:numel(ExpectedOutput)-1)');
            testCase.verifyEqual(D.InputSamplesReceived, N);
            testCase.verifyEqual( ...
                D.OutputSamplesProduced, numel(ExpectedOutput));
            testCase.verifyEqual( ...
                D.FramesProcessed, numel(FrameLengths));
            testCase.verifyEqual(D.PendingInput, zeros(0, 1));
            testCase.verifyTrue(D.StreamFinalized);
        end

        function testRandomizedPartitionsMatchWholeVectorReference(testCase)
            %% Reproducible property regression over irregular frame layouts

            P = testCase.createDefaultParameters();
            N = 191;
            SampleIndex = (0:N-1)';
            InputSignal = ...
                0.47 * sin(0.071 * SampleIndex) + ...
                0.13 * cos(0.193 * SampleIndex) + ...
                0.02 * sin(0.311 * SampleIndex);

            WholeD = DSP(P);
            [ExpectedOutput, ExpectedInfo] = ...
                WholeD.ProcessFrame(InputSignal, true);
            ExpectedDelayLines = WholeD.DelayLines;

            OldRngState = rng;
            CleanupObj = onCleanup(@() rng(OldRngState)); 
            rng(913, "twister");

            NumberTrials = 6;

            for TrialIndex = 1:NumberTrials
                NumberFrames = 3 + TrialIndex;
                FrameLengths = testCase.createRandomPartition( ...
                    N, NumberFrames);

                FrameD = DSP(P);
                [ActualOutput, ActualOutputIndex] = ...
                    testCase.processInFrames( ...
                    FrameD, InputSignal, FrameLengths);

                testCase.verifyEqual( ...
                    ActualOutput, ExpectedOutput, "AbsTol", 1e-12);
                testCase.verifyEqual( ...
                    ActualOutputIndex, ExpectedInfo.OutputSampleIndex);
                testCase.verifyEqual( ...
                    FrameD.DelayLines, ExpectedDelayLines, ...
                    "AbsTol", 1e-12);

                testCase.verifyEqual(FrameD.InputSamplesReceived, N);
                testCase.verifyEqual( ...
                    FrameD.OutputSamplesProduced, numel(ExpectedOutput));
                testCase.verifyEqual( ...
                    FrameD.FramesProcessed, numel(FrameLengths));
                testCase.verifyEqual( ...
                    FrameD.PendingInput, zeros(0, 1));
                testCase.verifyTrue(FrameD.StreamFinalized);
            end
        end

        function testResetDecimatorMatchesFreshObject(testCase)
            %% Validates Reset Clears Residual, FIR, Counter, and EOS State

            P = testCase.createDefaultParameters();
            ResetDSP = DSP(P);
            FreshDSP = DSP(P);

            ResetDSP.ProcessFrame((1:11)', false);
            ResetDSP.ResetDecimator();

            testCase.verifyEqual(ResetDSP.PendingInput, zeros(0, 1));
            testCase.verifyEqual( ...
                ResetDSP.DelayLines, zeros(size(ResetDSP.DelayLines)));
            testCase.verifyEqual(ResetDSP.InputSamplesReceived, 0);
            testCase.verifyEqual(ResetDSP.OutputSamplesProduced, 0);
            testCase.verifyEqual(ResetDSP.FramesProcessed, 0);
            testCase.verifyFalse(ResetDSP.StreamFinalized);

            InputSignal = (101:147)';
            FrameLengths = [5, 13, 29];
            ResetOutput = testCase.processInFrames( ...
                ResetDSP, InputSignal, FrameLengths);
            FreshOutput = testCase.processInFrames( ...
                FreshDSP, InputSignal, FrameLengths);

            testCase.verifyEqual( ...
                ResetOutput, FreshOutput, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ResetDSP.DelayLines, FreshDSP.DelayLines, ...
                "AbsTol", 1e-12);
        end

        function testEmptyNonfinalFrameDoesNotChangeState(testCase)
            %% Validates Empty Nonfinal Calls Are State-Neutral

            P = testCase.createDefaultParameters();
            D = DSP(P);
            D.ProcessFrame([1; 2; 3], false);

            PendingBefore = D.PendingInput;
            DelayLinesBefore = D.DelayLines;
            CountersBefore = [ ...
                D.InputSamplesReceived, ...
                D.OutputSamplesProduced, ...
                D.FramesProcessed];

            [OutputFrame, FrameInfo] = ...
                D.ProcessFrame(zeros(0, 1), false);

            CountersAfter = [ ...
                D.InputSamplesReceived, ...
                D.OutputSamplesProduced, ...
                D.FramesProcessed];

            testCase.verifySize(OutputFrame, [0, 1]);
            testCase.verifyEqual(D.PendingInput, PendingBefore);
            testCase.verifyEqual(D.DelayLines, DelayLinesBefore);
            testCase.verifyEqual(CountersAfter, CountersBefore);
            testCase.verifyEqual( ...
                FrameInfo.NumBufferedSamples, numel(PendingBefore));
            testCase.verifyFalse(D.StreamFinalized);
        end

        function testInvalidFrameAndLastFrameFlagAreRejected(testCase)
            %% Validates Frame and End-of-Stream Input Contracts

            P = testCase.createDefaultParameters();
            D = DSP(P);

            InvalidFrames = { ...
                ones(2, 2), [1; NaN], [1; Inf], [1; 1i]};

            for k = 1:numel(InvalidFrames)
                InvalidFrame = InvalidFrames{k};
                testCase.verifyError( ...
                    @() D.ProcessFrame(InvalidFrame, false), ...
                    'DSP:InvalidInputFrame');
            end

            InvalidFlags = {2, -1, NaN, [true, false], "true"};

            for k = 1:numel(InvalidFlags)
                InvalidFlag = InvalidFlags{k};
                testCase.verifyError( ...
                    @() D.ProcessFrame(1, InvalidFlag), ...
                    'DSP:InvalidLastFrameFlag');
            end

            testCase.verifyEqual(D.InputSamplesReceived, 0);
            testCase.verifyEqual(D.OutputSamplesProduced, 0);
            testCase.verifyEqual(D.FramesProcessed, 0);
        end

        function testInputAfterFinalFrameIsRejectedUntilReset(testCase)
            %% Validates Final Padding Can Be Applied Only Once per Stream

            P = testCase.createDefaultParameters();
            D = DSP(P);
            D.ProcessFrame((1:5)', true);

            testCase.verifyError( ...
                @() D.ProcessFrame(6, false), ...
                'DSP:StreamAlreadyFinalized');

            D.ResetDecimator();
            OutputAfterReset = D.ProcessFrame((1:4)', true);
            testCase.verifyLength(OutputAfterReset, 1);
        end

        function testUnassignedDecimationFactorIsRejected(testCase)
            %% Validates DSP Construction Requires a Valid DcF

            P = testCase.createFilterParameters();

            testCase.verifyError( ...
                @() DSP(P), ...
                'DSP:InvalidDecimationFactor');
        end
    end

    methods (Access = private)
        function P = createDefaultParameters(testCase)
            %% Creates Default Parameter Object For DSP Decimator Tests

            P = testCase.createFilterParameters();

            P.setValue("DcF", 4); % Decimation Factor
        end

        function P = createFilterParameters(~)
            %% Creates LPF Parameters Without Assigning DcF

            P = DSPParameters();

            % LPF design parameters
            P.setValue("Fs_DSP", 2000);
            P.setValue("Fpass", 200);
            P.setValue("Fstop", 300);
            P.setValue("Astop", 60);
            P.setValue("Apass", 1);
            P.setValue("B", 25);
        end

        function [Output, OutputSampleIndex] = ...
                processInFrames( ...
                    testCase, D, InputSignal, FrameLengths)
            %% Processes One Signal Using an Explicit Frame Partition

            if sum(FrameLengths) ~= numel(InputSignal)
                error('TestDSPDecimator:FrameLengthMismatch', ...
                    ['The frame lengths must contain every input ', ...
                     'sample exactly once.']);
            end

            Output = zeros(0, 1);
            OutputSampleIndex = zeros(0, 1);
            StartIndex = 1;

            for k = 1:numel(FrameLengths)
                EndIndex = StartIndex + FrameLengths(k) - 1;
                InputFrame = InputSignal(StartIndex:EndIndex);
                IsLastFrame = k == numel(FrameLengths);

                [OutputFrame, FrameInfo] = ...
                    D.ProcessFrame(InputFrame, IsLastFrame);

                Output = [Output; OutputFrame]; %#ok<AGROW>
                OutputSampleIndex = [ ...
                    OutputSampleIndex; ...
                    FrameInfo.OutputSampleIndex]; %#ok<AGROW>

                StartIndex = EndIndex + 1;
            end

            testCase.verifyTrue(D.StreamFinalized);
        end

        function FrameLengths = createRandomPartition( ...
                ~, TotalLength, NumberFrames)
            %% Creates Positive Frame Lengths That Sum to TotalLength

            if NumberFrames < 1 || NumberFrames > TotalLength
                error('TestDSPDecimator:InvalidRandomPartition', ...
                    ['NumberFrames must lie between one and the ', ...
                     'number of input samples.']);
            end

            if NumberFrames == 1
                FrameLengths = TotalLength;
                return
            end

            % Force one one-sample frame so every trial crosses the
            % decimation block phase; randomize all remaining boundaries.
            CandidateCutPoints = 2:TotalLength-1;
            NumberRandomCuts = NumberFrames - 2;
            RandomOrder = randperm( ...
                numel(CandidateCutPoints), NumberRandomCuts);
            CutPoints = sort([ ...
                1, CandidateCutPoints(RandomOrder)]);
            FrameLengths = diff([0, CutPoints, TotalLength]);
        end

        function ExpectedOutput = directFIRDecimatorReference( ...
                ~, InputSignal, FilterCoefficients, DcF)
            %% Creates Independent FIR-Then-Downsample Reference Output

            InputSignal = double(InputSignal(:));
            PadLength = mod( ...
                DcF - mod(numel(InputSignal), DcF), DcF);
            PaddedInput = [InputSignal; zeros(PadLength, 1)];

            FullFIR = conv( ...
                PaddedInput, FilterCoefficients(:));
            ExpectedOutput = ...
                FullFIR(DcF:DcF:numel(PaddedInput));
        end

        function P = createSignalChainParameters(testCase)
            %% Creates Parameters for the Full Chain Through Floating DSP

            P = testCase.createDefaultParameters();

            % 420 high-rate samples -> 105 ADC samples -> 27 DSP outputs.
            P.setValue("Fs", 20000);
            P.setValue("FrameLength", 31);
            P.setValue("Dur", 0.021);
            P.setValue("DF", 4);
            P.setValue("DcF", 4);

            % Signal generator.
            P.setValue("Aburst", 0.5);
            P.setValue("mu", 0.004);
            P.setValue("Sigma", 0.001);
            P.setValue("Ad", 1.0);
            P.setValue("Lambda", 120);
            P.setValue("EST", 0.015);
            P.setValue("FData", 200);
            P.setValue("An", 0.1);
            P.setValue("Fnoise", 7000);
            P.setValue("Anf", 1e-3);
            P.setValue("DC", 0.25);

            % Analog-front-end-equivalent HPF and anti-alias LPF.
            P.setValue("FcHigh", 20);
            P.setValue("FcLow", 2000);
            P.setValue("nHpf", 4);
            P.setValue("nLpf", 6);

            % AGC and bipolar midtread quantizer.
            P.setValue("Vfs", 1.0);
            P.setValue("NumBits", 8);
            P.setValue("EnvAttack", 0.005);
            P.setValue("EnvRelease", 0.020);
            P.setValue("GainAttack", 0.005);
            P.setValue("GainRelease", 0.020);
            P.setValue("GateAttack", 0.005);
            P.setValue("GateRelease", 0.020);

            % ADC output is 5 kHz; DSP output is 1.25 kHz with a
            % 625 Hz Nyquist frequency.
            P.setValue("Fs_DSP", 5000);
            P.setValue("Fpass", 400);
            P.setValue("Fstop", 600);
            P.setValue("Astop", 60);
            P.setValue("Apass", 1);
            P.setValue("B", 25);
        end
    end
end
