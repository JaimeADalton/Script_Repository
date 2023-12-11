#!/bin/bash

mensaje_reinicio="********************* IMPORTANTE *********************\nReinicio en breve.\n\n$(cat /etc/hostname) se reiniciara pronto para actualizaciones criticas de seguridad.\n******************************************************"
# Enviar el mensaje a todos los usuarios conectados
echo -e "$mensaje_reinicio" | wall
