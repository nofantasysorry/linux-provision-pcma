# PCMA Terminal Provision — Linux Mint 21.3

[Русский](#русский) | [English](#english)

---

## Русский

### Назначение

Один скрипт — `provision.sh` — полностью готовит терминал ввода данных на заводе под управлением **Linux Mint 21.3 «Virginia» (Cinnamon)** для непрерывной работы **24/7**:

- автоматический вход пользователя `pcma` (без пароля, без sudo) сразу после включения питания;
- автозапуск **Firefox** (основной браузер) с главной страницей `http://mainpage.pcmarus.loc/`;
- **Google Chrome** установлен и настроен как резервный браузер (ярлык «Терминал (резервный)»);
- сертификаты PCMA (Root CA и Sub CA) доверены на всех уровнях: система, Firefox, Chrome;
- сон, гибернация, гашение и блокировка экрана запрещены;
- автоматические обновления отключены — система обновляется только вручную;
- Conky показывает состояние терминала: имя хоста, время работы, IP- и MAC-адрес.

### Требования

- Установленная Linux Mint 21.3 (Cinnamon), подключение к сети завода.
- Пользователь `administrator`, созданный при установке Mint и входящий в группу `sudo`.
- Каталог `certificates/` рядом со скриптом с файлами `PCMA-Root-CA.crt` и `PCMA-Sub-CA.crt`.
- Доступ терминала к `http://mainpage.pcmarus.loc/` и к интернету на время установки (репозитории Mint и Google).

### Установка

Скопируйте репозиторий на терминал (или скачайте и распакуйте), затем:

```bash
cd linux-provision-pcma
sudo bash provision.sh
sudo reboot
```

По умолчанию скрипт работает в **тихом режиме**: команды скрыты, на экране — индикатор прогресса:

```
[3/14] [██████░░░░░░░░] 21% Установка пакетов (Firefox, Chrome, Conky) ✓ OK (34s)
```

- `[N/14]` — номер текущего шага; полоса и процент показывают долю завершённых шагов;
- долгие шаги (установка пакетов, сертификаты) сопровождаются вращающимся спиннером, короткие — сразу получают цветную галочку `✓` (успех) или крестик `✗` (сбой);
- при сбое шага на экран выводятся последние строки лога.

### Ключи запуска

| Ключ | Действие |
|---|---|
| *(без ключей)* | Тихий режим: скрытый вывод команд, индикатор прогресса |
| `-v`, `--verbose` | Подробный вывод команд в терминале (как в старых версиях скрипта) |
| `-h`, `--help` | Справка по ключам |

### Лог выполнения

В **любом** режиме полный вывод всех команд сохраняется в файл `provision.log` рядом со скриптом. При сбое в тихом режиме путь к логу и его последние строки выводятся на экран. Лог перезаписывается при каждом запуске скрипта.

### После установки

После перезагрузки: автоматический вход `pcma` → запуск Firefox с главной страницей. Повторный запуск скрипта безопасен — все операции идемпотентны.

### Что делает скрипт

| Шаг | Действие |
|---|---|
| 1 | Проверка пользователя `administrator` и сертификатов (валидность PEM) |
| 2 | Создание пользователя `pcma` без пароля и без прав sudo; группа `autologin` |
| 3 | Настройка автологина LightDM (сессия Cinnamon) |
| 4 | Подключение репозитория Google Chrome, единый `apt-get update`, установка пакетов (Firefox, Chrome, Conky и др.), разовое `dist-upgrade` |
| 5 | Установка сертификатов: системное хранилище (`update-ca-certificates`), политики Firefox, NSS-хранилище Chrome для обоих пользователей |
| 6 | Политики браузеров: домашняя страница заблокирована, история и менеджер паролей отключены |
| 7 | Firefox — системный браузер по умолчанию (`update-alternatives` + `xdg-settings`) |
| 8 | Ярлыки на рабочем столе: «Терминал» (Firefox) и «Терминал (резервный)» (Chrome), крупные значки Nemo |
| 9 | Запрет сна/гибернации (`systemctl mask`), отключение гашения и блокировки экрана |
| 10 | Отключение автоматических обновлений (apt-таймеры, unattended-upgrades) |
| 11 | Conky: конфиг с автоопределением сетевого интерфейса (вместо зашитого `eno1`), автозапуск |
| 12 | Автозапуск Firefox через `/etc/xdg/autostart`; файл автозапуска Chrome от старых версий скрипта удаляется |
| 13 | Итоговая проверка всех компонентов (версии, сертификаты, политики, автологин, Conky) |

### Обновление терминала вручную

Автоматические обновления отключены намеренно — обновляйте в контролируемое время:

```bash
sudo apt update
sudo apt full-upgrade
```

- `apt update` — обновить индексы пакетов;
- `apt upgrade` — установить обновления, не удаляя и не устанавливая новые зависимости;
- `apt full-upgrade` — то же, но может удалять/добавлять пакеты при конфликтах; **рекомендуется** для терминала (обновления ядра и системных компонентов).

После обновления ядра или браузера перезагрузите терминал. Перед обновлением закройте браузер, чтобы не потерять несохранённые данные.

### Резервный браузер

Если Firefox не работает — дважды щёлкните «Терминал (резервный)» на рабочем столе: откроется Google Chrome, полностью настроенный (сертификаты, политика, домашняя страница).

### Структура репозитория

```
linux-provision-pcma/
├── provision.sh                 # единый скрипт подготовки
├── README.md                    # этот файл
├── LICENSE                      # лицензия MIT
└── certificates/
    ├── PCMA-Root-CA.crt         # корневой сертификат PCMA
    └── PCMA-Sub-CA.crt          # промежуточный сертификат PCMA
```

### Автор и копирайт

Автор: [nofantasysorry](https://github.com/nofantasysorry). © 2026 Claude (Anthropic). Assisted by Claude (Anthropic). Лицензия MIT — см. [LICENSE](LICENSE).

---

## English

### Purpose

A single script — `provision.sh` — fully provisions a factory data-entry terminal running **Linux Mint 21.3 "Virginia" (Cinnamon)** for continuous **24/7** operation:

- automatic login of the `pcma` user (no password, no sudo) right after power-on;
- **Firefox** autostart (primary browser) with the home page `http://mainpage.pcmarus.loc/`;
- **Google Chrome** installed and configured as the backup browser ("Terminal (backup)" shortcut);
- PCMA certificates (Root CA and Sub CA) trusted at every level: OS, Firefox, Chrome;
- sleep, hibernation, screen blanking and locking are disabled;
- automatic updates are disabled — the system is updated manually only;
- Conky displays terminal status: hostname, uptime, IP and MAC address.

### Requirements

- Installed Linux Mint 21.3 (Cinnamon), connection to the factory network.
- The `administrator` user created during Mint installation and member of the `sudo` group.
- The `certificates/` directory next to the script containing `PCMA-Root-CA.crt` and `PCMA-Sub-CA.crt`.
- Terminal access to `http://mainpage.pcmarus.loc/` and to the Internet during installation (Mint and Google repositories).

### Installation

Copy the repository to the terminal (or download and extract it), then:

```bash
cd linux-provision-pcma
sudo bash provision.sh
sudo reboot
```

By default the script runs in **quiet mode**: command output is hidden and a progress indicator is shown:

```
[3/14] [██████░░░░░░░░] 21% Installing packages (Firefox, Chrome, Conky) ✓ OK (34s)
```

- `[N/14]` — current step number; the bar and percentage show the share of completed steps;
- long steps (package installation, certificates) show a spinning animation, short ones immediately get a colored check mark `✓` (success) or cross `✗` (failure);
- when a step fails, the last lines of the log are printed to the screen.

### Command-line options

| Option | Action |
|---|---|
| *(none)* | Quiet mode: hidden command output, progress indicator |
| `-v`, `--verbose` | Verbose command output in the terminal (as in older script versions) |
| `-h`, `--help` | Print option help |

### Execution log

In **any** mode the full output of every command is saved to `provision.log` next to the script. On failure in quiet mode, the log path and its last lines are printed to the screen. The log is overwritten on every script run.

### After installation

After the reboot: automatic `pcma` login → Firefox opens with the home page. Re-running the script is safe — all operations are idempotent.

### What the script does

| Step | Action |
|---|---|
| 1 | Validates the `administrator` user and the certificates (PEM validity) |
| 2 | Creates the `pcma` user with no password and no sudo rights; `autologin` group |
| 3 | Configures LightDM autologin (Cinnamon session) |
| 4 | Adds the Google Chrome repository, a single `apt-get update`, installs packages (Firefox, Chrome, Conky, etc.), a one-time `dist-upgrade` |
| 5 | Installs certificates: system store (`update-ca-certificates`), Firefox policies, Chrome NSS store for both users |
| 6 | Browser policies: home page locked, history and password manager disabled |
| 7 | Firefox as the default system browser (`update-alternatives` + `xdg-settings`) |
| 8 | Desktop shortcuts: "Terminal" (Firefox) and "Terminal (backup)" (Chrome), large Nemo icons |
| 9 | Sleep/hibernation forbidden (`systemctl mask`), screen blanking and locking disabled |
| 10 | Automatic updates disabled (apt timers, unattended-upgrades) |
| 11 | Conky: config with network interface auto-detection (instead of the hard-coded `eno1`), autostart |
| 12 | Firefox autostart via `/etc/xdg/autostart`; the Chrome autostart file from older script versions is removed |
| 13 | Final verification of all components (versions, certificates, policies, autologin, Conky) |

### Updating the terminal manually

Automatic updates are disabled on purpose — update at a controlled time:

```bash
sudo apt update
sudo apt full-upgrade
```

- `apt update` — refresh package indexes;
- `apt upgrade` — install updates without removing or newly installing dependencies;
- `apt full-upgrade` — the same, but may remove/add packages to resolve conflicts; **recommended** for the terminal (kernel and system component updates).

Reboot the terminal after a kernel or browser update. Close the browser before updating to avoid losing unsaved data.

### Backup browser

If Firefox fails — double-click "Terminal (backup)" on the desktop: Google Chrome opens, fully configured (certificates, policy, home page).

### Repository structure

```
linux-provision-pcma/
├── provision.sh                 # the provisioning script
├── README.md                    # this file
├── LICENSE                      # MIT license
└── certificates/
    ├── PCMA-Root-CA.crt         # PCMA root certificate
    └── PCMA-Sub-CA.crt          # PCMA sub-CA certificate
```

### Author and copyright

Author: [nofantasysorry](https://github.com/nofantasysorry). © 2026 Claude (Anthropic). Assisted by Claude (Anthropic). MIT license — see [LICENSE](LICENSE).
