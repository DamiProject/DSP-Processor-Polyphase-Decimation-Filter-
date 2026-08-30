classdef TestFindMACFormat < matlab.unittest.TestCase
    methods (Test)
        function testNominalMACFormat(testCase)
            %% ==========================================
            %% TEST FIXED-POINT FORMATS
            %% ==========================================

            InputFormat.WL  = 4;
            InputFormat.IWL = 2;
            InputFormat.FWL = 2;

            CoefficientFormat.WL  = 4;
            CoefficientFormat.IWL = 2;
            CoefficientFormat.FWL = 2;

            %% ==========================================
            %% TEST POLYPHASE COEFFICIENT CODES
            %% ==========================================

            % Real coefficients:
            %
            %   [ 0.25   -0.50
            %     0.75    0.00 ]
            %
            % FWL = 2 -> scale = 1/4

            BranchCoefficientCodes = int64([ ...
                 1, -2;
                 3,  0]);

            %% ==========================================
            %% REFERENCE MAC CHARACTERIZATION
            %% ==========================================

            MACData.ProductFormat.WL  = 8;
            MACData.ProductFormat.IWL = 4;
            MACData.ProductFormat.FWL = 4;

            MACData.Product.MaxAbsCode = int64(8);
            MACData.BranchAccumulator.MaxAbsCode = int64(20);
            MACData.FinalAccumulator.MaxAbsCode = int64(40);

            MACData.NumberProducts = 4;
            MACData.GuardBits = 2;
            MACData.ReferenceContainerWL = 10;

            %% ==========================================
            %% FIND FORMAT
            %% ==========================================

            MACFormat = FindMACFormat( ...
                InputFormat, ...
                CoefficientFormat, ...
                BranchCoefficientCodes, ...
                MACData);

            %% ==========================================
            %% EXPECTED ANALYTICAL RANGE
            %% ==========================================
            %
            % Input range:
            %
            %   -2.00 to +1.75
            %
            % Therefore:
            %
            %   InputMaxAbs = 2
            %
            % Branch 1:
            %
            %   2 * (0.25 + 0.50) = 1.5
            %
            % Branch 2:
            %
            %   2 * 0.75 = 1.5
            %
            % Final FIR bound:
            %
            %   1.5 + 1.5 = 3.0

            testCase.verifyEqual( ...
                MACFormat.InputMaxAbs, ...
                2);

            testCase.verifyEqual( ...
                MACFormat.AnalyticalBranchBound, ...
                [1.5, 1.5], ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                MACFormat.MaximumAnalyticalBranchBound, ...
                1.5, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                MACFormat.AnalyticalFinalBound, ...
                3.0, ...
                'AbsTol', 1e-12);

            %% ==========================================
            %% EXPECTED OBSERVED VALUES
            %% ==========================================
            %
            % Product FWL = 4
            %
            % Scale = 2^-4 = 1/16
            %
            % Product     = 8/16  = 0.5
            % Branch      = 20/16 = 1.25
            % Final       = 40/16 = 2.5

            testCase.verifyEqual( ...
                MACFormat.ObservedProductMaxAbs, ...
                0.5, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                MACFormat.ObservedBranchMaxAbs, ...
                1.25, ...
                'AbsTol', 1e-12);

            testCase.verifyEqual( ...
                MACFormat.ObservedFinalMaxAbs, ...
                2.5, ...
                'AbsTol', 1e-12);

            %% ==========================================
            %% REQUIRED MAGNITUDE
            %% ==========================================

            % Analytical requirement 3.0 dominates
            % the observed requirement 2.5.

            testCase.verifyEqual( ...
                MACFormat.RequiredMagnitude, ...
                3.0, ...
                'AbsTol', 1e-12);

            %% ==========================================
            %% EXPECTED ACCUMULATOR FORMAT
            %% ==========================================
            %
            % Product FWL = 4
            %
            % RequiredMagnitude = 3
            %
            % Signed IWL = 3
            %
            % Therefore:
            %
            %   WL = IWL + FWL
            %      = 3 + 4
            %      = 7

            testCase.verifyEqual(MACFormat.FWL, 4);
            testCase.verifyEqual(MACFormat.IWL, 3);
            testCase.verifyEqual(MACFormat.WL, 7);

            %% ==========================================
            %% PRODUCT FORMAT PRESERVATION
            %% ==========================================

            testCase.verifyEqual(MACFormat.ProductWL, 8);
            testCase.verifyEqual(MACFormat.ProductIWL, 4);
            testCase.verifyEqual(MACFormat.ProductFWL, 4);

            %% ==========================================
            %% ARITHMETIC POLICY
            %% ==========================================

            testCase.verifyEqual( ...
                MACFormat.RoundingMethod, ...
                'Nearest');

            testCase.verifyEqual( ...
                MACFormat.OverflowAction, ...
                'Saturate');

            %% ==========================================
            %% DEFAULT HEADROOM
            %% ==========================================

            testCase.verifyEqual( ...
                MACFormat.HeadroomBits, ...
                0);
        end

        function testHeadroomBits(testCase)

            %% ==========================================
            %% TEST DATA
            %% ==========================================

            InputFormat.WL  = 4;
            InputFormat.IWL = 2;
            InputFormat.FWL = 2;

            CoefficientFormat.WL  = 4;
            CoefficientFormat.IWL = 2;
            CoefficientFormat.FWL = 2;

            BranchCoefficientCodes = int64([ ...
                 1, -2;
                 3,  0]);

            MACData.ProductFormat.WL  = 8;
            MACData.ProductFormat.IWL = 4;
            MACData.ProductFormat.FWL = 4;

            MACData.Product.MaxAbsCode = int64(8);
            MACData.BranchAccumulator.MaxAbsCode = int64(20);
            MACData.FinalAccumulator.MaxAbsCode = int64(40);

            MACData.NumberProducts = 4;
            MACData.GuardBits = 2;
            MACData.ReferenceContainerWL = 10;

            %% ==========================================
            %% TWO HEADROOM BITS
            %% ==========================================

            MACFormat = FindMACFormat( ...
                InputFormat, ...
                CoefficientFormat, ...
                BranchCoefficientCodes, ...
                MACData, ...
                2);

            %% ==========================================
            %% VERIFY
            %% ==========================================
            %
            % Normal IWL = 3
            %
            % +2 headroom bits
            %
            % IWL = 5
            %
            % FWL remains 4
            %
            % WL = 9

            testCase.verifyEqual(MACFormat.HeadroomBits, 2);

            testCase.verifyEqual(MACFormat.IWL, 5);

            testCase.verifyEqual(MACFormat.FWL, 4);

            testCase.verifyEqual(MACFormat.WL, 9);
        end

        function testObservedRangeCanDominate(testCase)

            %% ==========================================
            %% TEST DATA
            %% ==========================================

            InputFormat.WL  = 4;
            InputFormat.IWL = 2;
            InputFormat.FWL = 2;

            CoefficientFormat.WL  = 4;
            CoefficientFormat.IWL = 2;
            CoefficientFormat.FWL = 2;

            BranchCoefficientCodes = int64([ ...
                 1, -2;
                 3,  0]);

            MACData.ProductFormat.WL  = 8;
            MACData.ProductFormat.IWL = 4;
            MACData.ProductFormat.FWL = 4;

            MACData.Product.MaxAbsCode = int64(8);
            MACData.BranchAccumulator.MaxAbsCode = int64(20);

            % 80 / 16 = 5.0
            %
            % This deliberately exceeds the
            % analytical bound of 3.0.

            MACData.FinalAccumulator.MaxAbsCode = ...
                int64(80);

            MACData.NumberProducts = 4;
            MACData.GuardBits = 2;
            MACData.ReferenceContainerWL = 10;

            %% ==========================================
            %% FIND FORMAT
            %% ==========================================

            MACFormat = FindMACFormat( ...
                InputFormat, ...
                CoefficientFormat, ...
                BranchCoefficientCodes, ...
                MACData);

            %% ==========================================
            %% VERIFY OBSERVED RANGE DOMINATES
            %% ==========================================

            testCase.verifyEqual( ...
                MACFormat.RequiredMagnitude, ...
                5.0, ...
                'AbsTol', 1e-12);

            % 5 requires IWL = 4 for a signed format.
            %
            % FWL = 4
            %
            % WL = 8

            testCase.verifyEqual(MACFormat.IWL, 4);
            testCase.verifyEqual(MACFormat.FWL, 4);
            testCase.verifyEqual(MACFormat.WL, 8);
        end
    end
end