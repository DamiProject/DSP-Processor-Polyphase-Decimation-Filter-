classdef TestFixedDSPDecimator < matlab.unittest.TestCase
    %% =====================================================
    %% UNIT TEST SUITE FOR FIXED-POINT POLYPHASE DECIMATOR
    %% =====================================================

    methods (Test)

        function testReferenceMACExactIntegerArithmeticAndState(testCase)
            D = testCase.createControlledDecimator(int64([1 2; 3 4]));

            InPadded = int64([1; 2; 3; 4; 5; 6]);
            NumBlocks = 3;

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            [DecimatedCodes, MACData] = D.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, CoefficientFormat);

            testCase.verifyEqual(DecimatedCodes, int64([5 21 41]));
            testCase.verifyClass(DecimatedCodes, 'int64');
            testCase.verifySize(DecimatedCodes, [1 NumBlocks]);

            testCase.verifyEqual(MACData.Product.MaxCode, int64(15));
            testCase.verifyEqual(MACData.Product.MinCode, int64(0));
            testCase.verifyEqual(MACData.Product.MaxAbsCode, int64(15));

            testCase.verifyEqual(MACData.BranchAccumulator.MaxCode, int64(27));
            testCase.verifyEqual(MACData.BranchAccumulator.MinCode, int64(2));
            testCase.verifyEqual(MACData.BranchAccumulator.MaxAbsCode, int64(27));
            testCase.verifyEqual( ...
                MACData.BranchAccumulator.GrowthByTapCode, int64([15 27]));

            testCase.verifyEqual(MACData.FinalAccumulator.MaxCode, int64(41));
            testCase.verifyEqual(MACData.FinalAccumulator.MinCode, int64(5));
            testCase.verifyEqual(MACData.FinalAccumulator.MaxAbsCode, int64(41));
            testCase.verifyEqual( ...
                MACData.FinalAccumulator.GrowthByBranchCode, int64([14 41]));

            testCase.verifyEqual(MACData.ProductFormat.WL, 16);
            testCase.verifyEqual(MACData.ProductFormat.IWL, 16);
            testCase.verifyEqual(MACData.ProductFormat.FWL, 0);

            testCase.verifyEqual(MACData.NumberProducts, 4);
            testCase.verifyEqual(MACData.GuardBits, 2);
            testCase.verifyEqual(MACData.ReferenceContainerWL, 18);

            testCase.verifyFalse(isfield(MACData, 'AccumulatorFormat'));

            testCase.verifyEqual(MACData.ProductCastOverflowCount, 0);
            testCase.verifyEqual(MACData.BranchAccumulatorOverflowCount, 0);
            testCase.verifyEqual(MACData.FinalAccumulatorOverflowCount, 0);
        end


        function testBoundedMACMatchesReferenceWhenFormatIsWideEnough(testCase)
            D = testCase.createControlledDecimator(int64([1 2; 3 4]));

            InPadded = int64([1; 2; 3; 4; 5; 6]);
            NumBlocks = 3;

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            [ReferenceCodes, ~] = D.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, CoefficientFormat);

            MACFormat.WL = 16;
            MACFormat.IWL = 16;
            MACFormat.FWL = 0;
            MACFormat.RoundingMethod = 'Nearest';
            MACFormat.OverflowAction = 'Saturate';

            [BoundedCodes, MACData] = D.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, ...
                CoefficientFormat, MACFormat);

            testCase.verifyEqual(BoundedCodes, ReferenceCodes);
            testCase.verifyEqual(BoundedCodes, int64([5 21 41]));
            testCase.verifyEqual(MACData.AccumulatorFormat, MACFormat);

            testCase.verifyEqual(MACData.ProductCastOverflowCount, 0);
            testCase.verifyEqual(MACData.BranchAccumulatorOverflowCount, 0);
            testCase.verifyEqual(MACData.FinalAccumulatorOverflowCount, 0);
        end


        function testNearestAndTruncateRequantization(testCase)
            D = testCase.createControlledDecimator(int64(1));

            InPadded = int64([3; -3]);
            NumBlocks = 2;

            InputFormat.WL = 3;
            InputFormat.IWL = 2;
            InputFormat.FWL = 1;

            CoefficientFormat.WL = 2;
            CoefficientFormat.IWL = 1;
            CoefficientFormat.FWL = 1;

            MACFormat.WL = 4;
            MACFormat.IWL = 3;
            MACFormat.FWL = 1;
            MACFormat.OverflowAction = 'Saturate';

            MACFormat.RoundingMethod = 'Nearest';
            NearestCodes = D.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, ...
                CoefficientFormat, MACFormat);

            MACFormat.RoundingMethod = 'Truncate';
            TruncatedCodes = D.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, ...
                CoefficientFormat, MACFormat);

            testCase.verifyEqual(NearestCodes, int64([2 -2]));
            testCase.verifyEqual(TruncatedCodes, int64([1 -1]));
        end


        function testProductCastSaturationAndCounter(testCase)
            D = testCase.createControlledDecimator(int64(3));

            InPadded = int64([4; -4]);
            NumBlocks = 2;

            InputFormat.WL = 4;
            InputFormat.IWL = 4;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 3;
            CoefficientFormat.IWL = 3;
            CoefficientFormat.FWL = 0;

            MACFormat.WL = 3;
            MACFormat.IWL = 3;
            MACFormat.FWL = 0;
            MACFormat.RoundingMethod = 'Nearest';
            MACFormat.OverflowAction = 'Saturate';

            [DecimatedCodes, MACData] = D.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, ...
                CoefficientFormat, MACFormat);

            testCase.verifyEqual(DecimatedCodes, int64([3 -4]));
            testCase.verifyEqual(MACData.ProductCastOverflowCount, 2);
            testCase.verifyEqual(MACData.BranchAccumulatorOverflowCount, 0);
            testCase.verifyEqual(MACData.FinalAccumulatorOverflowCount, 0);

            testCase.verifyEqual(MACData.Product.MaxCode, int64(12));
            testCase.verifyEqual(MACData.Product.MinCode, int64(-12));
        end


        function testBranchAccumulatorSaturationAndCounter(testCase)
            D = testCase.createControlledDecimator(int64([4 4]));

            InPadded = int64([1; 1]);
            NumBlocks = 2;

            InputFormat.WL = 2;
            InputFormat.IWL = 2;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 4;
            CoefficientFormat.IWL = 4;
            CoefficientFormat.FWL = 0;

            MACFormat.WL = 4;
            MACFormat.IWL = 4;
            MACFormat.FWL = 0;
            MACFormat.RoundingMethod = 'Nearest';
            MACFormat.OverflowAction = 'Saturate';

            [DecimatedCodes, MACData] = D.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, ...
                CoefficientFormat, MACFormat);

            testCase.verifyEqual(DecimatedCodes, int64([4 7]));
            testCase.verifyEqual(MACData.ProductCastOverflowCount, 0);
            testCase.verifyEqual(MACData.BranchAccumulatorOverflowCount, 1);
            testCase.verifyEqual(MACData.FinalAccumulatorOverflowCount, 0);
            testCase.verifyEqual( ...
                MACData.BranchAccumulator.GrowthByTapCode, int64([4 7]));
        end


        function testFinalAccumulatorSaturationAndCounter(testCase)
            D = testCase.createControlledDecimator(int64([5; 5]));

            InPadded = int64([1; 1; -1; -1]);
            NumBlocks = 2;

            InputFormat.WL = 2;
            InputFormat.IWL = 2;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 4;
            CoefficientFormat.IWL = 4;
            CoefficientFormat.FWL = 0;

            MACFormat.WL = 4;
            MACFormat.IWL = 4;
            MACFormat.FWL = 0;
            MACFormat.RoundingMethod = 'Nearest';
            MACFormat.OverflowAction = 'Saturate';

            [DecimatedCodes, MACData] = D.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, ...
                CoefficientFormat, MACFormat);

            testCase.verifyEqual(DecimatedCodes, int64([7 -8]));
            testCase.verifyEqual(MACData.ProductCastOverflowCount, 0);
            testCase.verifyEqual(MACData.BranchAccumulatorOverflowCount, 0);
            testCase.verifyEqual(MACData.FinalAccumulatorOverflowCount, 2);
        end


        function testOverflowActionError(testCase)
            D = testCase.createControlledDecimator(int64(3));

            InputFormat.WL = 4;
            InputFormat.IWL = 4;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 3;
            CoefficientFormat.IWL = 3;
            CoefficientFormat.FWL = 0;

            MACFormat.WL = 3;
            MACFormat.IWL = 3;
            MACFormat.FWL = 0;
            MACFormat.RoundingMethod = 'Nearest';
            MACFormat.OverflowAction = 'Error';

            testCase.verifyErrorContains( ...
                @() D.FixedDecimator( ...
                    int64(4), 1, InputFormat, ...
                    CoefficientFormat, MACFormat), ...
                'Fixed-point overflow occurred');
        end


        function testRejectsMACFractionLengthAboveProductPrecision(testCase)
            D = testCase.createControlledDecimator(int64(1));

            InputFormat.WL = 3;
            InputFormat.IWL = 2;
            InputFormat.FWL = 1;

            CoefficientFormat.WL = 2;
            CoefficientFormat.IWL = 1;
            CoefficientFormat.FWL = 1;

            MACFormat.WL = 6;
            MACFormat.IWL = 3;
            MACFormat.FWL = 3;
            MACFormat.RoundingMethod = 'Nearest';
            MACFormat.OverflowAction = 'Saturate';

            testCase.verifyErrorContains( ...
                @() D.FixedDecimator( ...
                    int64(1), 1, InputFormat, ...
                    CoefficientFormat, MACFormat), ...
                'MAC FWL cannot currently exceed');
        end


        function testRejectsCodesOutsideDeclaredWordLengths(testCase)
            InputFormat.WL = 2;
            InputFormat.IWL = 2;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 2;
            CoefficientFormat.IWL = 2;
            CoefficientFormat.FWL = 0;

            D = testCase.createControlledDecimator(int64(1));

            testCase.verifyErrorContains( ...
                @() D.FixedDecimator( ...
                    int64(2), 1, InputFormat, CoefficientFormat), ...
                'InPadded contains codes outside its declared WL');

            D = testCase.createControlledDecimator(int64(3));

            testCase.verifyErrorContains( ...
                @() D.FixedDecimator( ...
                    int64(1), 1, InputFormat, CoefficientFormat), ...
                'BranchCoefficients contains codes outside its declared WL');
        end


        function testRejectsProductWidthAboveInt64Limit(testCase)
            D = testCase.createControlledDecimator(int64(1));

            InputFormat.WL = 32;
            InputFormat.IWL = 32;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 32;
            CoefficientFormat.IWL = 32;
            CoefficientFormat.FWL = 0;

            testCase.verifyErrorContains( ...
                @() D.FixedDecimator( ...
                    int64(1), 1, InputFormat, CoefficientFormat), ...
                'supports product widths up to 63 bits');
        end


        function testConstructorInitializesFixedFrameState(testCase)
            P = testCase.createDefaultParameters(4);
            D = FixedDSPDecimator(P);

            ExpectedStateSize = ...
                [D.DcF, size(D.BranchCoefficients, 2)];

            testCase.verifyEqual( ...
                D.PendingInputCodes, zeros(0, 1, 'int64'));
            testCase.verifyEqual( ...
                D.DelayLines, zeros(ExpectedStateSize, 'int64'));
            testCase.verifyClass(D.DelayLines, 'int64');
            testCase.verifyEmpty(D.CumulativeMACData);
            testCase.verifyEqual(D.InputSamplesReceived, 0);
            testCase.verifyEqual(D.OutputSamplesProduced, 0);
            testCase.verifyEqual(D.FramesProcessed, 0);
            testCase.verifyFalse(D.StreamFormatInitialized);
            testCase.verifyFalse(D.StreamFinalized);
        end


        function testReferenceFramesMatchLegacyWholeVectorAndMACData(testCase)
            BranchCoefficients = int64([1 2; 3 4]);
            WholeD = testCase.createControlledDecimator( ...
                BranchCoefficients);
            FrameD = testCase.createControlledDecimator( ...
                BranchCoefficients);

            InputCodes = int64((1:11)');

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            [InPadded, NumBlocks] = ...
                WholeD.FixedPrepareInput(InputCodes);
            [ExpectedCodes, ExpectedMACData, ExpectedDelayLines] = ...
                WholeD.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, CoefficientFormat);

            [ActualCodes, ActualMACData, OutputSampleIndex] = ...
                testCase.processFixedFrames( ...
                FrameD, InputCodes, [1 4 2 4], ...
                InputFormat, CoefficientFormat, []);

            testCase.verifyEqual(ActualCodes, ExpectedCodes);
            testCase.verifyEqual(ActualMACData, ExpectedMACData);
            testCase.verifyEqual(FrameD.DelayLines, ExpectedDelayLines);
            testCase.verifyEqual( ...
                OutputSampleIndex, (0:NumBlocks-1)');
            testCase.verifyEqual(FrameD.InputSamplesReceived, 11);
            testCase.verifyEqual(FrameD.OutputSamplesProduced, NumBlocks);
            testCase.verifyEqual(FrameD.FramesProcessed, 4);
            testCase.verifyEqual( ...
                FrameD.PendingInputCodes, zeros(0, 1, 'int64'));
        end


        function testBoundedFramesMatchLegacyWithCumulativeOverflows(testCase)
            BranchCoefficients = int64([4 4]);
            WholeD = testCase.createControlledDecimator( ...
                BranchCoefficients);
            FrameD = testCase.createControlledDecimator( ...
                BranchCoefficients);

            InputCodes = int64(ones(5, 1));

            InputFormat.WL = 2;
            InputFormat.IWL = 2;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 4;
            CoefficientFormat.IWL = 4;
            CoefficientFormat.FWL = 0;

            MACFormat.WL = 4;
            MACFormat.IWL = 4;
            MACFormat.FWL = 0;
            MACFormat.RoundingMethod = 'Nearest';
            MACFormat.OverflowAction = 'Saturate';

            [ExpectedCodes, ExpectedMACData, ExpectedDelayLines] = ...
                WholeD.FixedDecimator( ...
                InputCodes, numel(InputCodes), ...
                InputFormat, CoefficientFormat, MACFormat);

            [ActualCodes, ActualMACData] = ...
                testCase.processFixedFrames( ...
                FrameD, InputCodes, [2 1 2], ...
                InputFormat, CoefficientFormat, MACFormat);

            testCase.verifyEqual(ActualCodes, ExpectedCodes);
            testCase.verifyEqual(ActualMACData, ExpectedMACData);
            testCase.verifyEqual(FrameD.DelayLines, ExpectedDelayLines);
            testCase.verifyGreaterThan( ...
                ActualMACData.BranchAccumulatorOverflowCount, 0);
        end


        function testFinalFrameAlonePadsIncompleteFixedBlock(testCase)
            BranchCoefficients = int64([1; 2; 3; 4]);
            WholeD = testCase.createControlledDecimator( ...
                BranchCoefficients);
            FrameD = testCase.createControlledDecimator( ...
                BranchCoefficients);

            InputCodes = int64((1:5)');

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            [InPadded, NumBlocks] = ...
                WholeD.FixedPrepareInput(InputCodes);
            ExpectedCodes = WholeD.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, CoefficientFormat);

            [FirstOutput, ~, FirstInfo] = FrameD.ProcessFrame( ...
                InputCodes(1:3), false, ...
                InputFormat, CoefficientFormat);

            testCase.verifyEqual( ...
                FirstOutput, zeros(1, 0, 'int64'));
            testCase.verifyEqual(FirstInfo.NumBufferedSamples, 3);
            testCase.verifyEqual(FirstInfo.NumPaddingSamples, 0);

            [FinalOutput, ~, FinalInfo] = FrameD.ProcessFrame( ...
                InputCodes(4:5), true, ...
                InputFormat, CoefficientFormat);

            % The second result comes from the final zero-padded block. It is
            % an intentional decimator output and must not be discarded.
            ExpectedOutputCount = ceil(numel(InputCodes) / FrameD.DcF);
            testCase.verifyEqual(FinalOutput, ExpectedCodes);
            testCase.verifyEqual( ...
                numel(FinalOutput), ExpectedOutputCount);
            testCase.verifyEqual(FinalInfo.NumBlocksProcessed, 2);
            testCase.verifyEqual(FinalInfo.NumPaddingSamples, 3);
            testCase.verifyEqual(FinalInfo.NumBufferedSamples, 0);
            testCase.verifyEqual(FinalInfo.OutputSampleIndex, [0; 1]);
            testCase.verifyEqual( ...
                FrameD.OutputSamplesProduced, ExpectedOutputCount);
            testCase.verifyTrue(FinalInfo.StreamFinalized);
        end

        function testImpulseTailCrossesFixedDecimatorFrameBoundary(testCase)
            %% Validates integer FIR state is retained after a boundary impulse

            BranchCoefficients = int64([1 2 1; 2 -1 3]);
            WholeD = testCase.createControlledDecimator( ...
                BranchCoefficients);
            FrameD = testCase.createControlledDecimator( ...
                BranchCoefficients);

            N = 24;
            BoundarySample = 6;
            InputCodes = zeros(N, 1, 'int64');
            InputCodes(BoundarySample) = int64(1);

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            [InPadded, NumBlocks] = ...
                WholeD.FixedPrepareInput(InputCodes);
            [ExpectedCodes, ExpectedMACData, ExpectedDelayLines] = ...
                WholeD.FixedDecimator( ...
                InPadded, NumBlocks, InputFormat, CoefficientFormat);

            [ActualCodes, ActualMACData, OutputSampleIndex] = ...
                testCase.processFixedFrames( ...
                FrameD, InputCodes, [6 1 7 10], ...
                InputFormat, CoefficientFormat, []);

            testCase.verifyEqual(ActualCodes, ExpectedCodes);
            testCase.verifyEqual(ActualMACData, ExpectedMACData);
            testCase.verifyEqual(FrameD.DelayLines, ExpectedDelayLines);
            testCase.verifyEqual( ...
                OutputSampleIndex, (0:NumBlocks-1)');

            FirstFrameOutputCount = BoundarySample / FrameD.DcF;
            testCase.verifyGreaterThan( ...
                norm(double( ...
                ActualCodes(FirstFrameOutputCount + 1:end)), inf), 0);
        end

        function testRandomizedFixedPartitionsMatchWholeVectorReference(testCase)
            %% Reproducible fixed-code regression over irregular partitions

            BranchCoefficients = int64([ ...
                 2 -1  3; ...
                -2  4  1; ...
                 1  0 -3; ...
                 3  2 -1]);

            WholeD = testCase.createControlledDecimator( ...
                BranchCoefficients);
            FrameD = testCase.createControlledDecimator( ...
                BranchCoefficients);

            N = 137;
            InputCodes = int64( ...
                mod((0:N-1)' * 37, 101) - 50);

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            MACFormat.WL = 24;
            MACFormat.IWL = 24;
            MACFormat.FWL = 0;
            MACFormat.RoundingMethod = 'Nearest';
            MACFormat.OverflowAction = 'Saturate';

            [InPadded, NumBlocks] = ...
                WholeD.FixedPrepareInput(InputCodes);
            [ExpectedCodes, ExpectedMACData, ExpectedDelayLines] = ...
                WholeD.FixedDecimator( ...
                InPadded, NumBlocks, ...
                InputFormat, CoefficientFormat, MACFormat);

            OldRngState = rng;
            CleanupObj = onCleanup(@() rng(OldRngState)); 
            rng(1913, "twister");

            NumberTrials = 6;

            for TrialIndex = 1:NumberTrials
                if TrialIndex > 1
                    FrameD.ResetDecimator();
                end

                NumberFrames = 3 + TrialIndex;
                FrameLengths = testCase.createRandomPartition( ...
                    N, NumberFrames);

                [ActualCodes, ActualMACData, OutputSampleIndex] = ...
                    testCase.processFixedFrames( ...
                    FrameD, InputCodes, FrameLengths, ...
                    InputFormat, CoefficientFormat, MACFormat);

                testCase.verifyEqual(ActualCodes, ExpectedCodes);
                testCase.verifyEqual(ActualMACData, ExpectedMACData);
                testCase.verifyEqual( ...
                    FrameD.DelayLines, ExpectedDelayLines);
                testCase.verifyEqual( ...
                    OutputSampleIndex, (0:NumBlocks-1)');

                testCase.verifyEqual(FrameD.InputSamplesReceived, N);
                testCase.verifyEqual( ...
                    FrameD.OutputSamplesProduced, NumBlocks);
                testCase.verifyEqual( ...
                    FrameD.FramesProcessed, numel(FrameLengths));
                testCase.verifyEqual( ...
                    FrameD.PendingInputCodes, zeros(0, 1, 'int64'));
                testCase.verifyTrue(FrameD.StreamFinalized);
            end
        end


        function testEmptyNonfinalFrameDoesNotChangeFixedState(testCase)
            D = testCase.createControlledDecimator( ...
                int64([1 2; 3 4]));

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            D.ProcessFrame( ...
                int64([1; 2]), false, ...
                InputFormat, CoefficientFormat);

            DelayLinesBefore = D.DelayLines;
            PendingBefore = D.PendingInputCodes;
            MACDataBefore = D.CumulativeMACData;
            InputCountBefore = D.InputSamplesReceived;
            OutputCountBefore = D.OutputSamplesProduced;
            FrameCountBefore = D.FramesProcessed;

            [OutputFrame, MACData, FrameInfo] = D.ProcessFrame( ...
                int64(zeros(0, 1)), false, ...
                InputFormat, CoefficientFormat);

            testCase.verifyEqual( ...
                OutputFrame, zeros(1, 0, 'int64'));
            testCase.verifyEqual(MACData, MACDataBefore);
            testCase.verifyEqual(D.DelayLines, DelayLinesBefore);
            testCase.verifyEqual(D.PendingInputCodes, PendingBefore);
            testCase.verifyEqual( ...
                D.InputSamplesReceived, InputCountBefore);
            testCase.verifyEqual( ...
                D.OutputSamplesProduced, OutputCountBefore);
            testCase.verifyEqual(D.FramesProcessed, FrameCountBefore);
            testCase.verifyEqual(FrameInfo.NumValidInputSamples, 0);
            testCase.verifyEqual(FrameInfo.NumBlocksProcessed, 0);
        end

        function testResetFixedDecimatorMatchesFreshObject(testCase)
            BranchCoefficients = int64([1 2; 3 4]);
            D = testCase.createControlledDecimator(BranchCoefficients);
            FreshD = testCase.createControlledDecimator(BranchCoefficients);

            InputCodes = int64((1:9)');

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            FirstCodes = testCase.processFixedFrames( ...
                D, InputCodes, [3 2 4], ...
                InputFormat, CoefficientFormat, []);

            D.ResetDecimator();

            ResetCodes = testCase.processFixedFrames( ...
                D, InputCodes, 9, ...
                InputFormat, CoefficientFormat, []);
            FreshCodes = testCase.processFixedFrames( ...
                FreshD, InputCodes, 9, ...
                InputFormat, CoefficientFormat, []);

            testCase.verifyEqual(ResetCodes, FirstCodes);
            testCase.verifyEqual(ResetCodes, FreshCodes);
            testCase.verifyEqual(D.DelayLines, FreshD.DelayLines);
            testCase.verifyEqual(D.InputSamplesReceived, 9);
            testCase.verifyEqual(D.OutputSamplesProduced, 5);
            testCase.verifyEqual(D.FramesProcessed, 1);
            testCase.verifyTrue(D.StreamFinalized);
        end


        function testInvalidFixedFrameInputsAndFlagAreRejected(testCase)
            D = testCase.createControlledDecimator(int64([1; 1]));

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            testCase.verifyError( ...
                @() D.ProcessFrame( ...
                    [1 2; 3 4], false, ...
                    InputFormat, CoefficientFormat), ...
                'FixedDSPDecimator:InvalidInputFrame');

            testCase.verifyError( ...
                @() D.ProcessFrame( ...
                    1.5, false, InputFormat, CoefficientFormat), ...
                'FixedDSPDecimator:InvalidInputFrame');

            testCase.verifyError( ...
                @() D.ProcessFrame( ...
                    1 + 1i, false, InputFormat, CoefficientFormat), ...
                'FixedDSPDecimator:InvalidInputFrame');

            testCase.verifyError( ...
                @() D.ProcessFrame( ...
                    NaN, false, InputFormat, CoefficientFormat), ...
                'FixedDSPDecimator:InvalidInputFrame');

            testCase.verifyError( ...
                @() D.ProcessFrame( ...
                    int64(1), 2, InputFormat, CoefficientFormat), ...
                'FixedDSPDecimator:InvalidLastFrameFlag');

            testCase.verifyEqual(D.InputSamplesReceived, 0);
            testCase.verifyEqual( ...
                D.PendingInputCodes, zeros(0, 1, 'int64'));
        end

        function testOutOfRangeCodeIsRejectedBeforeItIsBuffered(testCase)
            D = testCase.createControlledDecimator(int64([1; 1]));

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            testCase.verifyErrorContains( ...
                @() D.ProcessFrame( ...
                    int64(128), false, ...
                    InputFormat, CoefficientFormat), ...
                'InputFrame contains codes outside its declared WL');

            testCase.verifyEqual(D.InputSamplesReceived, 0);
            testCase.verifyEqual( ...
                D.PendingInputCodes, zeros(0, 1, 'int64'));
            testCase.verifyFalse(D.StreamFormatInitialized);
        end


        function testFixedFormatsCannotChangeInsideAStream(testCase)
            D = testCase.createControlledDecimator(int64([1; 1]));

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            D.ProcessFrame( ...
                int64(1), false, InputFormat, CoefficientFormat);

            ChangedInputFormat.WL = 9;
            ChangedInputFormat.IWL = 9;
            ChangedInputFormat.FWL = 0;

            testCase.verifyError( ...
                @() D.ProcessFrame( ...
                    int64(2), false, ...
                    ChangedInputFormat, CoefficientFormat), ...
                'FixedDSPDecimator:FormatChangedDuringStream');

            testCase.verifyEqual(D.InputSamplesReceived, 1);
            testCase.verifyEqual(D.PendingInputCodes, int64(1));
        end

        function testInputAfterFinalFixedFrameRequiresReset(testCase)
            D = testCase.createControlledDecimator(int64([1; 1]));

            InputFormat.WL = 8;
            InputFormat.IWL = 8;
            InputFormat.FWL = 0;

            CoefficientFormat.WL = 8;
            CoefficientFormat.IWL = 8;
            CoefficientFormat.FWL = 0;

            D.ProcessFrame( ...
                int64([1; 2]), true, ...
                InputFormat, CoefficientFormat);

            testCase.verifyError( ...
                @() D.ProcessFrame( ...
                    int64(3), false, ...
                    InputFormat, CoefficientFormat), ...
                'FixedDSPDecimator:StreamAlreadyFinalized');

            D.ResetDecimator();
            OutputAfterReset = D.ProcessFrame( ...
                int64([1; 2]), true, ...
                InputFormat, CoefficientFormat);

            testCase.verifyNotEmpty(OutputAfterReset);
            testCase.verifyTrue(D.StreamFinalized);
        end
    end

    methods (Access = private)

        function [OutputCodes, FinalMACData, OutputSampleIndex] = ...
                processFixedFrames( ...
                testCase, D, InputCodes, FrameLengths, ...
                InputFormat, CoefficientFormat, MACFormat)
            %% Process One Integer-Code Stream Using an Explicit Partition
            if sum(FrameLengths) ~= numel(InputCodes)
                error('TestFixedDSPDecimator:FrameLengthMismatch', ...
                    ['The frame lengths must contain every input code ', ...
                     'exactly once.']);
            end

            OutputCodes = zeros(1, 0, 'int64');
            FinalMACData = [];
            OutputSampleIndex = zeros(0, 1);
            StartIndex = 1;

            for k = 1:numel(FrameLengths)
                EndIndex = StartIndex + FrameLengths(k) - 1;
                InputFrame = InputCodes(StartIndex:EndIndex);
                IsLastFrame = k == numel(FrameLengths);

                [OutputFrame, FinalMACData, FrameInfo] = ...
                    D.ProcessFrame( ...
                    InputFrame, ...
                    IsLastFrame, ...
                    InputFormat, ...
                    CoefficientFormat, ...
                    MACFormat);

                OutputCodes = ...
                    [OutputCodes, OutputFrame]; %#ok<AGROW>
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
                error('TestFixedDSPDecimator:InvalidRandomPartition', ...
                    ['NumberFrames must lie between one and the ', ...
                     'number of input codes.']);
            end

            if NumberFrames == 1
                FrameLengths = TotalLength;
                return
            end

            % Force one one-code frame so every trial crosses the
            % decimation block phase; randomize all remaining boundaries.
            CandidateCutPoints = 2:TotalLength-1;
            NumberRandomCuts = NumberFrames - 2;
            RandomOrder = randperm( ...
                numel(CandidateCutPoints), NumberRandomCuts);
            CutPoints = sort([ ...
                1, CandidateCutPoints(RandomOrder)]);
            FrameLengths = diff([0, CutPoints, TotalLength]);
        end

        function D = createControlledDecimator(testCase, BranchCoefficients)
            BranchCoefficients = int64(BranchCoefficients);
            DcF = size(BranchCoefficients, 1);

            P = testCase.createDefaultParameters(DcF);
            D = FixedDSPDecimator(P);

            D.DcF = DcF;
            D.BranchCoefficients = BranchCoefficients;

            % Column-major flattening gives the corresponding prototype
            % coefficient-code sequence and the correct NumberProducts.
            D.FixedFilterCoefficients = ...
                reshape(BranchCoefficients, 1, []);
        end

        function P = createDefaultParameters(~, DcF)
            P = DSPParameters();

            P.setValue("DcF", DcF);
            P.setValue("Fs_DSP", 2000);
            P.setValue("Fpass", 200);
            P.setValue("Fstop", 300);
            P.setValue("Astop", 60);
            P.setValue("Apass", 1);
            P.setValue("B", 25);
        end
        
        function verifyErrorContains(testCase, FunctionHandle, TextFragment)
            ErrorOccurred = false;

            try
                FunctionHandle();
            catch ME
                ErrorOccurred = true;

                testCase.verifyTrue( ...
                    contains(ME.message, TextFragment), ...
                    sprintf('Unexpected error message:\n%s', ME.message));
            end

            testCase.verifyTrue( ...
                ErrorOccurred, ...
                sprintf('Expected an error containing "%s".', TextFragment));
        end
    end
end
