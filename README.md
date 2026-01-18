# SayHi Linux — Autenticação Facial

**Versão:**  Experimental
**Propósito:** Projeto de estudo pessoal; **não recomendado para produção**.  
**Plataformas testadas:** Alpine Linux (primário), compilável em Debian/Ubuntu, Fedora e Arch Linux.  

---

## ⚠ Avisos Importantes

* **Segurança:** Este projeto não fornece nível satisfatório de segurança para ambientes críticos.  
* **Uso:** Apenas para testes, aprendizado e estudo pessoal.  
* Alterações no PAM podem exigir restauração manual.  
* A autenticação do usuário `root` não é suportada.  
* Interface exclusivamente via terminal.  
* Suporte limitado a webcams compatíveis.

---

## Estrutura do Sistema

| Item | Caminho / Descrição |
|------|--------------------|
| Binário principal | `/usr/local/bin/sayhi` |
| Wrapper PAM | `/usr/local/lib/security/pam_sayhi.sh` |
| Dados do usuário | `~/.local/share/sayhilinux/` |
| Logs | `/var/log/sayhi.log` |
| Polkit PAM | `/etc/pam.d/polkit-1` (linha adicionada: `auth sufficient pam_exec.so quiet /usr/local/lib/security/pam_sayhi.sh`) |

---

## Instalação e Pré-requisitos

1. Usuário deve ter permissões administrativas via `doas` ou `sudo`.  
2. Instalar dependências de acordo com a distribuição:
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

3. Compilar o projeto:
   ```sh
   mkdir -p ~/sayhilinux/src
   cd ~/sayhilinux
   cargo build --release
```

4. Instalar binário e configurar wrapper PAM:

   ```sh
   doas cp target/release/sayhi /usr/local/bin/
   doas chmod 755 /usr/local/bin/sayhi
   doas mkdir -p /usr/local/lib/security
   # Criar pam_sayhi.sh conforme exemplo de instalação
   doas chmod 755 /usr/local/lib/security/pam_sayhi.sh
   ```

5. Integrar com Polkit (opcional):

   ```sh
   doas sed -i '/^auth.*pam_env.so/a auth sufficient pam_exec.so quiet /usr/local/lib/security/pam_sayhi.sh' /etc/pam.d/polkit-1
   ```

---

## Testes Básicos

```sh
sayhi test           # Testa webcam
sayhi enroll $USER   # Cadastra rosto
sayhi auth $USER     # Testa autenticação
```

> Substitua `$USER` pelo usuário alvo.

---

## Logs e Armazenamento

* Logs: `/var/log/sayhi.log`
* Dados do usuário: `~/.local/share/sayhilinux/`
* Wrapper PAM: `/usr/local/lib/security/pam_sayhi.sh`

---

**Resumo:**
SayHi Linux é um projeto experimental de autenticação facial via terminal. **Não use em produção.** Ideal para aprendizado sobre PAM, Polkit e integração de autenticação facial em Linux.
