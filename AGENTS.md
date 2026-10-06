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
| Secure Boot | **ligado** (`SecureBoot` = 1 em efivars). `mokutil` **não instalado**. Módulos DKMS carregam, assinados por `DKMS module signing key` (`/var/lib/dkms/mok.{key,pub}`, DKMS 3.4.3) |
| Driver oficial | `CONFIG_SAMSUNG_GALAXYBOOK=m`. **É o driver em uso desde 2026-10-05** (fork removido). O `.ko` está em `kernel/drivers/platform/x86/` nos kernels `7.2.9` e `6.18.55-lts` (o DKMS o devolveu ao remover o fork). Antes, ficava arquivado em `/var/lib/dkms/samsung-galaxybook-book5pro/original_module/` |
| Parecido com Book5, **não igual**: o fork do driver (já removido) foi escrito para o Book5 Pro |

O DSDT do repo `joshuagrisham/samsung-galaxybook-extras` **não serve**: o
firmware foi atualizado depois daquele dump.

## O que está instalado (relevante)

DKMS (`dkms status`): `max98390-hda/1.0`, `ov02c10/1.0`, `ipu-bridge-fix/1.4`,
`vboxhost`. **Nenhum módulo `samsung-galaxybook`**: o driver em uso é o do kernel.

### Driver `samsung-galaxybook-book5pro` — **REMOVIDO em 2026-10-05**

Desinstalado a pedido do usuário com `sudo ./install.sh --remove-fork` (de
`fnkeys-fix-960xgl/`), depois de medir que F4, F9, Fn+F10 e Fn+F11 funcionam igual
com o driver do kernel. Foi a **primeira execução real** do `--remove-fork` e
saiu sem erro. Verificado depois, sem `mokutil`: `dkms status` sem o fork; os 7
itens do fork apagados (serviço `fkeys-monitor`, os 2 scripts em
`/usr/local/bin`, `/etc/modules-load.d/samsung-galaxybook.conf`,
`fkeys-kernel.ver`, `/usr/src/...` e a árvore do DKMS); o `.ko` original
restaurado em `kernel/` nos dois kernels; `modinfo -n` aponta para ele; os outros
módulos DKMS ficaram intactos. **Não verificado ainda:** o carregamento automático
no boot sem o `modules-load.d` (deve vir do ACPI `SAM0430`) e o Fn+Esc depois da
remoção. A descrição abaixo é **histórica**:

- Era um **fork do driver do kernel**, gerado pelo `lib/fnkeys-fix/install.sh` do
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

### `kdeosd-fix` (em uso)

`lib/kdeosd-fix` do repo FPRINTD está instalado: `kde-power-osd.service`
(sistema, root, habilitado) roda `/usr/local/sbin/kde-power-osd.sh`, **idêntico**
ao heredoc do `install.sh` (65 linhas; marcador de 22/04). O script escuta o
D-Bus do **`power-profiles-daemon`** (`net.hadess.PowerProfiles`,
`ActiveProfile`) e mostra o aviso do KDE. **Não olha o kernel nem o fork.** Só
dispara quando o daemon está ligado ao `platform_profile`
(`powerprofilesctl list` mostra `PlatformDriver: platform_profile`).

Outros módulos do repo FPRINTD: `fingerprint-fix` (marcador de 18/08 em
`/etc/samsung-galaxybook-libfprint-sdcp-v2.installed`; `libfprint.sha256`
**ausente**, então o monitor não faz nada; o `fprintd` funciona com o libfprint
do CachyOS 1.94.100, sensor `1c7a:05a1`), `kdeosd-fix` (instalado, marcador de
22/04). Sem sinal de `fanspeed-fix` nem de `webcam-toggle`.

## Mapa das teclas (verificado com `evtest` + `journalctl -k`)

> Medido **com o fork instalado**; a coluna "Como chega" cita caminhos do fork
> (input "Hotkeys", filtro i8042). O fork foi removido e a seção "Driver original
> vs. fork" mostra que as teclas funcionam igual com o driver do kernel.

