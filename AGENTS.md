# AGENTS.md — Galaxy Book4 Ultra (NP960XGL) no CachyOS

Notas da investigação de 2026-10-05 sobre as teclas Fn e os eventos ACPI do
`samsung-galaxybook`. Escrito para o próximo agente (ou pessoa) não refazer o
trabalho. Itens marcados **[hipótese]** não foram confirmados.

## Regras de trabalho com este usuário

- **Analisar primeiro. Não modificar nada sem aprovação ANTES.** O usuário
  interrompeu uma sessão em que eu compilei e carreguei módulos sem ele ter
  pedido código. Tudo que foi criado teve de ser desfeito.
- Não escrever código quando o pedido é de análise.
- Idioma: português do Brasil.
- Ações públicas (fork, push, PR) só com confirmação explícita.
- `sudo` neste notebook pede a **digital** no terminal; o agente não roda `sudo`.
  O usuário roda os comandos e o agente lê o resultado pelo terminal ou pelos logs.

## Máquina

| Item | Valor |
|---|---|
| Modelo | Samsung Galaxy Book4 Ultra 16" — `NP960XGL-YG1BR`, board `P10ALX` |
| BIOS | `P10ALX.470.260413.05` (13/04/2026) |
| SO / kernel | CachyOS, `7.2.9-1-cachyos` (compilado com **clang**; módulos externos exigem `make LLVM=1`) |
| Plataforma | Meteor Lake (Core Ultra), IPU6, ALC298 + 4x MAX98390 |
| Dispositivo ACPI das teclas | `SAM0430:00` (`\_SB.SCAI`) |
| Parecido com Book5, **não igual**: o fork do driver foi escrito para o Book5 Pro |

O DSDT do repo `joshuagrisham/samsung-galaxybook-extras` **não serve**: o
firmware foi atualizado depois daquele dump.

## O que está instalado (relevante)

DKMS (`dkms status`): `samsung-galaxybook-book5pro/1.0`, `max98390-hda/1.0`,
`ov02c10/1.0`, `ipu-bridge-fix/1.4`, `vboxhost`.

### Driver `samsung-galaxybook-book5pro` (o importante)

- É um **fork do driver do kernel**, gerado pelo `lib/fnkeys-fix/install.sh` do
  repo `samsung-galaxy-book-linux-fixes-FPRINTD` (branch `galaxybook5-fixes`,
  commit `05008e5` de David Bartlett, 26/03). O script baixa
  `samsung-galaxybook.c` do kernel stable e aplica um patch em Python.
- Fonte em `/usr/src/samsung-galaxybook-book5pro-1.0/` e
  `/var/lib/dkms/samsung-galaxybook-book5pro/1.0/source/`. O `.ko` instalado
  fica em `/lib/modules/$(uname -r)/updates/dkms/` e **sobrepõe** o do kernel.
- Carregado no boot por `/etc/modules-load.d/samsung-galaxybook.conf`.
- Acrescenta ao driver do kernel: input "Samsung Galaxy Book Hotkeys", tecla
  Settings (`0x7c`), códigos de release (`0x7f`, `0xff`), máquina de estados do
  **F4** (Super+P via i8042 → `KEY_SWITCHVIDEOMODE`) e a tecla **Copilot** do Book5.
- Serviço `samsung-galaxybook-fkeys-monitor.service` detecta quando o kernel
  absorve o patch (grava `/var/lib/samsung-galaxybook/fkeys-kernel.ver`).

Outros módulos do repo FPRINTD: `fingerprint-fix` (marcador de 18/08 em
`/etc/samsung-galaxybook-libfprint-sdcp-v2.installed`; `libfprint.sha256`
**ausente**, então o monitor não faz nada; o `fprintd` funciona com o libfprint
do CachyOS 1.94.100, sensor `1c7a:05a1`), `kdeosd-fix` (instalado, marcador de
22/04). Sem sinal de `fanspeed-fix` nem de `webcam-toggle`.

## Mapa das teclas (verificado com `evtest` + `journalctl -k`)

| Tecla | Função | Como chega | Status |
|---|---|---|---|
| Fn+Esc | Suporte Samsung (ícone de headset) | ACPI `0x41` | **sem handler** |
| F1 | ? | `KEY_PROG1`, scan `0xce`, teclado comum (ev2) | ok (kernel) |
| F2 / F3 | Brilho da tela | Video Bus | ok |
| F4 | Troca de tela | scancodes Super+P → filtro i8042 do fork → `KEY_SWITCHVIDEOMODE` (ev8) | ok |
| F5 | Touchpad | scan `0x76`, `KEY_TOUCHPAD_TOGGLE` (+Ctrl+Meta) | ok |
| F6 / F7 / F8 | Mudo, vol −, vol + | scancodes comuns | ok |
| F9 | Backlight do teclado | scancode consumido pelo filtro i8042 (silencioso no evtest) | ok |
| F10 | Bloqueio da câmera | scancode consumido pelo filtro i8042 → `block_recording` | ok |
| F11 | Perfil de energia | ACPI `0x70` → `platform_profile_cycle()` | ok |
| F12 | Fn Lock | scan `0xa8`, `KEY_UNKNOWN`; o firmware faz a troca | funciona; evento solto |
| Copilot | — | Meta+Shift+F23 em ev2, sem ACPI | ok, sem driver |

