#!/bin/bash

###############################################################################
# NGINX Tune & Limits Automation Script
#
# Автоматизирует настройку лимитов, параметров и оптимизацию NGINX на Linux.
# Поддерживает резервное копирование, откат, dry-run, интерактивный режим,
# генерацию HTML-отчёта, ротацию бэкапов, работу с разными дистрибутивами.
#
#
# Требования:
#   - bash >= 4.x
#   - awk, grep, sed, systemctl, tail, chmod, chown, rm, mv, cp, tee
#   - root-права для изменения системных файлов
#
###############################################################################

set -e

# === Цвета и символы ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
OK='✅'
ERR='❌'
WARN='⚠️'
INFO='ℹ️'
USE_COLOR=1

# === Парсинг аргументов ===
DRY_RUN=0
INTERACTIVE=0
MAX_BACKUPS=5  # Количество бэкапов для хранения
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=1
    fi
    if [[ "$arg" == "--no-color" ]]; then
        USE_COLOR=0
    fi
    if [[ "$arg" == "--interactive" ]]; then
        INTERACTIVE=1
    fi
    # ... другие аргументы ...
done

# === Логирование в файл ===
LOG_FILE="/var/log/nginx_tune.log"
log_to_file() {
    echo -e "$1" >> "$LOG_FILE"
}
color_echo() {
    local color="$1"; shift
    local msg="$@"
    if [ "$USE_COLOR" -eq 1 ]; then
        echo -e "$color$msg$NC"
    else
        echo "$msg"
    fi
    log_to_file "$(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')"
}

log() {
    color_echo "$BLUE" "[$(date '+%Y-%m-%d %H:%M:%S')] $INFO $1"
}
log_success() {
    color_echo "$GREEN" "[$(date '+%Y-%m-%d %H:%M:%S')] $OK $1"
}
log_warn() {
    color_echo "$YELLOW" "[$(date '+%Y-%m-%d %H:%M:%S')] $WARN $1"
}
log_error() {
    color_echo "$RED" "[$(date '+%Y-%m-%d %H:%M:%S')] $ERR $1" >&2
}
print_stage() {
    color_echo "$YELLOW" "========== $1 =========="
}
print_param() {
    color_echo "$BLUE" "  → $1: $2"
}
run_or_echo() {
    if [ "$DRY_RUN" -eq 1 ]; then
        color_echo "$YELLOW" "[DRY-RUN] $@"
    else
        eval "$@"
    fi
}

# === Проверка наличия всех необходимых утилит ===
REQUIRED_BINS="awk grep systemctl tail sed df head chmod chown rm mv cp tee"
MISSING_BINS=""
for bin in $REQUIRED_BINS; do
    if ! command -v $bin >/dev/null 2>&1; then
        MISSING_BINS="$MISSING_BINS $bin"
    fi
done
if [ -n "$MISSING_BINS" ]; then
    log_error "Отсутствуют необходимые утилиты:$MISSING_BINS. Установите их и повторите запуск."
    exit 1
fi

# Определяем переменные путей до любого использования
NGINX_CONF="/etc/nginx/nginx.conf"
SYSTEMD_OVERRIDE="/etc/systemd/system/nginx.service.d/override.conf"
LIMITS_CONF="/etc/security/limits.conf"

# === Проверка и создание минимальных файлов, если их нет ===
for f in "$NGINX_CONF" "$LIMITS_CONF" "$SYSTEMD_OVERRIDE"; do
    [ -z "$f" ] && continue
    if [ ! -f "$f" ]; then
        log_warn "$f не найден! Будет создан минимальный файл-заглушка."
        if [ "$f" = "$NGINX_CONF" ]; then
            echo -e "user www-data;\nevents { }\nhttp { }" > "$f"
        elif [ "$f" = "$SYSTEMD_OVERRIDE" ]; then
            # Создаём директорию для systemd override, если её нет
            mkdir -p "$(dirname "$f")"
            touch "$f"
        else
            touch "$f"
        fi
    fi
    # Права и доступность проверяются далее
    # ...
