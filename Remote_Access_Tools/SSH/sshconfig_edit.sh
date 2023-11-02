#!/bin/bash

whoami=$(whoami)
file_name="/home/${whoami}/.ssh/config"
new_key="~/.ssh/access.key"


check_valid_ip () {
  local  ip=$1
  local  stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    OIFS=$IFS
    IFS='.'
    ip=($ip)
    IFS=$OIFS
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
      && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    stat=$?
  fi
  return $stat
}

while true; do
        read -p "Do you want to add (a) or remove (r) a host (default add)? " action
    if [[ $action = "" ]];then 
        action=${action:-a}
        break
    fi
    if [[ $action =~ ^a ]]; then
        action="a"
        break
    elif [[ $action =~ ^r ]]; then
        action="r"
        break
    else
        echo "Invalid input. Please try again."
    fi
done
case "$action" in
  "add"|"a")
    while true; do
        read -e -p "Enter the hostname: " hostname

        if [[ -z "$hostname" ]]; then
            printf "\033[0;91mHostname cannot be empty\033[0m\n"
        elif grep -Fq "Host $hostname" /home/kali/.ssh/config; then
            printf "\033[0;91mHostname already exists in /home/kali/.ssh/config\033[0m\n"
        else
            break
        fi
    done
    host_ip=
    while [[ -z $host_ip ]]; do
        read -e -p "Enter the host IP address: " host_ip
        while ! check_valid_ip $host_ip;do
            read -e -p "WRONG IP: Enter the host IP address: " host_ip
        done
    done

    read -e -p "Enter the user (default: root): " new_user
    new_user=${new_user:-root}
    if [[ $new_user == "root" ]];then
            home=
    else
            home="/home"
    fi
    read -e -p "Bastion as a ProxyJump (default: no): " proxyjump
    proxyjump=${proxyjump:-no}


    echo "Host $hostname" >> $file_name
    echo "        Hostname $host_ip" >> $file_name
    echo "        User $new_user" >> $file_name
    echo "        IdentityFile $new_key" >> $file_name

    valid_options=(yes y ye es s no n o si io )
    if echo "${valid_options[@]}" | grep -wq "$proxyjump"; then
      if [[ "$proxyjump" =~ ^(yes|y|ye|es|s|si|i)$ ]]; then
        echo "        ProxyJump bastion" >> $file_name
      fi
    else
      echo "Unkown input: $proxyjump"
    fi
    connect=
    while [[ -z $connect ]]; do
            read -e -p "Do you want to connect to ${new_user}@${host_ip}? (default: yes):" connect
            connect=${connect:-yes}
    done
    if [[ $connect == "yes" ]] && [[ $proxyjump == "yes" ]];then
        ssh-copy-id -o ProxyJump=bastion -i /home/${whoami}/.ssh/access.key.pub ${new_user}@${host_ip} 2>/dev/null
        ssh -o ProxyJump=bastion -i /home/${whoami}/.ssh/access.key ${new_user}@${host_ip}
    elif [[ $connect == "yes" ]]; then
        ssh-copy-id -i /home/${whoami}/.ssh/access.key.pub ${new_user}@${host_ip} 2>/dev/null
        ssh -i /home/${whoami}/.ssh/access.key ${new_user}@${host_ip}
    fi
    ;;
  "remove"|"r")
    # List all the hosts
    hosts=($(cat $file_name | awk '/^Host/ {print $2}'))
    i=0
    for host in "${hosts[@]}"; do
      i=$((i + 1))
      echo "$i) $host"
    done
    read -e -p "Enter the number of the host you want to remove: " host_number
    while true; do
        if [[ $host_number > $i ]];then
                read -e -p "Enter the number of the host you want to remove: " host_number
        elif [[ $host_number < 0 ]];then
                read -e -p "Enter the number of the host you want to remove: " host_number
        else
                break
        fi
    done            
    host_number=$((host_number - 1))
    host_to_remove=${hosts[host_number]}
    line_number=$(grep -n "Host $host_to_remove" $file_name | head -n 1 | cut -d: -f1)
    sed -i "${line_number},/^Host/ {/^Host/!d};${line_number}d" $file_name
    ;;
  *)
    echo "Invalid action"
    ;;
esac
