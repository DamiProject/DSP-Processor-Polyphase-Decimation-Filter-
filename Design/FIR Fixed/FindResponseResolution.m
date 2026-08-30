function NPoint = FindResponseResolution(...
    FilterCoefficients, Parameters)
%% ========================================
%%  FIR FREQUENCY RESPONSE GRID REFINEMENT
%% ========================================
Fs_DSP = Parameters.getValue("Fs_DSP");
Fpass  = Parameters.getValue("Fpass");
Fstop  = Parameters.getValue("Fstop");

% Ensure row-vector representation
FilterCoefficients = FilterCoefficients(:).';

% Initial frequency grid
NPoint = 512;

% Maximum permitted verification grid
MaxNPoint = 131072;


% Convergence tolerance for measured response extrema
ConvergenceTolerance_dB = 1e-3;

% Measure response using initial grid
[PrevPassMax_dB, PrevPassMin_dB, PrevStopMax_dB] = ...
    MeasureResponse(FilterCoefficients, ...
    Fs_DSP, Fpass, Fstop, NPoint);

while NPoint < MaxNPoint

    % Refine frequency grid by a factor of two.
    % Each refinement halves the frequency spacing, providing
    % a predictable convergence check on measured response 
    % extrema.
    % Double frequency-grid resolution
    CandidateNPoint = 2 * NPoint;

    % Measure response using finer grid
    [PassMax_dB, PassMin_dB, StopMax_dB] = ...
        MeasureResponse(FilterCoefficients, ...
        Fs_DSP, Fpass, Fstop, CandidateNPoint);

    % Change in measured extrema
    PassMaxChange = abs(PassMax_dB - PrevPassMax_dB);
    PassMinChange = abs(PassMin_dB - PrevPassMin_dB);
    StopMaxChange = abs(StopMax_dB - PrevStopMax_dB);

    % Check convergence
    if PassMaxChange <= ConvergenceTolerance_dB && ...
            PassMinChange <= ConvergenceTolerance_dB && ...
            StopMaxChange <= ConvergenceTolerance_dB

        NPoint = CandidateNPoint;
        break;
    end

    % Continue refinement
    NPoint = CandidateNPoint;

    PrevPassMax_dB = PassMax_dB;
    PrevPassMin_dB = PassMin_dB;
    PrevStopMax_dB = StopMax_dB;
end

fprintf("Frequency response verification points = %d\n", NPoint);

    function [PassMax_dB, PassMin_dB, StopMax_dB] = ...
            MeasureResponse(Coefficients, Fs_DSP, Fpass, Fstop, NPoint)
        %% ==============================
        %% FREQUENCY RESPONSE CALCULATION
        %% ==============================
        
        % Include specification edges explicitly;
        % a uniform grid alone can miss them.
        f = linspace(0, Fs_DSP/2, NPoint + 1);

        % Guarantee exact passband and stopband edges are evaluated
        f = unique([f, Fpass, Fstop]);

        % FIR frequency response
        [H, f] = freqz(Coefficients, 1, f, Fs_DSP);

        % Magnitude response in dB and use eps to prevent log10(0)
        % operations if a null occurs
        Magnitude_dB = 20 * log10(max(abs(H), eps));

        % Passband and stopband regions
        PassbandRegion = (f <= Fpass);
        StopbandRegion = (f >= Fstop);

        % Passband extrema
        PassMax_dB = max(Magnitude_dB(PassbandRegion));
        PassMin_dB = min(Magnitude_dB(PassbandRegion));

        % Worst-case stopband level
        StopMax_dB = max(Magnitude_dB(StopbandRegion));
    end
end