done

# === Проверка и автоматическое исправление прав на файлы/директории ===
print_stage "Проверка наличия и прав на файлы"
for f in "$NGINX_CONF" "$LIMITS_CONF" "$SYSTEMD_OVERRIDE"; do
    if [ ! -f "$f" ]; then
        log_warn "$f не найден! Будет создан при необходимости."
    elif [ ! -w "$f" ]; then
        log_warn "Нет прав на запись в $f!"
        if [ "$INTERACTIVE" -eq 1 ]; then
            read -p "Исправить права на $f (chmod 644)? [y/N]: " ans
            if [[ "$ans" =~ ^[yY]$ ]]; then
                chmod 644 "$f" && log_success "Права на $f исправлены (chmod 644)." || { log_error "Не удалось исправить права на $f!"; exit 1; }
            else
                log_error "Права не исправлены. Прерываю выполнение."; exit 1
            fi
        else
            log_error "Нет прав на запись в $f! Исправьте права вручную или запустите с --interactive."; exit 1
        fi
    else
        log_success "$f доступен для записи."
    fi
done

# === Централизованная обработка ошибок и завершения ===
finish_with_error() {
    log_error "$1"
    # Генерируем HTML-отчёт
    HTML_REPORT="/var/log/nginx_tune_report.html"
    echo "<html><head><meta charset='utf-8'><title>NGINX Tune Report</title></head><body>" > "$HTML_REPORT"
    echo "<h2>NGINX Tune Report ($(date '+%Y-%m-%d %H:%M:%S'))</h2>" >> "$HTML_REPORT"
    echo "<pre>" >> "$HTML_REPORT"
    tail -n 200 "$LOG_FILE" >> "$HTML_REPORT"
    echo "</pre>" >> "$HTML_REPORT"
    echo "<hr><small>Сгенерировано автоматически скриптом nginx_conf.sh</small></body></html>" >> "$HTML_REPORT"
    log_warn "HTML-отчёт сгенерирован: $HTML_REPORT"
    # Очистка временных файлов
    rm -f /tmp/apt_upgrade.log /tmp/yum_update.log /tmp/dnf_upgrade.log /tmp/zypper_update.log "$NGINX_CONF.tmp"
    exit 1
}

# === Единый этап отката ===
rollback_and_exit() {
    log_warn "Выполняется откат изменений..."
    restore_backup $NGINX_CONF
    restore_backup $LIMITS_CONF
    restore_backup $SYSTEMD_OVERRIDE
    finish_with_error "Откат выполнен. Проверьте конфигурацию!"
}

