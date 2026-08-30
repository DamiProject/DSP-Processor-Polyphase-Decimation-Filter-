classdef TestDSPDecompose < matlab.unittest.TestCase
    %% ===============================================
    %% UNIT TEST SUITE FOR DSP POLYPHASE DECOMPOSITION
    %% ===============================================

    methods (Test)
        function testBranchMatrixDimensions(testCase)
            %% Validates Number of Branches and Maximum Branch Length

            P = testCase.createDefaultParameters();
            D = DSP(P);

            h = D.FilterCoefficients;
            E = D.BranchCoefficients;

            DcF = P.getValue("DcF");
            expectedL = ceil(length(h) / DcF);

            testCase.verifySize(E, [DcF expectedL]);
        end

        function testPrototypeCoefficientsMapToCorrectBranches(testCase)
            %% Validates E_k[m] = h[mM + k]

            P = testCase.createDefaultParameters();
            D = DSP(P);

            h = D.FilterCoefficients;
            E = D.BranchCoefficients;

            DcF = P.getValue("DcF");
            L = ceil(length(h) / DcF);

            expectedBranches = zeros(DcF, L);

            for k = 0:DcF-1
                branchTaps = h(k+1:DcF:end);

                expectedBranches(k+1, 1:length(branchTaps)) = ...
                    branchTaps;
            end
            testCase.verifyEqual( ...
                E, expectedBranches, "AbsTol", 1e-12);
        end


        function testUnusedBranchLocationsAreZeroPadded(testCase)
            %% Validates Only Nonexistent FIR Tap Locations Are Zero Filled

            P = testCase.createDefaultParameters();
            D = DSP(P);

            h = D.FilterCoefficients;
            E = D.BranchCoefficients;

            DcF = P.getValue("DcF");
            L = size(E, 2);

            totalBranchLocations = DcF * L;
            expectedPadding = totalBranchLocations - length(h);

            actualPadding = 0;

            for k = 0:DcF-1
                numRealTaps = length(k+1:DcF:length(h));

                if numRealTaps < L
                    unusedLocations = E(k+1, numRealTaps+1:L);

                    testCase.verifyEqual( ...
                        unusedLocations, ...
                        zeros(size(unusedLocations)));

                    actualPadding = actualPadding + ...
                        length(unusedLocations);
                end
            end
            testCase.verifyEqual(actualPadding, expectedPadding);
        end
    end

    methods (Access = private)
        function P = createDefaultParameters(~)
            %% Creates Default Parameter Object For DSP Decomposition Tests

            P = DSPParameters();

            P.setValue("DcF", 4); % Decimation Factor

            % LPF design parameters
            P.setValue("Fs_DSP", 2000);
            P.setValue("Fpass", 200);
            P.setValue("Fstop", 300);
            P.setValue("Astop", 60);
            P.setValue("Apass", 1);
            P.setValue("B", 25);
        end
    end
end