| Tecla | Função | Como chega | Status |
|---|---|---|---|
| Fn+Esc | Suporte Samsung (ícone de headset) | ACPI `0x41` | **sem handler** |
| F1 | ? | `KEY_PROG1`, scan `0xce`, teclado comum (ev2) | ok (kernel) |
| F2 / F3 | Brilho da tela | Video Bus | ok |
| F4 | Troca de tela | scancodes Super+P → filtro i8042 do fork → `KEY_SWITCHVIDEOMODE` (ev8). **Também funciona com o driver original**: o firmware manda `video/switchmode VMOD 00000080` por ACPI video | ok, **sem precisar do fork** |
| F5 | Touchpad | scan `0x76`, `KEY_TOUCHPAD_TOGGLE` (+Ctrl+Meta) | ok |
| F6 / F7 / F8 | Mudo, vol −, vol + | scancodes comuns | ok |
| F9 | Backlight do teclado | scancode consumido pelo filtro i8042 (silencioso no evtest) | ok (testado também no driver original) |
| Fn+F10 | Bloqueio da câmera (**com Fn**, como o Fn+F11) | scancode consumido pelo filtro i8042 → `block_recording` | **medido nos dois, funciona**: `block_recording` `0` → `1` após um Fn+F10 (fork 21:55, driver original 22:33, 2026-10-05) |
| Fn+F11 | Perfil de energia | ACPI `0x70` → `platform_profile_cycle()`. **Só com Fn**: F11 sem Fn não faz nada, nem no fork nem no original (medido) | ok (fork e original) |
| F12 | Fn Lock | scan `0xa8`, `KEY_UNKNOWN`; o firmware faz a troca | funciona; evento solto |
| Copilot | — | Meta+Shift+F23 em ev2, sem ACPI | ok, sem driver |

Armadilha: F9 e F10 **parecem sem evento** no `evtest` porque o filtro i8042
engole o scancode. Isso não é falta de suporte.

Os cases ACPI `0x6e` (mic) e `0x6f` (webcam) que o fork trata **nunca dispararam**
neste modelo (código morto aqui, inofensivo).

## Driver original do kernel vs. fork (testado à noite, 2026-10-05)

Carregado o `.ko` original com `rmmod` + `insmod` (confirmado pelo
`srcversion`: original `201A05CD7164D0CCD868817`, fork `0A1825414CF30ACB7673EA6`).

| Tecla | Original | Fork |
|---|---|---|
| F4 (trocar tela) | **funciona** | funciona |
| F9 (backlight) | **funciona** | funciona |
| Fn+F10 (câmera) | **funciona** (`block_recording` `0` → `1`) | **funciona** (`block_recording` `0` → `1`) |
| F11 sem Fn | não troca o perfil (`performance` → `performance`) | não troca (`balanced` → `balanced`) |
| Fn+F11 | troca (`performance` → `quiet`) | troca |
| Fn+Esc | sem efeito (`0x41` no log) | sem efeito |

Conclusão: **para F4, F9, Fn+F10 e Fn+F11 o fork não faz diferença neste
modelo; não há mais nenhuma diferença medida a favor dele.** O "F11 não mudou
nada" inicial era só a tecla errada (faltava o Fn). A câmera é **Fn+F10**, não
F10 sozinho. O Fn+F10 foi medido **uma vez em cada driver**, lendo
`/sys/class/firmware-attributes/samsung-galaxybook/attributes/block_recording/current_value`
antes e depois; **não** se olhou a imagem da câmera. O fork só acrescenta o
input "Hotkeys", e nada que o usuário usa depende dele. Se o F9 também exige
Fn, não foi verificado.

Inputs com o original: só `Samsung Galaxy Book Camera Lens Cover`; o
`Samsung Galaxy Book Hotkeys` é do fork.

### Aviso do KDE no F11 e o `power-profiles-daemon`

- O aviso vem do `kde-power-osd` (ver acima) e depende de o **daemon** estar
  ligado ao `platform_profile`.
