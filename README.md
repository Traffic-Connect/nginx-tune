# NGINX Tune & Limits Automation Script

🚀 **Автоматизированный Bash-скрипт для настройки лимитов, оптимизации и безопасного управления параметрами NGINX на Linux.**

## 📋 Возможности

### 🔧 Основные функции
- **Автоматическая настройка лимитов** (worker_rlimit_nofile, limits.conf, systemd override)
- **Оптимизация параметров NGINX** (worker_connections, worker_processes, multi_accept, reuseport)
- **Резервное копирование и ротация бэкапов** (автоматическое удаление старых бэкапов)
- **Безопасный откат изменений** с восстановлением из бэкапов
- **Dry-run и интерактивный режим** для безопасного тестирования
- **Проверка окружения, прав, зависимостей** перед выполнением

### 🌐 Поддержка дистрибутивов
- **Debian/Ubuntu** (apt)
- **CentOS/RHEL** (yum)
- **Fedora** (dnf)
- **openSUSE** (zypper)

### 📊 Мониторинг и отчётность
- **Генерация HTML-отчёта** с подробной информацией
- **Подробная визуализация этапов** с цветным выводом
- **Проверка фактических лимитов** процесса nginx
- **Диагностика открытых файлов** и производительности

## ⚠️ Важные требования

### Системные требования
- **bash >= 4.x**
- **root-права** для изменения системных файлов
- **Необходимые утилиты**: awk, grep, sed, systemctl, tail, chmod, chown, rm, mv, cp, tee

### 🔄 Критически важно: Перезагрузка после настройки

**После выполнения скрипта ОБЯЗАТЕЛЬНО выполните перезагрузку сервера!**

```bash
# После успешного выполнения скрипта
reboot
```

**Почему это необходимо:**
- Изменения в `/etc/security/limits.conf` применяются только при новом логине
- systemd override может не примениться полностью без перезагрузки
- PAM-контекст обновляется только после полной перезагрузки
- Без перезагрузки `ulimit -n` может остаться на старом значении

**Проверка после перезагрузки:**
```bash
# Проверьте лимиты
ulimit -n                    # Должно быть 1048576
cat /proc/$(pidof nginx | awk '{print $1}')/limits | grep "Max open files"

# Проверьте статус nginx
systemctl status nginx
nginx -t
```

## 🚀 Установка и запуск

### Быстрая установка
```bash
# Скачайте скрипт
wget https://raw.githubusercontent.com/Traffic-Connect/nginx-tune/main/nginx_conf.sh

# Сделайте исполняемым
chmod +x nginx_conf.sh

# Запустите с правами root
sudo bash nginx_conf.sh
```

### Рекомендуемый запуск
```bash
# 1. Сначала тестовый запуск (dry-run)
sudo bash nginx_conf.sh --dry-run

# 2. Если всё выглядит правильно, запустите с интерактивным режимом
sudo bash nginx_conf.sh --interactive

# 3. После успешного выполнения ПЕРЕЗАГРУЗИТЕ СЕРВЕР
reboot
```

## 📖 Примеры использования

### Базовые команды
```bash
# Полная настройка с интерактивным режимом
sudo bash nginx_conf.sh --interactive

# Только просмотр изменений без применения
sudo bash nginx_conf.sh --dry-run

# Откат последних изменений
sudo bash nginx_conf.sh --rollback

# Запуск без цветного вывода
sudo bash nginx_conf.sh --no-color
```

### Комбинированные режимы
```bash
# Dry-run с интерактивным режимом
sudo bash nginx_conf.sh --dry-run --interactive

# Отключение цветов для логов
sudo bash nginx_conf.sh --no-color --interactive
```

## 🔧 Настраиваемые параметры

### Лимиты файлов
- **worker_rlimit_nofile**: 100000 → 1048576
- **systemd LimitNOFILE**: 1048576
- **limits.conf soft/hard nofile**: 1048576

### Параметры NGINX
- **worker_connections**: 1024 → 4096
- **worker_processes**: auto
- **multi_accept**: on
- **reuseport**: on

### Системные лимиты
- **fs.file-max**: автоматически увеличивается до 1048576
- **ulimit -n**: устанавливается в 1048576 для текущей сессии