Armadilha: F9 e F10 **parecem sem evento** no `evtest` porque o filtro i8042
engole o scancode. Isso não é falta de suporte.

Os cases ACPI `0x6e` (mic) e `0x6f` (webcam) que o fork trata **nunca dispararam**
neste modelo (código morto aqui, inofensivo).

## Interfaces expostas

- `/sys/devices/platform/SAM0430:00/`: `leds/samsung-galaxybook::kbd_backlight`,
  `platform-profile/`, `input/`.
- `/sys/class/firmware-attributes/samsung-galaxybook/attributes/`:
  `block_recording`, `power_on_lid_open`, `usb_charging`.
  (Não estão no diretório do dispositivo.)
- `platform_profile` (`/sys/firmware/acpi/platform_profile`): `quiet balanced performance`.
- Bateria `BAT1`: `charge_control_end_threshold` existe (limite de carga em uso).
- Inputs: `Samsung Galaxy Book Camera Lens Cover` (`SW_CAMERA_LENS_COVER`) e
  `Samsung Galaxy Book Hotkeys` (`KEY_PROG1/CAMERA/SWITCHVIDEOMODE/MICMUTE`).
  Os números `eventN` **mudam após recarregar o módulo**; confirme em
  `/proc/bus/input/devices`. Quando investigado: lens cover = `event7`,
  Hotkeys = `event8`, teclado = `event2`.

## Como os eventos de tecla chegam (DSDT decompilado)

- Todos os hotkeys ACPI passam por **um** caminho: o evento de EC `_Q7C` chama
  `NTCA(SCAI)`, que faz `Notify(SCAI, <byte>)`. O byte vem do registrador `SCAI`
  do EC (offset `0x9C`), escrito pelo firmware do EC.
- Por isso **os códigos não aparecem no DSDT**. Só se descobre o significado
  de cada um apertando a tecla e lendo o log. Os únicos `NTCA` fixos no AML são
  `0x53`, `0x54`, `0x61`, `0x75` (não são teclas).
- O driver do kernel trata isso num `switch` em `galaxybook_acpi_notify()`:
  `0x61`, `0x6c`, `0x6d` (ignorados), `0x70` (perfil), `0x7d` (backlight),
  `0x6e` (mic), `0x6f` (câmera); o resto cai em
  `unknown ACPI notification event: 0x%x`. Não há sparse keymap.

## Eventos ACPI desconhecidos no log

| Código | O que se sabe |
|---|---|
| `0x41` | **Fn+Esc**, confirmado. Sem função no Linux. |
| `0x42` | 4 ocorrências, todas em 2026-10-04 (21:27:55, 21:28:26, 22:38:34, 22:40:50), 1–4 s após `PM: suspend exit`. **Não é a tampa** (suspend por tampa às 20:33 não gerou). **Não é plugar/desplugar carregador.** Dois dos acordares trazem `typec port0-partner: PM: parent port0 should not be sleeping`. Causa desconhecida. |
| `0x73` | 146 ocorrências, intervalo de **92–93 s**, de 2026-10-04 19:36 a 2026-10-05 18:00, depois **parou**. **Não está ligado à fonte de energia:** 300 s na bateria sem nenhum. Causa desconhecida; **[hipótese]** processo/periférico que parou ou estado do EC. |

Ambos são só avisos de log. Nenhum afeta algo que o usuário tenha notado.

Descrição do Google (0x42 = tampa/tela, 0x73 = fonte de energia) **foi testada e
refutada** pelos logs acima; não cite como fato.

## Pendência (única tecla sem função): Fn+Esc

Proposta, **não aplicada**: no `lib/fnkeys-fix/install.sh` do repo FPRINTD, no
bloco `new_notify` do patch Python, adicionar `case 0x41` emitindo uma tecla
pelo `hotkey_input_dev`, e declarar a tecla com `set_bit`. Usar **`KEY_PROG2`**
(`KEY_PROG1` já é a tecla Settings `0x7c`). Depois reinstalar o DKMS. Exige
aprovação do usuário e a escolha da ação final (silenciar mic, abrir app etc.).

## Repositórios envolvidos

- `samsung-galaxy-book-linux-fixes` (este): upstream do Andycodeman, `main` em
  `a20fe91`. Tem speaker-fix, mic-fix, webcam (libcamera/book5/legacy),
  camera-relay, ov02c10-26mhz-fix, nixos. **Não tem** driver `samsung-galaxybook`,
  fingerprint nem teclas Fn.
