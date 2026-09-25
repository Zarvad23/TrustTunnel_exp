# TrustTunnel_exp

Полностью автоматическая установка **TrustTunnel Endpoint** на чистый Ubuntu/Debian VPS.

Скрипт повторяет весь путь от обновления системы до готовых клиентских профилей:

1. `apt update` + `full-upgrade`.
2. Установка необходимых пакетов.
3. Определение публичного IPv4 сервера.
4. Установка официального TrustTunnel Endpoint.
5. Настройка через официальный `setup_wizard` в non-interactive режиме.
6. Self-signed ECDSA сертификат TrustTunnel.
7. Три отдельных пользователя:
   - `Vadim_PC`
   - `Vadim_laptop`
   - `Vadim_phone`
8. Автозапуск через `systemd`.
9. UFW: текущий SSH-порт + `8443/tcp` + `8443/udp`.
10. Проверка TCP/UDP 8443.
11. Генерация отдельных `tt://?` deep-link и QR-кодов для всех трёх устройств.

По умолчанию используется TrustTunnel **v1.1.0** и порт **8443/TCP+UDP**. Порт выбран как рабочий вариант для сетей, где TrustTunnel-трафик на 443 может не проходить. При необходимости порт можно переопределить переменной `TT_PORT`.

## Запуск на чистом сервере

Если `curl` уже есть:

```bash
curl -fsSL https://raw.githubusercontent.com/Zarvad23/TrustTunnel_exp/main/install.sh | sudo bash
```

Если на совсем минимальном образе нет `curl`:

```bash
sudo apt-get update -y && sudo apt-get install -y curl && curl -fsSL https://raw.githubusercontent.com/Zarvad23/TrustTunnel_exp/main/install.sh | sudo bash
```

После запуска больше ничего вводить не требуется.

## Что получится

Основные конфиги:

```text
/opt/trusttunnel/vpn.toml
/opt/trusttunnel/hosts.toml
/opt/trusttunnel/credentials.toml
/opt/trusttunnel/rules.toml
/opt/trusttunnel/certs/cert.pem
/opt/trusttunnel/certs/key.pem
```

Клиентские данные:

```text
/root/trusttunnel-clients/links.txt

/root/trusttunnel-clients/Vadim_PC.link
/root/trusttunnel-clients/Vadim_laptop.link
/root/trusttunnel-clients/Vadim_phone.link

/root/trusttunnel-clients/Vadim_PC.png
/root/trusttunnel-clients/Vadim_laptop.png
/root/trusttunnel-clients/Vadim_phone.png
```

`links.txt` содержит для каждого устройства логин, пароль и готовую `tt://?` ссылку.

QR-коды создаются **локально на VPS**. Deep-link с паролем не отправляется на сторонние QR-сайты.

## Посмотреть ссылки и QR позже

```bash
sudo tt-clients
```

Команда покажет содержимое `links.txt` и выведет три сканируемых QR-кода прямо в SSH-терминал.

Только ссылки:

```bash
sudo cat /root/trusttunnel-clients/links.txt
```

## Проверка сервиса

```bash
systemctl status trusttunnel --no-pager
ss -lntup | grep ':8443'
sudo ufw status
```

## Повторный запуск

Если `/opt/trusttunnel` или каталог клиентских профилей уже существуют, скрипт не удаляет их безвозвратно — он переносит их в каталог с суффиксом `.backup.YYYYMMDD-HHMMSS`, после чего делает чистую установку.

## Важно

`tt://?` deep-link содержит данные авторизации и, при self-signed сертификате, данные сертификата. Файлы `links.txt`, `*.link` и QR-коды нужно хранить как пароли.

Если после `full-upgrade` системе требуется перезагрузка, скрипт сначала полностью закончит настройку TrustTunnel и сохранит профили, а затем сообщит, что можно выполнить:

```bash
reboot
```


## Другой порт

По умолчанию используется `8443`. При необходимости можно указать другой порт без редактирования скрипта:

```bash
curl -fsSL https://raw.githubusercontent.com/Zarvad23/TrustTunnel_exp/main/install.sh | sudo TT_PORT=9443 bash
```