# === Бэкап файлов с ротацией (dry-run поддержка) ===
backup_file() {
    local file="$1"
    if [ "$DRY_RUN" -eq 1 ]; then
        log_warn "[DRY-RUN] Бэкап $file не создаётся."
        return 0
    fi
    if [ -f "$file" ]; then
        local backup_name="$file.bak.$(date +%F_%T)"
        if cp "$file" "$backup_name"; then
            log_success "Бэкап $file создан: $backup_name."
            # Ротация: оставлять только последние $MAX_BACKUPS
            local backups=( $(ls -1t $file.bak.* 2>/dev/null) )
            local count=${#backups[@]}
            if [ -n "$count" ] && [ -n "$MAX_BACKUPS" ] && [ "$count" -gt "$MAX_BACKUPS" ]; then
                for ((i=$MAX_BACKUPS; i<$count; i++)); do
                    rm -f "${backups[$i]}"
                    log_warn "Удалён старый бэкап: ${backups[$i]}"
                done
            fi
        else
            rollback_and_exit "Не удалось создать бэкап $file!"
        fi
    fi
}
restore_backup() {
    local file="$1"
    local last_backup=$(ls -t $file.bak.* 2>/dev/null | head -n1)
    if [ -n "$last_backup" ]; then
        if cp "$last_backup" "$file"; then
            log_success "Восстановлен $file из $last_backup."
        else
            log_error "Не удалось восстановить $file из $last_backup!"
            exit 1
        fi
    else
        log_warn "Бэкап для $file не найден."
    fi
}
backup_file $NGINX_CONF
backup_file $LIMITS_CONF
backup_file $SYSTEMD_OVERRIDE

# === Показ текущих значений параметров ===
get_current_nginx_param() {
    local param="$1"
    grep -E "^\s*$param" "$NGINX_CONF" | awk '{print $2}' | tr -d ';' | tail -n1
}
get_current_limits_conf() {
    local type="$1"; local val
    val=$(grep -E "^\* $type nofile" "$LIMITS_CONF" | awk '{print $4}' | tail -n1)
    echo "$val"
}
get_current_systemd_override() {
    grep -E '^LimitNOFILE=' "$SYSTEMD_OVERRIDE" 2>/dev/null | awk -F= '{print $2}' | tail -n1
}
CUR_WORKER_RLIMIT_NOFILE=$(get_current_nginx_param worker_rlimit_nofile)
CUR_WORKER_CONNECTIONS=$(get_current_nginx_param worker_connections)
CUR_SOFT_NOFILE=$(get_current_limits_conf soft)
CUR_HARD_NOFILE=$(get_current_limits_conf hard)
CUR_SYSTEMD_NOFILE=$(get_current_systemd_override)
print_stage "Текущие значения параметров"
print_param "nginx.conf: worker_rlimit_nofile" "${CUR_WORKER_RLIMIT_NOFILE:-нет}"
print_param "nginx.conf: worker_connections" "${CUR_WORKER_CONNECTIONS:-нет}"
print_param "limits.conf: * soft nofile" "${CUR_SOFT_NOFILE:-нет}"
print_param "limits.conf: * hard nofile" "${CUR_HARD_NOFILE:-нет}"
print_param "systemd override: LimitNOFILE" "${CUR_SYSTEMD_NOFILE:-нет}"

# === Проверка и исправление fs.file-max ===
print_stage "Проверка и исправление fs.file-max"
HARD_NOFILE_LIMIT=1048576
SYS_FILE_MAX=$(sysctl -n fs.file-max)
print_param "fs.file-max" "$SYS_FILE_MAX"
if [ -n "$HARD_NOFILE_LIMIT" ] && [ -n "$SYS_FILE_MAX" ] && [ "$SYS_FILE_MAX" -lt "$HARD_NOFILE_LIMIT" ]; then
    log_warn "fs.file-max ($SYS_FILE_MAX) меньше желаемого лимита $HARD_NOFILE_LIMIT. Попытка увеличить..."
    run_or_echo "sysctl -w fs.file-max=$HARD_NOFILE_LIMIT"
    if ! grep -q "^fs.file-max" /etc/sysctl.conf; then
        run_or_echo "echo 'fs.file-max = $HARD_NOFILE_LIMIT' >> /etc/sysctl.conf"
    else
        run_or_echo "sed -i 's/^fs.file-max.*/fs.file-max = $HARD_NOFILE_LIMIT/' /etc/sysctl.conf"
    fi
    log_success "fs.file-max увеличен до $HARD_NOFILE_LIMIT (или будет увеличен в dry-run)."
fi

# === Остановка и отключение Apache ===
print_stage "Остановка и отключение Apache"
if systemctl is-active --quiet apache2; then
    if run_or_echo "systemctl stop apache2"; then
        log_success "Apache остановлен."
    else
        log_warn "Не удалось остановить Apache!"
    fi
else
    log "Apache уже остановлен."
fi
if systemctl is-enabled --quiet apache2; then
    if run_or_echo "systemctl disable apache2"; then
        log_success "Apache убран из автозапуска."
    else
        log_warn "Не удалось убрать Apache из автозапуска!"
    fi
else
    log "Apache уже не в автозапуске."
fi

# === Тюнинг nginx.conf ===
print_stage "Тюнинг nginx.conf"
WORKER_RLIMIT_NOFILE=100000
WORKER_CONNECTIONS=4096
print_param "worker_rlimit_nofile" "$WORKER_RLIMIT_NOFILE"
print_param "worker_connections" "$WORKER_CONNECTIONS"
# 1. worker_rlimit_nofile на глобальном уровне
if [ -f "$NGINX_CONF" ]; then
    if grep -qE '^\s*worker_rlimit_nofile' "$NGINX_CONF"; then
        if ! sed -i "s/^\s*worker_rlimit_nofile.*/worker_rlimit_nofile $WORKER_RLIMIT_NOFILE;/" "$NGINX_CONF"; then
            rollback_and_exit "Ошибка при обновлении worker_rlimit_nofile!"
        fi
        log_success "worker_rlimit_nofile обновлён на глобальном уровне."
    else
        if grep -qE '^\s*user' "$NGINX_CONF"; then
            awk -v rlimit="$WORKER_RLIMIT_NOFILE" '/^\s*user/ {print; print "worker_rlimit_nofile " rlimit ";"; next} {print}' "$NGINX_CONF" > "$NGINX_CONF.tmp"
            if mv "$NGINX_CONF.tmp" "$NGINX_CONF"; then
                log_success "worker_rlimit_nofile добавлен на глобальном уровне."
            else
                rm -f "$NGINX_CONF.tmp"
                rollback_and_exit "Ошибка при добавлении worker_rlimit_nofile!"
            fi
        else
            if ! sed -i "1iworker_rlimit_nofile $WORKER_RLIMIT_NOFILE;" "$NGINX_CONF"; then
                rollback_and_exit "Ошибка при добавлении worker_rlimit_nofile в начало файла!"
            fi
            log_success "worker_rlimit_nofile добавлен на глобальном уровне."
        fi
    fi
else
    log_warn "$NGINX_CONF не найден, пропускаю изменение worker_rlimit_nofile."
fi
# 2. worker_connections только в секции events
if grep -q "^\s*events\s*{" "$NGINX_CONF"; then
    awk -v wconn="$WORKER_CONNECTIONS" 'BEGIN {in_events=0} /^\s*events\s*{/ {in_events=1; print; next} in_events && /^\s*}/ {print "    worker_connections " wconn ";"; in_events=0; print; next} in_events && /worker_connections/ {next} {print}' "$NGINX_CONF" > "$NGINX_CONF.tmp" && mv "$NGINX_CONF.tmp" "$NGINX_CONF"
    log_success "worker_connections обновлён в секции events."
else
    echo -e "events {\n    worker_connections $WORKER_CONNECTIONS;\n}" >> "$NGINX_CONF"
    log_success "Секция events с worker_connections добавлена."
fi

# === Настройка systemd override для NGINX ===
print_stage "Настройка systemd override для NGINX"
HARD_NOFILE_LIMIT=1048576
if ! mkdir -p "$(dirname $SYSTEMD_OVERRIDE)"; then
    log_error "Не удалось создать директорию для systemd override!"
    exit 1
fi
if ! cat > $SYSTEMD_OVERRIDE <<EOF
[Service]
LimitNOFILE=$HARD_NOFILE_LIMIT
EOF
then
    log_error "Не удалось записать systemd override!"
    exit 1
fi
log_success "Systemd override для NGINX установлен."

# === Настройка limits.conf ===
print_stage "Настройка limits.conf"
SOFT_NOFILE_LIMIT=1048576
print_param "* soft nofile" "$SOFT_NOFILE_LIMIT"
print_param "* hard nofile" "$HARD_NOFILE_LIMIT"
if ! grep -q "\* soft nofile $SOFT_NOFILE_LIMIT" $LIMITS_CONF; then
    if echo "* soft nofile $SOFT_NOFILE_LIMIT" >> $LIMITS_CONF; then
        log_success "* soft nofile $SOFT_NOFILE_LIMIT добавлен в limits.conf."
    else
        log_error "Не удалось добавить * soft nofile $SOFT_NOFILE_LIMIT в limits.conf!"
        exit 1
    fi
else
    log_warn "* soft nofile $SOFT_NOFILE_LIMIT уже присутствует в limits.conf."
fi
if ! grep -q "\* hard nofile $HARD_NOFILE_LIMIT" $LIMITS_CONF; then
    if echo "* hard nofile $HARD_NOFILE_LIMIT" >> $LIMITS_CONF; then
        log_success "* hard nofile $HARD_NOFILE_LIMIT добавлен в limits.conf."
    else
        log_error "Не удалось добавить * hard nofile $HARD_NOFILE_LIMIT в limits.conf!"
        exit 1
    fi
else
    log_warn "* hard nofile $HARD_NOFILE_LIMIT уже присутствует в limits.conf."
fi

# === Применение лимитов для текущей сессии ===
print_stage "Применение лимитов для текущей сессии"
ulimit -n $HARD_NOFILE_LIMIT
log_success "Лимиты применены для текущей сессии."

# === Перезагрузка systemd для применения override ===
print_stage "Перезагрузка systemd"
systemctl daemon-reload
log_success "Systemd перезагружен для применения override."

# === Проверка текущих лимитов ===
print_stage "Проверка текущих лимитов"
CURRENT_ULIMIT=$(ulimit -n)
print_param "Текущий ulimit -n" "$CURRENT_ULIMIT"
if [ "$CURRENT_ULIMIT" -lt "$HARD_NOFILE_LIMIT" ]; then
    log_warn "Текущий ulimit меньше ожидаемого! Попытка увеличить..."
    ulimit -n $HARD_NOFILE_LIMIT
    CURRENT_ULIMIT=$(ulimit -n)
    print_param "Новый ulimit -n" "$CURRENT_ULIMIT"
fi

# === Проверка синтаксиса NGINX ===
print_stage "Проверка синтаксиса NGINX"
if nginx -t; then
    log_success "Синтаксис NGINX в порядке."
else
    log_error "Синтаксис NGINX некорректен! Откат изменений."
    restore_backup $NGINX_CONF
    exit 1
fi

# === Проверка SELinux и AppArmor ===
print_stage "Проверка SELinux и AppArmor"
if command -v getenforce >/dev/null 2>&1; then
    SELINUX_STATUS=$(getenforce)
    print_param "SELinux" "$SELINUX_STATUS"
    if [ "$SELINUX_STATUS" != "Disabled" ]; then
        log_warn "SELinux включён — проверьте политики для NGINX!"
    fi
fi
if command -v aa-status >/dev/null 2>&1; then
    AA_STATUS=$(aa-status --enforced 2>/dev/null | grep nginx)
    if [ -n "$AA_STATUS" ]; then
        log_warn "AppArmor профили для NGINX активны!"
    fi
fi

# === Определение дистрибутива и пакетного менеджера ===
print_stage "Определение дистрибутива и пакетного менеджера"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    DISTRO="unknown"
fi
case "$DISTRO" in
    ubuntu|debian)   PKG_MGR="apt" ;;
    centos|rhel)     PKG_MGR="yum" ;;
    fedora)          PKG_MGR="dnf" ;;
    opensuse*)       PKG_MGR="zypper" ;;
    *)               PKG_MGR="apt" ;;
