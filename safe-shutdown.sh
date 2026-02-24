#!/bin/bash

echo "Iniciando desligamento seguro do node Bitcoin..."

# Parar o serviço Bitcoin Core
echo "Parando o serviço bitcoin..."
sudo systemctl stop bitcoin

# Parar os scripts de monitor
echo "Parando status_listener..."
sudo systemctl stop status_listener

echo "Parando sync_monitor..."
sudo systemctl stop sync_monitor

# Aguardar até que os serviços terminem de parar
echo "Aguardando serviços encerrarem..."

# Espera se o serviço bitcoind ainda estiver ativo
sudo systemctl is-active --quiet bitcoin && sleep 2

# Espera se o status_listener ainda estiver ativo
sudo systemctl is-active --quiet status_listener && sleep 1

# Espera se o sync_monitor ainda estiver ativo
sudo systemctl is-active --quiet sync_monitor && sleep 1

echo "Serviços encerrados, desligando o sistema..."

# Finalmente desligar o sistema
sudo shutdown now
