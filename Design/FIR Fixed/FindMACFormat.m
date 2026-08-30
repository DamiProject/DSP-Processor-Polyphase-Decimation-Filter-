function MACFormat = FindMACFormat( ...
    InputFormat, ...
    CoefficientFormat, ...
    BranchCoefficientCodes, ...
    MACData, ...
    HeadroomBits)

%% ============================================================
%% FIND MAC FIXED-POINT FORMAT
%%
%% Determines the initial safe MAC accumulator representation
%% from:
%%
%%   - ADC input fixed-point format
%%   - fixed FIR coefficient format
%%   - fixed FIR coefficient integer codes
%%   - reference MAC characterization
%%   - analytical FIR worst-case range
%%
%% The initial MAC FWL preserves the complete product FWL.
%% ============================================================

    %% ==========================================
    %% OPTIONAL INTEGER HEADROOM
    %% ==========================================

    if nargin < 5 || isempty(HeadroomBits)
        HeadroomBits = 0;
    end

    %% ===============
    %% PRODUCT FORMAT
    %% ===============
    %
    % Already determined by FixedDSPDecimator.
    % Do not calculate it again here.

    ProductWL = ...
        MACData.ProductFormat.WL;

    ProductIWL = ...
        MACData.ProductFormat.IWL;

    ProductFWL = ...
        MACData.ProductFormat.FWL;

    %% ======================
    %% REFERENCE MAC SCALE
    %% =====================
    %
    % Reference MAC performs no requantization.
    %
    % Therefore:
    %
    %   Product FWL
    %       =
    %   Branch accumulator FWL
    %       =
    %   Final accumulator FWL

    ProductScale = ...
        2^(-ProductFWL);

    %% ==========================================
    %% ADC REPRESENTABLE RANGE
    %% ==========================================

    InputMinimum = ...
        -2^(InputFormat.IWL - 1);

    InputMaximum = ...
        2^(InputFormat.IWL - 1) - ...
        2^(-InputFormat.FWL);

    InputMaxAbs = ...
        max( ...
        abs(InputMinimum), ...
        abs(InputMaximum));


    %% ==========================================
    %% DECODE FIXED FILTER COEFFICIENTS
    %% ==========================================

    Coefficients = ...
        double(BranchCoefficientCodes) .* ...
        2^(-CoefficientFormat.FWL);

    %% ==========================================
    %% ANALYTICAL POLYPHASE BRANCH BOUNDS
    %% ==========================================
    %
    % For each branch:
    %
    % |A_branch| <= |x|max * SUM(|h_branch|)

    NumberBranches = ...
        size(Coefficients, 1);

    BranchBound = ...
        zeros(1, NumberBranches);


    for k = 1:NumberBranches

        BranchBound(k) = ...
            InputMaxAbs * ...
            sum(abs(Coefficients(k, :)));

    end


    MaximumBranchBound = ...
        max(BranchBound);


    %% ==========================================
    %% ANALYTICAL FINAL FIR BOUND
    %% ==========================================
    %
    % Sum of all polyphase branch bounds:
    %
    % |y|max <= |x|max * SUM(|h|)

    FinalAnalyticalBound = ...
        sum(BranchBound);


    %% ==========================================
    %% REFERENCE MAC CHARACTERIZATION
    %% ==========================================
    %
    % Reference MAC data are still integer codes.
    % Convert them using ProductFWL.

    ObservedProductMaxAbs = ...
        double(MACData.Product.MaxAbsCode) .* ...
        ProductScale;

    ObservedBranchMaxAbs = ...
        double(MACData.BranchAccumulator.MaxAbsCode) .* ...
        ProductScale;

    ObservedFinalMaxAbs = ...
        double(MACData.FinalAccumulator.MaxAbsCode) .* ...
        ProductScale;

    %% ==========================================
    %% REQUIRED MAC RANGE
    %% ==========================================
    %
    % Use whichever requirement is largest:
    %
    %   - analytical worst-case range
    %   - actually observed reference range
    %
    % Analytical bound protects against relying only
    % on the particular simulation waveform.

    RequiredMagnitude = ...
        max([ ...
        FinalAnalyticalBound, ...
        MaximumBranchBound, ...
        ObservedProductMaxAbs, ...
        ObservedBranchMaxAbs, ...
        ObservedFinalMaxAbs]);

    %% ==========================================
    %% INITIAL ACCUMULATOR FRACTIONAL LENGTH
    %% ==========================================
    %
    % Preserve complete multiplication precision.
    %
    % FWL_MAC = FWL_Product
    %
    % FWL optimization can be performed afterward.

    AccumulatorFWL = ...
        ProductFWL;

    %% ==========================================
    %% MINIMUM SAFE INTEGER LENGTH
    %% ==========================================

    AccumulatorIWL = ...
        RequiredSignedIWL( ...
        RequiredMagnitude, ...
        AccumulatorFWL);

    %% ==========================================
    %% OPTIONAL HEADROOM
    %% ==========================================

    AccumulatorIWL = ...
        AccumulatorIWL + ...
        HeadroomBits;

    %% ==========================================
    %% ACCUMULATOR WORD LENGTH
    %% ==========================================

    AccumulatorWL = ...
        AccumulatorIWL + ...
        AccumulatorFWL;


    %% ==========================================
    %% INT64 IMPLEMENTATION LIMIT
    %% ==========================================

    if AccumulatorWL > 63

        error(['Required MAC format is %d bits. ' ...
            'This exceeds the current int64 simulation container.'], ...
            AccumulatorWL);

    end

    %% ==========================================
    %% MAC FORMAT
    %% ==========================================

    MACFormat.WL = ...
        AccumulatorWL;

    MACFormat.IWL = ...
        AccumulatorIWL;

    MACFormat.FWL = ...
        AccumulatorFWL;

    %% ==========================================
    %% PRODUCT FORMAT
    %% ==========================================

    MACFormat.ProductWL = ...
        ProductWL;

    MACFormat.ProductIWL = ...
        ProductIWL;

    MACFormat.ProductFWL = ...
        ProductFWL;

    %% ==========================================
    %% MAC ARITHMETIC POLICIES
    %% ==========================================

    MACFormat.RoundingMethod = ...
        'Nearest';

    MACFormat.OverflowAction = ...
        'Saturate';

    %% ==========================================
    %% GENERIC ACCUMULATOR GROWTH INFORMATION
    %% ==========================================
    %
    % These values came from the reference-decimator
    % full-width calculation.

    MACFormat.NumberProducts = ...
        MACData.NumberProducts;

    MACFormat.GuardBits = ...
        MACData.GuardBits;

    MACFormat.ReferenceContainerWL = ...
        MACData.ReferenceContainerWL;

    %% ==========================================
    %% ANALYTICAL RANGE INFORMATION
    %% ==========================================

    MACFormat.InputMinimum = ...
        InputMinimum;

    MACFormat.InputMaximum = ...
        InputMaximum;

    MACFormat.InputMaxAbs = ...
        InputMaxAbs;


    MACFormat.AnalyticalBranchBound = ...
        BranchBound;

    MACFormat.MaximumAnalyticalBranchBound = ...
        MaximumBranchBound;

    MACFormat.AnalyticalFinalBound = ...
        FinalAnalyticalBound;


    %% ==========================================
    %% OBSERVED REFERENCE RANGE INFORMATION
    %% ==========================================

    MACFormat.ObservedProductMaxAbs = ...
        ObservedProductMaxAbs;

    MACFormat.ObservedBranchMaxAbs = ...
        ObservedBranchMaxAbs;

    MACFormat.ObservedFinalMaxAbs = ...
        ObservedFinalMaxAbs;


    %% ==========================================
    %% FINAL RANGE REQUIREMENT
    %% ==========================================

    MACFormat.RequiredMagnitude = ...
        RequiredMagnitude;

    MACFormat.HeadroomBits = ...
        HeadroomBits;

end

%% ============================================================
%% MINIMUM SIGNED INTEGER WORD LENGTH
%% ============================================================
function IWL = RequiredSignedIWL(MaxMagnitude, FWL)

    if ~isfinite(MaxMagnitude) || MaxMagnitude < 0
        error('MaxMagnitude must be finite and nonnegative.');
    end

    IWL = max( ...
        1, ...
        ceil(log2(MaxMagnitude + 2^(-FWL))) + 1);

end