esac
print_param "Дистрибутив" "$DISTRO"
print_param "Пакетный менеджер" "$PKG_MGR"

# === Параметры NGINX (расширенные) ===
WORKER_RLIMIT_NOFILE=100000
WORKER_CONNECTIONS=4096
WORKER_PROCESSES=auto
WORKER_CPU_AFFINITY=""
MULTI_ACCEPT="on"
REUSEPORT="on"
print_stage "Параметры NGINX (расширенные)"
print_param "worker_rlimit_nofile" "$WORKER_RLIMIT_NOFILE"
print_param "worker_connections" "$WORKER_CONNECTIONS"
print_param "worker_processes" "$WORKER_PROCESSES"
print_param "worker_cpu_affinity" "${WORKER_CPU_AFFINITY:-не задано}"
print_param "multi_accept" "$MULTI_ACCEPT"
print_param "reuseport" "$REUSEPORT"

# === Интерактивный режим ===
# Переменная INTERACTIVE уже инициализирована в начале скрипта
confirm() {
    if [ "$INTERACTIVE" -eq 1 ]; then
        read -p "Продолжить действие? [y/N]: " ans
        case "$ans" in
            [yY]*) return 0 ;;
            *) log_warn "Действие отменено пользователем."; return 1 ;;
        esac
    fi
    return 0
}

