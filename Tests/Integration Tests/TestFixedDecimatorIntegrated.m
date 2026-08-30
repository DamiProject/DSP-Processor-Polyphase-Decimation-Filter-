classdef TestFixedDecimatorIntegrated < matlab.unittest.TestCase
    %% =========================================================
    %% INTEGRATED TEST SUITE FOR FIXED-POINT POLYPHASE DECIMATOR
    %% =========================================================

    methods (Test)
        function testEndToEndFixedDecimatorIntegration(testCase)
            %% =====================================================
            %% END-TO-END FIXED-POINT DECIMATOR INTEGRATION TEST
            %% =====================================================
            %
            % Verifies the complete fixed-point decimator workflow:
            %
            %   Parameters
            %       ->
            %   FixedDSPDecimator construction
            %       ->
            %   FIR coefficient generation
            %       ->
            %   coefficient quantization
            %       ->
            %   polyphase decomposition
            %       ->
            %   input preparation
            %       ->
            %   reference MAC characterization
            %       ->
            %   MAC format determination
            %       ->
            %   bounded fixed-point MAC
            %       ->
            %   fixed-to-real conversion
            %
            % The bounded implementation must match the full-precision
            % integer reference when FindMACFormat selects a safe format.

            %% ==========================================
            %% DECIMATOR UNDER TEST
            %% ==========================================

            DcF = 4;

            P = testCase.createDefaultParameters(DcF);

            D = FixedDSPDecimator(P);

            %% ==========================================
            %% INPUT FIXED-POINT FORMAT
            %% ==========================================
            %
            % Signed Q-style representation:
            %
            %   WL  = 12
            %   IWL = 2
            %   FWL = 10
            %
            % Real range approximately:
            %
            %   -2.0 <= x < 2.0

            InputFormat.WL = 12;
            InputFormat.IWL = 2;
            InputFormat.FWL = 10;

            %% ==========================================
            %% COEFFICIENT FIXED-POINT FORMAT
            %% ==========================================
            %
            % Use the actual coefficient format determined
            % by the decimator constructor.

            CoefficientFormat.WL = ...
                D.CoeffWL;

            CoefficientFormat.IWL = ...
                D.CoeffIWL;

            CoefficientFormat.FWL = ...
                D.CoeffFWL;


            %% ==========================================
            %% DETERMINISTIC TEST SIGNAL
            %% ==========================================
            %
            % Use enough samples to exercise:
            %
            %   - several decimation blocks
            %   - delay-line state
            %   - all polyphase branches
            %   - FIR memory after initial startup
            %
            % 257 samples intentionally does not divide evenly
            % by DcF = 4, therefore FixedPrepareInput must also
            % perform zero padding.

            n = (0:256).';

            InputSignal = ...
                0.70 * sin(2*pi*0.037*n) + ...
                0.20 * cos(2*pi*0.081*n);


            %% ==========================================
            %% CONVERT TEST SIGNAL TO INTEGER CODES
            %% ==========================================
            %
            % This conversion is test stimulus generation.
            %
            % The actual fixed-point decimator receives integer
            % codes exactly as intended by the implementation.

            InputScale = ...
                2^(InputFormat.FWL);

            InputCodes = ...
                int64(round(InputSignal .* InputScale));

            %% ==========================================
            %% PREPARE INPUT
            %% ==========================================

            [InPadded, NumBlocks] = ...
                D.FixedPrepareInput(InputCodes);

            %% ==========================================
            %% PASS 1:
            %% FULL-PRECISION REFERENCE MAC
            %% ==========================================
            %
            % No MACFormat is supplied.
            %
            % Therefore:
            %
            %   ReferenceMode = true

            [ReferenceCodes, ReferenceMACData] = ...
                D.FixedDecimator( ...
                InPadded, ...
                NumBlocks, ...
                InputFormat, ...
                CoefficientFormat);

            %% ==========================================
            %% DETERMINE SAFE MAC FORMAT
            %% ==========================================
            %
            % FindMACFormat uses:
            %
            %   - input representation
            %   - coefficient representation
            %   - actual branch coefficient codes
            %   - reference MAC characterization
            %   - analytical FIR bounds
            %
            % One optional headroom bit is included.

            HeadroomBits = 1;

            MACFormat = ...
                FindMACFormat( ...
                InputFormat, ...
                CoefficientFormat, ...
                D.BranchCoefficients, ...
                ReferenceMACData, ...
                HeadroomBits);

            %% ==========================================
            %% PASS 2:
            %% BOUNDED FIXED-POINT MAC
            %% ==========================================

            [BoundedCodes, BoundedMACData] = ...
                D.FixedDecimator( ...
                InPadded, ...
                NumBlocks, ...
                InputFormat, ...
                CoefficientFormat, ...
                MACFormat);

            %% ==========================================
            %% CONVERT BOUNDED OUTPUT BACK TO REAL
            %% ==========================================

            [BoundedSignal, BoundedMACData] = ...
                FixedToRealConverter( ...
                BoundedCodes, ...
                BoundedMACData);

            %% ==========================================
            %% DECODE REFERENCE OUTPUT
            %% ==========================================
            %
            % ReferenceMode retains the full product fractional
            % precision throughout the MAC.

            ReferenceScale = ...
                2^(-ReferenceMACData.ProductFormat.FWL);

            ReferenceSignal = ...
                double(ReferenceCodes) .* ReferenceScale;

            %% ==========================================
            %% VERIFY INPUT PREPARATION
            %% ==========================================

            ExpectedNumBlocks = ...
                ceil(length(InputCodes) / DcF);

            testCase.verifyEqual( ...
                NumBlocks, ...
                ExpectedNumBlocks);

            testCase.verifyEqual( ...
                mod(length(InPadded), DcF), ...
                0);

            %% ==========================================
            %% VERIFY OUTPUT STRUCTURE
            %% ==========================================

            testCase.verifyClass( ...
                ReferenceCodes, ...
                'int64');

            testCase.verifyClass( ...
                BoundedCodes, ...
                'int64');

            testCase.verifySize( ...
                ReferenceCodes, ...
                [1 NumBlocks]);

            testCase.verifySize( ...
                BoundedCodes, ...
                [1 NumBlocks]);

            %% ==========================================
            %% VERIFY INTEGER-DOMAIN AGREEMENT
            %% ==========================================
            %
            % FindMACFormat is expected to select sufficient
            % range and preserve the full product FWL.
            %
            % Therefore the bounded implementation should be
            % exactly equal to the reference integer MAC.

            testCase.verifyEqual( ...
                BoundedCodes, ...
                ReferenceCodes);

            %% ==========================================
            %% VERIFY REAL-DOMAIN AGREEMENT
            %% ==========================================

            testCase.verifyEqual( ...
                BoundedSignal, ...
                ReferenceSignal);

            %% ==========================================
            %% VERIFY SELECTED MAC FORMAT WAS USED
            %% ==========================================

            testCase.verifyEqual( ...
                BoundedMACData.AccumulatorFormat, ...
                MACFormat);

            %% ==========================================
            %% VERIFY NO OVERFLOW OCCURRED
            %% ==========================================
            %
            % Because FindMACFormat was used to determine
            % the required safe accumulator representation.

            testCase.verifyEqual( ...
                BoundedMACData.ProductCastOverflowCount, ...
                0);

            testCase.verifyEqual( ...
                BoundedMACData.BranchAccumulatorOverflowCount, ...
                0);

            testCase.verifyEqual( ...
                BoundedMACData.FinalAccumulatorOverflowCount, ...
                0);

            testCase.verifyEqual( ...
                BoundedMACData.TotalAccumulatorOverflowCount, ...
                0);
        end
    end

    methods (Access = private)
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
    end
end

