#!/bin/bash  
#title          :openldap_configure_wizard.sh
#description    :Crea archivos de configuracion para OpenLDAP de usuarios, grupos y unidades organizativas
#author         :Jaime A. Dalton
#date           :07/11/2019
#version        :1.0    
#usage          :./openldap_configure_wizard.sh
#notes          :
#bash_version   :5.0.3(1)-release
#============================================================================


#Verificamos si el directorio LDAP esta en el HOME del usuario, sino, se crea.
LDAPATH="$HOME/LDAP"
if [ ! -d $HOME/LDAP/ ];then
	mkdir $HOME/LDAP
fi

#Esta funcion crea crea un usuario y lo guarda en un archivo llamado usuario.ldif en el directorio $LDAPTH.
#Procede preguntando los parametros necesarios para rellenar el archivo: uid, cn, sn, ou, dc, uidNumber, gidNumber, password
#(Ej: Nombre completo del usuario: Jaime Dalton; Nombre del dominio: asodalton.org).
#La funcion se encarga de configuar el archivo correctametne
function AddUser {
	read -p "Nombre de usuario (uid): " uid
	read -p "Nombre completo del usuario: " cnsn
	read -p "Nombre Unidad Organizativa: " ou
	read -p "Nombre del dominio: " dc
	read -p "uidNumber: " uidNumber
	read -p "gidNumber: " gidNumber
	read -s -p "Contraseña del usuario: " password
	echo ""
	cn=$(echo $cnsn | cut -d " " -f1)
	sn=$(echo $cnsn | cut -d " " -f2)
        dc1=$(echo $dc | cut -d "." -f1)
        dc2=$(echo $dc | cut -d "." -f2)
	hash_password=$(slappasswd -d $password)
	#hash_password=$(echo $password | md5sum)
	
	cat <<EOF >> ${LDAPATH}/usuario.ldif
dn: uid=$uid,ou=$ou,dc=$dc1,dc=$dc2
objectClass: top 
objectClass: posixAccount
objectClass: inetOrgPerson
objectClass: person
cn: $cn
sn: $sn
uid: $uid
uidNumber: $uidNumber
gidNumber: $gidNumber
homeDirectory: /home/${cn}${sn}
loginShell: /bin/bash
userPassword: $hash_password
givenName: $cn

EOF
echo
echo "Archivo usuario.ldif guardado en $LDAPATH"

}


#Esta funcion crea crea un grupo y lo guarda en un archivo llamado grupos.ldif en el directorio $LDAPTH.
#Procede preguntando los parametros necesarios para rellenar el archivo: cn, ou, dc, gidNumber. La funcion
#se encarga de separar dc entre el nombre del dominio y el dominio (Ej. Nombre de dominio: asodalton.org)
function AddGroup {
	read -p "Nombre del grupo: " cn
        read -p "Unidad Organizativa: " ou
        read -p "Nombre del dominio: " dc
        read -p "ID del grupo: " gidNumber
        dc1=$(echo $dc | cut -d "." -f1)
        dc2=$(echo $dc | cut -d "." -f2)

        cat <<EOF >> ${LDAPATH}/grupos.ldif
dn: cn=$cn,ou=$ou,dc=$dc1,dc=$dc2
objectClass: top
objectClass: posixGroup
gidNumber: $gidNumber
cn: $cn

EOF
echo
echo "Archivo grupos.ldif guardado en $LDAPATH"
}

#Esta funcion crea crea una unidad organizativa y lo guarda en un archivo llamado unidadesorganizativas.ldif
#en el directorio $LDAPTH. Procede igual que la funcion anterior salvo que pregunta los parametros: ou, dc
function AddOU {
        read -p "Unidad Organizativa: " ou
        read -p "Nombre del dominio: " dc
        dc1=$(echo $dc | cut -d "." -f1)
        dc2=$(echo $dc | cut -d "." -f2)

        cat <<EOF >> ${LDAPATH}/unidadesorganizativas.ldif
dn: ou=$ou,dc=$dc1,dc=$dc2
objectClass: top
objectClass: organizationalUnit
ou: $ou

EOF
echo
echo "Archivo unidadesorganizativas.ldif guardado en $LDAPATH"
}

#Obviamente esto es un menu que permite realizar una de las tres tareas tantas veces como se quiera.
#Seguirá en bucle hasta que se le pida salir del programa
while true;do
        echo -e "[1] Crear un Usuario"
        echo -e "[2] Crear un Grupo"
        echo -e "[3] Crear un Unidad Organizativa"
	echo -e "[e] Salir"
        read -p "Elige una opcion: " opcion
        case $opcion in
                1)
			read -p "Numero de usuarios: " n_usuarios
			for (( usuario = 0; usuario <= $n_usuarios; usuario++));do                    
				AddUser
			done
			;;
                2)
			read -p "Numero de grupos: " n_grupos
			for (( grupo = 0; grupo <= $n_grupos; grupo++));do                    
				AddGroup
			done
			;;
                3)
                        read -p "Numero de Unidades Organizativas: " n_uos
			for (( uo = 0; uo <= $n_uos; uo++ ));do                    
				AddOU
			done
			;;
		e|E)
			exit 0;;

                *)
			echo "Opciones 1-3; (e)xit";;
        esac
done
