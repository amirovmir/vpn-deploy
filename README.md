# vpn-deploy

Автодеплой VPN-контейнера на удалённый Linux-сервер через SSH.

## Требования

- **Windows**: PuTTY установлен в `C:\Program Files\PuTTY\` (нужны `plink.exe` и `pscp.exe`)
- **Сервер**: Ubuntu 20.04+ или Debian 11+, root-доступ, открытый порт 443

## Использование

```powershell
cd vpn-deploy

# Базовый запуск
.\deploy.ps1 -IP 1.2.3.4 -User root -Password "yourpassword"

# С явным указанием SSH-порта и протокола
.\deploy.ps1 -IP 1.2.3.4 -User root -Password "yourpassword" -Port 22 -Protocol vless-reality
```

## Что происходит при запуске

1. Проверка наличия plink.exe / pscp.exe
2. Тест SSH-соединения
3. Установка Docker на сервер (пропускается если уже есть)
4. Создание `/opt/vpn/xray/` на сервере
5. Загрузка конфигов и скриптов
6. Генерация x25519-ключей и UUID прямо на сервере через Docker
7. Запись `config.json` и старт контейнера (`docker compose up -d`)
8. Вывод VLESS-ссылки для импорта в клиент

## Пример вывода

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  VPN DEPLOY COMPLETE

  Protocol : VLESS + Reality
  Server   : 1.2.3.4:443
  SNI      : ads.x5.ru

  VLESS URI:
  vless://xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx@1.2.3.4:443?security=reality&sni=ads.x5.ru&fp=chrome&pbk=<key>&sid=<id>&flow=xtls-rprx-vision&type=tcp#vpn-deploy

  Import into: v2rayN (Win) · Shadowrocket (iOS)
               Hiddify · NekoBox (Android)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Повторный запуск

Скрипт идемпотентен: Docker не переустанавливается, но **ключи генерируются заново**. Существующие клиенты потеряют соединение и должны будут импортировать новый URI.

## Добавление нового протокола

Создать директорию `protocols/<name>/` с четырьмя файлами:

```
protocols/<name>/
├── generate-keys.sh        # выводит JSON с ключами
├── config.template.json    # шаблон с @@PLACEHOLDERS@@
├── docker-compose.yml      # один сервис
└── build-uri.ps1           # функция Build-VlessUri (или аналог)
```

Запуск: `.\deploy.ps1 -IP ... -Protocol <name>`

## Структура

```
vpn-deploy/
├── deploy.ps1
├── scripts/
│   └── setup-docker.sh
└── protocols/
    └── vless-reality/
        ├── generate-keys.sh
        ├── config.template.json
        ├── docker-compose.yml
        └── build-uri.ps1
```
