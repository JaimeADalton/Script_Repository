Para obtener un certificado SSL wildcard para tu dominio registrado en Namecheap, utilizando sus servicios DNS, seguirás un proceso similar al descrito anteriormente, pero con algunas variaciones específicas para Namecheap. Certbot no tiene un plugin específico para Namecheap, por lo que deberás utilizar el método de validación DNS manual. Aquí te explico cómo hacerlo:

1. Instalar Certbot

Primero, asegúrate de que Certbot esté instalado en tu servidor:

```bash
sudo apt update
sudo apt install certbot

```

2. Generar el Certificado Wildcard

Ejecuta Certbot en modo manual para iniciar el proceso de obtención de un certificado wildcard:

```bash
sudo certbot certonly --manual --preferred-challenges=dns -d '*.jaimedalton.online' -d jaimedalton.online

```

Durante el proceso, Certbot te proporcionará un valor de registro TXT que necesitarás agregar a tus registros DNS en Namecheap.

3. Agregar el Registro TXT en Namecheap

1. Inicia sesión en tu cuenta de Namecheap y ve al área de administración de tu dominio.
2. Navega hasta la sección de DNS o Administrador de DNS.
3. Agrega un nuevo registro TXT con los detalles proporcionados por Certbot. Esto generalmente implica:Host: _acme-challenge (o _acme-challenge.jaimedalton.online)Value: [El valor proporcionado por Certbot]TTL: El valor más bajo posible (para una propagación más rápida)
4. Host: _acme-challenge (o _acme-challenge.jaimedalton.online)
5. Value: [El valor proporcionado por Certbot]
6. TTL: El valor más bajo posible (para una propagación más rápida)
7. Guarda los cambios en tu configuración de DNS.

4. Espera a que se Propaguen los Cambios de DNS

La propagación de los cambios en DNS puede tardar desde unos minutos hasta varias horas. Puedes verificar el estado de la propagación utilizando herramientas en línea como [DNSChecker](https://dnschecker.org/).

5. Continúa la Generación del Certificado

Una vez que el registro TXT se haya propagado, regresa a la terminal donde ejecutaste Certbot y continúa el proceso. Certbot verificará automáticamente el registro TXT y, si es correcto, emitirá el certificado.

6. Configuración del Certificado en Nginx

Configura Nginx para usar el nuevo certificado wildcard:

```nginx
ssl_certificate /etc/letsencrypt/live/jaimedalton.online/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/jaimedalton.online/privkey.pem;

```

7. Verifica y Reinicia Nginx

Verifica la configuración de Nginx y reinicia el servicio:

```bash
sudo nginx -t
sudo systemctl restart nginx

```
