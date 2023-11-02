#!/bin/bash
GREEN="\033[32m"
RED="\033[31m"
NC="\033[0m"
HOST=$(hostname -I | cut -d " " -f 1)
DATE=$(date +%F_%H:%M:%S)
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
MY_PWD="/tmp/$(date +%s)_my.cnf"

function logo {
clear
echo -e "${BOLD} ooo        ooooo oooooo   oooo  .oooooo..o   .oooooo.      ooooo        ${NORMAL} " 
echo -e "${BOLD}  88.       .888    888.   .8   d8P      Y8  d8P    Y8b      888         ${NORMAL} "
echo -e "${BOLD}  888b     d 888     888. .8    Y88bo.      888      888     888         ${NORMAL} " 
echo -e "${BOLD}  8 Y88. .P  888      888.8       'Y8888o.  888      888     888         ${NORMAL} " 
echo -e "${BOLD}  8   888    888       888           ''Y88b 888      888     888         ${NORMAL} " 
echo -e "${BOLD}  8    Y     888       888      oo     .d8P  88b    d88b     888       o ${NORMAL} " 
echo -e "${BOLD} o8o        o888o     o888o     88888888P     Y8bood8P Ybd  o888ooooood8 ${NORMAL} " 
echo -e "${BOLD}                                                                         ${NORMAL} " 
echo -e "${BOLD}                                                                         ${NORMAL} " 
echo -e "${BOLD}                                                                         ${NORMAL} " 
echo -e "${BOLD}        oooooooooo.   ooooo     ooo ooo        ooooo ooooooooo.          ${NORMAL} " 
echo -e "${BOLD}         888     Y8b   888       8   88.       .888   888    Y88.        ${NORMAL} " 
echo -e "${BOLD}         888      888  888       8   888b     d 888   888   .d88         ${NORMAL} " 
echo -e "${BOLD}         888      888  888       8   8 Y88. .P  888   888ooo88P          ${NORMAL} " 
echo -e "${BOLD}         888      888  888       8   8   888    888   888                ${NORMAL} " 
echo -e "${BOLD}         888     d88    88.    .8    8    Y     888   888                ${NORMAL} " 
echo -e "${BOLD}        o888bood8P        YbodP     o8o        o888o o888o               ${NORMAL} " 
echo ""
echo "                                            Made By: Jaime A. Dalton"
echo "                                            Year: 2019              "
echo ""
echo ""
echo ""
echo ""

}

logo

function StartMySQL {
    echo -e -n "${GREEN}[?]${NC} ¿Desea iniciar el servicio mysql? (Y/n): "
    read iniciar
    case $iniciar in
        y|Y|"")
            sudo service mysql start;;
        n|N)
            exit;;
        *)
            echo -e "${RED}[!] NO EXISTE ESA OPCION, VUELVE A INTENTARLO...${NC}\n"
            StartMySQL
            ;;
    esac
}

function MySQLStatus {
    if [ ! "$(service mysql status | grep -o running)" == "running" ];then 
        echo -e "${RED} EL SERVICIO MYSQL ESTA PARADO. PARA PROCEDER DEBE INICIAR EL SERVICIO.${NC}"
        StartMySQL
    fi
}


function Login {
    read -p "Usuario de MySQL: " MYSQLUSER
    mysql_config_editor set --login-path=$MY_PWD --host=localhost --user=$MYSQLUSER --password
    USERNAME=$(mysql --login-path=$MY_PWD -e "SELECT user FROM mysql.user WHERE user='${MYSQLUSER}'" -s --skip-column-names)
    if [ "$USERNAME" == $MYSQLUSER ];then
        echo ""
        echo ""
        echo -e "${GREEN}|-------------------------------------------|${NC}"
        echo -e "${GREEN} HAS INICIADO SESION COMO${NC} ${BOLD}${RED}$MYSQLUSER${NC}${NORMAL}"
        echo -e "${GREEN}|-------------------------------------------|${NC}"
        echo ""
        Log LOGIN
    else
        echo -e "${RED}[!] USUARIO O CONTRASEÑA INCORRECTA${NC}\n"
        Log FAILLOGIN
        Login
    fi
}

