#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

# ============================================================
# provision.sh — подготовка заводского терминала PCMA
# Linux Mint 21.3 "Virginia" (Cinnamon)
#
# Терминал работает 24/7: автологин пользователя pcma,
# автозапуск Firefox (основной браузер) с главной страницей,
# Chrome — резервный браузер, Conky — мониторинг,
# сон и гашение экрана запрещены, автообновления отключены
# (обновляется вручную через sudo apt update / full-upgrade).
#
# Запуск:
#   sudo bash provision.sh            тихий режим + индикатор прогресса
#   sudo bash provision.sh -v         подробный вывод команд
#   sudo bash provision.sh --help     справка
#
# Полный лог всегда сохраняется в provision.log рядом со скриптом.
#
# Copyright:
#   Author: nofantasysorry (https://github.com/nofantasysorry)
#   © 2026 Claude (Anthropic). Assisted by Claude (Anthropic).
#   Лицензия MIT — см. LICENSE.
# ============================================================

# ============================================================
# Основные параметры
# ============================================================

START_URL="http://mainpage.pcmarus.loc/"

# Создаётся вручную во время установки Linux Mint.
ADMIN_USER="administrator"

# Создаётся этим скриптом без sudo и без пароля.
PCMA_USER="pcma"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CERT_SOURCE_DIR="${SCRIPT_DIR}/certificates"

CERT_1="${CERT_SOURCE_DIR}/PCMA-Root-CA.crt"
CERT_2="${CERT_SOURCE_DIR}/PCMA-Sub-CA.crt"

SYSTEM_CERT_DIR="/usr/local/share/ca-certificates/pcmarus"
PCMA_SHARE_DIR="/usr/local/share/pcma"

CHROME_POLICY_DIR="/etc/opt/chrome/policies/managed"
FIREFOX_POLICY_DIR="/etc/firefox/policies"
AUTOSTART_DIR="/etc/xdg/autostart"
LIGHTDM_CONF_DIR="/etc/lightdm/lightdm.conf.d"

LOG_FILE="${SCRIPT_DIR}/provision.log"

# ============================================================
# Режим вывода и цвета
# ============================================================

VERBOSE=0
TOTAL_STEPS=13
CURRENT_STEP=0
SPINNER_PID=""

# Цвета: только для интерактивного терминала.
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_GREEN='\033[32m'
    C_RED='\033[31m'
    C_YELLOW='\033[33m'
    C_CYAN='\033[36m'
    C_DIM='\033[2m'
else
    C_RESET=''
    C_GREEN=''
    C_RED=''
    C_YELLOW=''
    C_CYAN=''
    C_DIM=''
fi

# Спиннер.
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# ============================================================
# Вспомогательные функции
# ============================================================

# Лог всегда пишется в файл; в терминал — только в verbose.
verbose_print() {
    printf '%s\n' "$*" >>"${LOG_FILE}"
    if [[ "${VERBOSE}" -eq 1 ]]; then
        printf '%s\n' "$*"
    fi
}

log() {
    verbose_print "[$(date '+%F %T')] $*"
}

warning() {
    local msg
    msg="$(printf 'Предупреждение: %s' "$*")"
    printf '%s\n' "${msg}" >>"${LOG_FILE}"

    if [[ "${VERBOSE}" -eq 1 ]]; then
        printf '\n%s\n' "${msg}" >&2
    else
        printf '%b\n' "${C_YELLOW}! ${msg}${C_RESET}" >&2
    fi
}

die() {
    local msg
    msg="$(printf 'Ошибка: %s' "$*")"
    printf '%s\n' "${msg}" >>"${LOG_FILE}"

    stop_spinner
    printf '%b\n' "${C_RED}${msg}${C_RESET}" >&2
    printf 'Подробности: %s\n' "${LOG_FILE}" >&2
    exit 1
}

error_handler() {
    local exit_code=$?
    local line_number="${1:-неизвестно}"

    {
        printf '\nОшибка выполнения скрипта в строке %s.\n' \
            "${line_number}"
        printf 'Код возврата: %s\n' "${exit_code}"
    } >>"${LOG_FILE}"

    stop_spinner
    printf '\n%b\n' "${C_RED}Ошибка в строке ${line_number}, код ${exit_code}.${C_RESET}" >&2
    printf 'Подробности: %s\n' "${LOG_FILE}" >&2
    exit "${exit_code}"
}

trap 'error_handler ${LINENO}' ERR

# ============================================================
# Прогресс: полоса, счётчик шагов, спиннер
# ============================================================

# Печатает строку шага: [3/13] [██████░░░░░░░] 23% Название
step_header() {
    local title="$1"
    local percent
    local filled
    local empty
    local bar
    local i

    percent=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
    filled=$(( CURRENT_STEP * 14 / TOTAL_STEPS ))
    empty=$(( 14 - filled ))

    bar=""
    for (( i = 0; i < filled; i++ )); do bar+="█"; done
    for (( i = 0; i < empty; i++ )); do bar+="░"; done

    printf '%b' "${C_CYAN}[${CURRENT_STEP}/${TOTAL_STEPS}]${C_RESET} "
    printf '%b' "${C_DIM}[${bar}] ${percent}%${C_RESET} "
    printf '%s' "${title}"
}

