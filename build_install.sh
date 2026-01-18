#!/bin/sh
set -e

echo "╔═══════════════════════════════════════════════════╗"
echo "║   Instalação Alpine Face Auth + Integração PAM    ║"
echo "╚═══════════════════════════════════════════════════╝"
echo ""

# Verificar se doas existe
if ! command -v doas >/dev/null 2>&1; then
    echo "❌ ERRO: doas não encontrado!"
    echo "   Instale com: su -c 'apk add doas'"
    exit 1
fi

# Verificar se está rodando como usuário normal
if [ "$(id -u)" = "0" ]; then
    echo "❌ ERRO: Não execute este script como root!"
    echo "   O script pedirá senha quando necessário via doas"
    exit 1
fi

# Instalar dependências
echo "📦 Instalando dependências do sistema..."
doas apk add rust cargo v4l-utils v4l-utils-dev jpeg-dev libpng-dev musl-dev clang llvm make linux-headers linux-pam

# Criar diretório do projeto
echo ""
echo "📁 Criando projeto..."
mkdir -p ~/sayhilinux/src
cd ~/sayhilinux

# Compilar
echo ""
echo "🔨 Compilando..."
cargo build --release

# Verificar se compilou
if [ ! -f "target/release/sayhi" ]; then
    echo "❌ ERRO: Compilação falhou!"
    exit 1
fi

echo "✅ Compilação concluída!"

# Instalar binário
echo ""
echo "📥 Instalando binário..."
doas cp target/release/sayhi /usr/local/bin/
doas chmod +x /usr/local/bin/sayhi

# Criar diretório de dados
doas mkdir -p /var/lib/sayhilinux
doas chmod 1777 /var/lib/sayhilinux

# Criar wrapper PAM
echo ""
echo "🔐 Configurando wrapper PAM..."
doas mkdir -p /usr/local/lib/security

doas tee /usr/local/lib/security/pam_sayhi.sh > /dev/null << 'EOFPAM'
#!/bin/sh
USER="${PAM_USER:-$1}"

# Não permite root ou usuário desconhecido
if [ -z "$USER" ] || [ "$USER" = "root" ]; then
    exit 1
fi

PROFILE_PATH="/var/lib/sayhilinux/$USER.json"
if [ ! -f "$PROFILE_PATH" ]; then
    exit 1
fi

# Timeout de 10 segundos
timeout 10 /usr/local/bin/sayhi auth "$USER" >/dev/null 2>&1
exit $?
EOFPAM

doas chmod +x /usr/local/lib/security/pam_sayhi.sh

# Criar log
echo "📝 Configurando logs..."
doas touch /var/log/face-auth.log
doas chmod 644 /var/log/face-auth.log

# Adicionar usuário ao grupo video
REAL_USER=$(logname 2>/dev/null || echo "$USER")
doas addgroup "$REAL_USER" video 2>/dev/null || true

# Regras udev para webcam
echo "🔧 Configurando regras udev..."
doas tee /etc/udev/rules.d/99-webcam.rules > /dev/null << 'EOFUDEV'
KERNEL=="video[0-9]*", GROUP="video", MODE="0666"
EOFUDEV

doas udevadm control --reload-rules 2>/dev/null || true
doas udevadm trigger 2>/dev/null || true

# Perguntar sobre integração PAM
echo ""
printf "Deseja integrar reconhecimento facial com login do sistema? (s/N): "
read -r resposta

case "$resposta" in
    [Ss]*)
        PAM_FILE=""
        if ps aux | grep -q "[g]dm"; then PAM_FILE="/etc/pam.d/gdm-password"
        elif ps aux | grep -q "[l]ightdm"; then PAM_FILE="/etc/pam.d/lightdm"
        elif ps aux | grep -q "[s]ddm"; then PAM_FILE="/etc/pam.d/sddm"
        elif [ -f "/etc/pam.d/greetd" ]; then PAM_FILE="/etc/pam.d/greetd"; fi

        if [ -z "$PAM_FILE" ]; then
            echo "❌ Nenhum display manager detectado. Configure manualmente:"
            echo "auth optional pam_exec.so quiet /usr/local/lib/security/pam_sayhi.sh"
            exit 0
        fi

        # Backup
        BACKUP="${PAM_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
        doas cp "$PAM_FILE" "$BACKUP"
        echo "Backup criado: $BACKUP"

        # Inserir configuração PAM
        if ! doas grep -q "pam_sayhi.sh" "$PAM_FILE"; then
            doas sed -i '/^auth.*pam_unix.so/i auth     sufficient    pam_exec.so quiet \/usr\/local\/lib\/security\/pam_sayhi.sh' "$PAM_FILE"
            echo "✅ PAM configurado (modo SUFICIENTE)"
        else
            echo "ℹ️ PAM já configurado"
        fi
        ;;
    *)
        echo "   Pulando configuração PAM..."
        ;;
esac

# Final
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Próximos passos:"
echo "1. Testar webcam: sayhi test"
echo "2. Cadastrar rosto: sayhi enroll \$USER"
echo "3. Testar autenticação: sayhi auth \$USER"
echo "4. Testar login do sistema (após backup PAM)"
echo "📂 Dados: /var/lib/sayhilinux/"
echo "📝 Logs: /var/log/face-auth.log"
echo "🔧 Wrapper PAM: /usr/local/lib/security/pam_sayhi.sh"
if [ -n "$PAM_FILE" ]; then echo "🔐 Config PAM: $PAM_FILE"; fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