- Depois de várias trocas de módulo com `rmmod`/`modprobe`, o aviso **parou**:
  o `platform_profile` do kernel mudava (`quiet`) e o `ppd` ficava em
  `balanced`. Depois de **reiniciar**, voltou, com kernel e `ppd` iguais e
  `PlatformDriver: platform_profile`.
- **[hipótese, enfraquecida]** descarregar o módulo faz o `ppd` perder o driver
  de plataforma e ele não o reencontra quando o módulo volta. Não vi o
  `PlatformDriver` durante a fase quebrada. **Contraevidência (22:33):** uma
  troca fork → original com `rmmod` + `insmod`, **sem reiniciar**, deixou o
  `ppd` ligado (`PlatformDriver: platform_profile`, kernel e `ppd` em
  `balanced`) e o aviso do KDE funcionando (**o usuário testou o aviso** com o
  original carregado, antes de afirmar que funcionava). A quebra anterior veio depois de
  **várias** trocas seguidas (fork ↔ original, 3 vezes) e pode ter outra causa.
- Regra prática: **uma troca isolada não precisa de reinício**; depois de
  várias trocas seguidas, se o aviso do F11 parar (kernel e `ppd` divergentes),
  reiniciar resolve. Confirme com `powerprofilesctl get` contra
  `/sys/firmware/acpi/platform_profile`.

## Interfaces expostas

- `/sys/devices/platform/SAM0430:00/`: `leds/samsung-galaxybook::kbd_backlight`,
  `platform-profile/`, `input/`.
- `/sys/class/firmware-attributes/samsung-galaxybook/attributes/`:
  `block_recording`, `power_on_lid_open`, `usb_charging`.
  (Não estão no diretório do dispositivo.)
- `platform_profile` (`/sys/firmware/acpi/platform_profile`): `quiet balanced performance`.
- Bateria `BAT1`: `charge_control_end_threshold` existe (limite de carga em uso).
- Inputs com o driver do kernel (em uso): só `Samsung Galaxy Book Camera Lens
  Cover` (`SW_CAMERA_LENS_COVER`). `Samsung Galaxy Book Hotkeys` era do fork
  (removido) e **não existe mais**.
  Os números `eventN` **mudam após recarregar o módulo**; confirme em
  `/proc/bus/input/devices`. Quando o fork estava instalado: lens cover =
  `event7`, Hotkeys = `event8`, teclado = `event2`.

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
| `0x41` | **Fn+Esc**, confirmado. Sem função no Linux. **Chega ao userspace**: com o `acpid` rodando, `acpi_listen` mostra `samsung-galaxybook SAM0430:00 00000041 00000001` (o driver chama `acpi_bus_generate_netlink_event()` para todo evento, depois do `switch`). **Pode vir em rajada:** uma apertada gerou 3 eventos em 17 ms (22:19:54); nas apertadas seguintes, 1 evento cada. Gatilho desconhecido (ver `fnkeys-fix-960xgl`). |
| `0x42` | 4 ocorrências, todas em 2026-10-04 (21:27:55, 21:28:26, 22:38:34, 22:40:50), 1–4 s após `PM: suspend exit`. **Não é a tampa** (suspend por tampa às 20:33 não gerou). **Não é plugar/desplugar carregador.** Dois dos acordares trazem `typec port0-partner: PM: parent port0 should not be sleeping`. Causa desconhecida. |
| `0x73` | 146 ocorrências, intervalo de **92–93 s**, de 2026-10-04 19:36 a 2026-10-05 18:00, depois **parou**. **Não está ligado à fonte de energia:** 300 s na bateria sem nenhum. **Reapareceu uma vez** às 21:23:36, 3 s depois de um Fn+Esc e com o `acpid` rodando. Causa desconhecida; **[hipótese]** processo/periférico que parou ou estado do EC. |

Ambos são só avisos de log. Nenhum afeta algo que o usuário tenha notado.

Descrição do Google (0x42 = tampa/tela, 0x73 = fonte de energia) **foi testada e
refutada** pelos logs acima; não cite como fato.

## Fn+Esc (única tecla sem função): opções e estado

Opções avaliadas, da menos arriscada para a mais. **A e B estão implementadas**
em `fnkeys-fix-960xgl/` (próxima seção); C e D não.

