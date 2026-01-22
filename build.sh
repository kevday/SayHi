#!/bin/sh
# -----------------------------------------------------------------------------
# SayHi Linux - Script de construção multiplataforma
# -----------------------------------------------------------------------------
# Este script detecta a distribuição Linux, instala dependências e compila SayHi.
# Suporta: Alpine, Debian/Ubuntu, Fedora, Arch/Manjaro.
# -----------------------------------------------------------------------------
set -e

echo "Iniciando instalação e compilação do SayHi Linux..."

# --------------------------------------------------------------------------
# Verificação de pré-requisitos
# --------------------------------------------------------------------------
# Usa doas ou sudo para elevação de privilégios
if command -v doas >/dev/null 2>&1; then
    ELEV="doas"
elif command -v sudo >/dev/null 2>&1; then
    ELEV="sudo"
else
    echo "ERRO: Nenhum método de elevação de privilégios encontrado (doas ou sudo)."
    exit 1
fi

# Checa usuário não-root
if [ "$(id -u)" = "0" ]; then
    echo "ERRO: Execute este script como usuário normal, não root."
    exit 1
fi

# --------------------------------------------------------------------------
# Detectar distribuição
# --------------------------------------------------------------------------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "ERRO: Não foi possível detectar a distribuição Linux."
    exit 1
fi

echo "Distribuição detectada: $DISTRO"

# --------------------------------------------------------------------------
# Instalação de dependências
# --------------------------------------------------------------------------
install_deps_alpine() {
    $ELEV apk add rust cargo v4l-utils v4l-utils-dev jpeg-dev libpng-dev musl-dev clang llvm make linux-headers linux-pam
}

install_deps_debian() {
    $ELEV apt update
    $ELEV apt install -y rustc cargo v4l-utils libjpeg-dev libpng-dev clang llvm make linux-headers-$(uname -r) libpam0g-dev
}

install_deps_fedora() {
    $ELEV dnf install -y rust cargo v4l-utils libjpeg-turbo-devel libpng-devel clang llvm make kernel-devel pam-devel
}

install_deps_arch() {
    $ELEV pacman -Syu --needed rust v4l-utils libjpeg-turbo libpng clang llvm make linux-headers pam
}

echo "Instalando dependências..."
case "$DISTRO" in
    alpine)
        install_deps_alpine
        ;;
    debian|ubuntu)
        install_deps_debian
        ;;
    fedora)
        install_deps_fedora
        ;;
    arch|manjaro)
        install_deps_arch
        ;;
    *)
        echo "ERRO: Distribuição não suportada pelo script."
        exit 1
        ;;
esac

# --------------------------------------------------------------------------
# Preparação do projeto e compilação
# --------------------------------------------------------------------------
echo "Criando diretório do projeto em ~/SayHi/src..."
mkdir -p ~/SayHi/src
cd ~/SayHi

echo "Compilando o binário SayHi..."
cargo build --release

if [ ! -f "target/release/sayhi" ]; then
    echo "ERRO: Falha na compilação do binário SayHi."
    exit 1
fi

echo "Compilação concluída com sucesso."

# --------------------------------------------------------------------------
# Opção de cadastrar rosto após compilação
# --------------------------------------------------------------------------
if [ -f "target/release/sayhi" ]; then
    echo ""
    printf "Deseja cadastrar seu rosto agora para autenticação facial? (s/N): "
    read -r resposta
    case "$resposta" in
        [Ss]*)
            echo "Iniciando cadastro facial para o usuário $USER..."
            ./target/release/sayhi enroll "$USER"
            ;;
        *)
            echo "Cadastro facial pulado. Você pode executá-lo manualmente com:"
            echo "  ./target/release/sayhi enroll \$USER"
            ;;
    esac
fi


# --------------------------------------------------------------------------
# Finalização e instruções
# --------------------------------------------------------------------------
echo ""
echo "Instalação e compilação concluídas."
echo "Próximos passos recomendados:"
echo "1. Testar webcam: sayhi test"
echo "2. Cadastrar rosto: sayhi enroll \$USER"
echo "3. Testar autenticação facial: sayhi auth \$USER"
echo "4. Testar integração com Polkit"
echo "Local dos dados do usuário: ~/.local/share/sayhilinux/"
echo "Arquivo de logs: /var/log/face-auth.log"
echo "Wrapper PAM: /usr/local/lib/security/pam_sayhi.sh"
