#!/bin/sh
# -----------------------------------------------------------------------------
# SayHi Linux Face Auth - Script de Instalação
# -----------------------------------------------------------------------------
# Este script realiza a instalação do binário SayHi, configura o wrapper PAM
# e integra a autenticação facial ao Polkit.
# Estrutura final:
# - /usr/local/bin/sayhi      -> binário principal
# - /usr/local/lib/security/pam_sayhi.sh -> wrapper PAM
# - /etc/pam.d/polkit-1       -> arquivo PAM modificado
# -----------------------------------------------------------------------------
set -e

echo "Iniciando instalação do SayHi Linux ..."

# --------------------------------------------------------------------------
# Verificação de pré-requisitos
# --------------------------------------------------------------------------
if ! command -v doas >/dev/null 2>&1; then
    echo "ERRO: 'doas' não encontrado. Instale com: su -c 'apk add doas'"
    exit 1
fi

if [ "$(id -u)" = "0" ]; then
    echo "ERRO: Execute este script como usuário normal."
    exit 1
fi

# --------------------------------------------------------------------------
# Instalação do binário
# --------------------------------------------------------------------------
echo "Instalando binário SayHi em /usr/local/bin..."
doas cp target/release/sayhi /usr/local/bin/
doas chmod 755 /usr/local/bin/sayhi
doas chmod +x /usr/local/bin/sayhi

# --------------------------------------------------------------------------
# Configuração do wrapper PAM
# --------------------------------------------------------------------------
echo "Configurando wrapper PAM..."
doas mkdir -p /usr/local/lib/security

doas tee /usr/local/lib/security/pam_sayhi.sh > /dev/null << 'EOF'
#!/bin/sh
# pam_sayhi.sh - Wrapper PAM para SayHi Linux Face Auth
USER="${PAM_USER:-$1}"

# Não permite root ou usuário desconhecido
if [ -z "$USER" ] || [ "$USER" = "root" ]; then
    exit 1
fi

DATA_DIR="/home/$USER/.local/share/sayhilinux"
mkdir -p "$DATA_DIR" 2>/dev/null

PROFILE_PATH="$DATA_DIR/$USER.json"
if [ ! -f "$PROFILE_PATH" ]; then
    exit 1
fi

# Timeout de 10 segundos para evitar travamentos
timeout 10 /usr/local/bin/sayhi auth "$USER" >/dev/null 2>&1
exit $?
EOF

doas chmod 755 /usr/local/lib/security/pam_sayhi.sh

# --------------------------------------------------------------------------
# Configuração de logs
# --------------------------------------------------------------------------
echo "Configurando logs em /var/log/sayhi.log..."
doas touch /var/log/sayhi.log
doas chmod 644 /var/log/sayhi.log

# --------------------------------------------------------------------------
# Adicionar usuário ao grupo 'video'
# --------------------------------------------------------------------------
REAL_USER=$(logname 2>/dev/null || echo "$USER")
doas addgroup "$REAL_USER" video 2>/dev/null || true

# --------------------------------------------------------------------------
# Configuração de regras udev para webcam
# --------------------------------------------------------------------------
echo "Configurando regras udev para acesso à webcam..."
doas tee /etc/udev/rules.d/99-webcam.rules > /dev/null << 'EOFUDEV'
KERNEL=="video[0-9]*", GROUP="video", MODE="0666"
EOFUDEV

doas udevadm control --reload-rules 2>/dev/null || true
doas udevadm trigger 2>/dev/null || true

# --------------------------------------------------------------------------
# Integração com Polkit
# --------------------------------------------------------------------------
echo "Integrando autenticação facial com Polkit..."
POLKIT_FILE="/etc/pam.d/polkit-1"

if ! doas grep -q "pam_sayhi.sh" "$POLKIT_FILE"; then
    BACKUP="${POLKIT_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
    doas cp "$POLKIT_FILE" "$BACKUP"
    echo "Backup do Polkit criado: $BACKUP"

    doas sed -i '/^auth.*pam_env.so/a auth sufficient pam_exec.so quiet /usr/local/lib/security/pam_sayhi.sh' "$POLKIT_FILE"
    echo "Linha PAM adicionada com sucesso."
else
    echo "Linha PAM já existente no Polkit."
fi

# --------------------------------------------------------------------------
# Opção de cadastrar rosto após instalação
# --------------------------------------------------------------------------
if [ -f "/usr/local/bin/sayhi" ]; then
    echo ""
    printf "Deseja cadastrar seu rosto agora para autenticação facial? (s/N): "
    read -r resposta
    case "$resposta" in
        [Ss]*)
            echo "Iniciando cadastro facial para o usuário $USER..."
            /usr/local/bin/sayhi enroll "$USER"
            ;;
        *)
            echo "Cadastro facial pulado. Você pode executá-lo manualmente com:"
            echo "  /usr/local/bin/sayhi enroll \$USER"
            ;;
    esac
fi

# --------------------------------------------------------------------------
# Finalização
# --------------------------------------------------------------------------
echo "Instalação concluída."
echo "Próximos passos recomendados:"
echo "1. Testar webcam: sayhi test"
echo "2. Cadastrar rosto: sayhi enroll \$USER"
echo "3. Testar autenticação facial: sayhi auth \$USER"
echo "4. Testar integração com Polkit"
echo "Local dos dados do usuário: ~/.local/share/sayhilinux/"
echo "Arquivo de logs: /var/log/face-auth.log"
echo "Wrapper PAM: /usr/local/lib/security/pam_sayhi.sh"
echo "Arquivo Polkit: $POLKIT_FILE"