| # | Opção | Risco | Estado |
|---|---|---|---|
| A | **Userspace**: regra do `acpid` para `SAM0430:00 00000041` | nenhum (sem kernel, sem DKMS, sem Secure Boot) | **implementada, instalada e testada** nesta máquina |
| B | DKMS com `.c` patchado + `BUILD_EXCLUSIVE_KERNEL` | baixo: fora da série `7.2.x` o DKMS pula o build e o driver do kernel segue | **implementada, só compilada** (nunca carregada) |
| C | Mandar `case 0x41` para o kernel (lista `platform-driver-x86`) | zero depois de aceito | não feita; prazo longo |
| D | Fork inteiro com patch Python no instalador (como o FPRINTD faz) | médio: quebra quando o driver do kernel muda | não recomendada |

A tecla para o Fn+Esc na variante B é **`KEY_PROG2`** (`KEY_PROG1` é a Settings
`0x7c` do fork). O `acpid` só precisa estar rodando para a A; o instalador cuida disso.

## `fnkeys-fix-960xgl/` — o que foi construído

Diretório do repo (commits `a07f0e9` e `59954e4` no `custom`) com **duas
variantes** para o Fn+Esc, escolhidas no instalador. Só roda no NP960XGL (guarda
por DMI: `product_name` = `960XGL`).

```
fnkeys-fix-960xgl/
├── README.md  install.sh  uninstall.sh      # README em inglês, como os outros do repo
├── userspace/  gb-fnesc.rules  gb-fnesc.sh  fnesc.conf     # variante A
├── dkms/       dkms.conf  Makefile  samsung-galaxybook.c  firmware_attributes_class.h   # variante B
└── tests/      test-rule-match.sh  test-debounce.sh
```

Uso: `sudo ./install.sh` (A, sem reboot) · `sudo ./install.sh --action 'cmd'` ·
`sudo ./install.sh --dkms --remove-fork` (B, com reboot) · `sudo ./uninstall.sh`.

- **Uma variante por vez.** Trocar remove a outra (`uninstall.sh --variant X
  --keep-config`). Motivo: o driver encaminha o evento ao userspace mesmo quando
  o trata, então com as duas ativas a ação rodaria em dobro.
- Estado em `/var/lib/samsung-galaxybook-960xgl/state` (`STATE_VARIANT`,
  `STATE_ACPID_BY_US`).
- **`--remove-fork`** só existe como flag explícita. A variante B **recusa**
  instalar se o `samsung-galaxybook-book5pro` existir (mesmo nome de módulo).
  Sem a flag, o fork nunca é tocado.

**Variante A (userspace).** Regra `/etc/acpi/events/samsung-galaxybook-fnesc`
(`event=^samsung-galaxybook SAM0430:00 00000041 `) chama
`/usr/local/sbin/samsung-galaxybook-fnesc.sh`, que executa `FNESC_COMMAND` (de
`/etc/samsung-galaxybook-960xgl/fnesc.conf`, **padrão vazio = só uma linha no
journal**, etiqueta `samsung-galaxybook-fnesc`) como o usuário do `seat0`, via
`runuser` com `XDG_RUNTIME_DIR` e `DBUS_SESSION_BUS_ADDRESS`. `WAYLAND_DISPLAY`
**não** é definido: app gráfico precisa de um serviço de usuário. O instalador
habilita o `acpid` (`STATE_ACPID_BY_US=1`) e o desinstalador o desabilita.

**Variante B (DKMS).** `samsung-galaxybook-960xgl/1.0`,
`BUILD_EXCLUSIVE_KERNEL="^7\.2\."` (o kernel `6.18.x-lts` instalado **não**
compila). O `.c` é o do kernel **v7.2.9** mais 14 linhas: define do `0x41`,
`KEY_PROG2` no input existente e um `case`. Reiniciar depois de instalar ou
desinstalar. Sem tratamento de Secure Boot (decisão do usuário; o DKMS assina).
A base **não é provada idêntica** ao módulo carregado: o `srcversion` difere
(`1FD9…` contra `201A…`), mas todos os símbolos do original existem na base e as
strings do original são subconjunto das dela.

