# Архитектурная схема draw.io
https://drive.google.com/file/d/1jkdG6npx083bXfbXucCAbcDcR6uehXKM/view?usp=sharing




# Запуск 
chmod +x scripts/setup.sh
./scripts/setup.sh (docker-compose down -v && ./scripts/setup.sh)

# Шардированный кластер MongoDB с FastAPI

Этот проект демонстрирует настройку шардированного кластера MongoDB с приложением FastAPI для доступа к данным. Кластер состоит из:
- 2 шардов (каждый с 2 репликами для чтения)
- 3 конфигурационных серверов
- 3 роутеров (mongos)
- Приложение FastAPI для доступа к данным

## Предварительные требования

- Установленные Docker и Docker Compose
- Доступные порты 27017-27023, 28017-28019 и 8080
- Bash shell

## Структура проекта

```
.
├── api_app/
│   ├── app.py              # Приложение FastAPI
│   └── Dockerfile          # Конфигурация контейнера API
├── scripts/
│   ├── setup.sh            # Основной скрипт настройки
│   └── mongo-init.sh       # Скрипт инициализации данных
├── compose.yaml            # Конфигурация Docker Compose
└── README.md              # Этот файл
```

## Быстрый старт

1. Клонируйте репозиторий:
```bash
git clone <url-репозитория>
cd <имя-репозитория>
```

2. Сделайте скрипт настройки исполняемым:
```bash
chmod +x scripts/setup.sh
```

3. Запустите скрипт настройки:
```bash
./scripts/setup.sh
```

Скрипт выполнит:
- Проверку предварительных требований (Docker, порты)
- Запуск всех контейнеров
- Инициализацию кластера MongoDB
- Настройку шардирования
- Вставку тестовых данных
- Проверку настройки

## Ручная настройка

Если вы предпочитаете настраивать вручную, выполните следующие шаги:

1. Запустите контейнеры:
```bash
docker-compose up -d
```

2. Инициализируйте replica set конфигурационного сервера:
```bash
docker exec -it config1 mongosh --port 27019 --eval '
    rs.initiate({
        _id: "configReplSet",
        members: [
            {_id: 0, host: "config1:27019"},
            {_id: 1, host: "config2:27019"},
            {_id: 2, host: "config3:27019"}
        ]
    })
'
```

3. Инициализируйте replica set шардов:
```bash
docker exec -it shard1 mongosh --port 27018 --eval '
    rs.initiate({
        _id: "shard1",
        members: [
            {_id: 0, host: "shard1:27018"},
            {_id: 1, host: "shard1_replica1:27020"},
            {_id: 2, host: "shard1_replica2:27021"}
        ]
    })
'

docker exec -it shard2 mongosh --port 27018 --eval '
    rs.initiate({
        _id: "shard2",
        members: [
            {_id: 0, host: "shard2:27018"},
            {_id: 1, host: "shard2_replica1:27022"},
            {_id: 2, host: "shard2_replica2:27023"}
        ]
    })
'
```

4. Добавьте шарды в кластер:
```bash
docker exec -it mongos1 mongosh --eval '
    sh.addShard("shard1/shard1:27018");
    sh.addShard("shard2/shard2:27018")
'
```

5. Включите шардирование и создайте шардированную коллекцию:
```bash
docker exec -it mongos1 mongosh --eval '
    sh.enableSharding("somedb");
    sh.shardCollection("somedb.users", { "_id": "hashed" })
'
```

6. Инициализируйте тестовые данные:
```bash
docker cp scripts/mongo-init.sh mongos1:/mongo-init.sh
docker exec mongos1 bash /mongo-init.sh
```

## Доступ к кластеру

- API: http://localhost:8080
- Роутеры MongoDB: localhost:28017, localhost:28018, localhost:28019
- Конфигурационные серверы: localhost:27019
- Шарды: 
  - Shard1: localhost:27018 (primary), localhost:27020, localhost:27021 (replicas)
  - Shard2: localhost:27018 (primary), localhost:27022, localhost:27023 (replicas)

## API Endpoints

- `GET /`: Статус кластера и распределение шардов
- `GET /users/count`: Общее количество пользователей
- `GET /users/users/{name}`: Получить пользователя по имени

## Мониторинг распределения шардов

Вы можете отслеживать распределение шардов через:
1. API endpoint: http://localhost:8080/
2. Прямой запрос к MongoDB:
```bash
docker exec -it mongos1 mongosh --eval 'sh.status()'
```

## Проверка реплик

Для проверки статуса реплик:
```bash
# Проверка реплик shard1
docker exec -it shard1_replica1 mongosh --port 27020 --eval 'rs.status()'

# Проверка реплик shard2
docker exec -it shard2_replica1 mongosh --port 27022 --eval 'rs.status()'
```

## Устранение неполадок

1. Если порты уже используются:
   - Остановите все запущенные экземпляры MongoDB
   - Проверьте другие сервисы, использующие требуемые порты
   - При необходимости измените маппинг портов в compose.yaml

2. Если контейнеры не запускаются:
   - Проверьте логи Docker: `docker-compose logs`
   - Убедитесь в достаточности системных ресурсов
   - Проверьте сетевое подключение

3. Если шардирование не работает:
   - Проверьте статус конфигурационного сервера
   - Проверьте replica set шардов
   - Убедитесь в правильности сетевого подключения между компонентами

## Очистка

Чтобы остановить и удалить все контейнеры:
```bash
docker-compose down -v
```

