FROM kalilinux/kali-rolling

# Evitar interacciones durante la instalación
ENV DEBIAN_FRONTEND=noninteractive

# Variables de entorno
ENV USERNAME=security
ENV PASSWORD=security123

# Actualizar repositorios
RUN apt-get update && apt-get upgrade -y

# Instalar herramientas esenciales y de sistema
RUN apt-get install -y \
    sudo \
    openssh-server \
    net-tools \
    iputils-ping \
    curl \
    wget \
    vim \
    nano \
    htop \
    git \
    tmux \
    screen \
    zsh \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    golang \
    ruby \
    ruby-dev \
    build-essential \
    zip \
    unzip \
    tcpdump \
    ncat \
    socat \
    netcat-traditional \
    openssl \
    jq \
    locales \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    gnupg \
    software-properties-common \
    cron \
    iproute2 \
    sqlite3

# Configurar locale
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Instalar herramientas de seguridad y análisis
RUN apt-get install -y \
    nmap \
    wireshark-cli \
    tshark \
    metasploit-framework \
    sqlmap \
    dirb \
    dirbuster \
    nikto \
    hydra \
    john \
    hashcat \
    aircrack-ng \
    kismet \
    wpscan \
    gobuster \
    masscan \
    dnsutils \
    whois \
    traceroute \
    hping3 \
    fping \
    netdiscover \
    exploitdb \
    webshells \
    set \
    maltego \
    responder \
    mimikatz \
    hashid \
    crunch \
    cewl \
    wordlists \
    binwalk \
    foremost \
    exiftool \
    steghide \
    stegosuite \
    volatility3 \
    ghidra \
    gdb \
    radare2 \
    lldb \
    tcpflow \
    scapy \
    ngrep \
    fcrackzip \
    ssh-audit \
    sslscan \
    testssl.sh \
    ffuf \
    figlet \
    lolcat \
    proxychains4 \
    tor \
    torbrowser-launcher

# Instalar herramientas adicionales desde pip
RUN pip3 install --upgrade pip && \
    pip3 install \
    pwntools \
    requests \
    beautifulsoup4 \
    ldapdomaindump \
    impacket \
    crackmapexec \
    bloodhound \
    dnsrecon \
    fierce \
    dnspython \
    ipython \
    jupyter \
    matplotlib \
    numpy \
    pandas \
    pyinstaller

# Instalar Oh My Zsh para un mejor shell
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Instalar Docker CLI dentro del contenedor (solo el cliente, no el daemon)
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - && \
    echo "deb [arch=amd64] https://download.docker.com/linux/debian bullseye stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y docker-ce-cli docker-compose-plugin

# Instalar BurpSuite Community Edition
RUN curl -L "https://portswigger.net/burp/releases/download?product=community&version=latest&type=jar" -o /opt/burpsuite_community.jar && \
    echo "java -jar /opt/burpsuite_community.jar" > /usr/local/bin/burpsuite && \
    chmod +x /usr/local/bin/burpsuite

# Configurar SSH
RUN mkdir -p /var/run/sshd
RUN echo 'root:kali' | chpasswd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Crear usuario no-root
RUN useradd -m ${USERNAME} -s /bin/zsh && echo "${USERNAME}:${PASSWORD}" | chpasswd
RUN usermod -aG sudo ${USERNAME}
RUN echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Crear directorios de trabajo
RUN mkdir -p /home/${USERNAME}/workspace /home/${USERNAME}/tools /home/${USERNAME}/scripts /home/${USERNAME}/reports /home/${USERNAME}/data
RUN chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}

# Configurar directorio de trabajo
WORKDIR /home/${USERNAME}/workspace

# Añadir scripts útiles
COPY ./scripts/ /home/${USERNAME}/scripts/
RUN chmod +x /home/${USERNAME}/scripts/*.sh
RUN chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/scripts

# Exponer puertos comunes
EXPOSE 22 80 443 8080 4444 5555

# Script de inicio
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