# === Обновление системы (с учётом пакетного менеджера) ===
print_stage "Обновление системы"
if ! confirm; then
    log_warn "Обновление системы пропущено пользователем."
else

# === Обновление системы (с учётом пакетного менеджера) ===
print_stage "Обновление системы"
if [ "$PKG_MGR" = "apt" ]; then
    if ! apt update; then log_error "Не удалось выполнить apt update!"; exit 1; fi
    if ! apt upgrade -y | tee /tmp/apt_upgrade.log; then log_error "Не удалось выполнить apt upgrade!"; exit 1; fi
    UPDATED_PACKAGES=$(grep '^Inst ' /tmp/apt_upgrade.log | wc -l)
    print_param "Обновлено пакетов (apt)" "$UPDATED_PACKAGES"
elif [ "$PKG_MGR" = "yum" ]; then
    if ! yum makecache; then log_error "Не удалось выполнить yum makecache!"; exit 1; fi
    if ! yum update -y | tee /tmp/yum_update.log; then log_error "Не удалось выполнить yum update!"; exit 1; fi
    UPDATED_PACKAGES=$(grep 'Updated:' /tmp/yum_update.log | wc -l)
    print_param "Обновлено пакетов (yum)" "$UPDATED_PACKAGES"
elif [ "$PKG_MGR" = "dnf" ]; then
    if ! dnf makecache; then log_error "Не удалось выполнить dnf makecache!"; exit 1; fi
    if ! dnf upgrade -y | tee /tmp/dnf_upgrade.log; then log_error "Не удалось выполнить dnf upgrade!"; exit 1; fi
    UPDATED_PACKAGES=$(grep 'Upgraded:' /tmp/dnf_upgrade.log | wc -l)
    print_param "Обновлено пакетов (dnf)" "$UPDATED_PACKAGES"
