classdef TestDSPParameters < matlab.unittest.TestCase
    %% ===================================================
    %% UNIT TEST SUITE FOR THE PARAMETERS CONTAINER CLASS
    %% ===================================================

    methods (Test)

        function testConstructorCreatesParameters(testCase)
            %% Validates Constructor Creates Expected Parameters
            P = DSPParameters();

            testCase.verifyClass(P.getDSPMeta("Fs_DSP"), "DSPMeta");
            testCase.verifyClass(P.getDSPMeta("Fpass"), "DSPMeta");
        end

        function testGetValueReturnsAssignedValue(testCase)
            %% Validates getValue Returns Stored Parameter Value
            P = DSPParameters();

            P.setValue("Fs_DSP", 1e6);

            testCase.verifyEqual(P.getValue("Fs_DSP"), 1e6);
        end

        function testSetValueUpdatesValue(testCase)
            %% Validates setValue Updates Existing Parameter Values
            P = DSPParameters();

            P.setValue("Fs_DSP", 10);
            P.setValue("Fs_DSP", 25);

            testCase.verifyEqual(P.getValue("Fs_DSP"), 25);
        end

        function testGetMetaReturnsCorrectMetadata(testCase)
            %% Validates getMeta Returns Correct Metadata
            P = DSPParameters();

            FsMeta = P.getDSPMeta("Fs_DSP");

            testCase.verifyEqual(FsMeta.Name, "DSP Sampling Frequency");
            testCase.verifyEqual(FsMeta.Unit, "Hz");
        end

        function testUnknownKeyThrowsOnGetValue(testCase)
            %% Validates getValue Rejects Unknown Keys
            P = DSPParameters();

            fh = @() P.getValue("WrongKey");

            testCase.verifyError(fh, 'Parameters:UnknownKey');
        end

        function testUnknownKeyThrowsOnSetValue(testCase)
            %% Validates setValue Rejects Unknown Keys
            P = DSPParameters();

            fh = @() P.setValue("WrongKey", 10);

            testCase.verifyError(fh, 'Parameters:UnknownKey');
        end

        function testUnknownKeyThrowsOnGetMeta(testCase)
            %% Validates getMeta Rejects Unknown Keys
            P = DSPParameters();

            fh = @() P.getDSPMeta("WrongKey");

            testCase.verifyError(fh, 'Parameters:UnknownKey');
        end

        function testSetValueUsesMetaValidation(testCase)
            %% Validates Parameter Validation Is Enforced
            P = DSPParameters();

            fh = @() P.setValue("Fs_DSP", -1);

            testCase.verifyError(fh, 'DSPMeta:ValidationFailed');
        end

        function testDefaultValueIsNaN(testCase)
            %% Validates Parameters Start Unassigned
            P = DSPParameters();

            testCase.verifyTrue(isnan(P.getValue("Fs_DSP")));
        end
    end
end