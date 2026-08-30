function [DecimatedSignal, MACData] = ...
    FixedToRealConverter(DecimatedCodes, MACData)

% FIXEDTOREALCONVERTER
% Converts the integer-code output and MAC characterization data
% of the bounded fixed-point decimator back to real-valued quantities.
%
% This function is intended for verification and analysis after
% quantization, rounding/truncation, and overflow handling have
% been applied.
%
% Inputs:
%   DecimatedCodes - Final decimator output integer codes
%   MACData        - Integer-domain MAC characterization data
%
% Outputs:
%   DecimatedSignal - Real-valued representation of DecimatedCodes
%   MACData         - MAC data with real-valued characterization added


    %% ==========================================
    %% VERIFY BOUNDED FIXED-POINT RESULT
    %% ==========================================

    if ~isfield(MACData, 'AccumulatorFormat')

        error([ ...
            'FixedToRealConverter requires the bounded fixed-point ' ...
            'MAC result containing MACData.AccumulatorFormat.']);

    end

    %% ==========================================
    %% FIXED-POINT SCALING
    %% ==========================================

    ProductFWL = ...
        MACData.ProductFormat.FWL;

    AccumulatorFWL = ...
        MACData.AccumulatorFormat.FWL;


    ProductScale = ...
        2^(-ProductFWL);

    AccumulatorScale = ...
        2^(-AccumulatorFWL);


    %% ==========================================
    %% DECODE FINAL OUTPUT
    %% ==========================================

    DecimatedSignal = ...
        double(DecimatedCodes) .* ...
        AccumulatorScale;

    %% ==========================================
    %% STORE OUTPUT CODES
    %% ==========================================

    MACData.DecimatedCodes = ...
        DecimatedCodes;

    %% ==========================================
    %% CONVERT PRODUCT CHARACTERIZATION
    %% ==========================================

    MACData.Product.Max = ...
        double(MACData.Product.MaxCode) .* ...
        ProductScale;

    MACData.Product.Min = ...
        double(MACData.Product.MinCode) .* ...
        ProductScale;

    MACData.Product.MaxAbs = ...
        double(MACData.Product.MaxAbsCode) .* ...
        ProductScale;

    %% ==========================================
    %% CONVERT BRANCH ACCUMULATOR CHARACTERIZATION
    %% ==========================================

    MACData.BranchAccumulator.Max = ...
        double(MACData.BranchAccumulator.MaxCode) .* ...
        AccumulatorScale;

    MACData.BranchAccumulator.Min = ...
        double(MACData.BranchAccumulator.MinCode) .* ...
        AccumulatorScale;

    MACData.BranchAccumulator.MaxAbs = ...
        double(MACData.BranchAccumulator.MaxAbsCode) .* ...
        AccumulatorScale;

    MACData.BranchAccumulator.GrowthByTap = ...
        double(MACData.BranchAccumulator.GrowthByTapCode) .* ...
        AccumulatorScale;

    %% ==========================================
    %% CONVERT FINAL ACCUMULATOR CHARACTERIZATION
    %% ==========================================

    MACData.FinalAccumulator.Max = ...
        double(MACData.FinalAccumulator.MaxCode) .* ...
        AccumulatorScale;

    MACData.FinalAccumulator.Min = ...
        double(MACData.FinalAccumulator.MinCode) .* ...
        AccumulatorScale;

    MACData.FinalAccumulator.MaxAbs = ...
        double(MACData.FinalAccumulator.MaxAbsCode) .* ...
        AccumulatorScale;

    MACData.FinalAccumulator.GrowthByBranch = ...
        double(MACData.FinalAccumulator.GrowthByBranchCode) .* ...
        AccumulatorScale;

    %% ==========================================
    %% CONVENIENT CHARACTERIZATION VALUES
    %% ==========================================

    MACData.BranchAccumulator.MaxPositive = ...
        max(0, MACData.BranchAccumulator.Max);

    MACData.BranchAccumulator.MinNegative = ...
        min(0, MACData.BranchAccumulator.Min);

    MACData.FinalAccumulator.MaxPositive = ...
        max(0, MACData.FinalAccumulator.Max);

    MACData.FinalAccumulator.MinNegative = ...
        min(0, MACData.FinalAccumulator.Min);

    %% ==========================================
    %% TOTAL ACCUMULATOR OVERFLOW COUNT
    %% ==========================================

    MACData.TotalAccumulatorOverflowCount = ...
        MACData.BranchAccumulatorOverflowCount + ...
        MACData.FinalAccumulatorOverflowCount;
end