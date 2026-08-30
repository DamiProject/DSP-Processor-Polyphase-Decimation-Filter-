classdef TestFindResponseResolution < matlab.unittest.TestCase
    %% ===========================================================
    %% UNIT TEST SUITE FOR FREQUENCY RESPONSE RESOLUTION SELECTION
    %% ===========================================================

    methods (Test)
        function testReturnedNPointIsValid(testCase)
            %% Validates Returned Frequency Grid Is Within Search Limits

            P = testCase.createDefaultParameters();

            h = testCase.createReferenceFilter(P);

            NPoint = FindResponseResolution(h, P);

            % Search begins at 512 and first candidate is 1024
            testCase.verifyGreaterThanOrEqual(NPoint, 1024);

            % Maximum search limit used by FindResponseResolution
            testCase.verifyLessThanOrEqual(NPoint, 131072);
        end

        function testReturnedNPointIsPowerOfTwo(testCase)
            %% Validates Factor-Of-Two Frequency Grid Refinement

            P = testCase.createDefaultParameters();

            h = testCase.createReferenceFilter(P);

            NPoint = FindResponseResolution(h, P);

            % A power of two has an integer log2
            testCase.verifyEqual( ...
                log2(NPoint), ...
                round(log2(NPoint)), ...
                "AbsTol", eps);
        end

        function testResponseExtremaHaveConverged(testCase)
            %% Validates Final Grid Meets Response Convergence Requirement

            P = testCase.createDefaultParameters();

            h = testCase.createReferenceFilter(P);

            NPoint = FindResponseResolution(h, P);

            Fs_DSP = P.getValue("Fs_DSP");
            Fpass  = P.getValue("Fpass");
            Fstop  = P.getValue("Fstop");

            % Measure response at previous and selected grid sizes
            [PrevPassMax, PrevPassMin, PrevStopMax] = ...
                testCase.measureResponseForTest( ...
                h, Fs_DSP, Fpass, Fstop, NPoint / 2);

            [PassMax, PassMin, StopMax] = ...
                testCase.measureResponseForTest( ...
                h, Fs_DSP, Fpass, Fstop, NPoint);

            % Same tolerance used by FindResponseResolution
            Tolerance_dB = 1e-3;

            testCase.verifyLessThanOrEqual( ...
                abs(PassMax - PrevPassMax), Tolerance_dB);

            testCase.verifyLessThanOrEqual( ...
                abs(PassMin - PrevPassMin), Tolerance_dB);

            testCase.verifyLessThanOrEqual( ...
                abs(StopMax - PrevStopMax), Tolerance_dB);
        end

        function testReturnedGridIsFirstConvergedGrid(testCase)
            %% Validates Search Does Not Continue After Convergence

            P = testCase.createDefaultParameters();

            h = testCase.createReferenceFilter(P);

            NPoint = FindResponseResolution(h, P);

            % 1024 is the first possible returned grid
            if NPoint > 1024

                Fs_DSP = P.getValue("Fs_DSP");
                Fpass  = P.getValue("Fpass");
                Fstop  = P.getValue("Fstop");

                PreviousNPoint = NPoint / 2;
                EarlierNPoint  = NPoint / 4;

                [EarlierPassMax, EarlierPassMin, EarlierStopMax] = ...
                    testCase.measureResponseForTest( ...
                    h, Fs_DSP, Fpass, Fstop, EarlierNPoint);

                [PreviousPassMax, PreviousPassMin, PreviousStopMax] = ...
                    testCase.measureResponseForTest( ...
                    h, Fs_DSP, Fpass, Fstop, PreviousNPoint);

                Tolerance_dB = 1e-3;

                Changes = [ ...
                    abs(PreviousPassMax - EarlierPassMax), ...
                    abs(PreviousPassMin - EarlierPassMin), ...
                    abs(PreviousStopMax - EarlierStopMax)];

                % At least one metric must still have exceeded
                % the convergence tolerance at the previous stage.
                testCase.verifyTrue(any(Changes > Tolerance_dB));
            end
        end

        function testOffGridSpecificationEdgesAreEvaluated(testCase)
            %% Proves Fpass/Fstop are inserted rather than merely approached

            P = DSPParameters();
            P.setValue("Fs_DSP", 1000);

            % Neither edge lies on the 512- or 1024-point uniform grid.
            P.setValue("Fpass", 123.456);
            P.setValue("Fstop", 234.567);

            % This two-tap response decreases monotonically from DC to
            % Nyquist. Exact Fpass and Fstop therefore determine the band
            % extrema at every resolution when the edges are inserted.
            h = [0.5, 0.5];

            NPoint = FindResponseResolution(h, P);

            % With explicit edges, the 512- and 1024-point measurements are
            % already identical, so 1024 is the first returned candidate.
            testCase.verifyEqual(NPoint, 1024);

            % Counterfactual check: a uniform-only grid has not converged at
            % 1024 for this same filter. This makes the test discriminate
            % between explicit edge insertion and ordinary grid refinement.
            [PassMax512, PassMin512, StopMax512] = ...
                testCase.measureResponseForTest( ...
                h, 1000, 123.456, 234.567, 512);
            [PassMax1024, PassMin1024, StopMax1024] = ...
                testCase.measureResponseForTest( ...
                h, 1000, 123.456, 234.567, 1024);

            UniformGridChanges = abs([ ...
                PassMax1024 - PassMax512, ...
                PassMin1024 - PassMin512, ...
                StopMax1024 - StopMax512]);

            testCase.verifyGreaterThan( ...
                max(UniformGridChanges), 1e-3);
        end
    end

    methods (Access = private)
        function P = createDefaultParameters(~)
            %% Creates Parameters For Response Resolution Tests

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

            % Cutoff placed at transition-band centre
            Fc = (Fpass + Fstop) / 2;

            % Reference FIR used only by the unit test
            Order = 48;
            Beta = 8;

            h = fir1( ...
                Order, ...
                Fc / (Fs_DSP / 2), ...
                kaiser(Order + 1, Beta));

            % Explicit unity DC gain
            h = h / sum(h);
        end

        function [PassMax_dB, PassMin_dB, StopMax_dB] = ...
                measureResponseForTest( ...
                ~, Coefficients, Fs_DSP, Fpass, Fstop, NPoint)
            %% Independent Response Measurement For Verification

            [H, f] = freqz( ...
                Coefficients, 1, NPoint, Fs_DSP);

            Magnitude_dB = ...
                20 * log10(max(abs(H), eps));

            PassbandRegion = (f <= Fpass);
            StopbandRegion = (f >= Fstop);

            PassMax_dB = ...
                max(Magnitude_dB(PassbandRegion));

            PassMin_dB = ...
                min(Magnitude_dB(PassbandRegion));

            StopMax_dB = ...
                max(Magnitude_dB(StopbandRegion));
        end
    end
end