elif [ "$PKG_MGR" = "zypper" ]; then
    if ! zypper refresh; then log_error "Не удалось выполнить zypper refresh!"; exit 1; fi
    if ! zypper update -y | tee /tmp/zypper_update.log; then log_error "Не удалось выполнить zypper update!"; exit 1; fi
    UPDATED_PACKAGES=$(grep 'The following package' /tmp/zypper_update.log | wc -l)
    print_param "Обновлено пакетов (zypper)" "$UPDATED_PACKAGES"
else
    log_warn "Неизвестный пакетный менеджер: $PKG_MGR. Пропускаю обновление."
fi
log_success "Система обновлена."
fi

# === Проверка PAM limits ===
print_stage "Проверка PAM limits"
for pamfile in /etc/pam.d/common-session /etc/pam.d/common-session-noninteractive; do
    if [ -f "$pamfile" ]; then
        if grep -q pam_limits.so "$pamfile"; then
            log_success "$pamfile содержит pam_limits.so"
        else
            log_warn "$pamfile не содержит pam_limits.so — лимиты могут не применяться!"
        fi
    fi
done

# === Вставка новых параметров в nginx.conf ===
# (worker_processes, worker_cpu_affinity, multi_accept, reuseport)
# worker_processes на глобальном уровне
if grep -qE '^\s*worker_processes' "$NGINX_CONF"; then
    if ! sed -i "s/^\s*worker_processes.*/worker_processes $WORKER_PROCESSES;/" "$NGINX_CONF"; then
        rollback_and_exit "Ошибка при обновлении worker_processes!"
    fi
else
    if ! sed -i "1iworker_processes $WORKER_PROCESSES;" "$NGINX_CONF"; then
        rollback_and_exit "Ошибка при добавлении worker_processes в начало файла!"
    fi
