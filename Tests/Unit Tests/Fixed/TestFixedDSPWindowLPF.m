classdef TestFixedDSPWindowLPF < matlab.unittest.TestCase
    %% =====================================
    %% UNIT TEST SUITE FOR DSP WINDOWED LPF
    %% =====================================

    methods (Test)
        function testFilterLengthMatchesKaiserEstimateAndIsOdd(testCase)
            %% Validates Kaiser Length Estimate and Type-I Odd Tap Count

            P = testCase.createDefaultParameters();
            D = FixedDSPDecimator(P);

            h = D.FilterCoefficients;

            Fs_DSP = P.getValue("Fs_DSP");
            Fstop  = P.getValue("Fstop");
            Fpass  = P.getValue("Fpass");
            Astop  = P.getValue("Astop");
            Apass  = P.getValue("Apass");

            delta_f = Fstop - Fpass;
            delta_f_norm = delta_f / Fs_DSP;

            delta_p = (10^(Apass/20) - 1) / ...
                      (10^(Apass/20) + 1);
            delta_s = 10^(-Astop/20);

            delta = min(delta_p, delta_s);
            A = -20 * log10(delta);

            if A > 21
                Dscale = (A - 7.95) / 14.36;
            else
                Dscale = 0.922;
            end

            Nkaiser = ceil(1 + (Dscale / delta_f_norm));

            if mod(Nkaiser, 2) == 0
                expectedLength = Nkaiser + 1;
            else
                expectedLength = Nkaiser;
            end

            testCase.verifyLength(h, expectedLength);
            testCase.verifyEqual(mod(length(h), 2), 1);
        end

        function testFilterCoefficientsAreSymmetric(testCase)
            %% Validates Type-I FIR Coefficient Symmetry

            P = testCase.createDefaultParameters();
            D = FixedDSPDecimator(P);

            h = D.FilterCoefficients;

            testCase.verifyEqual(h, fliplr(h), "AbsTol", 1e-12);
        end

        function testCenterCoefficientMatchesIdealLowpass(testCase)
            %% Validates Centre Tap of Windowed Ideal Lowpass

            P = testCase.createDefaultParameters();
            D = FixedDSPDecimator(P);

            h = D.FilterCoefficients;

            Fs_DSP = P.getValue("Fs_DSP");
            Fpass  = P.getValue("Fpass");
            Fstop  = P.getValue("Fstop");

            Fc_norm = (Fpass + Fstop) / (2 * Fs_DSP);

            centerIndex = (length(h) + 1) / 2;
            expectedCenterCoefficient = 2 * Fc_norm;

            testCase.verifyEqual( ...
                h(centerIndex), expectedCenterCoefficient, ...
                "AbsTol", 1e-12);
        end

        function testFilterMeetsPassbandAndStopbandSpecifications(testCase)
      %% Validates LPF Meets Passband Ripple and Stopband Attenuation Specs

            P = testCase.createDefaultParameters();
            D = FixedDSPDecimator(P);

            h = D.FilterCoefficients;

            Fs_DSP = P.getValue("Fs_DSP");
            Fpass  = P.getValue("Fpass");
            Fstop  = P.getValue("Fstop");
            Apass  = P.getValue("Apass");
            Astop  = P.getValue("Astop");

            % Frequency response
            Nfft = 8192;
            [H, f] = freqz(h, 1, Nfft, Fs_DSP);

            Magnitude = abs(H);

            %% Passband Check
            PassbandIndex = f <= Fpass;

            PassbandMagnitude = Magnitude(PassbandIndex);

            % Convert allowed passband ripple from dB to magnitude limits
            PassbandUpper = 10^(Apass/20);
            PassbandLower = 10^(-Apass/20);

            testCase.verifyGreaterThanOrEqual( ...
                min(PassbandMagnitude), PassbandLower);

            testCase.verifyLessThanOrEqual( ...
                max(PassbandMagnitude), PassbandUpper);

            %% Stopband Check
            StopbandIndex = f >= Fstop;

            StopbandMagnitude = Magnitude(StopbandIndex);

            % Maximum allowed stopband magnitude
            StopbandLimit = 10^(-Astop/20);

            testCase.verifyLessThanOrEqual( ...
                max(StopbandMagnitude), StopbandLimit);
        end
    end

    methods (Access = private)
        function P = createDefaultParameters(~)
            %% Creates Default Parameter Object For DSP LPF Tests

            P = DSPParameters();

            P.setValue("DcF", 4); % Decimation Factor

            % LPF design parameters required by DSP constructor
            P.setValue("Fs_DSP", 2000);
            P.setValue("Fpass", 200);
            P.setValue("Fstop", 300);
            P.setValue("Astop", 60);
            P.setValue("Apass", 1);
            P.setValue("B", 25);
        end
    end
end
