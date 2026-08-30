function [FixedFilterCoefficients, CoeffWL, CoeffIWL, ...
    CoeffFWL, CoeffScale] =  FindCoefficientFormat(...
   FilterCoefficients, Parameters, NPoint)
%% =========================================================
%% FIXED-POINT FIR COEFFICIENT RANGE AND RESOLUTION SELECTION 
%% ==========================================================

Fs_DSP = Parameters.getValue("Fs_DSP");
Fpass  = Parameters.getValue("Fpass");
Fstop  = Parameters.getValue("Fstop");
Apass  = Parameters.getValue("Apass");
Astop  = Parameters.getValue("Astop");

% Ensure row-vector representation
FilterCoefficients = FilterCoefficients(:).';

% Passband ripple tolerance
delta_p = (10^(Apass/20) - 1) / ...
    (10^(Apass/20) + 1);

% Stopband magnitude tolerance
delta_s = 10^(-Astop/20);

% Numerical safety limit for automatic FWL search.
MaxFWL = 32;
FormatFound = false;

for CandidateFWL = 0:MaxFWL

    % Fixed-point scaling factor
    CandidateScale = 2^CandidateFWL;

    % Quantize prototype FIR into integer coefficient codes
    CandidateFixed = round( ...
        FilterCoefficients * CandidateScale);

    %% ----------------------------------------------
    %% Determine Minimum Signed Word Length Required
    %% ----------------------------------------------

    % Start with one sign/integer bit plus fractional bits
    CandidateWL = CandidateFWL + 1;

    % Increase WL until every coefficient integer fits
    while max(CandidateFixed) > ...
            (2^(CandidateWL - 1) - 1) || ...
            min(CandidateFixed) < ...
            (-2^(CandidateWL - 1))

        CandidateWL = CandidateWL + 1;
    end

    % Integer word length includes sign bit
    CandidateIWL = CandidateWL - CandidateFWL;

    %% ------------------------------------------------------
    %% Reconstruct Quantized Coefficients For DSP Verification
    %% ------------------------------------------------------

    QuantizedCoefficients = ...
        CandidateFixed / CandidateScale;

    %% ------------------------------------------------------
    %% Test Quantized FIR Against Original DSP Specifications
    %% ------------------------------------------------------

    [PassbandOK, StopbandOK] = CheckResponse( ...
        QuantizedCoefficients, ...
        Fs_DSP, Fpass, Fstop, ...
        delta_p, delta_s, NPoint);

    %% ------------------------------------------------------
    %% First Passing Format = Minimum Required FWL
    %% ------------------------------------------------------

    if PassbandOK && StopbandOK

        FormatFound = true;

        % Store selected coefficient integer codes
        FixedFilterCoefficients = int64(CandidateFixed);

        CoeffWL    = CandidateWL;
        CoeffIWL   = CandidateIWL;
        CoeffFWL   = CandidateFWL;
        CoeffScale = CandidateScale;

        break;
    end
end

if ~FormatFound
    error(['No coefficient format satisfied the filter ', ...
        'specifications up to FWL = %d.'], MaxFWL);
end

    function [PassbandOK, StopbandOK] = CheckResponse( ...
            Coefficients, Fs_DSP, Fpass, Fstop, ...
            delta_p, delta_s, NPoint)
        %% ==============================
        %% FREQUENCY RESPONSE CALCULATION
        %% ==============================
        
        % Include specification edges explicitly;
        % a uniform grid alone can miss them.
        f = linspace(0, Fs_DSP/2, NPoint + 1);

        % Guarantee exact passband and stopband edges are evaluated
        f = unique([f, Fpass, Fstop]);

        % Frequency response
        [H, f] = freqz(Coefficients, 1,  f, Fs_DSP);

        Magnitude = abs(H);

        % Passband and stopband frequency regions
        PassbandRegion = (f <= Fpass);
        StopbandRegion = (f >= Fstop);

        % Worst-case passband deviation from unity
        PassbandError = ...
            max(abs(Magnitude(PassbandRegion) - 1));

        % Worst-case stopband magnitude
        StopbandMagnitude = ...
            max(Magnitude(StopbandRegion));

        % Specification checks
        PassbandOK = PassbandError <= delta_p;
        StopbandOK = StopbandMagnitude <= delta_s;
    end
end