FROM kalilinux/kali-rolling

# Avoid interactions during installation
ENV DEBIAN_FRONTEND=noninteractive

# Environment variables
ENV USERNAME=security
ENV PASSWORD=security123

# Update repositories - use only Kali repositories
RUN echo "deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb-src http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    apt-get update && apt-get upgrade -y

# Install essential system tools - split into smaller groups to better handle dependencies
RUN apt-get update && apt-get install -y \
    sudo \
    openssh-server \
    net-tools \
    iputils-ping \
    curl \
    wget \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install editors and terminal utilities
RUN apt-get update && apt-get install -y \
    vim \
    nano \
    htop \
    git \
    tmux \
    screen \
    zsh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install development tools and languages
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-setuptools \
    python3-wheel \
    nodejs \
    npm \
    golang \
    ruby \
    ruby-dev \
    build-essential \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install additional utilities
RUN apt-get update && apt-get install -y \
    zip \
    unzip \
    tcpdump \
    ncat \
    socat \
    netcat-traditional \
    openssl \
    jq \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install system components and configure locale
RUN apt-get update && apt-get install -y \
    locales \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    gnupg \
    software-properties-common \
    cron \
    iproute2 \
    sqlite3 \
    mtr \
    && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install security and analysis tools from repositories
RUN apt-get update && apt-get install -y \
    nmap \
    tshark \
    sqlmap \
    dirb \
    dirbuster \
    nikto \
    hydra \
    john \
    hashcat \
    dnsutils \
    whois \
    traceroute \
    hping3 \
    fping \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install more Kali security tools
RUN apt-get update && apt-get install -y \
    kali-linux-headless \
    metasploit-framework \
    exploitdb \
    webshells \
    hashid \
    crunch \
    cewl \
    wordlists \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install additional Kali tool collections
RUN apt-get update && apt-get install -y \
    kali-tools-fuzzing \
    kali-tools-vulnerability \
    kali-tools-database \
    kali-tools-passwords \
    kali-tools-reverse-engineering \
    kali-tools-sniffing-spoofing \
    kali-tools-forensics \
    kali-tools-reporting \
    kali-tools-information-gathering \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install additional tools
RUN apt-get update && apt-get install -y \
    aircrack-ng \
    kismet \
    wpscan \
    gobuster \
    masscan \
    netdiscover \
    binwalk \
    foremost \
    exiftool \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install reverse engineering and analysis tools
RUN apt-get update && apt-get install -y \
    steghide \
    stegosuite \
    ghidra \
    gdb \
    radare2 \
    lldb \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install networking and web tools
RUN apt-get update && apt-get install -y \
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
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Python tools from Kali repositories
RUN apt-get update && apt-get install -y \
    python3-impacket \
    python3-ldapdomaindump \
    python3-dnspython \
    python3-numpy \
    python3-pandas \
    python3-requests \
    python3-bs4 \
    python3-scapy \
    python3-pwntools \
    pipx \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create virtual environment for additional Python tools
RUN mkdir -p /opt/venvs && \
    python3 -m venv /opt/venvs/security && \
    /opt/venvs/security/bin/pip install --upgrade pip setuptools wheel

# Install popular tools from GitHub (without pip installation)
RUN mkdir -p /opt/tools && \
    cd /opt/tools && \
    git clone --depth 1 https://github.com/swisskyrepo/PayloadsAllTheThings.git && \
    # PEASS-ng (privilege escalation tools)
    git clone --depth 1 https://github.com/carlospolop/PEASS-ng.git && \
    # dirsearch (web enumeration)
    git clone --depth 1 https://github.com/maurosoria/dirsearch.git && \
    chmod +x /opt/tools/dirsearch/dirsearch.py && \
    ln -sf /opt/tools/dirsearch/dirsearch.py /usr/local/bin/dirsearch

# Configure paths for tools installed with pipx
RUN mkdir -p /root/.local/bin && \
    echo 'export PATH="/root/.local/bin:$PATH"' >> /root/.zshrc && \
    echo 'export PATH="/root/.local/bin:$PATH"' >> /root/.bashrc

# Install Oh My Zsh for a better shell
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Configure SSH
RUN mkdir -p /var/run/sshd
RUN echo 'root:kali' | chpasswd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Create non-root user
RUN useradd -m ${USERNAME} -s /bin/zsh && echo "${USERNAME}:${PASSWORD}" | chpasswd
RUN usermod -aG sudo ${USERNAME}
RUN echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Create work directories
RUN mkdir -p /home/${USERNAME}/workspace /home/${USERNAME}/tools /home/${USERNAME}/scripts /home/${USERNAME}/reports /home/${USERNAME}/data
RUN chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}

# Add virtual environment activation and paths for the user
RUN echo 'export PATH="/opt/venvs/security/bin:$PATH"' >> /home/${USERNAME}/.zshrc && \
    echo 'export PATH="/opt/venvs/security/bin:$PATH"' >> /home/${USERNAME}/.bashrc && \
    echo 'export PATH="/home/${USERNAME}/.local/bin:$PATH"' >> /home/${USERNAME}/.zshrc && \
    echo 'export PATH="/home/${USERNAME}/.local/bin:$PATH"' >> /home/${USERNAME}/.bashrc

# Configure symbolic links for pipx tools
RUN mkdir -p /home/${USERNAME}/.local/bin && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.local && \
    ln -sf /root/.local/bin/crackmapexec /usr/local/bin/ || echo "crackmapexec not available" && \
    ln -sf /root/.local/bin/bloodhound-python /usr/local/bin/ || echo "bloodhound-python not available"

# Configure work directory
WORKDIR /home/${USERNAME}/workspace

# Add useful scripts
COPY ./scripts/ /home/${USERNAME}/scripts/
RUN chmod +x /home/${USERNAME}/scripts/*.sh
RUN chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/scripts

# Expose common ports
EXPOSE 22 80 443 8080 4444 5555

# Startup script
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