## 📁 Изменяемые файлы

### Основные конфигурационные файлы
- `/etc/nginx/nginx.conf` - основная конфигурация NGINX
- `/etc/security/limits.conf` - системные лимиты
- `/etc/systemd/system/nginx.service.d/override.conf` - systemd override

### Логи и отчёты
- `/var/log/nginx_tune.log` - подробный лог выполнения
- `/var/log/nginx_tune_report.html` - HTML-отчёт
- `/etc/nginx/nginx.conf.bak.*` - бэкапы конфигурации

## 🔍 Диагностика и мониторинг

### Проверка лимитов
```bash
# Проверка лимитов текущей сессии
ulimit -n

# Проверка лимитов процесса nginx
cat /proc/$(pidof nginx | awk '{print $1}')/limits | grep "Max open files"

# Проверка systemd override
systemctl show nginx | grep LimitNOFILE
```

### Проверка статуса
```bash
# Статус nginx
systemctl status nginx

# Тест конфигурации
nginx -t

# Количество открытых файлов
lsof -p $(pidof nginx | awk '{print $1}') | wc -l
```

## 🛡️ Безопасность и откат

### Автоматические бэкапы
- **Автоматическое создание** бэкапов перед изменениями
- **Ротация бэкапов** (сохраняются только последние 5)
- **Временные метки** в именах файлов

### Откат изменений
```bash
# Автоматический откат при ошибках
# Скрипт автоматически восстанавливает файлы из бэкапов

# Ручной откат
sudo bash nginx_conf.sh --rollback
```

## 📊 Результаты оптимизации

### До оптимизации
- **worker_connections**: 1024
- **worker_rlimit_nofile**: 65535
- **ulimit -n**: 1024
- **systemd LimitNOFILE**: не настроено

### После оптимизации
- **worker_connections**: 4096 (в 4 раза больше)
- **worker_rlimit_nofile**: 1048576 (в 16 раз больше)
- **ulimit -n**: 1048576 (в 1024 раза больше)
- **systemd LimitNOFILE**: 1048576

## ⚡ Производительность

### Ожидаемые улучшения
- **Увеличение пропускной способности** на 300-400%
- **Снижение ошибок "Too many open files"** до нуля
- **Улучшение стабильности** при высоких нагрузках
- **Оптимизация использования ресурсов**

## 🐛 Устранение неполадок

### Частые проблемы

**1. Ошибка "Too many open files" после выполнения скрипта**
```bash
# Решение: ПЕРЕЗАГРУЗИТЕ СЕРВЕР
reboot

# После перезагрузки проверьте
ulimit -n
```

**2. NGINX не запускается после изменений**
```bash
# Проверьте синтаксис
nginx -t

# Если ошибки - откатите изменения
sudo bash nginx_conf.sh --rollback
```

**3. Лимиты не применяются**
```bash
# Проверьте systemd override
systemctl show nginx | grep LimitNOFILE

# Перезагрузите systemd
systemctl daemon-reload
systemctl restart nginx
```

## 📞 Поддержка

### Обратная связь
- **Issues**: [GitHub Issues](https://github.com/Traffic-Connect/nginx-tune/issues)
- **Bug reports**: создавайте issue с подробным описанием
- **Feature requests**: предлагайте новые функции

### Логи для диагностики
При возникновении проблем приложите:
- `/var/log/nginx_tune.log`
- `/var/log/nginx_tune_report.html`
- Вывод команды `nginx -t`
- Вывод команды `systemctl status nginx`

## 📄 Лицензия

Этот проект распространяется под лицензией MIT. См. файл LICENSE для подробностей.

---

## 🎯 Быстрый старт

```bash
# 1. Скачайте и запустите
wget https://raw.githubusercontent.com/Traffic-Connect/nginx-tune/main/nginx_conf.sh
chmod +x nginx_conf.sh
sudo bash nginx_conf.sh --interactive

# 2. ПЕРЕЗАГРУЗИТЕ СЕРВЕР
reboot

# 3. Проверьте результат
ulimit -n
nginx -t
systemctl status nginx
```

**Удачной оптимизации! 🚀** 
