#!/bin/sh
# pam-face-auth.sh - Wrapper PAM para SayHi Linux Face Auth
# Coloque em: /usr/local/lib/security/pam_sayhi.sh
# Deve ter permissão: chmod +x

# Detecta o usuário
USER="${PAM_USER:-$1}"

# Não permite root ou usuário desconhecido
if [ -z "$USER" ] || [ "$USER" = "root" ]; then
    exit 1
fi

# Perfil facial do usuário
PROFILE_PATH="/home/$USER/.local/share/sayhilinux/$USER.json"
if [ ! -f "$PROFILE_PATH" ]; then
    exit 1
fi

# Timeout de 10 segundos para evitar travamentos
# Usa sayhi auth <user>
timeout 10 /usr/local/bin/sayhi auth "$USER" >/dev/null 2>&1
EXIT_CODE=$?

# Retorna código para PAM
# 0 = sucesso, qualquer outro = falha
exit $EXIT_CODE
