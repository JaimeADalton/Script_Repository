#!/bin/bash

# Script para descargar y configurar herramientas adicionales
# Este script se incluirá en la imagen y también puede ejecutarse posteriormente
# para actualizar o añadir más herramientas

TOOLS_DIR="/home/security/tools"
mkdir -p $TOOLS_DIR
cd $TOOLS_DIR

echo "[+] Instalando herramientas adicionales de GitHub..."

# Herramientas comunes que no están en los repositorios
tools=(
  "https://github.com/danielmiessler/SecLists.git"
  "https://github.com/swisskyrepo/PayloadsAllTheThings.git"
  "https://github.com/carlospolop/PEASS-ng.git"
  "https://github.com/Tib3rius/AutoRecon.git"
  "https://github.com/aboul3la/Sublist3r.git"
  "https://github.com/maurosoria/dirsearch.git"
  "https://github.com/PowerShellMafia/PowerSploit.git"
  "https://github.com/samratashok/nishang.git"
  "https://github.com/SecureAuthCorp/impacket.git"
  "https://github.com/BloodHoundAD/BloodHound.git"
  "https://github.com/hashcat/hashcat.git"
  "https://github.com/s0md3v/XSStrike.git"
  "https://github.com/sherlock-project/sherlock.git"
  "https://github.com/r3motecontrol/Ghostpack-CompiledBinaries.git"
  "https://github.com/byt3bl33d3r/CrackMapExec.git"
  "https://github.com/SecWiki/windows-kernel-exploits.git"
  "https://github.com/AlessandroZ/LaZagne.git"
  "https://github.com/drwetter/testssl.sh.git"
)

for tool in "${tools[@]}"; do
  tool_name=$(basename $tool .git)
  echo "[+] Descargando $tool_name..."
  if [ -d "$tool_name" ]; then
    echo "[!] Ya existe el directorio $tool_name, actualizando..."
    cd "$tool_name"
    git pull
    cd ..
  else
    git clone --depth 1 "$tool"
  fi
done

# Instalar AutoRecon
if [ -d "AutoRecon" ]; then
  cd AutoRecon
  pip3 install -r requirements.txt
  cd ..
fi

# Instalar Sherlock
if [ -d "sherlock" ]; then
  cd sherlock
  pip3 install -r requirements.txt
  cd ..
fi

# Instalar Sublist3r
if [ -d "Sublist3r" ]; then
  cd Sublist3r
  pip3 install -r requirements.txt
  cd ..
fi

# Herramientas específicas para análisis forense
echo "[+] Configurando herramientas forenses..."
mkdir -p $TOOLS_DIR/forensics
cd $TOOLS_DIR/forensics

forensic_tools=(
  "https://github.com/volatilityfoundation/volatility.git"
  "https://github.com/sleuthkit/sleuthkit.git"
  "https://github.com/DidierStevens/DidierStevensSuite.git"
)

for tool in "${forensic_tools[@]}"; do
  tool_name=$(basename $tool .git)
  echo "[+] Descargando $tool_name..."
  if [ -d "$tool_name" ]; then
    echo "[!] Ya existe el directorio $tool_name, actualizando..."
    cd "$tool_name"
    git pull
    cd ..
  else
    git clone --depth 1 "$tool"
  fi
done

# Descargar wordlists adicionales
echo "[+] Configurando wordlists adicionales..."
mkdir -p $TOOLS_DIR/wordlists
cd $TOOLS_DIR/wordlists

# Descargar rockyou
if [ ! -f "rockyou.txt" ]; then
  echo "[+] Descargando rockyou.txt..."
  wget https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt
fi

echo "[+] Instalación completada!"
