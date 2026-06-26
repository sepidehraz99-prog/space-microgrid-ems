%% Space Microgrid Energy Management System
% Rule-based EMS for PV-Battery-Load system
%
% This MATLAB simulation is an original educational implementation inspired by:
% [1] R. H. Lasseter, "MicroGrids," IEEE PES Winter Meeting, 2002.
% [2] D. E. Olivares et al., "Trends in Microgrid Control," IEEE Trans. Smart Grid, 2014.
% [3] M. R. Patel, "Spacecraft Power Systems," CRC Press, 2005.
% [4] O. Tremblay and L.-A. Dessaint, "Experimental Validation of a Battery Dynamic Model,"
%     World Electric Vehicle Journal, 2009.
% [5] MathWorks Simscape Electrical documentation: PV Array and Battery modeling.
%
% Main concepts used:
% - PV generation profile
% - Battery state of charge update
% - Load classification into critical, normal, and sheddable loads
% - SOC-based rule-based energy management

clc;
clear;
close all;

%% Simulation time
dt = 1;                  % Time step [s]
Tsim = 3600;             % Total simulation time [s]
t = 0:dt:Tsim;           % Time vector
N = length(t);

%% PV System Parameters
Ppv_rated = 1200;        % Rated PV power at standard test condition [W]
G_stc = 1000;            % Standard irradiance [W/m^2]
T_stc = 25;              % Standard temperature [deg C]
alpha_p = -0.004;        % PV temperature coefficient [1/deg C]

% Irradiance profile [W/m^2]
G = zeros(1,N);

for k = 1:N
    if t(k) < 600
        G(k) = 300;
    elseif t(k) < 1500
        G(k) = 800;
    elseif t(k) < 2500
        G(k) = 1000;
    elseif t(k) < 3200
        G(k) = 450;
    else
        G(k) = 200;
    end
end

% Cell temperature profile [deg C]
Tcell = 25 * ones(1,N);

% Simplified PV power model
% Ppv = Pstc * (G/Gstc) * [1 + alpha*(Tcell - Tstc)]
Ppv = Ppv_rated .* (G ./ G_stc) .* (1 + alpha_p .* (Tcell - T_stc));

% Avoid negative PV power
Ppv(Ppv < 0) = 0;

%% Load Classification
% In spacecraft and microgrid systems, loads can be classified by priority.
% Critical loads must remain connected as long as possible.

Pcritical = 350;         % Critical load power [W]
Pnormal   = 300;         % Normal load power [W]
Pshed     = 250;         % Sheddable load power [W]

%% Battery Parameters
Ebat_Wh = 1200;          % Battery energy capacity [Wh]
SOC = zeros(1,N);        % Battery state of charge [%]
SOC(1) = 70;             % Initial SOC [%]

SOC_max = 95;            % Maximum allowed SOC [%]
SOC_min = 20;            % Minimum safe SOC [%]
SOC_low = 30;            % Low SOC threshold [%]
SOC_reconnect = 40;      % Reconnection threshold [%]

eta_ch = 0.95;           % Charging efficiency
eta_dis = 0.95;          % Discharging efficiency

%% EMS Variables
Pload = zeros(1,N);      % Total connected load power [W]
Pbat = zeros(1,N);       % Battery power [W]
Pcurt = zeros(1,N);      % Curtailed PV power [W]

critical_status = ones(1,N);
normal_status   = ones(1,N);
shed_status     = ones(1,N);

mode = strings(1,N);

