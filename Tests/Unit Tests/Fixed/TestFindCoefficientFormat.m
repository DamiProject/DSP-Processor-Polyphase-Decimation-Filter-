classdef TestFindCoefficientFormat < matlab.unittest.TestCase
    %% ==================================================================
    %% UNIT TEST SUITE FOR FIR COEFFICIENT RANGE AND RESOLUTION SELECTION
    %% ==================================================================

    methods (Test)

        function testScaleMatchesFractionLength(testCase)
            %% Validates Scale = 2^FWL

            P = testCase.createDefaultParameters();

            h = testCase.createReferenceFilter(P);

            NPoint = FindResponseResolution(h, P);

            [~, ~, ~, FWL, Scale] = ...
                FindCoefficientFormat(h, P, NPoint);

            testCase.verifyEqual(Scale, 2^FWL);
        end

        function testWordLengthRelationship(testCase)
            %% Validates WL = IWL + FWL

            P = testCase.createDefaultParameters();

            h = testCase.createReferenceFilter(P);

            NPoint = FindResponseResolution(h, P);

            [~, WL, IWL, FWL, ~] = ...
                FindCoefficientFormat(h, P, NPoint);

            testCase.verifyEqual(WL, IWL + FWL);
        end

        function testFixedCoefficientsMatchQuantizationRule(testCase)
            %% Validates round(h * 2^FWL) Integer-Code Conversion

            P = testCase.createDefaultParameters();

            h = testCase.createReferenceFilter(P);

            NPoint = FindResponseResolution(h, P);

            [FixedCoefficients, ~, ~, FWL, Scale] = ...
                FindCoefficientFormat(h, P, NPoint);

            ExpectedFixedCoefficients = ...
                int64(round(h * 2^FWL));

            testCase.verifyEqual( ...
                Scale, ...
                2^FWL);

            testCase.verifyEqual( ...
                FixedCoefficients, ...
                ExpectedFixedCoefficients);

            testCase.verifyClass( ...
                FixedCoefficients, ...
                'int64');

            testCase.verifyTrue( ...
                isinteger(FixedCoefficients));
        end

        function testAllCoefficientCodesFitReturnedWordLength(testCase)
            %% Validates No Positive Or Negative Coefficient Overflow

            P = testCase.createDefaultParameters();

            h = testCase.createReferenceFilter(P);

            NPoint = FindResponseResolution(h, P);

            [FixedCoefficients, WL, ~, ~, ~] = ...
                FindCoefficientFormat(h, P, NPoint);

           Magnitude = bitshift(int64(1), WL - 1);

           MaxStored = ...
               Magnitude - 1;

           MinStored = ...
               -Magnitude;

            testCase.verifyLessThanOrEqual( ...
                max(FixedCoefficients), MaxStored);

            testCase.verifyGreaterThanOrEqual( ...
                min(FixedCoefficients), MinStored);
        end

        function testSelectedFormatMeetsFilterSpecifications(testCase)
            %% Validates Quantized FIR Preserves Required DSP Response

            P = testCase.createDefaultParameters();

            h = testCase.createReferenceFilter(P);

            NPoint = FindResponseResolution(h, P);

            [FixedCoefficients, ~, ~, ~, Scale] = ...
                FindCoefficientFormat(h, P, NPoint);

            % Reconstruct represented fixed-point values
            QuantizedCoefficients = ...
                double(FixedCoefficients) / Scale;

            [PassbandOK, StopbandOK] = ...
                testCase.checkResponseForTest( ...
                QuantizedCoefficients, P, NPoint);

            testCase.verifyTrue(PassbandOK);
            testCase.verifyTrue(StopbandOK);
        end

        function testSelectedFWLIsMinimumPassingPrecision(testCase)
            %% Validates Previous FWL Does Not Meet DSP Specifications

            P = testCase.createDefaultParameters();

            h = testCase.createReferenceFilter(P);

            NPoint = FindResponseResolution(h, P);

            [~, ~, ~, FWL, ~] = ...
                FindCoefficientFormat(h, P, NPoint);

            % If FWL = 0 there is no smaller candidate to test
            if FWL > 0

                PreviousFWL = FWL - 1;

                PreviousScale = 2^PreviousFWL;

                PreviousFixed = ...
                    round(h * PreviousScale);

                PreviousQuantized = ...
                    PreviousFixed / PreviousScale;

                [PreviousPassbandOK, PreviousStopbandOK] = ...
                    testCase.checkResponseForTest( ...
                    PreviousQuantized, P, NPoint);

                % Previous FWL must fail at least one requirement
                testCase.verifyFalse( ...
                    PreviousPassbandOK && PreviousStopbandOK);
            end
        end

    end

    methods (Access = private)
        function P = createDefaultParameters(~)
            %% Creates Parameters For Coefficient Format Tests

            P = DSPParameters();

            P.setValue("Fs_DSP", 5000);
            P.setValue("Fpass", 500);
            P.setValue("Fstop", 1000);
            P.setValue("Apass", 0.1);
            P.setValue("Astop", 60);
        end

        function h = createReferenceFilter(~, P)
            %% Creates Deterministic Lowpass FIR Used By Utility Tests

            Fs_DSP = P.getValue("Fs_DSP");
            Fpass  = P.getValue("Fpass");
            Fstop  = P.getValue("Fstop");

            Fc = (Fpass + Fstop) / 2;

            Order = 48;
            Beta = 8;

            h = fir1( ...
                Order, ...
                Fc / (Fs_DSP / 2), ...
                kaiser(Order + 1, Beta));

            h = h / sum(h);
        end

        function [PassbandOK, StopbandOK] = ...
                checkResponseForTest( ...
                ~, Coefficients, P, NPoint)
            %% Independent DSP Specification Verification

            Fs_DSP = P.getValue("Fs_DSP");
            Fpass  = P.getValue("Fpass");
            Fstop  = P.getValue("Fstop");
            Apass  = P.getValue("Apass");
            Astop  = P.getValue("Astop");

            delta_p = ...
                (10^(Apass/20) - 1) / ...
                (10^(Apass/20) + 1);

            delta_s = 10^(-Astop/20);

            [H, f] = freqz( ...
                Coefficients, 1, NPoint, Fs_DSP);

            Magnitude = abs(H);

            PassbandRegion = (f <= Fpass);
            StopbandRegion = (f >= Fstop);

            PassbandError = ...
                max(abs(Magnitude(PassbandRegion) - 1));

            StopbandMagnitude = ...
                max(Magnitude(StopbandRegion));

            PassbandOK = ...
                PassbandError <= delta_p;

            StopbandOK = ...
                StopbandMagnitude <= delta_s;
        end
    end
end