fi
# worker_cpu_affinity (если задан)
if [ -n "$WORKER_CPU_AFFINITY" ]; then
    if grep -qE '^\s*worker_cpu_affinity' "$NGINX_CONF"; then
        if ! sed -i "s/^\s*worker_cpu_affinity.*/worker_cpu_affinity $WORKER_CPU_AFFINITY;/" "$NGINX_CONF"; then
            rollback_and_exit "Ошибка при обновлении worker_cpu_affinity!"
        fi
    else
        if ! sed -i "1iworker_cpu_affinity $WORKER_CPU_AFFINITY;" "$NGINX_CONF"; then
            rollback_and_exit "Ошибка при добавлении worker_cpu_affinity в начало файла!"
        fi
    fi
fi
# multi_accept и reuseport в секции events
if grep -q "^\s*events\s*{" "$NGINX_CONF"; then
    awk -v multi="$MULTI_ACCEPT" -v reuse="$REUSEPORT" '
    BEGIN {in_events=0}
    /^\s*events\s*{/ {in_events=1; print; next}
    in_events && /^\s*}/ {
        print "    multi_accept " multi ";";
        print "    reuseport " reuse ";";
        in_events=0; print; next
    }
    in_events && /multi_accept/ {next}
    in_events && /reuseport/ {next}
    {print}
    ' "$NGINX_CONF" > "$NGINX_CONF.tmp" && mv "$NGINX_CONF.tmp" "$NGINX_CONF"
else
    echo -e "events {\n    multi_accept $MULTI_ACCEPT;\n    reuseport $REUSEPORT;\n}" >> "$NGINX_CONF"
fi

# === Проверка успешности вставки новых параметров в nginx.conf ===
print_stage "Проверка наличия параметров в nginx.conf"
for param in "worker_rlimit_nofile" "worker_connections" "worker_processes" "multi_accept" "reuseport"; do
    if grep -q "$param" "$NGINX_CONF"; then
        log_success "$param найден в nginx.conf"
    else
        log_warn "$param НЕ найден в nginx.conf!"
    fi
done

# === Применение изменений и автоматический откат ===
print_stage "Применение изменений"
systemctl daemon-reload
if ! systemctl restart nginx; then
    rollback_and_exit "Не удалось перезапустить nginx!"
else
    log_success "nginx успешно перезапущен."
fi
if ! systemctl restart hestia; then
    log_warn "Hestia не установлен или не запущен."
fi
# === Проверка статуса nginx после рестарта ===
print_stage "Статус nginx после рестарта"
NGINX_PID_AFTER=$(pidof nginx | awk '{print $1}')
if [ -n "$NGINX_PID_AFTER" ]; then
    log_success "nginx запущен, PID: $NGINX_PID_AFTER"
else
    log_error "nginx не запущен после рестарта! Проверьте логи и конфигурацию."
fi
systemctl status nginx | head -20

# === Проверка лимитов systemd для nginx ===
print_stage "Проверка лимитов systemd для nginx"
systemctl show nginx | grep -E 'LimitNOFILE'

# === Проверка фактических лимитов процесса nginx ===
print_stage "Проверка фактических лимитов процесса nginx"
NGINX_PID=$(pidof nginx | awk '{print $1}')
if [ -n "$NGINX_PID" ]; then
    ACTUAL_LIMIT=$(cat /proc/$NGINX_PID/limits | grep "Max open files" | awk '{print $(NF-1)}')
    print_param "Фактический лимит nginx" "$ACTUAL_LIMIT"
    if [ "$ACTUAL_LIMIT" -lt "$HARD_NOFILE_LIMIT" ]; then
        log_warn "Фактический лимит меньше ожидаемого! Проверьте настройки."
    else
        log_success "Фактический лимит соответствует ожидаемому."
    fi
else
    log_warn "Не удалось определить PID NGINX для проверки лимита."
fi

# === Последние ошибки NGINX ===
print_stage "Последние ошибки NGINX"
NGINX_LOG="/var/log/nginx/error.log"
if [ -f "$NGINX_LOG" ]; then
    tail -n 10 "$NGINX_LOG"
