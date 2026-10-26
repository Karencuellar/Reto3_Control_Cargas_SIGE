%% =====================================================================
%  RETO 3 - ALGORITMO DE CONTROL Y CARGAS
%  Proyecto: Sistema Inteligente de Gestion Energetica (SIGE)
%  Curso: Software para Ingenieria (203036) - UNAD
%  Autora: Karen Yulieth Cuellar Murcia
%
%  Proposito: simular durante 24 horas el controlador central de la
%  micro-red hibrida. En cada hora el algoritmo compara la generacion
%  (solar + eolica) con la demanda de la comunidad:
%    - Si hay superavit, carga el banco de baterias (maximo 100 %).
%    - Si hay deficit, descarga las baterias y aplica el protocolo de
%      desconexion de cargas (Load Shedding) segun el estado de carga:
%         SOC > 40 %         -> Ruta segura: todo encendido
%         20 % < SOC <= 40 % -> Ruta de alerta: se apaga el alumbrado
%         SOC <= 20 %        -> Ruta de emergencia: solo la escuela
%  Se simulan dos escenarios con los vectores del Reto 2:
%    1) Dia nominal: generacion completa.
%    2) Dia critico: generacion reducida al 30 % (dia nublado y sin
%       viento), para comprobar que se activan las rutas de alerta y
%       de emergencia.
%  =====================================================================

clc;          % Limpia la ventana de comandos para mostrar solo este reporte
clear;        % Borra las variables de ejecuciones anteriores
close all;    % Cierra las figuras abiertas

%% 1. CONFIGURACION INICIAL
horas = 1:24;                 % Vector de tiempo: cada posicion es una hora del dia

% --- Generacion solar (Reto 2): media onda senoidal entre las horas 6 y 18, pico de 25 kW
Pmax_solar = 25;                                              % Potencia pico del arreglo fotovoltaico (kW)
solar = zeros(1, 24);                                         % Sin radiacion en la noche (vector de ceros)
solar(6:18) = Pmax_solar * sin(pi * (horas(6:18) - 5) / 14);  % Curva solar solo en horas de luz

% --- Generacion eolica (Reto 2): perfil fijo e irregular, limitado a 15 kW
eolica = [8.2 9.4 10.1 8.7 6.3 0.8 2.4 3.8 5.1 6.6 4.9 7.3 ...
          8.8 10.2 11.6 12.9 13.8 11.4 9.7 10.5 9.2 8.4 9.9 8.8];  % Potencia eolica por hora (kW)
eolica = min(eolica, 15);                                     % Limitador de potencia nominal del aerogenerador

% --- Demanda de la comunidad (Reto 2): escuela + bombeo + alumbrado
demanda = [3.0 2.6 2.2 2.4 3.1 ...                            % Horas 1-5: consumo base de madrugada
           7.2 7.6 8.8 9.6 9.2 8.4 7.9 8.1 9.3 9.8 8.7 7.4 ... % Horas 6-17: escuela y bombeo agricola
           12.9 15.0 14.6 13.1 ...                            % Horas 18-21: pico con alumbrado publico
           3.8 3.3 2.7];                                      % Horas 22-24: regreso al consumo base
Edem = demanda;                                               % Energia demandada en cada hora (kWh), 1 h por posicion

% --- Parametros de la bateria
Capacidad_bat = 100;   % Capacidad total del banco de baterias (kWh)
SOC_inicial = 50;      % Estado de carga inicial: 50 % (carga de seguridad)
SOC_max = 100;         % Limite superior de seguridad (evita sobrecarga)
SOC_min = 0;           % Limite inferior absoluto (evita vaciamiento profundo)

% --- Escenarios a simular
factores = [1 0.3];                                           % 1 = dia nominal, 0.3 = generacion al 30 %
nombres = {'DIA NOMINAL (datos del Reto 2)', 'DIA CRITICO (generacion al 30 %)'};
SOC_escenarios = zeros(2, 24);                                % Fila 1: SOC del dia nominal; fila 2: dia critico
estados = {'SUSPENDIDO', 'ACTIVO'};                           % Texto del reporte: posicion 1 = 0, posicion 2 = 1

