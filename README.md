# Task Manager API

REST API сервис для управления задачами, построенный на .NET 8 с использованием Clean Architecture.

## Оглавление

- [Описание проекта](#описание-проекта)
- [Технологический стек](#технологический-стек)
- [Архитектура проекта](#архитектура-проекта)
- [Модель данных](#модель-данных)
- [Быстрый старт](#быстрый-старт)
- [Запуск после клонирования с GitHub](#запуск-после-клонирования-с-github)
- [API Endpoints](#api-endpoints)
- [Основная сущность для масштабирования](#основная-сущность-для-масштабирования)
- [Сложные SQL-запросы](#сложные-sql-запросы)
- [Генерация данных](#генерация-данных)
- [Индексы (ЛР №1)](#индексы-лр-1)
- [Рост данных (ЛР №2)](#рост-данных-лр-2)
- [Партиционирование (ЛР №3)](#партиционирование-лр-3)
- [Масштабирование чтения (ЛР №4)](#масштабирование-чтения-лр-4)
- [Шардирование (ЛР №5)](#шардирование-лр-5)
- [Аутентификация и авторизация](#аутентификация-и-авторизация)
- [Кэширование](#кэширование)
- [Мониторинг и метрики](#мониторинг-и-метрики)
- [Тестирование](#тестирование)
- [Конфигурация](#конфигурация)
- [Troubleshooting](#troubleshooting)

---

## Описание проекта

Task Manager API — это полнофункциональный CRUD-сервис для управления задачами с поддержкой:

- **Управления пользователями** с ролевой моделью (Admin/User)
- **Проектов** с возможностью добавления участников
- **Задач** с приоритетами, статусами и сроками выполнения
- **Тегов** для категоризации задач
- **Связи many-to-many** между задачами и тегами, пользователями и проектами

---

## Технологический стек

| Компонент | Технология | Версия |
|-----------|------------|--------|
| Фреймворк | .NET | 8.0 |
| База данных | PostgreSQL | 16 |
| Кэширование | Redis | 7 |
| ORM | Entity Framework Core | 8.0 |
| Микро-ORM | Dapper | 2.1 |
| Миграции БД | Liquibase | 4.25 |
| Аутентификация | JWT Bearer + API Key | - |
| Логирование | Serilog | 8.0 |
| Метрики | prometheus-net | 8.2 |
| Визуализация | Grafana | 10.2 |
| Документация | Swagger/OpenAPI | - |
| Тестирование | xUnit + Moq + FluentAssertions | - |
| Rate Limiting | AspNetCoreRateLimit | 5.0 |

---

## Архитектура проекта

Проект построен на принципах **Clean Architecture** с чётким разделением на слои:

```
TaskManager/
├── src/
│   ├── TaskManager.API/              # Презентационный слой (Web API)
│   │   ├── Controllers/              # REST контроллеры
│   │   ├── Middleware/               # Middleware (ошибки, логирование, идемпотентность)
│   │   ├── Auth/                     # Обработчики аутентификации
│   │   └── Program.cs                # Точка входа и конфигурация DI
│   │
│   ├── TaskManager.Application/      # Слой бизнес-логики
│   │   ├── DTOs/                     # Data Transfer Objects
│   │   │   ├── Auth/                 # DTO для аутентификации
│   │   │   ├── Tasks/                # DTO для задач
│   │   │   ├── Projects/             # DTO для проектов
│   │   │   ├── Tags/                 # DTO для тегов
│   │   │   ├── Users/                # DTO для пользователей
│   │   │   └── Common/               # Общие DTO (ApiError, ApiResponse)
│   │   ├── Services/                 # Реализации сервисов
│   │   ├── Interfaces/               # Интерфейсы сервисов и репозиториев
│   │   ├── Exceptions/               # Пользовательские исключения
│   │   └── Common/                   # Общие классы (PagedResult)
│   │
│   ├── TaskManager.Domain/           # Доменный слой
│   │   ├── Entities/                 # Доменные сущности
│   │   │   ├── User.cs               # Пользователь
│   │   │   ├── TaskItem.cs           # Задача
│   │   │   ├── Project.cs            # Проект
│   │   │   ├── Tag.cs                # Тег
│   │   │   ├── TaskTag.cs            # Связь задача-тег (M:M)
│   │   │   ├── UserProject.cs        # Связь пользователь-проект (M:M)
│   │   │   ├── ApiKey.cs             # API ключ
│   │   │   └── IdempotencyKey.cs     # Ключ идемпотентности
│   │   └── Enums/                    # Перечисления
│   │       ├── UserRole.cs           # Роли пользователей
│   │       ├── TaskItemStatus.cs     # Статусы задач
│   │       ├── TaskPriority.cs       # Приоритеты задач
│   │       └── ProjectRole.cs        # Роли в проекте
│   │
│   └── TaskManager.Infrastructure/   # Слой инфраструктуры
│       ├── Data/                     # Работа с данными
│       │   ├── AppDbContext.cs       # EF Core контекст
│       │   └── Configurations/       # Fluent API конфигурации
│       ├── Repositories/             # Реализации репозиториев
│       │   ├── BaseRepository.cs     # Базовый репозиторий (EF Core)
│       │   ├── TaskTagRepository.cs  # Репозиторий с Dapper
│       │   └── ...                   # Остальные репозитории
│       └── Services/                 # Инфраструктурные сервисы
│           └── RedisCacheService.cs  # Сервис кэширования
│
├── tests/
│   └── TaskManager.Tests/            # Unit-тесты
│       └── Repositories/             # Тесты репозиториев
│
├── docker/
│   ├── liquibase/                    # Миграции базы данных
│   │   ├── db.changelog-master.xml   # Главный changelog
│   │   └── changesets/               # Отдельные миграции
│   ├── prometheus/                   # Конфигурация Prometheus
│   └── grafana/                      # Дашборды и источники данных
│
├── scripts/
│   ├── generate-data.sql             # Массовая генерация тестовых данных
│   ├── lab-01/                       # Скрипты экспериментов ЛР №1 (индексы)
│   ├── lab-02/                       # Скрипты экспериментов ЛР №2 (рост данных)
│   ├── lab-03/                       # Скрипты экспериментов ЛР №3 (партиционирование)
│   ├── lab-04/                       # Скрипты экспериментов ЛР №4 (Primary + Replica)
│   └── lab-05/                       # Скрипты экспериментов ЛР №5 (шардирование)
│
├── docs/
│   ├── lab-01-indexes.md             # Отчёт по ЛР №1
│   ├── lab-02-growth.md              # Отчёт по ЛР №2
│   ├── lab-03-partitioning.md        # Отчёт по ЛР №3
│   ├── lab-04-read-scaling.md        # Отчёт по ЛР №4
│   ├── lab-05-sharding.md            # Отчёт по ЛР №5
│   └── lab-0N/results/               # Сырые результаты EXPLAIN ANALYZE
│
├── Dockerfile                        # Образ API
└── docker-compose.yml                # Весь проект в Docker
```

### Принципы архитектуры

1. **Разделение ответственности**: Каждый слой имеет чётко определённую роль
2. **Инверсия зависимостей**: Высокоуровневые модули не зависят от низкоуровневых
3. **Единый формат ответов**: Все API ответы обёрнуты в `ApiResponse<T>`
4. **Асинхронность**: Все операции I/O выполняются асинхронно

---

## Модель данных

### ER-диаграмма

```
┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│   Users     │       │   Projects  │       │    Tags     │
├─────────────┤       ├─────────────┤       ├─────────────┤
│ Id (PK)     │       │ Id (PK)     │       │ Id (PK)     │
│ Username    │◄──────┤ Name        │       │ Name        │
│ Email       │   M:M │ Description │       │ Color       │
│ PasswordHash│       │ CreatedAt   │       │ CreatedAt   │
│ Role        │       │ UpdatedAt   │       └──────┬──────┘
│ CreatedAt   │       └──────┬──────┘              │
│ UpdatedAt   │              │                     │ M:M
└──────┬──────┘              │                     │
       │                     │               ┌─────┴─────┐
       │ 1:M           1:M   │               │ TaskTags  │
       │                     │               ├───────────┤
       ▼                     ▼               │ TaskId    │
┌──────────────────────────────────┐         │ TagId     │
│            Tasks                 │◄────────┘           
├──────────────────────────────────┤
│ Id (PK)                          │
│ Title                            │
│ Description                      │
│ Status (Pending/InProgress/...)  │
│ Priority (Low/Medium/High/...)   │
│ DueDate                          │
│ UserId (FK)                      │
│ ProjectId (FK, nullable)         │
│ CreatedAt                        │
│ UpdatedAt                        │
└──────────────────────────────────┘

┌─────────────────┐
│  UserProjects   │  (M:M связь Users-Projects)
├─────────────────┤
│ UserId (FK)     │
│ ProjectId (FK)  │
│ Role            │
│ JoinedAt        │
└─────────────────┘
```

### Статусы задач

| Значение | Описание |
|----------|----------|
| Pending | Ожидает выполнения |
| InProgress | В процессе |
| Completed | Завершена |
| Cancelled | Отменена |

### Приоритеты задач

| Значение | Описание |
|----------|----------|
| Low | Низкий |
| Medium | Средний |
| High | Высокий |
| Critical | Критический |

---

## Быстрый старт

### Предварительные требования

- [Docker](https://www.docker.com/get-started) и Docker Compose v2
- (Опционально, для разработки) [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0), Visual Studio 2022 или VS Code

### 1. Запуск всего проекта одной командой

```bash
cd TaskManager
docker compose up -d --build
```

Будут запущены:
- **PostgreSQL** — порт 5432 (логин: taskmanager, пароль: taskmanager_password)
- **Liquibase** — автоматически применит миграции и завершится
- **API** — порт 5000, стартует после успешного применения миграций
- **Redis** — порт 6379
- **Prometheus** — порт 9090
- **Grafana** — порт 3000 (логин: admin, пароль: admin)

### 2. (Опционально) Запуск API локально для отладки

```bash
docker compose stop api        # освободить порт 5000
cd src/TaskManager.API
dotnet run
```

### 3. Доступные URL

| Сервис | URL |
|--------|-----|
| API | http://localhost:5000 |
| Swagger UI | http://localhost:5000/swagger |
| Health Check | http://localhost:5000/health |
| PostgreSQL Primary | localhost:5432 |
| PostgreSQL Replica (только чтение) | localhost:5433 |
| PostgreSQL шарды задач 0–2 (3 — профиль `scale`) | localhost:5440–5443 |
| Prometheus Metrics | http://localhost:5000/metrics |
| Prometheus UI | http://localhost:9090 |
| Grafana | http://localhost:3000 |

---

## Запуск после клонирования с GitHub

### Требования к системе

Перед началом убедитесь, что установлено:

| Компонент | Версия | Проверка | Ссылка для скачивания |
|-----------|--------|----------|----------------------|
| **Docker Desktop** | 4.0+ | `docker --version` | [docker.com/get-started](https://www.docker.com/get-started) |
| **.NET 8 SDK** | 8.0+ | `dotnet --version` | [dotnet.microsoft.com](https://dotnet.microsoft.com/download/dotnet/8.0) |
| **Git** | 2.0+ | `git --version` | [git-scm.com](https://git-scm.com/downloads) |

> ⚠️ **Важно:** Необходим именно **Docker Desktop** (не просто Docker Engine), так как используется `host.docker.internal` для связи между контейнерами и хост-машиной.

### Пошаговая инструкция

#### Шаг 1: Клонирование репозитория

```bash
git clone https://github.com/UsachovaUlyana/TaskManager.git
cd TaskManager
```

#### Шаг 2: Запуск проекта

```bash
docker compose up -d --build
```

Первая сборка образа API занимает пару минут. Проверить статус контейнеров:

```bash
docker compose ps -a
```

Ожидаемый результат — все контейнеры в статусе `Up` (кроме liquibase, который завершится после миграций):

```
NAME                     STATUS
taskmanager-postgres     Up (healthy)
taskmanager-redis        Up (healthy)
taskmanager-api          Up
taskmanager-prometheus   Up
taskmanager-grafana      Up
taskmanager-liquibase    Exited (0)   ← это нормально!
```

#### Шаг 3: (Опционально) Генерация большого объёма данных

См. раздел [Генерация данных](#генерация-данных).

#### Шаг 4: Проверка работоспособности

Откройте браузер и перейдите по адресам:

| Сервис | URL | Ожидаемый результат |
|--------|-----|---------------------|
| Swagger UI | http://localhost:5000/swagger | Документация API |
| Health Check | http://localhost:5000/health | `Healthy` |
| Prometheus | http://localhost:9090 | Web-интерфейс Prometheus |
| Grafana | http://localhost:3000 | Логин: `admin` / `admin` |

### Быстрый тест API

1. **Регистрация пользователя** — в Swagger выполните `POST /api/auth/register`:
   ```json
   {
     "username": "testuser",
     "email": "test@example.com",
     "password": "Password123!"
   }
   ```

2. **Получение токена** — выполните `POST /api/auth/login`:
   ```json
   {
     "username": "testuser",
     "password": "Password123!"
   }
   ```

3. **Авторизация в Swagger** — нажмите кнопку "Authorize" и введите:
   ```
   Bearer <скопированный_токен>
   ```
   > ⚠️ Не забудьте префикс `Bearer ` (с пробелом после)!

4. **(Опционально) Генерация API Key** — выполните `POST /api/auth/api-key`:
   ```json
   {
     "name": "Test Key",
     "expirationDays": 30
   }
   ```
   Скопируйте `apiKey` из ответа и используйте в **Authorize → ApiKey**.

5. **Создание задачи** — выполните `POST /api/tasks`:
   ```json
   {
     "title": "Моя первая задача",
     "description": "Описание задачи",
     "priority": "High",
     "status": "Pending"
   }
   ```

### Остановка проекта

```bash
# Остановить API (в терминале где запущен)
Ctrl+C

# Остановить Docker контейнеры
docker-compose down

# Остановить и удалить данные (БД, кэш)
docker-compose down -v
```

---

## API Endpoints

### Аутентификация (`/api/auth`)

| Метод | Endpoint | Описание | Авторизация |
|-------|----------|----------|-------------|
| POST | `/api/auth/register` | Регистрация нового пользователя | Нет |
| POST | `/api/auth/login` | Вход и получение JWT токена | Нет |
| POST | `/api/auth/api-key` | Генерация API ключа | JWT |

### Задачи (`/api/tasks`)

| Метод | Endpoint | Описание | Авторизация |
|-------|----------|----------|-------------|
| GET | `/api/tasks` | Получить список задач (с пагинацией и фильтрацией) | JWT/ApiKey |
| GET | `/api/tasks/stats` | Количество задач и просроченных задач по статусам (`GROUP BY`) | JWT/ApiKey |
| GET | `/api/tasks/{id}` | Получить задачу по ID | JWT/ApiKey |
| POST | `/api/tasks` | Создать задачу | JWT/ApiKey |
| PUT | `/api/tasks/{id}` | Обновить задачу | JWT/ApiKey |
| DELETE | `/api/tasks/{id}` | Удалить задачу | JWT (Admin/Owner) |

**Параметры фильтрации для GET /api/tasks:**
- `status` — фильтр по статусу (Pending, InProgress, Completed, Cancelled)
- `priority` — фильтр по приоритету (Low, Medium, High, Critical)
- `projectId` — фильтр по проекту
- `dueDateFrom` — минимальная дата выполнения
- `dueDateTo` — максимальная дата выполнения
- `page` — номер страницы (по умолчанию 1)
- `pageSize` — размер страницы (по умолчанию 10)
- `sort` — сортировка: `created_at`, `due_date`, `priority`, `title`; минус перед полем — по убыванию (по умолчанию `-created_at`, сначала новые)

Те же параметры принимают `GET /api/projects/{id}/tasks` и `GET /api/users/{id}/tasks`.

### Проекты (`/api/projects`)

| Метод | Endpoint | Описание | Авторизация |
|-------|----------|----------|-------------|
| GET | `/api/projects` | Получить список проектов | JWT/ApiKey |
| GET | `/api/projects/{id}` | Получить проект по ID | JWT/ApiKey |
| GET | `/api/projects/{id}/tasks` | Задачи проекта (фильтры, сортировка, пагинация) | JWT/ApiKey (участник проекта) |
| POST | `/api/projects` | Создать проект | JWT/ApiKey |
| PUT | `/api/projects/{id}` | Обновить проект | JWT/ApiKey |
| DELETE | `/api/projects/{id}` | Удалить проект | JWT (Admin) |
| POST | `/api/projects/{id}/members` | Добавить участника | JWT/ApiKey |
| DELETE | `/api/projects/{id}/members/{userId}` | Удалить участника | JWT/ApiKey |

### Теги (`/api/tags`)

| Метод | Endpoint | Описание | Авторизация |
|-------|----------|----------|-------------|
| GET | `/api/tags` | Получить список тегов | JWT/ApiKey |
| GET | `/api/tags/{id}` | Получить тег по ID | JWT/ApiKey |
| POST | `/api/tags` | Создать тег | JWT/ApiKey |
| PUT | `/api/tags/{id}` | Обновить тег | JWT/ApiKey |
| DELETE | `/api/tags/{id}` | Удалить тег | JWT (Admin) |

### Пользователи (`/api/users`) — только для Admin

| Метод | Endpoint | Описание | Авторизация |
|-------|----------|----------|-------------|
| GET | `/api/users` | Получить список пользователей | JWT (Admin) |
| GET | `/api/users/{id}` | Получить пользователя по ID | JWT (Admin) |
| GET | `/api/users/{id}/tasks` | Задачи пользователя (фильтры, сортировка, пагинация) | JWT (Admin) |
| POST | `/api/users` | Создать пользователя | JWT (Admin) |
| DELETE | `/api/users/{id}` | Удалить пользователя | JWT (Admin) |

---

## Основная сущность для масштабирования

**Основная сущность для масштабирования:** `tasks`

**Почему она подходит:** задачи — самая «горячая» таблица сервиса. Пользователи, проекты и теги создаются редко, а задачи — постоянно: у каждого пользователя их десятки и сотни, у активных — тысячи, и после завершения они не удаляются (история нужна для статистики). Таблица растёт вместе с числом пользователей и временем, через неё проходят все основные запросы (список задач с фильтрами и пагинацией, статистика по статусам). У неё есть `created_at` — ключ для будущего партиционирования по времени — и `user_id` — естественный ключ шардирования.

## Сложные SQL-запросы

Все запросы ниже выполняет сам сервис. Текст запросов EF Core снят из лога PostgreSQL (`docs/lab-01/results/part2-01-captured-sql.txt`); список колонок сокращён.

**JOIN 1. Страница задач пользователя** — `GET /api/tasks`, `TaskRepository.GetByUserIdAsync`: задачи, проект и теги (M:M через `task_tags`).

```sql
SELECT t0.*, p.*, t1.*
FROM (
    SELECT t.* FROM tasks AS t
    WHERE t.user_id = $1                      -- + фильтры status / priority / project_id / due_date
    ORDER BY t.created_at DESC
    LIMIT $2 OFFSET $3
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id
ORDER BY t0.created_at DESC, t0.id, p.id, t1.task_id, t1.tag_id;
```

**JOIN 2. Все задачи с автором** — `GET /api/tasks` для Admin и API Key, `TaskRepository.GetAllFilteredAsync`: тот же запрос без условия на `user_id` и с `INNER JOIN users AS u ON t0.user_id = u.id`.

**JOIN 3. Теги задачи** — `TaskTagRepository.GetTagsByTaskIdAsync` (Dapper):

```sql
SELECT t.id, t.name, t.color, t.created_at AS CreatedAt
FROM tags t
INNER JOIN task_tags tt ON t.id = tt.tag_id
WHERE tt.task_id = @TaskId;
```

**Агрегация. Количество задач по статусам** — `GET /api/tasks/stats`, `TaskRepository.GetStatusStatsAsync`:

```sql
SELECT t.status, count(*)::int AS "Count",
       count(*) FILTER (WHERE t.due_date < $1 AND t.status IN (0, 1))::int AS "OverdueCount"
FROM tasks AS t
WHERE t.user_id = $2                          -- только для обычного пользователя
GROUP BY t.status
ORDER BY t.status;
```

Кроме того, каждая страница `GET /api/tasks` сопровождается `SELECT count(*) FROM tasks WHERE …` для пагинации.

## Генерация данных

Небольшой набор данных для проверки API создаётся через Swagger (`POST /api/auth/register`, `POST /api/tasks`). Для экспериментов с производительностью есть SQL-генератор:

```bash
docker compose up -d
docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -f /scripts/generate-data.sql
```

По умолчанию создаётся 10 000 пользователей, 1 000 проектов, 50 тегов, ~20 000 связей пользователь–проект, 1 000 000 задач и ~800 000 связей задача–тег (около 2.5 минут). Объёмы задаются переменными psql:

```bash
docker compose exec -T postgres psql -U taskmanager -d taskmanager_db \
  -v users=100000 -v tasks=5000000 -f /scripts/generate-data.sql
```

- повторный запуск дописывает задачи, не дублируя пользователей, проекты и теги;
- логины `gen_user_1` … `gen_user_N` и администратор `gen_admin`, пароль у всех `Password123!`;
- задачи распределены по пользователям неравномерно, как в реальном сервисе: `gen_user_1` получает ~1% всех задач (≈10 000), типичный пользователь — около сотни;
- статусы: Pending 20%, InProgress 20%, Completed 55%, Cancelled 5%; приоритеты: Low 30%, Medium 40%, High 22%, Critical 8%.

> В Git Bash на Windows перед командой с путём `/scripts/...` добавьте `MSYS_NO_PATHCONV=1`, иначе путь будет искажён.

## Индексы (ЛР №1)

Отчёт с планами выполнения до и после — [docs/lab-01-indexes.md](docs/lab-01-indexes.md); он же оформлен по ГОСТ 7.32-2017 — [docs/lab-01-report.docx](docs/lab-01-report.docx) ([PDF](docs/lab-01-report.pdf)).

Изменения схемы вносятся миграциями Liquibase и применяются автоматически при `docker compose up`:

| Миграция | Что делает | Зачем |
|---|---|---|
| `009-create-tasks-created-at-indexes.xml` | создаёт `idx_tasks_user_id_created_at (user_id, created_at DESC)` и `idx_tasks_created_at (created_at DESC)`, удаляет избыточный `idx_tasks_user_id` | `GET /api/tasks` всегда сортирует по `created_at DESC`: страница администратора 118 ms → 0.55 ms, страница активного пользователя 3.8 ms → 0.35 ms (1 млн задач) |
| `010-drop-duplicate-indexes.xml` | удаляет 7 индексов, дублирующих UNIQUE-ограничения и первичные ключи | меньше работы при каждой записи, −32 MB |

Повторить эксперименты:

```bash
bash scripts/lab-01/run-all.sh             # часть 1: тестовая БД lab01, результаты в docs/lab-01/results
bash scripts/lab-01/part2-capture-sql.sh   # часть 2: SQL из лога PostgreSQL и время ответа API
docker compose exec -T postgres psql -U taskmanager -d taskmanager_db < scripts/lab-01/part2-explain.sql
```

## Рост данных (ЛР №2)

Отчёт — [docs/lab-02-growth.md](docs/lab-02-growth.md); он же по ГОСТ 7.32-2017 — [docs/lab-02-report.docx](docs/lab-02-report.docx) ([PDF](docs/lab-02-report.pdf)).

![Запись терминала: 10 млн строк, поиск без индекса и с индексом, агрегация за год](docs/lab-02/demo.gif)

| Изменение | Зачем |
|---|---|
| Миграция `011-create-tasks-created-at-due-date-index.xml`: индекс `(created_at DESC)` заменён на `(created_at DESC, due_date)` | `GET /api/tasks?dueDateFrom=…&dueDateTo=…` на 5 млн задач: 2.8 s → 18.6 ms |
| `TaskService`: даты фильтра приводятся к UTC | фильтр по сроку без часового пояса возвращал 500 |
| `docker-compose.yml`: `shm_size: 512mb` у postgres | параллельному `VACUUM` на 10 млн строк не хватало 64 MB `/dev/shm` |
| `scripts/generate-data.sql` можно запускать повторно | таблицу `tasks` можно растить ступенями: `-v tasks=4000000` |

Для списка задач по срокам используйте `?sort=due_date` — 0.5 ms на любом объёме.

Повторить эксперименты:

```bash
bash scripts/lab-02/run-part-a.sh            # часть A: таблица lab02.events до 10 млн строк (~3 мин, ~1.5 ГБ на диске)
RESET=1 bash scripts/lab-02/run-part-b.sh    # часть B: tasks 100 тыс. → 1 млн → 5 млн (RESET=1 удаляет все задачи!)
vhs scripts/lab-02/demo.tape                 # запись терминала (нужны vhs, ttyd, ffmpeg)
```

## Партиционирование (ЛР №3)

Отчёт — [docs/lab-03-partitioning.md](docs/lab-03-partitioning.md); он же по ГОСТ 7.32-2017 — [docs/lab-03-report.docx](docs/lab-03-report.docx) ([PDF](docs/lab-03-report.pdf)).

![Запись терминала: сбой ночной задачи партиций, alert в Telegram, восстановление и recovery](docs/lab-03/demo.gif)

| Изменение | Зачем |
|---|---|
| Миграция `012-partition-tasks-by-created-at.xml`: `tasks` → RANGE-партиции по месяцу `created_at`, первичный ключ `(id, created_at)`, в `task_tags` колонка `task_created_at` и составной внешний ключ | запросы за период читают 1 партицию из 30: неделя + статус на 5 млн задач 297 ms → 3.8 ms |
| Фильтр `createdFrom` / `createdTo` в `GET /api/tasks` | запрос по ключу партиционирования |
| `PartitionMaintenanceWorker`: job создаёт партиции на горизонт + 1 период при старте и в 01:00 UTC, проверка — каждые 5 минут | партиции для новых данных всегда есть |
| `GET /api/partitions`, `POST /api/partitions/ensure`, `POST /api/partitions/check` (Admin), `GET /health/partitions` | состояние, ручной запуск job и проверки, мониторинг |
| Alert в Telegram и миграция `013` (таблица `partition_alert_state`) | один alert на проблему и recovery после исправления |

Таблицы и горизонт — секция `Partitioning` в `appsettings.json`. Для alert в Telegram скопируйте `.env.example` в `.env` и укажите `TELEGRAM_BOT_TOKEN` (от @BotFather) и `TELEGRAM_CHAT_ID`, затем `docker compose up -d`. Файл `.env` в `.gitignore`; без него alert только пишется в лог API.

Повторить эксперименты:

```bash
bash scripts/lab-03/run-sql-part.sh                    # части 1–9: RANGE, LIST, HASH на таблицах схемы lab03
bash scripts/lab-03/run-service-part.sh before         # часть 12: запросы к tasks до миграции 012
bash scripts/lab-03/run-service-part.sh after          # … и после неё (+ EXPLAIN реальных запросов API)
powershell -File scripts/lab-03/demo-alert.ps1         # части 10–11: сбой, alert, восстановление, recovery
vhs scripts/lab-03/demo.tape                           # запись терминала
```

## Масштабирование чтения (ЛР №4)

Отчёт — [docs/lab-04-read-scaling.md](docs/lab-04-read-scaling.md); он же по ГОСТ 7.32-2017 — [docs/lab-04-report.docx](docs/lab-04-report.docx) ([PDF](docs/lab-04-report.pdf)).

![Запись терминала: Primary и Replica, streaming replication, read-only и replication lag](docs/lab-04/demo.gif)

| Изменение | Зачем |
|---|---|
| `docker-compose.yml`: второй PostgreSQL `postgres-replica` на порту 5433 и общий `docker/postgres/pg_hba.conf` | Primary принимает запись, Replica — копия только для чтения |
| `docker/postgres/replica-entrypoint.sh` | при первом запуске реплика сама создаёт роль и слот репликации, снимает копию `pg_basebackup` и стартует в режиме standby |
| `ReplicaDbContext`, `ITaskReadRepository`, `TaskReadRepository` | `GET /api/tasks` и `GET /api/tasks/stats` читают с Replica; запись и чтение сразу после записи — с Primary |
| `GET /api/replication` (Admin), `GET /health/replica` | состояние streaming replication и отставание реплики в байтах WAL и секундах |

Измерения: задержка репликации без нагрузки 120–270 мс, под массовым `UPDATE` — до 30 MB неприменённого WAL. Разделение читающей нагрузки между двумя серверами по 4 ядра дало 869 запросов в секунду против 271 на одном сервере; на общих ядрах хоста прироста нет.

Повторить эксперименты:

```bash
docker compose up -d                                   # Primary, Replica, миграции, API
bash scripts/lab-04/run-all.sh                         # части 1–6 и опыты по пропускной способности
powershell -File scripts/lab-04/demo-replication.ps1   # репликация, read-only, replication lag
vhs scripts/lab-04/demo.tape                           # запись терминала
```

---

## Шардирование (ЛР №5)

Отчёт — [docs/lab-05-sharding.md](docs/lab-05-sharding.md); он же по ГОСТ 7.32-2017 — [docs/lab-05-report.docx](docs/lab-05-report.docx) ([PDF](docs/lab-05-report.pdf)).

![Запись терминала: шардирование задач по user_id, hash % N и consistent hashing](docs/lab-05/demo.gif)

Задачи шардируются по `user_id` между независимыми PostgreSQL `postgres-shard-0…2`; четвёртый `postgres-shard-3` запускается профилем `scale` для опыта с добавлением шарда. Пользователи, проекты и топология шардов (`shard_topology`, миграция 014) остаются в основной базе.

| Изменение | Зачем |
|---|---|
| `ModuloShardRouter`, `ConsistentHashRouter` (hash ring с виртуальными узлами) | router: по `user_id` выбирает шард |
| `ShardPlanner` | распределение ключей и расчёт переноса данных при изменении числа шардов |
| `ShardedTaskStore`, `ShardingService`, `ShardsController` | загрузка задач на шарды через `COPY`, чтение и запись через router, настоящий перенос данных |
| `GET /api/shards`, `…/route/{userId}`, `…/users/{userId}/tasks`, `POST …/load`, `…/rebalance`, `GET …/simulate/…` | работа с шардами (роль Admin) |

Измерения на 1 млн задач: при переходе 3 → 4 шарда `hash % N` переносит 75.3 % задач, consistent hashing — 24–27 %, и только на новый шард. Настоящий перенос на четвёртый PostgreSQL совпал с расчётом: 273 461 задача за 8 секунд.

Повторить эксперименты (нужны `curl` и `jq`):

```bash
docker compose up -d                                   # основная база, шарды 0–2, API
bash scripts/lab-05/run-all.sh                         # задания 2–7 и настоящий перенос данных
powershell -File scripts/lab-05/demo-sharding.ps1      # демонстрация: шарды, router, сравнение стратегий
vhs scripts/lab-05/demo.tape                           # запись терминала
```

---

## Аутентификация и авторизация

### JWT Bearer Token

Получение токена:

```http
POST /api/auth/login
Content-Type: application/json

{
  "username": "user@example.com",
  "password": "password123"
}
```

Использование токена:

```http
GET /api/tasks
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### API Key

Альтернативный способ аутентификации для сервис-to-сервис взаимодействия.

**Генерация API Key через Swagger:**

1. Авторизуйтесь через JWT (см. выше)
2. Выполните `POST /api/auth/api-key`:
   ```json
   {
     "name": "My API Key",
     "expirationDays": 30
   }
   ```
3. Скопируйте `apiKey` из ответа — он показывается **только один раз!**

**Использование API Key:**

```http
GET /api/tasks
X-Api-Key: tm_ваш_сгенерированный_ключ
```

В Swagger UI нажмите **Authorize** и введите ключ в поле **ApiKey**.

### Матрица авторизации

| Действие | Admin | User | API Key |
|----------|-------|------|---------|
| GET /tasks | Все задачи | Только свои | Все задачи |
| POST /tasks | ✅ | ✅ | ✅ |
| PUT /tasks/{id} | Любая | Только своя | Любая |
| DELETE /tasks/{id} | Любая | Только своя | ❌ |
| GET /users | ✅ | ❌ | ❌ |
| POST /users | ✅ | ❌ | ❌ |
| DELETE /users/{id} | ✅ | ❌ | ❌ |
| GET /projects | Все | Только участвует | Все |
| DELETE /projects/{id} | ✅ | ❌ | ❌ |
| DELETE /tags/{id} | ✅ | ❌ | ❌ |

---

## Кэширование

### Redis Cache

GET-запросы кэшируются в Redis с TTL 5 минут:

- `tasks:list:*` — списки задач
- `tasks:{id}` — отдельные задачи
- `projects:*` — проекты

### Инвалидация кэша

Кэш автоматически инвалидируется при:
- Создании новой сущности (POST)
- Обновлении сущности (PUT)
- Удалении сущности (DELETE)

---

## Мониторинг и метрики

### Prometheus Metrics

Доступны на `/metrics`:

- `http_requests_received_total` — общее количество запросов
- `http_request_duration_seconds` — время выполнения запросов
- `http_requests_in_progress` — текущие запросы

### Grafana Dashboard

Предустановленный дашборд включает:
- График частоты запросов
- Распределение времени ответа (p50, p95)
- Количество ошибок (4xx, 5xx)
- Запросы по методам и статус-кодам

### Health Checks

```http
GET /health
```

Проверяются:
- PostgreSQL — подключение к базе данных
- Redis — подключение к кэшу

```http
GET /health/partitions
```

Есть ли партиции `tasks` и `lab03.events` на текущий период и 3 вперёд (ЛР №3): `200 Healthy` или `503 Unhealthy` со списком отсутствующих. В общий `/health` не входит.

```http
GET /health/replica
```

Состояние реплики (ЛР №4): подключена ли она, находится ли в режиме восстановления и насколько отстала — `lagBytes` и `lagSeconds`.

---

## Тестирование

### Запуск тестов

```bash
cd TaskManager
dotnet test
```

### Покрытие тестами

Репозитории покрыты unit-тестами (48 тестов):

| Репозиторий | Тесты |
|-------------|-------|
| UserRepository | 12 тестов (CRUD, GetByUsername, GetByEmail) |
| TaskRepository | 12 тестов (CRUD, фильтрация, пагинация) |
| ProjectRepository | 12 тестов (CRUD, GetByUserId, IsUserMember) |
| TagRepository | 12 тестов (CRUD, GetByName, GetByIds) |

Логику партиций (ЛР №3) проверяют тесты в `tests/TaskManager.Tests/Partitioning`: планировщик партиций, разбор границ из `pg_get_expr`, политика алертов и сервис целиком на подменённых часах. Разделение чтения и записи между Primary и Replica (ЛР №4) проверяют тесты `TaskServiceTests`. Router'ы шардирования и расчёт переноса данных (ЛР №5) проверяют тесты в `tests/TaskManager.Tests/Sharding`. Всего в проекте 105 тестов.

---

## Конфигурация

### appsettings.json

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=taskmanager_db;Username=taskmanager;Password=taskmanager_password",
    "Redis": "localhost:6379"
  },
  "Jwt": {
    "Key": "YourSecretKeyHere_MinLength32Characters",
    "Issuer": "TaskManager",
    "Audience": "TaskManagerUsers",
    "ExpiresInMinutes": 60
  }
}
```

### Переменные окружения

Можно переопределить через переменные окружения:

| Переменная | Описание |
|------------|----------|
| `ConnectionStrings__DefaultConnection` | Строка подключения к PostgreSQL |
| `ConnectionStrings__Redis` | Строка подключения к Redis |
| `Jwt__Key` | Секретный ключ для JWT |
| `Sharding__Shards__N__ConnectionString` | Строка подключения к шарду задач номер N (ЛР №5) |
| `ConnectionStrings__ReplicaConnection` | Строка подключения к реплике PostgreSQL для чтения; пусто — читаем с Primary |
| `Alerts__Telegram__BotToken` | Токен Telegram-бота для alert о партициях; в Docker — `TELEGRAM_BOT_TOKEN` из `.env` |
| `Alerts__Telegram__ChatId` | Чат для alert; в Docker — `TELEGRAM_CHAT_ID` из `.env` |

---

## Дополнительные функции

### Rate Limiting

Ограничение запросов:
- 100 запросов в минуту
- 1000 запросов в час

При превышении лимита возвращается HTTP 429 (Too Many Requests).

### Idempotency

Для POST-запросов поддерживается идемпотентность через заголовок:

```http
POST /api/tasks
X-Idempotency-Key: unique-request-id-123
```

Повторный запрос с тем же ключом в течение 24 часов вернёт сохранённый ответ.

### Единый формат ответов

**Успешный ответ:**
```json
{
  "success": true,
  "data": { ... },
  "error": null
}
```

**Ответ с ошибкой:**
```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "NOT_FOUND",
    "message": "Task with ID '...' was not found.",
    "details": null,
    "traceId": "0HN9ABCD..."
  }
}
```

### Коды ошибок

| Код | HTTP статус | Описание |
|-----|-------------|----------|
| `NOT_FOUND` | 404 | Ресурс не найден |
| `CONFLICT` | 409 | Конфликт данных (дубликат) |
| `VALIDATION_ERROR` | 400 | Ошибка валидации |
| `UNAUTHORIZED` | 401 | Не авторизован |
| `FORBIDDEN` | 403 | Доступ запрещён |
| `INTERNAL_ERROR` | 500 | Внутренняя ошибка сервера |

---

## Troubleshooting

### Проблема: "Не удается получить доступ к сайту" на localhost:5000

**Причина:** API не запущен или запущен на другом порту.

**Решение:**
1. Убедитесь, что API запущен командой `dotnet run`
2. Проверьте вывод в консоли — там будет указан фактический URL
3. Если порт отличается от 5000, используйте указанный порт

### Проблема: Ошибка подключения к PostgreSQL

**Причина:** Docker контейнер с PostgreSQL не запущен или не готов.

**Решение:**
```bash
# Проверить статус контейнеров
docker-compose ps

# Если postgres не запущен
docker-compose up -d postgres

# Подождать 10-15 секунд и проверить логи
docker-compose logs postgres
```

### Проблема: 401 Unauthorized при использовании токена

**Причина:** Неправильный формат токена в Swagger.

**Решение:**
В поле Authorize вводить токен **с префиксом `Bearer `**:
```
Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```
> Обратите внимание на пробел после слова `Bearer`!

### Проблема: Grafana показывает "No data"

**Причина:** Нет данных метрик или Prometheus не собирает метрики.

**Решение:**
1. Сделайте несколько запросов к API через Swagger
2. Подождите 15-30 секунд (интервал сбора метрик)
3. Проверьте, что API отдает метрики: http://localhost:5000/metrics
4. Проверьте статус target в Prometheus: http://localhost:9090/targets
5. Если target показывает `DOWN`, убедитесь что Docker Desktop запущен


Проверить успешность миграций:
```bash
docker-compose logs liquibase
```

### Проблема: Порт 5432/6379/3000/9090 уже занят

**Решение:**
1. Найти процесс, занимающий порт:
   ```bash
   # Windows PowerShell
   netstat -ano | findstr :5432
   
   # Завершить процесс по PID
   taskkill /PID <pid> /F
   ```

2. Или изменить порты в `docker-compose.yml`:
   ```yaml
   ports:
     - "5433:5432"  # Внешний порт изменен на 5433
   ```

### Проблема: Ошибки при сборке проекта

**Решение:**
```bash
# Очистить и пересобрать
dotnet clean
dotnet restore
dotnet build
```

### Проверка общего состояния системы

```bash
# 1. Проверить Docker
docker --version
docker-compose --version

# 2. Проверить .NET
dotnet --version

# 3. Проверить контейнеры
docker-compose ps

# 4. Проверить логи всех контейнеров
docker-compose logs

# 5. Полный перезапуск
docker-compose down
docker-compose up -d
```

---

## Лицензия

MIT