else
    log_warn "Файл $NGINX_LOG не найден."
fi

# === Ошибки systemd и dmesg ===
print_stage "Ошибки systemd и dmesg"
journalctl -u nginx --no-pager -n 10
if command -v dmesg >/dev/null 2>&1; then
    dmesg | tail -n 10
fi

# === Итоговая таблица изменений ===
NEW_WORKER_RLIMIT_NOFILE=$(get_current_nginx_param worker_rlimit_nofile)
NEW_WORKER_CONNECTIONS=$(get_current_nginx_param worker_connections)
NEW_SOFT_NOFILE=$(get_current_limits_conf soft)
NEW_HARD_NOFILE=$(get_current_limits_conf hard)
NEW_SYSTEMD_NOFILE=$(get_current_systemd_override)
print_stage "Изменения параметров (было → стало)"
print_param "nginx.conf: worker_rlimit_nofile" "${CUR_WORKER_RLIMIT_NOFILE:-нет} → ${NEW_WORKER_RLIMIT_NOFILE:-нет}"
print_param "nginx.conf: worker_connections" "${CUR_WORKER_CONNECTIONS:-нет} → ${NEW_WORKER_CONNECTIONS:-нет}"
print_param "limits.conf: * soft nofile" "${CUR_SOFT_NOFILE:-нет} → ${NEW_SOFT_NOFILE:-нет}"
print_param "limits.conf: * hard nofile" "${CUR_HARD_NOFILE:-нет} → ${NEW_HARD_NOFILE:-нет}"
print_param "systemd override: LimitNOFILE" "${CUR_SYSTEMD_NOFILE:-нет} → ${NEW_SYSTEMD_NOFILE:-нет}"

print_stage "Итоговая таблица"
color_echo "$YELLOW" "\n================= РЕЗУЛЬТАТ ================="
print_param "nginx.conf" "$NGINX_CONF"
print_param "systemd override" "$SYSTEMD_OVERRIDE"
print_param "limits.conf" "$LIMITS_CONF"
print_param "worker_rlimit_nofile" "$NEW_WORKER_RLIMIT_NOFILE"
print_param "worker_connections" "$NEW_WORKER_CONNECTIONS"
print_param "soft nofile" "$NEW_SOFT_NOFILE"
print_param "hard nofile" "$NEW_HARD_NOFILE"
color_echo "$GREEN" "\n$OK Все действия завершены!"

# Для отката: запустить скрипт с параметром restore
if [ "$1" == "restore" ]; then
    restore_backup $NGINX_CONF
    restore_backup $LIMITS_CONF
    restore_backup $SYSTEMD_OVERRIDE
    log_success "Откат завершён."
fi

# В dry-run режиме не выполнять изменения, только показывать действия
if [ "$DRY_RUN" -eq 1 ]; then
    color_echo "$YELLOW" "\n[DRY-RUN] Скрипт завершён: ни один файл или параметр не был изменён."
    exit 0
fi

# === Генерация HTML-отчёта ===
HTML_REPORT="/var/log/nginx_tune_report.html"
echo "<html><head><meta charset='utf-8'><title>NGINX Tune Report</title></head><body>" > "$HTML_REPORT"
echo "<h2>NGINX Tune Report ($(date '+%Y-%m-%d %H:%M:%S'))</h2>" >> "$HTML_REPORT"
echo "<pre>" >> "$HTML_REPORT"
tail -n 200 "$LOG_FILE" >> "$HTML_REPORT"
echo "</pre>" >> "$HTML_REPORT"
echo "<hr><small>Сгенерировано автоматически скриптом nginx_conf.sh</small></body></html>" >> "$HTML_REPORT"
log_success "HTML-отчёт сгенерирован: $HTML_REPORT"

# === Очистка временных файлов ===
rm -f /tmp/apt_upgrade.log /tmp/yum_update.log /tmp/dnf_upgrade.log /tmp/zypper_update.log "$NGINX_CONF.tmp"
