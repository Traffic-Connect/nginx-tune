# nginx-tune

Автоматизированный Bash-скрипт для настройки лимитов, оптимизации и безопасного управления параметрами NGINX на Linux.

## Возможности
- Автоматическая настройка лимитов (worker_rlimit_nofile, limits.conf, systemd override)
- Резервное копирование и ротация бэкапов
- Безопасный откат изменений
- Dry-run и интерактивный режим
- Проверка окружения, прав, зависимостей
- Поддержка разных дистрибутивов (apt/yum/dnf/zypper)
- Генерация HTML-отчёта
- Подробная визуализация этапов

## Требования
- bash >= 4.x
- awk, grep, sed, systemctl, tail, chmod, chown, rm, mv, cp, tee
- root-права для изменения системных файлов

## Установка
Скачайте скрипт:
```bash
wget https://raw.githubusercontent.com/Traffic-Connect/nginx-tune/main/nginx_conf.sh
chmod +x nginx_conf.sh
```

## Примеры запуска
```bash
sudo bash nginx_conf.sh --interactive
sudo bash nginx_conf.sh --dry-run
sudo bash nginx_conf.sh --rollback
```

## Аргументы
- `--dry-run`      — только показать, что будет сделано
- `--interactive`  — спрашивать подтверждение перед действиями
- `--no-color`     — отключить цветной вывод
- `--rollback`     — откатить последние изменения из бэкапов

## Рекомендации
- Перед запуском убедитесь, что у вас есть резервные копии важных данных.
- Используйте dry-run для предварительного просмотра изменений.
- Для отката изменений используйте `--rollback`.

## Обратная связь
Вопросы, баги и предложения — через [issues](https://github.com/Traffic-Connect/nginx-tune/issues) на GitHub. 