### Estado na máquina e o que foi verificado

- **Variante A instalada** (2026-10-05, 22:19). O fork `book5pro` foi
  **removido depois** (ver acima); a variante A foi reinstalada junto, no mesmo
  comando. `acpid` ativo e habilitado; ele carrega 2 regras (a outra é a
  `anything`, padrão do pacote). O script do sistema é idêntico ao do repo (`cmp`).
- **Ponta a ponta (A):** uma apertada do Fn+Esc → 1 evento → 1 execução
  (22:25:11, 22:25:22 e 22:26:11 segurando a tecla).
- **Testes:** `test-rule-match.sh` (5/5) e `test-debounce.sh` (falha no script
  antigo com 3 chamadas, passa no novo com 1). `shellcheck` limpo nos scripts.
- **A variante B compilou** num `make LLVM=1` na pasta de rascunho, mas **nunca
  foi carregada** nem instalada.

### Bug achado e corrigido: rajada de eventos

Às 22:19:54, **uma** apertada gerou **3 eventos `0x41` em 17 ms** (+0, +16 ms,
+1 ms) e o script, ainda sem trava, rodou 3 vezes. Não reproduziu depois: três
apertadas seguintes deram 1 evento cada, e segurar a tecla por 1–2 s também. Antes
do reboot o `0x41` já aparecia em duplas e trincas. **Gatilho desconhecido.**
Correção em `gb-fnesc.sh`: a primeira instância pega um `flock` e o segura por
0,5 s; as outras saem. Efeito colateral: uma segunda apertada **deliberada** em
menos de 0,5 s é ignorada. `FNESC_CONF` e `FNESC_LOCK` existem só para o teste
trocar os caminhos. A trava **não foi vista em ação numa rajada real**; a lógica
está provada só pelo teste sintético.

### Decisões do usuário para este módulo

Nome `fnkeys-fix-960xgl`; variante padrão A; ação padrão = só registrar no log;
`--remove-fork` só explícito; teste = `test-rule-match.sh` (o `test-debounce.sh`
veio depois do bug).

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

1. **[histórico, o fork já foi removido]** Trocar o módulo carregava o driver
   errado. Compilei o driver do kernel puro e o carreguei com `rmmod` + `insmod`:
   isso **removeu o input Hotkeys** e a tecla Settings/F4/Copilot do fork. Para voltar:
   `sudo rmmod samsung_galaxybook && sudo modprobe samsung_galaxybook`
   (ou reiniciar). O `modprobe` pega a versão de `updates/dkms/`. Trocar várias
   vezes seguidas **pode** desligar o `power-profiles-daemon` do
   `platform_profile` e matar o aviso do F11 (uma troca isolada não deu
   problema; ver acima). Se acontecer, reiniciar reconecta.
   Para testar o driver **original**, o `.ko` está em
   `/var/lib/dkms/samsung-galaxybook-book5pro/original_module/$(uname -r)/x86_64/`
   (`zstd -dc ... > /tmp/x.ko`). O caminho `kernel/drivers/platform/x86/` **não
   existe** (o DKMS o move). Um `insmod` de arquivo vazio falha **depois** do
   `rmmod`, deixando o sistema sem driver: valide com `test -s` antes.
2. Carregar à mão um `.ko` do driver do kernel **substitui o fork** e some o
   input Hotkeys (ver 1). Já a variante B de `fnkeys-fix-960xgl` instala via
   DKMS um `.c` do kernel com só o `0x41` e exige tirar o fork (`--remove-fork`).
   Build avulso precisa de `make LLVM=1` e de `firmware_attributes_class.h`
   (a variante B já leva o header).
3. `sudo pacman -S linux-cachyos-headers` (mesmo "reinstalando") **remove e
   reinstala todos os módulos DKMS** do kernel atual.
