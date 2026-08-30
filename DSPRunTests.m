%% Runs all tests for Polyphase Decimator DSP

clear;
clc;

%% ==========================================
%% PROJECT ROOT
%% ==========================================

projectRoot = fileparts(mfilename("fullpath"));

%% ==========================================
%% PROJECT PATHS
%% ==========================================

addpath(genpath(fullfile(projectRoot, "Design")));

%% ==========================================
%% RUN TESTS
%% ==========================================

TestRoot = fullfile(projectRoot, "Tests");

results = runtests( ...
    TestRoot, ...
    "IncludeSubfolders", true);

disp(results);

%% ==========================================
%% VERIFY TEST RESULTS
%% ==========================================

assertSuccess(results);