start_spinner() {
    # В verbose или non-interactive спиннер не нужен.
    if [[ "${VERBOSE}" -eq 1 ]] || ! [[ -t 2 ]]; then
        return 0
    fi

    (
        local frame=0
        while true; do
            printf '\r%b' "${C_CYAN}${SPINNER_FRAMES[frame]}${C_RESET}" >&2
            frame=$(( (frame + 1) % ${#SPINNER_FRAMES[@]} ))
            sleep 0.2
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    if [[ -n "${SPINNER_PID}" ]]; then
        kill "${SPINNER_PID}" 2>/dev/null || true
        wait "${SPINNER_PID}" 2>/dev/null || true
        SPINNER_PID=""
        # Стираем символ спиннера.
        printf '\r \r' >&2
    fi
}

finish_step_ok() {
    local elapsed="$1"

    if [[ "${VERBOSE}" -eq 1 ]]; then
        log "Шаг завершён успешно (${elapsed}s)"
        return 0
    fi

    printf '\r%b\n' "${C_GREEN}✓${C_RESET} OK (${elapsed}s)"
}

finish_step_fail() {
    local elapsed="$1"

    if [[ "${VERBOSE}" -eq 1 ]]; then
        log "Шаг ЗАВЕРШИЛСЯ ОШИБКОЙ (${elapsed}s)"
        return 0
    fi

    printf '\r%b\n' "${C_RED}✗${C_RESET} FAIL (${elapsed}s)"
}

# ============================================================
# Выполнение шага
# ============================================================

# run_step <title> <long|short> <function> [args...]
# Тихий режим: вывод шага идёт только в provision.log,
# долгие шаги сопровождаются спиннером, по завершении —
# цветная галочка (успех) или крестик (сбой).
# Verbose: вывод шага виден в терминале и пишется в лог.
run_step() {
    local title="$1"
    local weight="$2"
    local func="$3"
    shift 3

    CURRENT_STEP=$(( CURRENT_STEP + 1 ))

    if [[ "${VERBOSE}" -eq 1 ]]; then
        printf '\n=== [%d/%d] %s ===\n' \
            "${CURRENT_STEP}" "${TOTAL_STEPS}" "${title}"
    else
        step_header "${title}"
        if [[ "${weight}" == "long" ]]; then
            start_spinner
        else
            printf '\n'
        fi
    fi

    log ">>> Шаг ${CURRENT_STEP}/${TOTAL_STEPS}: ${title}"

    local start_time
    local elapsed
    start_time="$(date +%s)"

    if "${func}" "$@" >>"${LOG_FILE}" 2>&1; then
        elapsed=$(( $(date +%s) - start_time ))
        stop_spinner
        finish_step_ok "${elapsed}"
        return 0
    else
        elapsed=$(( $(date +%s) - start_time ))
        stop_spinner
        finish_step_fail "${elapsed}"

        # В тихом режиме пользователь должен понять, что случилось.
        if [[ "${VERBOSE}" -eq 0 ]]; then
            printf '%b\n' "${C_YELLOW}Последние строки лога:${C_RESET}" >&2
            tail -n 15 "${LOG_FILE}" >&2
        fi

        return 1
    fi
}

# ============================================================
# Права root и лог
# ============================================================

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        printf '%b\n' "${C_RED}Ошибка: скрипт необходимо запускать через sudo.${C_RESET}" >&2
        exit 1
    fi
}

init_log() {
    : >"${LOG_FILE}"
    chmod 0600 "${LOG_FILE}"

    {
        echo "===================================================="
        echo "PCMA terminal provision — $(date '+%F %T')"
        echo "Скрипт: ${SCRIPT_DIR}/provision.sh"
        echo "Режим: verbose=${VERBOSE}"
        echo "===================================================="
    } >>"${LOG_FILE}"
}

# ============================================================
# Аргументы командной строки
# ============================================================

usage() {
    cat <<'EOF'
provision.sh — подготовка заводского терминала PCMA (Linux Mint 21.3)

Использование:
    sudo bash provision.sh [КЛЮЧ]

Ключи:
    -v, --verbose    подробный вывод команд (по умолчанию — тихий
                     режим с индикатором прогресса)
    -h, --help       эта справка

В любом режиме полный лог команд сохраняется в provision.log
рядом со скриптом.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v | --verbose)
                VERBOSE=1
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                printf 'Неизвестный ключ: %s\n' "$1" >&2
                usage
                exit 1
                ;;
        esac
        shift
    done
}

# ============================================================
# Пользовательские утилиты
# ============================================================

get_user_home() {
    local username="$1"
    local home_dir

    home_dir="$(getent passwd "${username}" | cut -d: -f6)"

    [[ -n "${home_dir}" ]] ||
        die "Не удалось определить домашний каталог пользователя ${username}."

    printf '%s\n' "${home_dir}"
}

get_user_group() {
    local username="$1"
    local primary_group

    primary_group="$(id -gn "${username}")"

    [[ -n "${primary_group}" ]] ||
        die "Не удалось определить основную группу пользователя ${username}."

    printf '%s\n' "${primary_group}"
}

# gsettings от имени пользователя с отдельной D-Bus-сессией.
# При неудаче — предупреждение, скрипт не останавливается.
gsettings_user() {
    local username="$1"
    local schema="$2"
    local key="$3"
    local value="$4"
    local home_dir

    home_dir="$(get_user_home "${username}")"

    if ! runuser -u "${username}" -- \
        env HOME="${home_dir}" \
        dbus-run-session -- \
        gsettings writable \
            "${schema}" \
            "${key}" \
        >/dev/null 2>&1; then

        warning "Не удалось получить доступ к настройкам ${schema} для ${username}."
        return 0
    fi

    runuser -u "${username}" -- \
        env HOME="${home_dir}" \
        dbus-run-session -- \
        gsettings set \
            "${schema}" \
            "${key}" \
            "${value}"
}

# ============================================================
# Шаг 1. Проверка administrator
# ============================================================

validate_admin_user() {
    local home_dir

    log "Проверка пользователя ${ADMIN_USER}"

    id "${ADMIN_USER}" >/dev/null 2>&1 ||
        die "Пользователь ${ADMIN_USER} не существует. Создайте его при установке Linux Mint."

    if ! id -nG "${ADMIN_USER}" |
        tr ' ' '\n' |
        grep -qx "sudo"; then

        die "Пользователь ${ADMIN_USER} не входит в группу sudo."
    fi

    home_dir="$(get_user_home "${ADMIN_USER}")"

    [[ -d "${home_dir}" ]] ||
        die "Домашний каталог ${home_dir} пользователя ${ADMIN_USER} не существует."

    log "Пользователь ${ADMIN_USER} найден и имеет права sudo"
}

# ============================================================
# Шаг 2. Подключение репозитория Google Chrome
# ============================================================

add_chrome_repository() {
    log "Подключение официального репозитория Google Chrome"

    install -d -m 0755 /etc/apt/keyrings

    curl -fsSL \
        https://dl.google.com/linux/linux_signing_key.pub |
        gpg \
            --dearmor \
            --yes \
            -o /etc/apt/keyrings/google-chrome.gpg

    chmod 0644 /etc/apt/keyrings/google-chrome.gpg

    cat > /etc/apt/sources.list.d/google-chrome.list <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main
EOF
}

# ============================================================
# Шаг 3. Установка и обновление пакетов
# ============================================================

install_packages() {
    log "Установка необходимых пакетов"

    export DEBIAN_FRONTEND=noninteractive

    # Один apt-get update после подключения всех репозиториев.
    apt-get update

    apt-get install -y \
        ca-certificates \
        conky-all \
        curl \
        dbus-x11 \
        firefox \
        gnupg \
        google-chrome-stable \
        libnss3-tools \
        openssl \
        xdg-user-dirs \
        xdg-utils

    log "Обновление установленных пакетов"

    # Разовое приведение свежеустановленной системы к актуальному
    # состоянию. Дальнейшие обновления — только вручную.
    apt-get dist-upgrade -y
}

# ============================================================
# Шаг 4. Проверка сертификатов
# ============================================================

validate_certificate_files() {
    log "Проверка файлов сертификатов"

    [[ -f "${CERT_1}" ]] ||
        die "Не найден сертификат ${CERT_1}"

    [[ -f "${CERT_2}" ]] ||
        die "Не найден сертификат ${CERT_2}"

    openssl x509 \
        -in "${CERT_1}" \
        -noout \
        >/dev/null 2>&1 ||
        die "${CERT_1} не является корректным PEM-сертификатом."

    openssl x509 \
        -in "${CERT_2}" \
        -noout \
        >/dev/null 2>&1 ||
        die "${CERT_2} не является корректным PEM-сертификатом."

    log "Файлы сертификатов успешно проверены"
}

# ============================================================
# Шаг 5. Создание пользователя pcma
# ============================================================

create_pcma_user() {
    local home_dir

    log "Настройка пользователя ${PCMA_USER}"

    if ! id "${PCMA_USER}" >/dev/null 2>&1; then
        adduser \
            --disabled-password \
            --gecos "PCMA" \
            "${PCMA_USER}"

        log "Пользователь ${PCMA_USER} создан"
    else
        log "Пользователь ${PCMA_USER} уже существует"
    fi

    # Гарантированно удаляем административные права.
    deluser "${PCMA_USER}" sudo 2>/dev/null || true
    deluser "${PCMA_USER}" admin 2>/dev/null || true

    home_dir="$(get_user_home "${PCMA_USER}")"

    [[ -d "${home_dir}" ]] ||
        die "Домашний каталог ${home_dir} пользователя ${PCMA_USER} не существует."
}

remove_pcma_password() {
    log "Удаление пароля пользователя ${PCMA_USER}"

    # Полностью удаляет пароль и устанавливает статус NP.
    passwd --delete "${PCMA_USER}"

    # Не допускаем блокировки учётной записи.
    usermod --unlock "${PCMA_USER}" 2>/dev/null || true

    log "Пользователь ${PCMA_USER} настроен без пароля"
}

# Составной шаг 5.
create_pcma_user_full() {
    create_pcma_user
    remove_pcma_password
}

# ============================================================
# Шаг 6. Автологин pcma (LightDM)
# ============================================================

configure_autologin() {
    log "Настройка автологина пользователя ${PCMA_USER}"

    # Группа autologin требуется LightDM в Linux Mint.
    # Создаём её на случай нестандартной сборки системы.
    getent group autologin >/dev/null 2>&1 ||
        groupadd autologin

    usermod -aG autologin "${PCMA_USER}"

    install -d -m 0755 "${LIGHTDM_CONF_DIR}"

    cat > "${LIGHTDM_CONF_DIR}/50-pcma-autologin.conf" <<'EOF'
[Seat:*]
autologin-user=pcma
autologin-user-timeout=0
autologin-session=cinnamon
EOF

    chmod 0644 "${LIGHTDM_CONF_DIR}/50-pcma-autologin.conf"

    log "Автологин настроен: после включения питания сразу открывается сессия ${PCMA_USER}"
}

# ============================================================
# Шаг 7. Системное хранилище сертификатов
# ============================================================

install_system_certificates() {
    log "Установка сертификатов в системное хранилище"

    install -d -m 0755 "${SYSTEM_CERT_DIR}"

    install \
        -m 0644 \
        "${CERT_1}" \
        "${SYSTEM_CERT_DIR}/pcma-root-ca.crt"

    install \
        -m 0644 \
        "${CERT_2}" \
        "${SYSTEM_CERT_DIR}/pcma-sub-ca.crt"

    update-ca-certificates
}

# ============================================================
# Шаг 8. Политики Firefox (основной браузер)
# ============================================================

configure_firefox_policies() {
    log "Настройка обязательных политик Firefox"

    install -d -m 0755 "${FIREFOX_POLICY_DIR}"

    cat > "${FIREFOX_POLICY_DIR}/policies.json" <<EOF
{
  "policies": {
    "Homepage": {
      "URL": "${START_URL}",
      "StartPage": "homepage",
      "Locked": true
    },

    "PasswordManagerEnabled": false,
    "OfferToSaveLogins": false,

    "DisableFirefoxAccounts": true,
    "DisableProfileRefresh": true,
    "DisableTelemetry": true,
    "DontCheckDefaultBrowser": true,

    "OverrideFirstRunPage": "",

    "Preferences": {
      "browser.privatebrowsing.autostart": {
        "Value": true,
        "Status": "locked"
      },

      "places.history.enabled": {
        "Value": false,
        "Status": "locked"
      },

      "browser.formfill.enable": {
        "Value": false,
        "Status": "locked"
      }
    },

    "SanitizeOnShutdown": {
      "Cache": true,
      "Cookies": true,
      "Downloads": true,
      "FormData": true,
      "History": true,
      "Sessions": true,
      "SiteSettings": true,
      "Locked": true
    },

    "Certificates": {
      "Install": [
        "${SYSTEM_CERT_DIR}/pcma-root-ca.crt",
        "${SYSTEM_CERT_DIR}/pcma-sub-ca.crt"
      ]
    }
  }
}
EOF

    chmod 0644 "${FIREFOX_POLICY_DIR}/policies.json"

    # Дополнительное размещение для сборок Firefox,
    # которые ожидают policies.json в distribution.
    if [[ -d /usr/lib/firefox ]]; then
        install -d -m 0755 /usr/lib/firefox/distribution

        cp \
            "${FIREFOX_POLICY_DIR}/policies.json" \
            /usr/lib/firefox/distribution/policies.json

        chmod 0644 /usr/lib/firefox/distribution/policies.json
    fi
}

# ============================================================
# Шаг 9. Политики Google Chrome (резервный браузер)
# ============================================================

configure_chrome_policies() {
    log "Настройка обязательных политик Google Chrome"

    install -d -m 0755 "${CHROME_POLICY_DIR}"

    cat > "${CHROME_POLICY_DIR}/pcmarus.json" <<EOF
{
  "HomepageLocation": "${START_URL}",
  "HomepageIsNewTabPage": false,

  "RestoreOnStartup": 4,
  "RestoreOnStartupURLs": [
    "${START_URL}"
  ],

  "PasswordManagerEnabled": false,
  "SavingBrowserHistoryDisabled": true,

  "BrowserSignin": 0,
  "SyncDisabled": true,

  "AutofillAddressEnabled": false,
  "AutofillCreditCardEnabled": false
}
EOF

    chmod 0644 "${CHROME_POLICY_DIR}/pcmarus.json"
}

# ============================================================
# Шаг 10. Firefox — системный браузер по умолчанию
# ============================================================

set_default_browser() {
    local username home_dir

    log "Установка Firefox браузером по умолчанию"

    # Системные альтернативы: сбой не должен останавливать скрипт,
    # пользовательские настройки ниже важнее.
    update-alternatives --set \
        x-www-browser \
        /usr/bin/firefox \
        2>/dev/null || warning "Не удалось задать системную альтернативу x-www-browser."

    update-alternatives --set \
        gnome-www-browser \
        /usr/bin/firefox \
        2>/dev/null || warning "Не удалось задать системную альтернативу gnome-www-browser."

    # Пользовательские MIME-настройки для обоих пользователей.
    for username in "${ADMIN_USER}" "${PCMA_USER}"; do
        home_dir="$(get_user_home "${username}")"

        runuser -u "${username}" -- \
            env HOME="${home_dir}" \
            xdg-settings set \
                default-web-browser \
                firefox.desktop \
            2>/dev/null || warning "Не удалось задать браузер по умолчанию для ${username}."
    done

    log "Firefox установлен браузером по умолчанию"
}

# ============================================================
# Импорт сертификатов в NSS-хр8 лище Chrome
# ============================================================

import_chrome_certificates_for_user() {
    local username="$1"
    local home_dir
    local primary_group
    local nss_dir

    home_dir="$(get_user_home "${username}")"
    primary_group="$(get_user_group "${username}")"
    nss_dir="${home_dir}/.pki/nssdb"

    log "Импорт сертификатов Chrome для ${username}"

    install \
        -d \
        -o "${username}" \
        -g "${primary_group}" \
        -m 0700 \
        "${home_dir}/.pki"

    install \
        -d \
        -o "${username}" \
        -g "${primary_group}" \
        -m 0700 \
        "${nss_dir}"

    if [[ ! -f "${nss_dir}/cert9.db" ]]; then
        runuser -u "${username}" -- \
            certutil \
                -N \
                -d "sql:${nss_dir}" \
                --empty-password
    fi

    # Удаляем старые сертификаты с такими именами,
    # чтобы скрипт можно было запускать повторно.
    runuser -u "${username}" -- \
        certutil \
            -D \
            -d "sql:${nss_dir}" \
            -n "PCMA Root CA" \
            >/dev/null 2>&1 || true

    runuser -u "${username}" -- \
        certutil \
            -D \
            -d "sql:${nss_dir}" \
            -n "PCMA Sub CA" \
            >/dev/null 2>&1 || true

    runuser -u "${username}" -- \
        certutil \
            -A \
            -d "sql:${nss_dir}" \
            -n "PCMA Root CA" \
            -t "C,," \
            -i "${SYSTEM_CERT_DIR}/pcma-root-ca.crt"

    runuser -u "${username}" -- \
        certutil \
            -A \
            -d "sql:${nss_dir}" \
            -n "PCMA Sub CA" \
            -t "C,," \
            -i "${SYSTEM_CERT_DIR}/pcma-sub-ca.crt"

    chown -R \
        "${username}:${primary_group}" \
        "${home_dir}/.pki"
}

# ============================================================
# Определение рабочего стола
# ============================================================

desktop_directory_for_user() {
    local username="$1"
    local home_dir
    local configured_desktop

    home_dir="$(get_user_home "${username}")"

    configured_desktop="$(
        runuser -u "${username}" -- \
            env HOME="${home_dir}" \
            xdg-user-dir DESKTOP 2>/dev/null || true
    )"

    if [[ -n "${configured_desktop}" ]] &&
        [[ "${configured_desktop}" != "${home_dir}" ]]; then

        printf '%s\n' "${configured_desktop}"
    elif [[ -d "${home_dir}/Рабочий стол" ]]; then
        printf '%s\n' "${home_dir}/Рабочий стол"
    elif [[ -d "${home_dir}/Desktop" ]]; then
        printf '%s\n' "${home_dir}/Desktop"
    else
        printf '%s\n' "${home_dir}/Desktop"
    fi
}

# ============================================================
# Ярлыки браузеров (Firefox — основной, Chrome — резервный)
# ============================================================

create_shortcuts_for_user() {
    local username="$1"
    local desktop_dir
    local primary_group
    local home_dir

    desktop_dir="$(desktop_directory_for_user "${username}")"
    primary_group="$(get_user_group "${username}")"
    home_dir="$(get_user_home "${username}")"

    log "Создание ярлыков для ${username} в ${desktop_dir}"

    install \
        -d \
        -o "${username}" \
        -g "${primary_group}" \
        -m 0755 \
        "${desktop_dir}"

    cat > "${desktop_dir}/terminal.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Терминал
Comment=Основной терминал (Firefox)
Exec=/usr/bin/firefox --new-window ${START_URL}
Icon=firefox
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
EOF

    cat > "${desktop_dir}/terminal-reserve.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Терминал (резервный)
Comment=Резервный терминал (Google Chrome)
Exec=/usr/bin/google-chrome-stable --new-window ${START_URL}
Icon=google-chrome
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
EOF

    chmod 0755 \
        "${desktop_dir}/terminal.desktop" \
        "${desktop_dir}/terminal-reserve.desktop"

    chown \
        "${username}:${primary_group}" \
        "${desktop_dir}/terminal.desktop" \
        "${desktop_dir}/terminal-reserve.desktop"

    # Cinnamon может считать новые .desktop-файлы недоверенными.
    # Попытка отметить их доверенными выполняется без остановки скрипта.
    if command -v gio >/dev/null 2>&1; then
        runuser -u "${username}" -- \
            env HOME="${home_dir}" \
            gio set \
                "${desktop_dir}/terminal.desktop" \
                metadata::trusted true \
            >/dev/null 2>&1 || true

        runuser -u "${username}" -- \
            env HOME="${home_dir}" \
            gio set \
                "${desktop_dir}/terminal-reserve.desktop" \
                metadata::trusted true \
            >/dev/null 2>&1 || true
    fi
}

# ============================================================
# Максимально крупные значки рабочего стола
# ============================================================

configure_large_desktop_icons_for_user() {
    local username="$1"

    log "Настройка очень больших значков для ${username}"

    gsettings_user \
        "${username}" \
        org.nemo.icon-view \
        default-zoom-level \
        "'largest'"
}

configure_large_desktop_icons() {
    configure_large_desktop_icons_for_user "${ADMIN_USER}"
    configure_large_desktop_icons_for_user "${PCMA_USER}"
}

# Составной шаг 11.
configure_desktop_and_certs() {
    import_chrome_certificates_for_user "${ADMIN_USER}"
    import_chrome_certificates_for_user "${PCMA_USER}"

    create_shortcuts_for_user "${ADMIN_USER}"
    create_shortcuts_for_user "${PCMA_USER}"

    configure_large_desktop_icons
}

# ============================================================
# Запрет сна, гашения экрана и блокировки
# ============================================================

disable_sleep_targets() {
    log "Запрет сна и гибернации на уровне systemd"

    systemctl mask \
        sleep.target \
        suspend.target \
        hibernate.target \
        hybrid-sleep.target
}

configure_power_settings_for_user() {
    local username="$1"

    log "Отключение сна и гашения экрана для ${username}"

    # Не засыпать ни от сети, ни от батареи (батарея — на случай ИБП).
    gsettings_user \
        "${username}" \
        org.cinnamon.settings-daemon.plugins.power \
        sleep-inactive-ac-timeout \
        "0"

    gsettings_user \
        "${username}" \
        org.cinnamon.settings-daemon.plugins.power \
        sleep-inactive-battery-timeout \
        "0"

    # Закрытие крышки ноутбука не должно усыплять терминал.
    gsettings_user \
        "${username}" \
        org.cinnamon.settings-daemon.plugins.power \
        lid-close-ac-action \
        "'nothing'"

    gsettings_user \
        "${username}" \
        org.cinnamon.settings-daemon.plugins.power \
        lid-close-battery-action \
        "'nothing'"

    # Не затемнять и не блокировать экран при простое.
    gsettings_user \
        "${username}" \
        org.cinnamon.desktop.screensaver \
        idle-activation-enabled \
        "false"

    gsettings_user \
        "${username}" \
        org.cinnamon.desktop.screensaver \
        lock-enabled \
        "false"
}

configure_power_settings() {
    configure_power_settings_for_user "${ADMIN_USER}"
    configure_power_settings_for_user "${PCMA_USER}"
}

# ============================================================
# Отключение автоматических обновлений
# (ручные sudo apt update / upgrade / full-upgrade не затрагиваются)
# ============================================================

disable_auto_updates() {
    log "Отключение автоматических обновлений"

    systemctl disable --now \
        apt-daily.timer \
        apt-daily-upgrade.timer \
        motd-news.timer \
        2>/dev/null || warning "Не удалось отключить apt-таймеры."

    systemctl mask \
        apt-daily.timer \
        apt-daily-upgrade.timer \
        motd-news.timer \
        2>/dev/null || warning "Не удалось замаскировать apt-таймеры."

    # unattended-upgrades, если установлен, — выключаем.
    if dpkg -s unattended-upgrades >/dev/null 2>&1; then
        if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
            cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
            chmod 0644 /etc/apt/apt.conf.d/20auto-upgrades
        fi

        systemctl disable --now unattended-upgrades.service \
            2>/dev/null || true
    fi

    log "Автоматические обновления отключены; обновляйте вручную: sudo apt update && sudo apt full-upgrade"
}

# ============================================================
# Conky — мониторинг состояния терминала
# ============================================================

detect_network_interface() {
    # Первый активный не-loopback интерфейс вместо зашитого eno1.
    local iface
    local carrier

    for iface in /sys/class/net/*; do
        iface="$(basename -- "${iface}")"

        [[ "${iface}" == "lo" ]] && continue

        if [[ -f "/sys/class/net/${iface}/carrier" ]]; then
            carrier="$(cat "/sys/class/net/${iface}/carrier" 2>/dev/null || true)"

            if [[ "${carrier}" == "1" ]]; then
                printf '%s\n' "${iface}"
                return 0
            fi
        fi
    done

    # Активных интерфейсов не найдено — берём первый не-loopback.
    for iface in /sys/class/net/*; do
        iface="$(basename -- "${iface}")"

        if [[ "${iface}" != "lo" ]]; then
            printf '%s\n' "${iface}"
            return 0
        fi
    done

    die "Не найден ни один сетевой интерфейс для Conky."
}

configure_conky() {
    local net_iface
    local pcma_home
    local pcma_group

    net_iface="$(detect_network_interface)"
    pcma_home="$(get_user_home "${PCMA_USER}")"
    pcma_group="$(get_user_group "${PCMA_USER}")"

    log "Установка Conky (сетевой интерфейс: ${net_iface})"

    install -d -m 0755 "${PCMA_SHARE_DIR}"

    cat > "${PCMA_SHARE_DIR}/conky.conf" <<EOF
conky.config = {
    -- Настройки окна
    background = true,
    own_window = true,
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',

    -- Расположение и размеры
    alignment = 'top_right',
    gap_x = 30,
    gap_y = 50,

    -- Шрифты и цвета
    use_xft = true,
    font = 'DejaVu Sans:bold:size=12',
    font_shadow_color = '#000000',
    font_shadow_alpha = 0.5,
    default_color = '#FFFFFF',

    -- Обновление
    update_interval = 5.0,
    double_buffer = true,
};

conky.text = [[
\${color #FFCC00}ИНФОРМАЦИЯ О ТЕРМИНАЛЕ\${color}

Имя хоста: \$nodename
Время работы: \$uptime

IP-адрес: \${addr ${net_iface}}
MAC-адрес: \${execi 3200 cat /sys/class/net/${net_iface}/address}
]];
EOF

    chmod 0644 "${PCMA_SHARE_DIR}/conky.conf"

    # Копия конфига для пользователя pcma.
    runuser -u "${PCMA_USER}" -- \
        cp \
        "${PCMA_SHARE_DIR}/conky.conf" \
        "${pcma_home}/.conkyrc"

    chown \
        "${PCMA_USER}:${pcma_group}" \
        "${pcma_home}/.conkyrc"

    # Автозапуск Conky в сессии Cinnamon.
    cat > "${AUTOSTART_DIR}/pcmarus-conky.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Conky
Comment=Мониторинг состояния терминала PCMA
Exec=conky -d -c /usr/local/share/pcma/conky.conf
Terminal=false
StartupNotify=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
OnlyShowIn=X-Cinnamon;
EOF

    chmod 0644 "${AUTOSTART_DIR}/pcmarus-conky.desktop"

    log "Conky настроен и добавлен в автозагрузку"
}

# Составной шаг 12.
configure_runtime_hardening() {
    disable_sleep_targets
    configure_power_settings
    disable_auto_updates
    configure_conky
}

# ============================================================
# Шаг 17. Автозагрузка Firefox (основной браузер)
# ============================================================

configure_firefox_autostart() {
    log "Добавление Firefox в автозагрузку"

    install -d -m 0755 "${AUTOSTART_DIR}"

    # Убираем возможный файл автозапуска Chrome от прежних версий
    # скрипта, чтобы не запускались оба браузера одновременно.
    rm -f "${AUTOSTART_DIR}/pcmarus-google-chrome.desktop"

    cat > "${AUTOSTART_DIR}/pcmarus-firefox.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Терминал
Comment=Автоматический запуск основного терминала (Firefox)
Exec=/usr/bin/firefox --new-window ${START_URL}
Icon=firefox
Terminal=false
StartupNotify=true
NoDisplay=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
OnlyShowIn=X-Cinnamon;
EOF

    chmod 0644 \
        "${AUTOSTART_DIR}/pcmarus-firefox.desktop"
}

# ============================================================
# Шаг 18. Проверка результата
# ============================================================

verify_configuration() {
    local pcma_password_status
    local default_browser

    log "Проверка основных компонентов"

    echo
    echo "Версия Firefox:"
    firefox --version || true

    echo
    echo "Версия Google Chrome:"
    google-chrome-stable --version || true

    echo
    echo "Проверка системного корневого сертификата:"
    openssl verify \
        -CAfile /etc/ssl/certs/ca-certificates.crt \
        "${SYSTEM_CERT_DIR}/pcma-root-ca.crt" || true

    echo
    echo "Проверка промежуточного сертификата:"
    openssl verify \
        -CAfile /etc/ssl/certs/ca-certificates.crt \
        "${SYSTEM_CERT_DIR}/pcma-sub-ca.crt" || true

    echo
    echo "Группы пользователя ${ADMIN_USER}:"
    id "${ADMIN_USER}"

    echo
    echo "Группы пользователя ${PCMA_USER}:"
    id "${PCMA_USER}"

    echo
    echo "Состояние пароля пользователя ${PCMA_USER}:"
    passwd -S "${PCMA_USER}" || true

    pcma_password_status="$(
        passwd -S "${PCMA_USER}" 2>/dev/null |
        awk '{print $2}'
    )"

    if [[ "${pcma_password_status}" == "NP" ]]; then
        echo "OK: у пользователя ${PCMA_USER} отсутствует пароль."
    else
        warning "Статус пароля ${PCMA_USER}: ${pcma_password_status}"
    fi

    echo
    if [[ -f "${LIGHTDM_CONF_DIR}/50-pcma-autologin.conf" ]] &&
        id -nG "${PCMA_USER}" | tr ' ' '\n' | grep -qx "autologin"; then
        echo "OK: автологин пользователя ${PCMA_USER} настроен."
    else
        warning "Автологин ${PCMA_USER} не настроен."
    fi

    if [[ -L /etc/systemd/system/sleep.target ]]; then
        echo "OK: сон и гибернация запрещены на уровне systemd."
    else
        warning "Сон не замаскирован в systemd."
    fi

    if [[ -L /etc/systemd/system/apt-daily.timer ]] &&
        [[ -L /etc/systemd/system/apt-daily-upgrade.timer ]]; then
        echo "OK: автоматические обновления отключены."
    else
        warning "Автоматические обновления не отключены."
    fi

    default_browser="$(update-alternatives --query x-www-browser 2>/dev/null |
        awk '/^Value:/ {print $2}')"

    if [[ "${default_browser}" == "/usr/bin/firefox" ]]; then
        echo "OK: Firefox — системный браузер по умолчанию."
    else
        warning "Системный браузер по умолчанию: ${default_browser:-не определён}."
    fi

    if [[ -f "${CHROME_POLICY_DIR}/pcmarus.json" ]]; then
        echo "OK: политика Google Chrome установлена."
    else
        warning "Политика Google Chrome не найдена."
    fi

    if [[ -f "${FIREFOX_POLICY_DIR}/policies.json" ]]; then
        echo "OK: политика Firefox установлена."
    else
        warning "Политика Firefox не найдена."
    fi

    if [[ -f "${AUTOSTART_DIR}/pcmarus-firefox.desktop" ]]; then
        echo "OK: Firefox добавлен в автозагрузку."
    else
        warning "Файл автозагрузки Firefox не найден."
    fi

    if ! [[ -f "${AUTOSTART_DIR}/pcmarus-google-chrome.desktop" ]]; then
        echo "OK: автозагрузка Chrome отсутствует (Firefox — основной браузер)."
    else
        warning "Обнаружен файл автозагрузки Chrome — удалите его вручную."
    fi

    if command -v conky >/dev/null 2>&1; then
        echo "OK: Conky установлен."

        if [[ -f "${PCMA_SHARE_DIR}/conky.conf" ]]; then
            echo "OK: конфигурация Conky установлена."
        else
            warning "Конфигурация Conky не найдена."
        fi

        if [[ -f "${AUTOSTART_DIR}/pcmarus-conky.desktop" ]]; then
            echo "OK: Conky добавлен в автозагрузку."
        else
            warning "Файл автозагрузки Conky не найден."
        fi
    else
        warning "Conky не установлен."
    fi
}

# ============================================================
# Основная последовательность
# ============================================================

main() {
    parse_args "$@"
    require_root

    # Лог инициализируем до первого шага.
    init_log

    if [[ "${VERBOSE}" -eq 0 ]]; then
        printf '%b\n' "${C_CYAN}Подготовка терминала PCMA — Linux Mint 21.3${C_RESET}"
        printf '%b\n' "${C_DIM}Полный лог: ${LOG_FILE} (подробный вывод: -v)${C_RESET}"
        printf '\n'
    fi

    run_step "Проверка пользователя ${ADMIN_USER}" \
        short validate_admin_user

    run_step "Подключение репозитория Google Chrome" \
        long add_chrome_repository

    run_step "Установка пакетов (Firefox, Chrome, Conky)" \
        long install_packages

    run_step "Проверка сертификатов" \
        short validate_certificate_files

    run_step "Создание пользователя ${PCMA_USER}" \
        short create_pcma_user_full

    run_step "Автологин ${PCMA_USER}" \
        short configure_autologin

    run_step "Установка сертификатов в систему" \
        long install_system_certificates

    run_step "Политики Firefox" \
        short configure_firefox_policies

    run_step "Политики Google Chrome" \
        short configure_chrome_policies

    run_step "Firefox — браузер по умолчанию" \
        short set_default_browser

    run_step "Сертификаты браузеров и ярлыки" \
        long configure_desktop_and_certs

    run_step "Запрет сна, отключение автообновлений, Conky" \
        long configure_runtime_hardening

    run_step "Автозагрузка Firefox" \
        short configure_firefox_autostart

    run_step "Итоговая проверка" \
        long verify_configuration

    printf '%b\n' "${C_GREEN}Настройка завершена.${C_RESET}"

    echo
    echo "Перезагрузите компьютер:"
    echo
    echo "    sudo reboot"
    echo
    echo "После перезагрузки произойдёт автоматический вход"
    echo "пользователя ${PCMA_USER} и запуск Firefox."
    echo

    log "Настройка завершена"
}

main "$@"