- `samsung-galaxy-book-linux-fixes-FPRINTD` (`~/Documents/git/`): fork de
  David Bartlett, branch `galaxybook5-fixes`, baseado em `79f9d64` (23/03).
  Tudo que é novo está em `lib/` (`fnkeys-fix`, `fingerprint-fix`,
  `fanspeed-fix`, `kdeosd-fix`, `webcam-toggle`, GUI `samsung-galaxybook-gui*`).
  O usuário quer **juntar** isso a este repo "nos moldes" dele. Os diretórios
  duplicados (`speaker-fix`, `webcam-*`, `camera-relay`) divergem e vão gerar
  conflito num rebase.
- Fork público do usuário deste repo: `snooptheone/samsung-galaxy-book-linux-fixes`
  (remote `fork`; `origin` continua apontando para o upstream).

## Armadilhas já encontradas

1. **Trocar o módulo carrega o driver errado.** Compilei o driver do kernel puro
   e o carreguei com `rmmod` + `insmod`: isso **removeu o input Hotkeys** e a
   tecla Settings/F4/Copilot do fork. Para voltar:
   `sudo rmmod samsung_galaxybook && sudo modprobe samsung_galaxybook`
   (ou reiniciar). O `modprobe` pega a versão de `updates/dkms/`.
2. Patchear o driver do **kernel** não resolve; o alvo certo é o fonte do fork
   (acima). Build avulso precisa de `make LLVM=1` e de
   `firmware_attributes_class.h` (está na pasta do fork).
3. `sudo pacman -S linux-cachyos-headers` (mesmo "reinstalando") **remove e
   reinstala todos os módulos DKMS** do kernel atual.
4. `evtest` não vem instalado (`sudo pacman -S evtest`). Gravar o `event2`
   registra **tudo o que o usuário digita**, inclusive senhas; apague os logs
   (`/tmp/*.log`) e mate os órfãos (`sudo pkill evtest`) ao terminar. O `Ctrl+C`
   num `bash -c '... & ... wait'` deixa os `evtest` rodando em segundo plano.
5. `/tmp/dsdt-*.dat` copiado com `sudo` fica do root; só `sudo rm` apaga.

## Como reproduzir o mapeamento

```bash
# 1. números dos dispositivos
grep -A5 -E 'Name="(Samsung Galaxy Book Hotkeys|AT Translated Set 2 keyboard)"' /proc/bus/input/devices | grep -E "Name|Handlers"
# 2. gravar (usuário roda; sem saída na tela)
sudo bash -c 'for d in 2 8; do evtest /dev/input/event$d | sed -u "s/^/[ev$d] /" & done; wait' > /tmp/keys.log
# 3. o agente lê o log do kernel (sem sudo) cruzando os horários
journalctl -k --since "-10min" --no-pager -o short-unix | grep "unknown ACPI"
# 4. limpar
sudo pkill evtest; rm -f /tmp/keys.log
```

Para decompilar o DSDT: `sudo cp /sys/firmware/acpi/tables/DSDT /tmp/d.dat`
(usuário), depois `iasl -d` (já instalado). Apague ao terminar.

## Estrutura do projeto e padrão DKMS (análise de 2026-10-05, só leitura)

Este repo é o upstream `Andycodeman/samsung-galaxy-book-linux-fixes` (tag
`v0.3.75`). O branch `custom` é a base do fork do usuário.

### Layout

- **Um diretório por correção**, independente das outras. Cada um tem
  `README.md`, `install.sh` e `uninstall.sh`: `speaker-fix`,
  `speaker-fix-940xfg`, `mic-fix`, `ov02c10-26mhz-fix`, `webcam-fix-libcamera`,
  `webcam-fix-book5`, `webcam-fix` (legado), `camera-relay`, mais `nixos/` e `docs/`.
- **Sem CI** (não há `.github/`), sem build central, sem `VERSION`; versão por
  **tags** (`v0.3.x`). README raiz lista as correções, hardware testado e como
  reportar problema.
- `docs/triage/` guarda notas de issues e PRs (`issue-NN-findings.md`,
  `pr-NNN-review.md`). Faz parte do repo.
- **Testes** só em `camera-relay/tests/` (scripts de shell). Os módulos DKMS não têm.
- `nixos/` tem um `.nix` por correção, com opção `enable`, lendo arquivos dos
  diretórios irmãos.
- O `.gitignore` do upstream ignora `AGENTS.md` e `CLAUDE.md` (linhas geradas
  por ferramenta). Este `AGENTS.md` foi commitado com `git add -f`.

### Convenção dos módulos DKMS

