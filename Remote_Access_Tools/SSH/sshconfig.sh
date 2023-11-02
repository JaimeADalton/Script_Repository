#!/bin/bash
whoami=$(whoami)
home="/home"
if [[ $whoami == "root" ]];then
   home=
fi

cat ${home}/${whoami}/.ssh/config | awk '/Host/ {print $2}' | awk '{if (NR % 2 == 0) printf "\033[31m%s\033[0m\n", $1; else printf "\033[32m%s\033[0m ", $1;}' | sort | column -t
