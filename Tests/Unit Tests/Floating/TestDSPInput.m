classdef TestDSPInput < matlab.unittest.TestCase
    %% =================================================-=======
    %% UNIT TEST SUITE FOR THE DSP (PREPAREINPUT FUNCTION)
    %% =========================================================

    methods (Test)
        function testPrepareInputConvertsRowToColumn(testCase)
            %% Validates Input Signal Is Converted To Column Vector

            P = testCase.createDefaultParameters();
            D = DSP(P);

            Input = [1 2 3 4];

            [InPadded, NumBlocks] = D.PrepareInput(Input);

            expectedOutput = [1; 2; 3; 4];

            testCase.verifySize(InPadded, [4 1]);
            testCase.verifyEqual(InPadded, expectedOutput);
            testCase.verifyEqual(NumBlocks, 1);
        end


        function testPrepareInputPadsIncompleteBlock(testCase)
            %% Validates Incomplete Input Block Is Zero Padded

            P = testCase.createDefaultParameters();
            D = DSP(P);

            % DcF = 4, therefore 5 samples require 3 zeros
            Input = [1 2 3 4 5];

            [InPadded, NumBlocks] = D.PrepareInput(Input);

            expectedOutput = [1; 2; 3; 4; 5; 0; 0; 0];

            testCase.verifyEqual(InPadded, expectedOutput);
            testCase.verifyEqual(NumBlocks, 2);
        end


        function testPrepareInputDoesNotPadCompleteBlocks(testCase)
            %% Validates Complete DcF Blocks Receive No Extra Padding

            P = testCase.createDefaultParameters();
            D = DSP(P);

            % Eight samples already form two complete DcF = 4 blocks
            Input = [1 2 3 4 5 6 7 8];

            [InPadded, NumBlocks] = D.PrepareInput(Input);

            expectedOutput = (1:8)';

            testCase.verifyEqual(InPadded, expectedOutput);
            testCase.verifyLength(InPadded, 8);
            testCase.verifyEqual(NumBlocks, 2);
        end


        function testPrepareInputPadsSignalShorterThanOneBlock(testCase)
            %% Validates Short Input Is Padded To One Complete Block

            P = testCase.createDefaultParameters();
            D = DSP(P);

            % Three samples with DcF = 4 require one zero
            Input = [1 2 3];

            [InPadded, NumBlocks] = D.PrepareInput(Input);

            expectedOutput = [1; 2; 3; 0];

            testCase.verifyEqual(InPadded, expectedOutput);
            testCase.verifyEqual(NumBlocks, 1);
        end
    end

    methods (Access = private)
        function P = createDefaultParameters(~)
            %% Creates Default Parameter Object For DSP Tests

            P = DSPParameters();

            P.setValue("DcF", 4); % Decimation Factor

            % LPF design parameters required 
            P.setValue("Fs_DSP", 2000);
            P.setValue("Fpass", 200);
            P.setValue("Fstop", 300);
            P.setValue("Astop", 60);
            P.setValue("Apass", 1);
            P.setValue("B", 25);
        end
    end
end