function CheckPath {
    read -p "[*] Ruta para el guardado del Backup: " HOMEPATH
    if [ ! -d "$HOMEPATH" ];then 
        echo -e "${RED}[!] LA RUTA NO EXISTE${NC}"
        echo -e -n "${GREEN}[?]${NC} ¿Desea crear la ruta indicada? (Y/n): " 
        read option
        case $option in
            y|Y|"")
                mkdir -p -v $HOMEPATH
                ;;
            n|N)
                CheckPath
                ;;
            *)
                echo -e "${RED}[!] NO EXISTE ESA OPCION, VUELVE A INTENTARLO...${NC}\n"
                CheckPath
                ;;
        esac
    fi
}

function DoCompress {
    echo -e -n "${GREEN}[?]${NC} ¿Desea comprimir el Backup? (Y/n): "
    read option
    case $option in
        y|Y|"")
            tar -czf $1.tar.gz $1
            rm -f $1
            ;;
        n|N)
            ;;
        *)
            echo -e "${RED}[!] NO EXISTE ESA OPCION, VUELVE A INTENTARLO...${NC}\n"
            DoCompress
            ;;
    esac
            
}

function ShowDB {
    mysql --login-path=local -e "SHOW DATABASES;"
}

function DBName {
    read -p "[*] Escribe el nombre exacto de la base de datos: " database
}

function Log {
    case $1 in
        LOGIN) echo "$(date +%F:%H:%M:%S) [LOGIN] Inicio de sesion de '$MYSQLUSER'@'$HOST'" >> $HOME/DumpMySQL.log;;
        FAILLOGIN) echo "$(date +%F:%H:%M:%S) [WARNING] Intento de Inicio de sesion de '$MYSQLUSER'@'$HOST'" >> $HOME/DumpMySQL.log;;
        START) echo "$(date +%F:%H:%M:%S) [START] Inicio copia seguridad" >> $HOME/DumpMySQL.log;;
        COMPLETE) echo "$(date +%F:%H:%M:%S) [COMPLETE] Copia seguridad completada de '$2' en el directorio '${HOMEPATH}'" >> $HOME/DumpMySQL.log;;
        ERROR) echo "$(date +%F:%H:%M:%S) [ERROR] Copia de seguridad no realizada de '$2'" >> $HOME/DumpMySQL.log;;
        UNKOWN) echo "$(date +%F:%H:%M:%S) [MISSING] Base de Datos '$2' no existe o no tiene permisos para realizar una copia de seguridad" >> $HOME/DumpMySQL.log;;
        END) echo "$(date +%F:%H:%M:%S)  [END] Fin copia seguridad" >> $HOME/DumpMySQL.log;;
    esac
}