%% 2. SIMULACION DE LOS DOS ESCENARIOS
for e = 1:2                                    % Recorre los dos escenarios

    Egen = factores(e) * (solar + eolica);     % Generacion hibrida total del escenario (kWh por hora)
    SOC = SOC_inicial;                         % Cada escenario arranca con la bateria al 50 %
    balance   = zeros(1, 24);                  % Balance Egen - Edem de cada hora (kWh)
    ruta_hist = zeros(1, 24);                  % Codigo de ruta: 0 superavit, 1 segura, 2 alerta, 3 emergencia

    % --- Encabezado del reporte por consola
    fprintf('=================================================================================\n');
    fprintf('   SIGE - REPORTE HORARIO DEL CONTROLADOR - %s\n', nombres{e});
    fprintf('=================================================================================\n');
    fprintf('Hora | Egen(kWh) | Edem(kWh) | Balance(kWh) | SOC(%%) | Escuela | Bombeo | Alumbrado\n');
    fprintf('---------------------------------------------------------------------------------\n');

    %% 3. BUCLE DE SIMULACION DE 24 HORAS
    for h = 1:24                               % Recorre secuencialmente las 24 horas del dia

        balance(h) = Egen(h) - Edem(h);        % Diferencia entre generacion y demanda en la hora h

        % Por defecto los tres servicios quedan activos (1 = activo, 0 = suspendido)
        escuela = 1;                           % Escuela rural: prioridad critica
        bombeo = 1;                            % Bombeo de agua agricola: prioridad media
        alumbrado = 1;                         % Alumbrado publico: prioridad baja

        if Egen(h) >= Edem(h)
            % ----- ESCENARIO DE SUPERAVIT -----
            Excedente = Egen(h) - Edem(h);                      % Energia sobrante de la hora (kWh)
            SOC = SOC + (Excedente / Capacidad_bat) * 100;      % Carga la bateria con el excedente
            if SOC > SOC_max
                SOC = SOC_max;                                  % Limita la carga al 100 % para proteger los equipos
            end
            ruta_hist(h) = 0;                                   % Superavit: todos los servicios activos
        else
            % ----- ESCENARIO DE DEFICIT -----
            Faltante = Edem(h) - Egen(h);                       % Energia que falta para cubrir la demanda (kWh)
            SOC = SOC - (Faltante / Capacidad_bat) * 100;       % Extrae el faltante del banco de baterias
            if SOC < SOC_min
                SOC = SOC_min;                                  % Impide que el SOC baje del 0 %
            end

            % Protocolo de desconexion de cargas (Load Shedding) segun el nuevo SOC
            if SOC > 40
                ruta_hist(h) = 1;                               % Ruta segura: la bateria sostiene todos los servicios
            elseif SOC > 20
                alumbrado = 0;                                  % Ruta de alerta: se apaga el alumbrado publico
                ruta_hist(h) = 2;
            else
                alumbrado = 0;                                  % Ruta de emergencia: se apaga el alumbrado
                bombeo = 0;                                     % y tambien el bombeo agricola
                ruta_hist(h) = 3;                               % Solo la escuela permanece energizada
            end
        end

        SOC_escenarios(e, h) = SOC;                             % Guarda el SOC al final de la hora

        % Imprime la fila del reporte de la hora h
        fprintf('%4d | %9.2f | %9.2f | %12.2f | %6.2f | %-7s | %-10s | %-10s\n', ...
                h, Egen(h), Edem(h), balance(h), SOC, ...
                estados{escuela + 1}, estados{bombeo + 1}, estados{alumbrado + 1});
    end

    %% 4. RESUMEN DEL ESCENARIO
    fprintf('---------------------------------------------------------------------------------\n');
    fprintf('Energia generada en el dia:   %.2f kWh\n', sum(Egen));          % Total generado
    fprintf('Energia demandada en el dia:  %.2f kWh\n', sum(Edem));          % Total demandado
    fprintf('SOC final de la bateria:      %.2f %%\n', SOC);                  % Estado de carga al terminar el dia
    fprintf('Horas en superavit:           %d\n', sum(ruta_hist == 0));      % Horas que cargaron la bateria
    fprintf('Horas en ruta segura:         %d\n', sum(ruta_hist == 1));      % Deficit sin desconexion
    fprintf('Horas en ruta de alerta:      %d\n', sum(ruta_hist == 2));      % Alumbrado apagado
    fprintf('Horas en ruta de emergencia:  %d\n\n', sum(ruta_hist == 3));    % Solo escuela activa
end

%% 5. GRAFICA DEL ESTADO DE CARGA EN LOS DOS ESCENARIOS
figure('Name', 'SOC de la bateria - SIGE', 'Color', 'w');                   % Ventana de figura con fondo blanco
plot(horas, SOC_escenarios(1, :), '-o', 'Color', [0 0.45 0.74], 'LineWidth', 2);    % Dia nominal (azul)
hold on;
plot(horas, SOC_escenarios(2, :), '-s', 'Color', [0.80 0 0], 'LineWidth', 2);       % Dia critico (rojo)
plot([1 24], [40 40], '--', 'Color', [0.93 0.69 0.13], 'LineWidth', 1.2);   % Umbral de alerta (40 %)
plot([1 24], [20 20], '--', 'Color', [0.85 0.33 0.10], 'LineWidth', 1.2);   % Umbral de emergencia (20 %)
hold off;
title('Estado de carga de la bateria durante 24 horas');                    % Titulo
xlabel('Hora del dia'); ylabel('SOC (%)');                                  % Etiquetas de ejes
legend('Dia nominal', 'Dia critico (generacion al 30 %)', ...
       'Umbral de alerta 40 %', 'Umbral de emergencia 20 %', 'Location', 'south');
grid on; xlim([1 24]); ylim([0 105]);                                       % Cuadricula y limites
set(gca, 'XTick', 1:24);                                                    % Una marca por hora