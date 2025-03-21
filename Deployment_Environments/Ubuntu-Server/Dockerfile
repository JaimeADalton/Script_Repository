FROM ubuntu:24.04

# Evitar interacciones durante la instalación
ENV DEBIAN_FRONTEND=noninteractive

# Configuración para prevenir problemas con pcp y systemd
RUN echo 'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/99norecommends && \
    echo 'APT::Install-Suggests "0";' >> /etc/apt/apt.conf.d/99norecommends && \
    echo 'exit 0' > /usr/sbin/policy-rc.d && \
    chmod +x /usr/sbin/policy-rc.d && \
    echo 'Package: pcp' > /etc/apt/preferences.d/no-pcp && \
    echo 'Pin: release *' >> /etc/apt/preferences.d/no-pcp && \
    echo 'Pin-Priority: -1' >> /etc/apt/preferences.d/no-pcp

# Actualizar sistema base y configurar zona horaria
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y tzdata && \
    ln -fs /usr/share/zoneinfo/Europe/Madrid /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Configurar locale en español de España
RUN apt-get update && apt-get install -y locales && \
    locale-gen es_ES.UTF-8 && \
    update-locale LANG=es_ES.UTF-8 LC_ALL=es_ES.UTF-8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=es_ES.UTF-8
ENV LC_ALL=es_ES.UTF-8
ENV LANGUAGE=es_ES

# Instalar herramientas esenciales del sistema
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    apt-utils \
    bash-completion \
    build-essential \
    ca-certificates \
    cron \
    curl \
    dirmngr \
    dnsutils \
    file \
    gnupg \
    htop \
    iproute2 \
    iputils-ping \
    jq \
    less \
    lsb-release \
    lsof \
    mtr-tiny \
    nano \
    net-tools \
    openssh-server \
    procps \
    rsync \
    software-properties-common \
    sudo \
    tcpdump \
    telnet \
    traceroute \
    tzdata \
    unzip \
    vim \
    wget \
    whois \
    zip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar editores y herramientas de terminal
RUN apt-get update && apt-get install -y \
    emacs-nox \
    git \
    screen \
    tmux \
    tree \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar utilidades de monitoreo y diagnóstico seguras
# (sin usar pcp/dstat, solo paquetes oficiales)
RUN apt-get update && apt-get install -y \
    atop \
    htop \
    iftop \
    iotop \
    ncdu \
    neofetch \
    netcat-openbsd \
    nload \
    pv \
    sysstat \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Intentar instalar glances directamente de los repositorios
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-glances \
    || echo "python3-glances no está disponible, continuando sin él"

# Instalar servicios de red y herramientas de seguridad
RUN apt-get update && apt-get install -y \
    arp-scan \
    dnsmasq \
    fail2ban \
    fping \
    hping3 \
    iptables \
    iptraf-ng \
    masscan \
    ncat \
    ngrep \
    nftables \
    nmap \
    openssl \
    openvpn \
    proxychains4 \
    socat \
    sshpass \
    ssldump \
    sslscan \
    tcpdump \
    ufw \
    wireguard \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar lenguajes de programación y herramientas de desarrollo
RUN apt-get update && apt-get install -y \
    clang \
    gcc \
    g++ \
    gdb \
    make \
    nodejs \
    npm \
    perl \
    python3 \
    python3-dev \
    ruby \
    ruby-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar módulos Python oficiales de Ubuntu
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-numpy \
    python3-pandas \
    python3-requests \
    python3-cryptography \
    python3-psutil \
    python3-flask \
    python3-django \
    python3-matplotlib \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar Go
RUN apt-get update && apt-get install -y golang-go && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar Rust
RUN apt-get update && apt-get install -y rustc cargo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar bases de datos
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    mariadb-server \
    postgresql \
    redis-server \
    sqlite3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar servidores web y proxy
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    haproxy \
    nginx \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar herramientas para contenedores
RUN apt-get update && apt-get install -y --no-install-recommends \
    podman \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar herramientas de cloud y automatización
RUN apt-get update && apt-get install -y --no-install-recommends \
    ansible \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instalar herramientas adicionales en español
RUN apt-get update && apt-get install -y --no-install-recommends \
    aspell-es \
    hunspell-es \
    manpages-es \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Crear un usuario no-root para pruebas con nombre en español
RUN useradd -m -s /bin/bash usuario && \
    echo "usuario:contraseña" | chpasswd && \
    adduser usuario sudo && \
    echo "usuario ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/usuario

# Configurar bash para el usuario
RUN echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /home/usuario/.bashrc && \
    echo 'alias ll="ls -la"' >> /home/usuario/.bashrc && \
    echo 'alias update="sudo apt-get update && sudo apt-get upgrade -y"' >> /home/usuario/.bashrc && \
    echo 'export PATH=$PATH:/home/usuario/.local/bin' >> /home/usuario/.bashrc && \
    chown usuario:usuario /home/usuario/.bashrc

# Configurar SSH
RUN mkdir -p /var/run/sshd && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Crear estructura de directorios para el usuario
RUN mkdir -p /home/usuario/espacio_trabajo /home/usuario/scripts /home/usuario/datos /home/usuario/copias_seguridad && \
    chown -R usuario:usuario /home/usuario

# Configurar los servicios de base de datos para que inicien correctamente
RUN mkdir -p /var/run/postgresql && chown -R postgres:postgres /var/run/postgresql && \
    mkdir -p /var/run/mysqld && chown -R mysql:mysql /var/run/mysqld

# Preparar script de entrada para iniciar servicios correctamente
RUN echo '#!/bin/bash\n\
mkdir -p /var/run/sshd\n\
mkdir -p /var/run/apache2\n\
mkdir -p /var/run/nginx\n\
mkdir -p /var/run/postgresql\n\
mkdir -p /var/run/mysqld\n\
mkdir -p /var/run/redis\n\
chown -R postgres:postgres /var/run/postgresql\n\
chown -R mysql:mysql /var/run/mysqld\n\
\n\
service ssh start\n\
service cron start\n\
\n\
echo "Intentando iniciar Apache..."\n\
service apache2 start || echo "Apache no pudo iniciarse correctamente, pero continuamos"\n\
\n\
echo "Intentando iniciar Nginx..."\n\
service nginx start || echo "Nginx no pudo iniciarse correctamente, pero continuamos"\n\
\n\
echo "Intentando iniciar PostgreSQL..."\n\
service postgresql start || echo "PostgreSQL no pudo iniciarse correctamente, pero continuamos"\n\
\n\
echo "Intentando iniciar MariaDB..."\n\
service mariadb start || echo "MariaDB no pudo iniciarse correctamente, pero continuamos"\n\
\n\
echo "Intentando iniciar Redis..."\n\
service redis-server start || echo "Redis no pudo iniciarse correctamente, pero continuamos"\n\
\n\
echo "========================================================"\n\
echo "    Ubuntu Server 24.04 - Kit de Herramientas Listo     "\n\
echo "========================================================"\n\
echo "SSH: Activo - usuario@localhost -p 2222 (contraseña: contraseña)"\n\
echo "========================================================"\n\
\n\
tail -f /dev/null\n\
' > /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Exponer puertos comunes
EXPOSE 22 80 443 3306 5432 6379 8080

# Directorio de trabajo dentro del contenedor
WORKDIR /home/usuario/espacio_trabajo

ENTRYPOINT ["/entrypoint.sh"]