4. `evtest` não vem instalado (`sudo pacman -S evtest`). Gravar o `event2`
   registra **tudo o que o usuário digita**, inclusive senhas; apague os logs
   (`/tmp/*.log`) e mate os órfãos (`sudo pkill evtest`) ao terminar. O `Ctrl+C`
   num `bash -c '... & ... wait'` deixa os `evtest` rodando em segundo plano.
5. `/tmp/dsdt-*.dat` copiado com `sudo` fica do root; só `sudo rm` apaga.
6. **Secure Boot ligado e sem `mokutil`.** Os instaladores do upstream só
   configuram assinatura nos ramos `dnf` e `apt`; no `pacman` as checagens
   `mokutil --sb-state 2>/dev/null` **falham em silêncio**. O `fnkeys-fix` do
   FPRINTD não trata Secure Boot. Tudo funciona no CachyOS porque o DKMS 3.x
   assina sozinho com `/var/lib/dkms/mok.*` (chave já inscrita; confirmado por
   `modinfo -F signer`). Sem `mokutil`, dá para ler o estado em
   `/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c`
   (último byte 1 = ligado). **Decisão do usuário: deixar igual** (confiar na
   assinatura do DKMS, sem tratamento extra), válida só se houver módulo.
7. O `acpi_listen` exige o **serviço** `acpid` rodando (`sudo systemctl start
   acpid`); sem ele falha com `can't open socket /var/run/acpid.socket`.
8. Os headers do CachyOS não são `linux-headers`; o nome vem de
   `/usr/lib/modules/$(uname -r)/pkgbase` + `-headers`.
9. Para ver o que a ação do Fn+Esc fez: `journalctl -t samsung-galaxybook-fnesc
   --no-pager -n 5`. A etiqueta é **`samsung-galaxybook-fnesc`**; qualquer
   variação volta `No entries`. Sem `--no-pager` o `journalctl` abre o
   paginador (sair com `q`).
10. O instalador da variante A **muda o sistema**: habilita o `acpid` no boot e
    grava em `/etc/acpi/events/`, `/usr/local/sbin/` e `/etc/samsung-galaxybook-960xgl/`.
    O `uninstall.sh` desfaz tudo e só desabilita o `acpid` se foi o instalador
    que o habilitou.
11. O `0x41` pode chegar em rajada (3 eventos em 17 ms). Qualquer ação nova ligada
    ao Fn+Esc precisa tolerar isso; a variante A já tem a trava.

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
- O próximo trabalho será **só para o Galaxy Book4 Ultra (NP960XGL)**, o único
  modelo que o usuário consegue testar. Não é genérico Book4/Book5.
- **O usuário aceitou implementar as duas variantes (A e B) e escolher no
  instalador.** Isso virou `fnkeys-fix-960xgl/` (seção acima). Nenhum módulo
  carrega o fork, o Copilot nem os cases ACPI do Book5.
- **Decisão superada:** uma proposta anterior de módulo DKMS que **mantinha** a
  máquina de estados do F4 e o input "Hotkeys" do fork. Foi descartada: o F4
  funciona com o driver original (o firmware manda `video/switchmode`), e o
  `.c` da variante B só acrescenta o `0x41`.
- **Pendências abertas:**
  1. ~~Medir o Fn+F10 no driver original~~ **feito** (2026-10-05 22:33,
     `block_recording` `0` → `1`). Já não há diferença medida a favor do fork.
  2. **Variante B**: carregar e testar (hoje só compilou).
  3. Decidir se o **`kdeosd-fix`** entra no repo, e se junto com o Fn+Esc.
  4. ~~Desinstalar o fork `book5pro`~~ **feito** (2026-10-05). Sobra verificar
     o **Fn+Esc** depois da remoção e o **carregamento do driver no boot** sem o
     `modules-load.d` (só reiniciando).
  5. Opcional: mandar o `case 0x41` ao kernel (opção C) e acompanhar a rajada
     do `0x41`.

## Fora de escopo / outro problema

- `pop-os/pop#3980`: mesmo modelo e mesma BIOS, mas o problema é a **bateria que
  não aparece** em boot a frio sem carregador. Sem relação com as teclas; sem
  códigos `0x41/0x42/0x73` no texto. Sem solução publicada.