%% Rule-Based Energy Management System
for k = 1:N-1
    
    % Load management based on SOC
    if SOC(k) <= SOC_min
        % Emergency mode: only critical load remains connected
        critical_status(k) = 1;
        normal_status(k) = 0;
        shed_status(k) = 0;
        mode(k) = "Emergency";
        
    elseif SOC(k) <= SOC_low
        % Low SOC mode: sheddable load is disconnected
        critical_status(k) = 1;
        normal_status(k) = 1;
        shed_status(k) = 0;
        mode(k) = "Low SOC";
        
    elseif SOC(k) >= SOC_reconnect
        % Normal mode: all loads are connected
        critical_status(k) = 1;
        normal_status(k) = 1;
        shed_status(k) = 1;
        mode(k) = "Normal";
        
    else
        % Intermediate range: keep sheddable load disconnected
        critical_status(k) = 1;
        normal_status(k) = 1;
        shed_status(k) = 0;
        mode(k) = "Recovery";
    end
    
    % Total connected load
    Pload(k) = critical_status(k)*Pcritical + ...
               normal_status(k)*Pnormal + ...
               shed_status(k)*Pshed;
    
    % Power balance:
    % If Pbat > 0: battery discharges
    % If Pbat < 0: battery charges
    Psurplus = Ppv(k) - Pload(k);
    
    if Psurplus >= 0
        % PV supplies load and charges battery
        if SOC(k) < SOC_max
            Pbat(k) = -Psurplus * eta_ch;
            Pcurt(k) = 0;
        else
            Pbat(k) = 0;
            Pcurt(k) = Psurplus;
        end
    else
        % Battery supports the load
        Pbat(k) = abs(Psurplus) / eta_dis;
        Pcurt(k) = 0;
    end
    
    % SOC update using energy balance
    % SOC(k+1) = SOC(k) - battery energy change / capacity
    dE_Wh = Pbat(k) * dt / 3600;      
    dSOC = (dE_Wh / Ebat_Wh) * 100;
    
    SOC(k+1) = SOC(k) - dSOC;
    
    % Limit SOC between 0 and SOC_max
    if SOC(k+1) > SOC_max
        SOC(k+1) = SOC_max;
    elseif SOC(k+1) < 0
        SOC(k+1) = 0;
    end
end

%% Last sample correction
Pload(end) = Pload(end-1);
Pbat(end) = Pbat(end-1);
Pcurt(end) = Pcurt(end-1);
critical_status(end) = critical_status(end-1);
normal_status(end) = normal_status(end-1);
shed_status(end) = shed_status(end-1);
mode(end) = mode(end-1);

%% Plot Results

figure('Name','Space Microgrid EMS Results');

subplot(4,1,1)
plot(t/60, G, 'LineWidth', 2)
grid on
ylabel('G [W/m^2]')
title('Solar Irradiance Profile')

subplot(4,1,2)
plot(t/60, Ppv, 'LineWidth', 2)
hold on
plot(t/60, Pload, 'LineWidth', 2)
grid on
ylabel('Power [W]')
legend('PV Power','Connected Load Power')
title('PV Power and Load Demand')

subplot(4,1,3)
plot(t/60, SOC, 'LineWidth', 2)
hold on
yline(SOC_min,'--r','SOC_{min}');
yline(SOC_low,'--m','SOC_{low}');
yline(SOC_reconnect,'--g','SOC_{reconnect}');
grid on
ylabel('SOC [%]')
title('Battery State of Charge')

subplot(4,1,4)
plot(t/60, Pbat, 'LineWidth', 2)
grid on
ylabel('P_{bat} [W]')
xlabel('Time [min]')
title('Battery Power: Positive = Discharge, Negative = Charge')

figure('Name','Load Connection Status');

stairs(t/60, critical_status, 'LineWidth', 2)
hold on
stairs(t/60, normal_status, 'LineWidth', 2)
stairs(t/60, shed_status, 'LineWidth', 2)
grid on
ylim([-0.2 1.2])
xlabel('Time [min]')
ylabel('Status')
title('EMS Load Connection Status')
legend('Critical Load','Normal Load','Sheddable Load')

figure('Name','PV Curtailment');

plot(t/60, Pcurt, 'LineWidth', 2)
grid on
xlabel('Time [min]')
ylabel('P_{curtailed} [W]')
title('Curtailed PV Power When Battery SOC Reaches Maximum Limit')