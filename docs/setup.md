# Развёртывание: вариант 4

Домен kv.devops.local -> 192.168.56.101 в hosts Windows. ВМ devops-vm, devops, SSH 2222, вход только по ключу. Docker 29.9.3, Compose 5.7.1. Перед началом создан снимок 06-before-kr2, ufw status numbered сохранён в /home/devops/ufw-before-kr2.txt.

Доставка из корня репозитория (сначала --dry-run):
```bash
rsync -avz --delete --exclude=.env --exclude=.git --chmod=D755,F644 ./ devops:kr2/
```
На сервере, от devops:
```bash
cd ~/kr2
umask 077
# Только если .env ещё не существует:
printf 'REDIS_PASSWORD=%s\n' "$(openssl rand -hex 16)" > .env
chmod 600 .env
unset REDIS_PASSWORD
docker compose up -d --build --wait
```
Не экспортировать REDIS_PASSWORD в оболочку: значение для подстановки Compose должно совпасть с env_file. Не выводить compose config или inspect без фильтрации: аргументы Redis содержат пароль.

Сертификат и Nginx:
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/kr2.key -out /etc/ssl/certs/kr2.crt -subj '/CN=kv.devops.local' -addext 'subjectAltName=DNS:kv.devops.local'
sudo chmod 600 /etc/ssl/private/kr2.key
sudo chmod 644 /etc/ssl/certs/kr2.crt
sudo install -m 644 config/nginx/kr2 /etc/nginx/sites-available/kr2
sudo ln -s /etc/nginx/sites-available/kr2 /etc/nginx/sites-enabled/kr2
sudo nginx -t && sudo systemctl reload nginx
```
Конфигурация старого сайта и UFW не меняются. Публичный kr2.crt копируется на хост по проверенному SSH; закрытый ключ остаётся в /etc/ssl/private.

Проверки: /health без Redis — ok; UID 999; CMD exec; docker stop 0.643 секунды. При добавлении комментария слой pip CACHED. Приложение и Redis работают с UID 999. Redis без пароля NOAUTH. DNS redis разрешается общей backend-сетью. Опубликован только 127.0.0.1:8004; Redis не опубликован. После down без -v счётчик 7 -> 8, контейнер сменился. Том kr2_redis_data смонтирован в /data, AOF включён.

HTTP 301; без доверия TLS exit 60; с --cacert exit 0. /whoami показывает scheme:https, client:192.168.56.1, host:kv.devops.local. Это IP Windows, переданный Nginx через X-Real-IP; TCP peer приложения — прокси/bridge. Старые / и /app/ работают. Внешний запрос к 8004 истекает по таймауту. Ключ root600, .env devops600. Пароль не найден в других доставленных файлах.

Расширенный scripts/audit.sh: 19 PASS/0 FAIL. Redis определяется через compose ps -q redis. Ошибка публикации 0.0.0.0:8004 даёт 18 PASS/1 FAIL и exit 1; восстановление 127.0.0.1 возвращает exit 0. Аудит следует запускать через sudo bash, поскольку проверки SSH/UFW требуют прав root.

Диагностическая тренировка (не реальная неисправность от преподавателя): остановленный app -> HTTPS 502, nginx error.log connect() failed (111), Redis healthy. Восстановление compose up -d --wait без перезагрузки и отката.

Основная ветка содержит небезопасную восстановленную базу. Рабочая версия — kr2/variant-4. Pull Request оставлен без слияния до защиты, как требует задание.
