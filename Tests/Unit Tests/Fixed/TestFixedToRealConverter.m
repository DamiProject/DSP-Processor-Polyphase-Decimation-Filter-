classdef TestFixedToRealConverter < matlab.unittest.TestCase
    methods (Test)
        function testIntegerCodeConversion(testCase)

            %% ==========================================
            %% FINAL DECIMATOR CODES
            %% ==========================================
            %
            % Accumulator FWL = 2
            %
            % Scale = 2^-2 = 0.25
            %
            % Expected:
            %
            %    4 ->  1.00
            %   -2 -> -0.50
            %    7 ->  1.75

            DecimatedCodes = ...
                int64([4, -2, 7]);

            %% ==========================================
            %% PRODUCT FORMAT
            %% ==========================================

            MACData.ProductFormat.WL  = 8;
            MACData.ProductFormat.IWL = 4;
            MACData.ProductFormat.FWL = 4;

            %% ==========================================
            %% ACCUMULATOR FORMAT
            %% ==========================================

            MACData.AccumulatorFormat.WL  = 6;
            MACData.AccumulatorFormat.IWL = 4;
            MACData.AccumulatorFormat.FWL = 2;

            %% ==========================================
            %% PRODUCT CHARACTERIZATION
            %% ==========================================
            %
            % Product scale = 1/16

            MACData.Product.MaxCode = int64(16);
            MACData.Product.MinCode = int64(-8);
            MACData.Product.MaxAbsCode = int64(16);

            %% ==========================================
            %% BRANCH ACCUMULATOR CHARACTERIZATION
            %% ==========================================
            %
            % Accumulator scale = 1/4

            MACData.BranchAccumulator.MaxCode = int64(6);
            MACData.BranchAccumulator.MinCode = int64(-4);
            MACData.BranchAccumulator.MaxAbsCode = int64(6);

            MACData.BranchAccumulator.GrowthByTapCode = ...
                int64([1, 3, 6]);

            %% ==========================================
            %% FINAL ACCUMULATOR CHARACTERIZATION
            %% ==========================================

            MACData.FinalAccumulator.MaxCode = int64(7);
            MACData.FinalAccumulator.MinCode = int64(-6);
            MACData.FinalAccumulator.MaxAbsCode = int64(7);

            MACData.FinalAccumulator.GrowthByBranchCode = ...
                int64([2, 5, 7]);

            %% ==========================================
            %% OVERFLOW COUNTERS
            %% ==========================================

            MACData.BranchAccumulatorOverflowCount = 2;
            MACData.FinalAccumulatorOverflowCount = 3;

            %% ==========================================
            %% CONVERT
            %% ==========================================

            [DecimatedSignal, ConvertedMACData] = ...
                FixedToRealConverter( ...
                DecimatedCodes, ...
                MACData);

            %% ==========================================
            %% VERIFY OUTPUT SIGNAL
            %% ==========================================

            ExpectedSignal = ...
                [1.0, -0.5, 1.75];

            testCase.verifyEqual( ...
                DecimatedSignal, ...
                ExpectedSignal, ...
                'AbsTol', 1e-12);

            %% ==========================================
            %% VERIFY ORIGINAL CODES STORED
            %% ==========================================

            testCase.verifyEqual( ...
                ConvertedMACData.DecimatedCodes, ...
                DecimatedCodes);

            testCase.verifyClass( ...
                ConvertedMACData.DecimatedCodes, ...
                'int64');

            %% ==========================================
            %% VERIFY PRODUCT CONVERSION
            %% ==========================================

            testCase.verifyEqual( ...
                ConvertedMACData.Product.Max, ...
                1.0, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                ConvertedMACData.Product.Min, ...
                -0.5, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                ConvertedMACData.Product.MaxAbs, ...
                1.0, ...
                'AbsTol', 1e-12);

            %% ==========================================
            %% VERIFY BRANCH ACCUMULATOR CONVERSION
            %% ==========================================

            testCase.verifyEqual( ...
                ConvertedMACData.BranchAccumulator.Max, ...
                1.5, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                ConvertedMACData.BranchAccumulator.Min, ...
                -1.0, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                ConvertedMACData.BranchAccumulator.MaxAbs, ...
                1.5, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                ConvertedMACData.BranchAccumulator.GrowthByTap, ...
                [0.25, 0.75, 1.5], ...
                'AbsTol', 1e-12);

            %% ==========================================
            %% VERIFY FINAL ACCUMULATOR CONVERSION
            %% ==========================================

            testCase.verifyEqual( ...
                ConvertedMACData.FinalAccumulator.Max, ...
                1.75, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                ConvertedMACData.FinalAccumulator.Min, ...
                -1.5, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                ConvertedMACData.FinalAccumulator.MaxAbs, ...
                1.75, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                ConvertedMACData.FinalAccumulator.GrowthByBranch, ...
                [0.5, 1.25, 1.75], ...
                'AbsTol', 1e-12);

            %% ==========================================
            %% VERIFY CONVENIENCE CHARACTERIZATION
            %% ==========================================

            testCase.verifyEqual( ...
                ConvertedMACData.BranchAccumulator.MaxPositive, ...
                1.5);

            testCase.verifyEqual( ...
                ConvertedMACData.BranchAccumulator.MinNegative, ...
                -1.0);

            testCase.verifyEqual( ...
                ConvertedMACData.FinalAccumulator.MaxPositive, ...
                1.75);

            testCase.verifyEqual( ...
                ConvertedMACData.FinalAccumulator.MinNegative, ...
                -1.5);

            %% ==========================================
            %% VERIFY TOTAL OVERFLOW COUNT
            %% ==========================================

            testCase.verifyEqual( ...
                ConvertedMACData.TotalAccumulatorOverflowCount, ...
                5);
        end

        function testRejectsReferenceMACResult(testCase)

            %% ==========================================
            %% REFERENCE DATA WITHOUT ACCUMULATOR FORMAT
            %% ==========================================

            DecimatedCodes = int64([1, 2, 3]);

            MACData.ProductFormat.FWL = 4;

            %% ==========================================
            %% VERIFY ERROR
            %% ==========================================

            ErrorOccurred = false;

            try

                FixedToRealConverter( ...
                    DecimatedCodes, ...
                    MACData);

            catch ME

                ErrorOccurred = true;

                testCase.verifySubstring( ...
                    ME.message, ...
                    'MACData.AccumulatorFormat');

            end
            
            testCase.verifyTrue(ErrorOccurred);
        end
    end
end