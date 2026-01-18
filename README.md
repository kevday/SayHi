# SayHi

**Autenticação facial experimental via terminal para Linux (foco inicial em Alpine)**

SayHi é um projeto pessoal de aprendizado que implementa um sistema rudimentar de autenticação facial usando apenas webcam comum e Rust.

**Status atual:** Pré-alpha / Prova de conceito  
**Objetivo principal:** Estudo e experimentação com visão computacional + autenticação em Linux

**AVISO MUITO IMPORTANTE – NÃO USE EM PRODUÇÃO NEM EM AMBIENTES REAIS**

Este projeto **não oferece segurança mínima** para autenticação.  
Ele foi criado como material de estudo e demonstração de conceitos básicos.

Principais limitações de segurança atuais:
- Sem detecção real de rosto (processa a imagem inteira)
- Sem alinhamento facial (ângulos diferentes = falha)
- Sem detecção de vivacidade/liveness (foto, vídeo ou máscara burlam facilmente)
- Comparação muito simples e suscetível a variações de iluminação
- Templates armazenados em JSON puro (sem criptografia)
- Integração com PAM experimental

**NUNCA** utilize este software como método de autenticação real. 
É mais frágil do que uma senha de 4 dígitos.

## Recursos atuais (o que já funciona... mais ou menos)

- Captura de vídeo da webcam (MJPG/YUYV)
- Criação de "template" facial simples via binarização adaptativa
- Cadastro (enroll) com múltiplas poses/sessões
- Autenticação básica via terminal
- Suporte experimental a PAM (via pam_exec)
- Bloqueio temporário após falhas (rudimentar)
- Teste rápido de câmera

## Instalar dependências de acordo com a distribuição:
   * **Alpine Linux:**  
     ```sh
     doas apk add rust cargo v4l-utils v4l-utils-dev jpeg-dev libpng-dev musl-dev clang llvm make linux-headers linux-pam
     ```
   * **Debian / Ubuntu:**  
     ```sh
     sudo apt update
     sudo apt install -y rustc cargo v4l-utils libjpeg-dev libpng-dev clang llvm make linux-headers-$(uname -r) libpam0g-dev
     ```
   * **Fedora:**  
     ```sh
     sudo dnf install -y rust cargo v4l-utils libjpeg-turbo-devel libpng-devel clang llvm make kernel-devel pam-devel
     ```
   * **Arch / Manjaro:**  
     ```sh
     sudo pacman -Syu --needed rust v4l-utils libjpeg-turbo libpng clang llvm make linux-headers pam
     ```

## Instalação (método atual – manual)

```bash
git clone https://github.com/SEU_USUARIO/sayhi.git
cd sayhi

# Compilar com otimizações para tamanho
cargo build --release

# Instalar (exemplo)
sudo cp target/release/sayhi /usr/local/bin/
sudo chmod +x /usr/local/bin/sayhi
```

## Comandos disponíveis

```bash
sayhi test                    # Testa a câmera e salva imagem de exemplo
sayhi enroll seu_usuario      # Cadastra rosto (3 sessões recomendadas)
sayhi auth [seu_usuario]      # Tenta autenticar (usa PAM_USER se disponível)
```

## Integração experimental com PAM (use com extremo cuidado!)

Faça backup antes de qualquer alteração!

Exemplo básico (apenas terminal/login – NÃO funciona bem com GDM/SDDM):

```bash
# Backup importante!
sudo cp /etc/pam.d/login /etc/pam.d/login.bak-$(date +%F)

# Adicione no início do arquivo /etc/pam.d/login (depois do pam_securetty se existir)
auth       sufficient   pam_exec.so quiet /usr/local/bin/sayhi auth
```

**Observações reais sobre PAM:**
- Ordem importa muito (colocar no início pode quebrar o login)
- Atualmente instável em Alpine + display managers
- Não suporta root (por escolha de segurança)


## Do projeto

"SayHi" existe para aprender:  
Rust + visão computacional + integração low-level com Linux + limitações reais de segurança em biometria.

Se você chegou até aqui:  
Parabéns pela curiosidade!  
Mas por favor, use com consciência — biometria facial sem hardware dedicado e algoritmos modernos é mais teatro do que segurança.

```