function Menu {
    if [[ "$1" =~ ^[0-9]+$ ]];then
        opcion=$1
    else
        echo -e "${GREEN}[1]${NC} Realizar una copia de seguridad de una base de datos cualquiera."
        echo -e "${GREEN}[2]${NC} Realizar una copia de seguridad de todas las bases de datos existentes en un solo archivo."
        echo -e "${GREEN}[3]${NC} Realizar una copia de seguridad de todas las bases de datos existentes en archivos independientes."
        echo -e "${GREEN}[4]${NC} Mostrar todas las base de datos."
        echo -e "${GREEN}[E]${NC} Salir."
        echo ""
        echo -e -n "${GREEN}[?]${NC} Elige una opción: "
        read opcion
        if [[ "$opcion" =~ ^[1-3]+$ ]];then
            echo -e "${GREEN}[-] REALIZANDO COPIA DE SEGURIDAD${NC}"
            CheckPath
        fi
    fi
    FILENAME="${database}_${DATE}_${HOST}"
    case $opcion in 
        1)
            if [ -w ${HOMEPATH} ];then
                Log START
                DBName
                FILENAME="${database}_${DATE}_${HOST}"
                mysqldump  --login-path=$MY_PWD $database 1> ${HOMEPATH}/$FILENAME.sql 2> /tmp/error.txt
                if [[ "$?" -eq 0 ]];then
                    DoCompress ${HOMEPATH}/$FILENAME.sql
                    Log COMPLETE ${database}
                    echo -e "${GREEN}[-] COPIA DE SEGURIDAD COMPLETADA${NC}"
                    Log END
                    exit
                else
                    Log ERROR ${database}
                    echo -e "${RED}[!] COPIA DE SEGURIDAD FALLIDA${NC}"
                    if [[ "$(grep -o 'Unknown database' /tmp/error.txt)" == "Unknown database" ]];then
                        echo -e "${RED}[!] UNKNOWN DATABASE ${BOLD}${database}${NORMAL}${NC}\n"
                        Log UNKOWN ${database}
                        Log END
                        rm -f ${HOMEPATH}/$FILENAME.sql
                        Menu 1
                    fi
                    Log END
                fi
            else
                echo -e "${RED}[!] NO TIENES PERMISOS DE ESCRITURA EN ESTE DIRECTORIO.${NC}\n"
                CheckPath
                Menu 1
            fi
            ;;
        2)
            if [ -w ${HOMEPATH} ];then
                Log START 
                mysqldump --login-path=$MY_PWD --all-databases > ${HOMEPATH}/all-databases${FILENAME}.sql
                if [[ "$?" -eq 0 ]];then
                    DoCompress ${HOMEPATH}/all-databases${FILENAME}.sql
                    Log COMPLETE all-databases
                    echo -e "${GREEN}[-] COPIA DE SEGURIDAD COMPLETADA${NC}"
                else
                    Log ERROR all-databases
                    echo -e "${RED}[!] COPIA DE SEGURIDAD FALLIDA${NC}"
                fi
            else
                echo -e "${RED}[!] NO TIENES PERMISOS DE ESCRITURA EN ESTE DIRECTORIO.${NC}\n"
                CheckPath
                Menu 2
            fi
            Log END
            ;;
        3)
            if [ -w ${HOMEPATH} ];then
                Log START
                databases=$(mysql --login-path=$MY_PWD -e  "show databases"  -s --skip-column-names)
                for db in $databases; do
                    echo "[-] Realizando backup: $db"
                    if [[ "$db" != "information_schema" ]] && [[ "$db" != "performance_schema" ]] && [[ "$db" != "mysql" ]] && [[ "$db" != _* ]]; then
                        mysqldump --login-path=$MY_PWD --databases $db > ${HOMEPATH}/$db$FILENAME.sql
                        if [[ "$?" -eq 0 ]];then
                            DoCompress ${HOMEPATH}/${db}${FILENAME}.sql
                            Log COMPLETE $db
                            echo -e "${GREEN}[-] COPIA DE SEGURIDAD COMPLETADA${NC}"
                        fi
                    else
                        Log ERROR $db
                        echo -e "${RED}[!] COPIA DE SEGURIDAD FALLIDA${NC}"
                    fi
                done  
            else
                echo -e "${RED}[!] NO TIENES PERMISOS DE ESCRITURA EN ESTE DIRECTORIO.${NC}\n"
                CheckPath
                Menu 3
            fi
            Log END
            ;;

        4)
            ShowDB
            echo -e "\n"
            Menu
            ;;
        e|E)
            Log END
            ;;
        *)
            echo -e "${RED}[!] NO EXISTE ESA OPCION, VUELVE A INTENTARLO...${NC}\n"
            Menu
            ;;
    esac
    rm -f /tmp/error.txt
    rm -f $MY_PWD
}

MySQLStatus
Login
Menu