Exemplos: `speaker-fix` (2 módulos), `ov02c10-26mhz-fix` (1),
`webcam-fix-book5/ipu-bridge-fix` (1).

| Elemento | Convenção |
|---|---|
| `dkms.conf` | `PACKAGE_NAME`, `PACKAGE_VERSION`, `BUILT_MODULE_NAME[n]`, `DEST_MODULE_LOCATION="/updates"` (ou `/updates/dkms`), `AUTOINSTALL="yes"`, `MAKE[0]`/`CLEAN` com `${kernel_source_dir}` |
| `Makefile` | `obj-m += x.o`; no `speaker-fix` fica em `src/` com `KVER ?=` e `KDIR ?=` |
| Fonte | copiado para `/usr/src/<nome>-<versão>/` |
| Instalação | `dkms add` → `build` → `install`; remove a versão anterior antes (`dkms remove --all`) |
| Secure Boot | `mokutil --sb-state`; configura `mok_signing_key`/`mok_certificate` no DKMS; confere se o módulo está **assinado** e se a chave está **inscrita**; orienta o MOK enroll |

Os `dkms.conf` do projeto **não usam `LLVM=1`**, mas o kernel do usuário é
clang e `ipu-bridge-fix`/`ov02c10` já constam como instalados no `dkms status`,
então o DKMS resolve isso. Mesmo assim, **teste o build do módulo novo** no
sistema antes de assumir.

### Convenção dos `install.sh`

`#!/bin/bash`, `set -e`, exige root (`id -u`), detecta `dnf`/`pacman`/`apt`,
instala `dkms` e headers; variáveis no topo (`DKMS_NAME`, `DKMS_VER`,
`SRC_DIR`); `echo` simples. **Os instaladores não compartilham código** (cada um
repete detecção de distro e assinatura de módulo). O `uninstall.sh` espelha o
`install.sh`: para serviços, `rmmod`, `dkms remove`, apaga
`/etc/systemd/system`, `/etc/modules-load.d`, `/usr/local/sbin`, `/usr/src`.

### Auto-remoção quando o kernel absorve o patch

`speaker-fix` instala `*-check-upstream.service` (oneshot no boot) que verifica
se o kernel tem suporte nativo e, se tiver, **remove o DKMS, os serviços e os
arquivos sozinho**. É o mesmo conceito do `fkeys-monitor` do FPRINTD e deve ser
reaproveitado em qualquer módulo novo.

### Comparação com o repo FPRINTD

| FPRINTD | Equivalente no padrão deste repo |
|---|---|
| `lib/fnkeys-fix` (baixa o `.c` do kernel e aplica patch Python em tempo de instalação) | diretório com `dkms.conf`, `Makefile`, `.c` **já patchado e versionado**, `install.sh`, `uninstall.sh`, `check-upstream`, `README.md` |
| `lib/fingerprint-fix` | só instalador (compila libfprint), sem DKMS |
| `lib/fanspeed-fix`, `kdeosd-fix`, `webcam-toggle` | scripts de usuário, sem DKMS |
| GUI e `lib/` compartilhado | **não existe equivalente** neste repo |

Trade-off: versionar o `.c` é mais estável (o patch Python do FPRINTD quebra
quando o driver do kernel muda), mas passa a ser trabalho nosso acompanhar o
kernel.

## Decisões do usuário (2026-10-05)

- Fork público criado: `snooptheone/samsung-galaxy-book-linux-fixes`; branch
  **`custom`** é o padrão do fork. O `main` do fork e o local ficam espelhando o
  upstream e **não devem receber commits próprios**.
- Atualizar o `custom`: `git fetch origin && git rebase origin/main` e
  `git push --force-with-lease fork custom`.
- O próximo módulo será **só para o Galaxy Book4 Ultra (NP960XGL)**, o único
  modelo que o usuário consegue testar. Não é um módulo genérico Book4/Book5.
  Ele deve seguir o padrão DKMS acima (fonte `.c` versionado, não baixado no
  instalador) e tratar o Fn+Esc (`0x41`).
  - **Manter** o que foi verificado funcionando no NP960XGL: a máquina de
    estados do **F4** (Super+P do i8042 → `KEY_SWITCHVIDEOMODE`) e o input
    Hotkeys; F9/F10/F11 já vêm do driver do kernel.
  - **Não carregar sem teste no hardware** o que é só do Book5: os cases ACPI
    `0x7c`, `0x6e`/`0x6f` (nunca dispararam aqui) e o tratamento da tecla
    Copilot por i8042 (aqui ela chega como Meta+Shift+F23 e já funciona).

## Fora de escopo / outro problema

- `pop-os/pop#3980`: mesmo modelo e mesma BIOS, mas o problema é a **bateria que
  não aparece** em boot a frio sem carregador. Sem relação com as teclas; sem
  códigos `0x41/0x42/0x73` no texto. Sem solução publicada.
