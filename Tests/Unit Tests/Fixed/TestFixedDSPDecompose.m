classdef TestFixedDSPDecompose < matlab.unittest.TestCase
    %% =======================================================
    %% UNIT TEST SUITE FOR FIXED-POINT POLYPHASE DECOMPOSITION
    %% =======================================================

    methods (Test)

        function testFixedDecomposePreservesMappingAndIntegerCodes(testCase)
            %% ==========================================================
            %% VALIDATES FIXED-POINT POLYPHASE DECOMPOSITION
            %%
            %% Confirms:
            %%   - Correct DcF x L branch-matrix dimensions
            %%   - Correct polyphase coefficient mapping
            %%   - Zero padding of unused branch locations
            %%   - Integer datatype preservation
            %%   - Exact reconstruction of the original coefficient codes
            %% ==========================================================

            %% ------------------------------------------
            %% CREATE FIXED-POINT DECIMATOR
            %% ------------------------------------------

            P = testCase.createDefaultParameters();
            D = FixedDSPDecimator(P);


            %% ------------------------------------------
            %% FIXED COEFFICIENT DATA
            %% ------------------------------------------

            FixedCoefficients = ...
                D.FixedFilterCoefficients;

            BranchCoefficients = ...
                D.BranchCoefficients;

            DcF = ...
                D.DcF;


            %% ------------------------------------------
            %% EXPECTED POLYPHASE DIMENSIONS
            %% ------------------------------------------

            NumberCoefficients = ...
                length(FixedCoefficients);

            L = ...
                ceil(NumberCoefficients / DcF);

            testCase.verifySize( ...
                BranchCoefficients, ...
                [DcF, L]);


            %% ------------------------------------------
            %% BUILD EXPECTED POLYPHASE MATRIX
            %% ------------------------------------------
            %
            % FixedDecompose maps the coefficient sequence as:
            %
            %   h(1)     -> Branch 1,   Tap 1
            %   h(2)     -> Branch 2,   Tap 1
            %   ...
            %   h(DcF)   -> Branch DcF, Tap 1
            %   h(DcF+1) -> Branch 1,   Tap 2
            %
            % Pad only the incomplete final branch column, then reshape
            % column-by-column into the expected DcF x L matrix.

            PadLength = ...
                DcF * L - NumberCoefficients;

            PaddedCoefficients = [ ...
                FixedCoefficients(:).', ...
                zeros(1, PadLength, 'like', FixedCoefficients)];

            ExpectedBranches = ...
                reshape( ...
                PaddedCoefficients, ...
                DcF, ...
                L);


            %% ------------------------------------------
            %% VERIFY EXACT INTEGER-CODE MAPPING
            %% ------------------------------------------

            testCase.verifyEqual( ...
                BranchCoefficients, ...
                ExpectedBranches);


            %% ------------------------------------------
            %% VERIFY DATATYPE PRESERVATION
            %% ------------------------------------------

            testCase.verifyClass( ...
                BranchCoefficients, ...
                class(FixedCoefficients));

            testCase.verifyTrue( ...
                isinteger(BranchCoefficients));


            %% ------------------------------------------
            %% VERIFY ZERO PADDING
            %% ------------------------------------------

            if PadLength > 0

                PaddedLocations = ...
                    BranchCoefficients(end-PadLength+1:end);

                testCase.verifyEqual( ...
                    PaddedLocations, ...
                    zeros(size(PaddedLocations), ...
                    'like', BranchCoefficients));
            end


            %% ------------------------------------------
            %% VERIFY LOSSLESS COEFFICIENT RECONSTRUCTION
            %% ------------------------------------------
            %
            % Reading the branch matrix column-by-column and removing
            % decomposition padding must recover the original fixed
            % coefficient-code sequence exactly.

            ReconstructedCoefficients = ...
                reshape(BranchCoefficients, 1, []);

            ReconstructedCoefficients = ...
                ReconstructedCoefficients(1:NumberCoefficients);

            testCase.verifyEqual( ...
                ReconstructedCoefficients, ...
                FixedCoefficients(:).');

        end

    end

    methods (Access = private)

        function P = createDefaultParameters(~)
            %% Creates Default Parameters For Fixed Decomposition Test

            P = DSPParameters();

            P.setValue("DcF", 4);

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
