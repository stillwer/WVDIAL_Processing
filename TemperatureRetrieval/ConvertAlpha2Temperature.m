



function [TCurrent] = ConvertAlpha2Temperature(Alpha,Const,Data1D,Data2D,Options,Surf,Spectra,Op)
%
%
% Add moisture mixing ratio
% Add ability to check lapse rate
%
%
%% Constants used to run this function
GuessLapse = -0.0098;
Tolerance  = 0.05;

Qwv = 0;

LoopNumber = 50;  % Number of times to run the temperature iterator
To         = 296; % Hitran reference temperature
%% Calculating constants
Gamma = Const.G0*Const.MolMAir/Const.R;
%% Iterating
% Seeding the loop with initial guesses of temperature and lapse rate
ConstProfile = (Options.Range').*(GuessLapse);
% Creating current temperature structure
TCurrent.TimeStamp = Data2D.NCIP.Temperature.TimeStamp;
TCurrent.Range     = Data2D.NCIP.Temperature.Range;
TCurrent.Value     = repmat(ConstProfile,1,size(Alpha,2))+Surf.Temperature.Value';
% TCurrent.Value     = repmat(ConstProfile,1,size(Alpha,2))+283.15;
% Looping
for m=1:1:LoopNumber
    % Calculating the absorption lineshape function (update with temp)
    PCA.O2Online.Absorption = Spectra.PCA.O2Online.Absorption;
    SpecNew = BuildSpectra(PCA,TCurrent,Data2D.NCIP.Pressure,Data1D.Wavelength,Op);
    LineShape = SpecNew.O2Online.AbsorptionObserved./Const.O2LineS;
    % Calculating lapse rate fo the current temperature profile
%     Lapse = FittingLapseRate(TCurrent);
    Lapse = ones(1,length(Surf.Temperature.Value)).*GuessLapse; 
    % Calculating simplifying constants
    [C1,C2,C3] = CalculateConstants(Const,Surf,Gamma,Lapse,TCurrent.Value,To);
    % Calculating the update temperature
    DeltaT = Alpha./(C1.*C2.*C3.*LineShape.*Const.QO2.*(1-Qwv)) - 1./C3;
    % Limiting the gradient possible
    DeltaT(abs(DeltaT) > 2) = sign(DeltaT(abs(DeltaT) > 2)).*2;
    % Outputting temperature state
    TempDiffAvg = mean(mean(DeltaT,'omitnan'),'omitnan');
    
    CWLogging(sprintf('      Mean dT: %4.3f\n',TempDiffAvg),Op,'Retrievals')

    % Updating the current temperature
    TCurrent.Value = TCurrent.Value + DeltaT;
    if abs(TempDiffAvg) <= Tolerance
        break
    end
%     % Plotting just to see whats going on
%     figure(101);
%     subplot(LoopNumber,1,m)
%     pcolor(DeltaT); shading flat; colorbar; caxis([-2,2]); colormap(gca,redblue(64))

% % %     % Plotting just to see whats going on
% % %     if mod(m,5)==1
% % %         figure(101);
% % %         subplot(ceil(LoopNumber/5),1,floor(m/5)+1)
% % %         pcolor(DeltaT); shading flat; colorbar; caxis([-2,2]); colormap(gca,redblue(64))
% % %     end
end
end

function [C1,C2,C3] = CalculateConstants(Const,Surf,Gamma,Lapse,Tc,To)
%
% Tc = temp current
%
%
%
%% Calculating intermediate variable for simplicity
GL = Gamma./Lapse;
%% Calculating the simplifying constant variables Kevin uses
% Updates each time because the lapse rate updates
C1 = Const.O2LineS.*To.*(Surf.Pressure.Value'.*Const.Atm2Pa).*exp(Const.Eo/Const.Kb/To)./...
                                                   (Const.Kb.*Surf.Temperature.Value'.^(-GL));
% Updates each time because it depends on current iteration's temperature 
C2 = Tc.^(-GL-2).*exp(-Const.Eo./Const.Kb./Tc);
% Updates each time because it depends on current iteration's temperature
%%%%%%%%%%%%%%%% Kevin and I vary here by a negative sign %%%%%%%%%%%%%%%%%
C3 = (-GL - 2)./Tc + Const.Eo./Const.Kb./(Tc.^2);
end

function [LapseRates] = FittingLapseRate(TCurrent)
%
%
%
%% Setting fit perameters
RangeAllowed = [1e3,2.5e3];

Indices = [find(TCurrent.Range>RangeAllowed(1),1,'first'),...
           find(TCurrent.Range>RangeAllowed(2),1,'first')];

%% Pre-allocating data
LapseRates = zeros(1,length(TCurrent.TimeStamp));
%% Least squares fitting data to find the lapse rate
tic
for m=1:1:length(LapseRates)
    % Grabbing data to check for nans
    TData     = TCurrent.Value(Indices(1):Indices(2),m);
    RangeData = TCurrent.Range(Indices(1):Indices(2));
    % Removing nan values from data
    RangeData(isnan(TData)) = [];
    TData(isnan(TData)) = []; 
    % Making weight table (intercept, slope)
    X = [ones(size(TData)),RangeData'];
    % Doing a least squares fit
    Coeffs = X\TData;
    % Saving data
    LapseRates(m) = Coeffs(2);
end
fprintf(['      Lapse rate fitting took: ',num2str(toc),' [sec] with mean: ',num2str(mean(LapseRates)),'\n'])
end