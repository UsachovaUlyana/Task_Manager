# Лабораторная работа №4
# Масштабирование чтения PostgreSQL: Primary + Replica

## Среда и воспроизводимость

<!-- caption: Среда выполнения экспериментов -->
| Параметр | Значение |
|---|---|
| СУБД | PostgreSQL 16.14 (`postgres:16-alpine`), два экземпляра в Docker Desktop, Windows 11 |
| Ресурсы Docker | 20 CPU, 10.7 GB памяти на оба контейнера вместе |
| Primary | контейнер `taskmanager-postgres`, порт 5432 |
| Replica | контейнер `taskmanager-postgres-replica`, порт 5433 |
| Репликация | streaming replication, асинхронная, через слот `replica_slot` |
| Сервис | TaskManager: .NET 8, EF Core 8, Dapper, Liquibase, Redis |
| Данные | 1 000 000 задач, 796 872 связи задача–тег, 10 001 пользователь, база 677 MB |

Все эксперименты автоматизированы:

<!-- caption: Скрипты и результаты -->
| Часть | Запуск | Результаты |
|---|---|---|
| 1–2 — роли экземпляров и состояние репликации | `bash scripts/lab-04/01-replication-status.sh` | `docs/lab-04/results/01-status.txt` |
| 3 — изменения доезжают до Replica | `bash scripts/lab-04/02-prove-replication.sh` | `02-prove.txt` |
| 4 — Replica только для чтения | `bash scripts/lab-04/03-read-only.sh` | `03-read-only.txt` |
| 6 — replication lag | `bash scripts/lab-04/04-lag.sh` | `04-lag.txt`, `04-lag-samples.csv` |
| 5 — чтение сервиса идёт на Replica | `bash scripts/lab-04/05-api-read-path.sh` | `05-api.txt` |
| Что масштабируется | `bash scripts/lab-04/06-read-scaling.sh`, `07-cpu-limited-scaling.sh` | `06-read-scaling.txt`, `07-cpu-limited.txt` |
| Всё подряд | `bash scripts/lab-04/run-all.sh` | `docs/lab-04/results/` |
| Запись терминала | `vhs scripts/lab-04/demo.tape` | `docs/lab-04/demo.gif` |

**Как измерялось.** Состояние репликации берётся из системных представлений PostgreSQL: `pg_stat_replication` на Primary и `pg_stat_wal_receiver` на Replica. Отставание считается двумя способами: в байтах WAL — `pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)`, и во времени — поля `write_lag`, `flush_lag`, `replay_lag`. Замеры под нагрузкой складывает функция `lab04.sample_lag` (`scripts/lab-04/00-setup.sql`): она раз в 0.2 секунды пишет строку в таблицу `lab04.lag_samples`.

**Запись терминала.** GIF снят инструментом VHS на работающем сервисе: роли экземпляров, streaming replication, отказ Replica принимать запись и момент, когда Replica отстала от Primary.

<!-- figure: lab-04/demo-1-replication.png | Primary и Replica: pg_is_in_recovery, состояние streaming, запись на Primary видна на Replica, попытка записи на Replica отклонена -->
<!-- figure: lab-04/demo-2-lag.png | Применение WAL на Replica остановлено: Primary отдаёт новое значение, Replica — старое, отставание 200 байт WAL -->
![Запись терминала: Primary и Replica, репликация, read-only и replication lag](lab-04/demo.gif)

---

## Часть 1. Primary и Replica

### Два экземпляра PostgreSQL

Второй экземпляр добавлен в `docker-compose.yml` рядом с первым. Primary — обычный контейнер `postgres:16-alpine` с явно заданными параметрами репликации:

<!-- caption: Primary в docker-compose.yml -->
```yaml
  postgres:
    image: postgres:16-alpine
    container_name: taskmanager-postgres
    command:
      - postgres
      - -c
      - hba_file=/etc/postgresql/pg_hba.conf
      - -c
      - wal_level=replica
      - -c
      - max_wal_senders=10
      - -c
      - max_replication_slots=10
      - -c
      - max_slot_wal_keep_size=2GB
      - -c
      - cluster_name=taskmanager-primary
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./docker/postgres/pg_hba.conf:/etc/postgresql/pg_hba.conf:ro
```

<!-- caption: Replica в docker-compose.yml -->
```yaml
  postgres-replica:
    image: postgres:16-alpine
    container_name: taskmanager-postgres-replica
    depends_on:
      postgres:
        condition: service_healthy
    entrypoint: ["/bin/sh", "/replica-entrypoint.sh"]
    command:
      - postgres
      - -c
      - hba_file=/etc/postgresql/pg_hba.conf
      - -c
      - hot_standby=on
      - -c
      - hot_standby_feedback=on
      - -c
      - cluster_name=taskmanager-replica
    ports:
      - "5433:5432"
    volumes:
      - postgres_replica_data:/var/lib/postgresql/data
      - ./docker/postgres/replica-entrypoint.sh:/replica-entrypoint.sh:ro
      - ./docker/postgres/pg_hba.conf:/etc/postgresql/pg_hba.conf:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U taskmanager -d taskmanager_db && psql -U taskmanager -d taskmanager_db -tAc 'SELECT pg_is_in_recovery()' | grep -q t"]
```

Реплика поднимается сама: при первом запуске её entrypoint (`docker/postgres/replica-entrypoint.sh`, приложение Б) дожидается Primary, создаёт на нём роль `replicator` и слот репликации, снимает базовую копию через `pg_basebackup --write-recovery-conf` и запускает PostgreSQL в режиме standby. Весь стенд поднимается одной командой `docker compose up -d`.

### Кто есть кто и как подключиться

Роль экземпляра определяет функция `pg_is_in_recovery()`: на Primary она возвращает `f`, на Replica — `t`, потому что Replica постоянно находится в процессе восстановления из WAL.

<!-- caption: Роли экземпляров -->
```
      instance       | in_recovery |  wal_lsn   | cluster_name
---------------------+-------------+------------+---------------------
 primary (порт 5432) | f           | 0/527E48E8 | taskmanager-primary

      instance       | in_recovery | replay_lsn |    cluster_name
---------------------+-------------+------------+---------------------
 replica (порт 5433) | t           | 0/527E48E8 | taskmanager-replica
```

<!-- caption: Как подключиться к каждому экземпляру -->
| Куда | Команда или строка подключения |
|---|---|
| Primary из контейнера | `docker compose exec postgres psql -U taskmanager -d taskmanager_db` |
| Replica из контейнера | `docker compose exec postgres-replica psql -U taskmanager -d taskmanager_db` |
| Primary с хоста | `psql -h localhost -p 5432 -U taskmanager -d taskmanager_db` |
| Replica с хоста | `psql -h localhost -p 5433 -U taskmanager -d taskmanager_db` |
| Сервис: запись | `ConnectionStrings__DefaultConnection = Host=postgres;Port=5432;…` |
| Сервис: чтение | `ConnectionStrings__ReplicaConnection = Host=postgres-replica;Port=5432;…` |

---

## Часть 2. Streaming replication

### Как изменение попадает на Replica

Цепочка одинакова для любой записи:

1. Primary меняет данные в своих страницах памяти.
2. Изменение записывается в WAL (Write-Ahead Log) — журнал предзаписи. Транзакция считается зафиксированной, когда её запись в WAL сброшена на диск.
3. Процесс `walsender` на Primary отправляет поток WAL реплике по обычному подключению к порту 5432, но к «базе» `replication`.
4. Процесс `walreceiver` на Replica принимает поток, записывает его у себя и сбрасывает на диск.
5. Процесс восстановления (startup) применяет записи WAL к файлам данных Replica. После этого изменение видно запросам на Replica.

Асинхронность означает, что Primary не ждёт шагов 3–5: он отвечает клиенту «готово» сразу после шага 2. Отсюда и берётся replication lag (часть 6).

### Что пришлось настроить

<!-- caption: Параметры репликации на Primary -->
| Параметр | Значение | Зачем |
|---|---|---|
| `wal_level` | `replica` | В WAL пишется достаточно данных, чтобы другой сервер мог их применить |
| `max_wal_senders` | 10 | Сколько реплик могут читать поток WAL одновременно |
| `max_replication_slots` | 10 | Сколько слотов репликации можно создать |
| `max_slot_wal_keep_size` | 2 GB | Ограничение на WAL, который Primary хранит ради отставшей Replica |
| `hot_standby` (на Replica) | `on` | Разрешает читать с Replica, пока она применяет WAL |
| `hot_standby_feedback` (на Replica) | `on` | Replica сообщает Primary, какие версии строк ей ещё нужны |

Отдельная настройка — файл `pg_hba.conf`. Стандартный файл разрешает подключения к «базе» `replication` только с localhost, поэтому Replica из соседнего контейнера получала бы отказ. В проект добавлен общий `docker/postgres/pg_hba.conf`, он подключается обоим экземплярам параметром `hba_file`:

<!-- caption: Правила подключения для репликации -->
```
# Приложение и psql с хоста: только по паролю
host    all             all             all                     scram-sha-256

# Подключения репликации: Replica приходит по сети docker как роль replicator
local   replication     all                                     trust
host    replication     all             all                     scram-sha-256
```

**Слот репликации.** Replica подключена через слот `replica_slot`. Слот — это отметка на Primary о том, какие WAL уже получила Replica. Пока слот существует, Primary не удаляет неотданные WAL, даже если Replica выключена, и после включения она догонит Primary без повторного `pg_basebackup`. Обратная сторона: если Replica выключена надолго, WAL копятся и занимают диск, поэтому задан предел `max_slot_wal_keep_size = 2GB`.

### Состояние репликации

<!-- caption: pg_stat_replication на Primary -->
```
application_name | taskmanager-replica
client_addr      | 172.20.0.4
state            | streaming
sync_state       | async
sent_lsn         | 0/527E48E8
write_lsn        | 0/527E48E8
flush_lsn        | 0/527E48E8
replay_lsn       | 0/527E48E8
lag_bytes        | 0
```

`state = streaming` означает, что Replica догнала Primary и получает изменения потоком, `sync_state = async` — что Primary не ждёт подтверждений от Replica. Четыре позиции LSN показывают, до какого места WAL отправлен, записан, сброшен на диск и применён.

<!-- caption: pg_stat_wal_receiver на Replica -->
```
status                | streaming
sender_host           | postgres
sender_port           | 5432
slot_name             | replica_slot
written_lsn           | 0/527E48E8
latest_end_lsn        | 0/527E48E8
last_msg_receipt_time | 2026-09-13 23:02:42.361368+00
conninfo              | user=replicator password=******** dbname=replication host=postgres port=5432 ...
```

---

## Часть 3. Доказательство, что репликация работает

Скрипт `02-prove-replication.sh` выполняет запись на Primary и сразу читает ту же строку на Replica.

<!-- caption: Запись на Primary и чтение на Replica -->
```
=== 1. Запись на Primary: INSERT в tasks (id = 58089a12-2195-47ea-a1f1-09ee1c813e3b)
id         | 58089a12-2195-47ea-a1f1-09ee1c813e3b
title      | ЛР4: проверка репликации 2026-09-13 23:05:47 UTC
created_at | 2026-09-13 23:05:48.511966+00
 primary_wal_lsn | 0/52822900

=== 2. Чтение на Replica: та же строка
id         | 58089a12-2195-47ea-a1f1-09ee1c813e3b
title      | ЛР4: проверка репликации 2026-09-13 23:05:47 UTC
created_at | 2026-09-13 23:05:48.511966+00
 replica_replay_lsn | 0/52822900
 last_xact_replayed | 2026-09-13 23:05:48.517088+00
```

Позиции WAL на обоих экземплярах совпали, строка на Replica та же самая. Дальше скрипт проверяет остальные операции:

<!-- caption: Все виды изменений доезжают до Replica -->
| Операция на Primary | Что видит Replica |
|---|---|
| `INSERT` задачи | строка появилась |
| `UPDATE`: изменены `title` и `status` | новые значения |
| `DELETE` задачи | строк 0 |

После всех операций `pg_stat_replication` показывает `state = streaming` и `lag_bytes = 0`: Replica применила весь WAL.

---

## Часть 4. Replica только для чтения

Скрипт `03-read-only.sh` пробует выполнить на Replica запись всех видов. PostgreSQL отклоняет каждую попытку:

<!-- caption: Попытки записи на Replica -->
| Запрос на Replica | Ответ PostgreSQL | SQLSTATE |
|---|---|---|
| `SELECT count(*) FROM tasks` | 1 000 000 — чтение работает | — |
| `INSERT INTO tags …` | `cannot execute INSERT in a read-only transaction` | 25006 |
| `UPDATE tasks SET …` | `cannot execute UPDATE in a read-only transaction` | 25006 |
| `DELETE FROM tags …` | `cannot execute DELETE in a read-only transaction` | 25006 |
| `CREATE TABLE replica_test …` | `cannot execute CREATE TABLE in a read-only transaction` | 25006 |
| `BEGIN READ WRITE` | `cannot set transaction read-write mode during recovery` | 0A000 |

Сам экземпляр сообщает о своём режиме так: `pg_is_in_recovery() = t`, `transaction_read_only = on`, `hot_standby = on`.

**Почему приложение не должно использовать Replica как отдельную базу для записи.** Replica не принимает запись не из-за настройки, которую можно было бы отключить, а по устройству: она непрерывно применяет чужой WAL. Если бы на ней разрешили менять данные, её файлы разошлись бы с потоком WAL от Primary, и применить следующую запись журнала стало бы невозможно. Кроме того, у Primary и Replica общая история: две независимо принимающие запись копии — это уже два разных кластера, между которыми пришлось бы решать конфликты. Поэтому вся запись идёт на Primary, а Replica используется только для чтения.

---

## Часть 5. Чтение сервиса через Replica

### Как это устроено в коде

В сервисе появилось второе подключение к базе. Модель EF Core та же самая, отличается только строка подключения, поэтому запросы не пришлось писать заново:

<!-- caption: Компоненты чтения с Replica -->
| Компонент | Слой | Роль |
|---|---|---|
| `ReplicaDbContext : AppDbContext` | Infrastructure | Тот же набор сущностей, но на строке подключения к Replica и без отслеживания изменений (`NoTracking`) |
| `ITaskReadRepository` | Application | Интерфейс только с читающими методами: записать через него нельзя |
| `TaskReadRepository : TaskRepository` | Infrastructure | Те же запросы, что и у обычного репозитория, но на `ReplicaDbContext` |
| `TaskService` | Application | Решает, какой запрос куда отправить |
| `IReplicationMonitor` | Application, Infrastructure | Читает `pg_stat_replication` и состояние Replica для `/api/replication` и `/health/replica` |

<!-- caption: Регистрация двух подключений в Program.cs -->
```csharp
// Configure Database: writes and read-your-writes go to the primary
var primaryConnection = builder.Configuration.GetConnectionString("DefaultConnection");
builder.Services.AddDbContext<AppDbContext>(options =>
{
    options.UseNpgsql(primaryConnection);
});

// Read replica: lists and statistics are served from here. Without a replica connection
// the same context points at the primary, so the service works with a single server too.
var replicaConnection = builder.Configuration.GetConnectionString("ReplicaConnection");
builder.Services.AddDbContext<ReplicaDbContext>(options =>
{
    options.UseNpgsql(string.IsNullOrWhiteSpace(replicaConnection) ? primaryConnection : replicaConnection);
    options.UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking);
});
```

Если строка подключения к Replica не задана, оба контекста смотрят на Primary, и сервис работает на одном сервере — это удобно для локальной отладки.

<!-- caption: Маршрутизация запросов сервиса -->
| Операция API | Куда идёт | Почему |
|---|---|---|
| `GET /api/tasks` — список задач | Replica | Основной читающий сценарий, список допускает отставание на доли секунды |
| `GET /api/tasks/stats` — статистика по статусам | Replica | Тяжёлое чтение по всей таблице |
| `POST`, `PUT`, `DELETE /api/tasks` | Primary | Любая запись возможна только на Primary |
| Чтение задачи сразу после создания или изменения | Primary | Read-your-writes: на Replica изменения может ещё не быть |
| `GET /api/tasks/{id}` | Primary | Клиент часто открывает задачу сразу после её создания |
| Проверка прав (`IsOwnerAsync`) | Primary | Решение о доступе не должно приниматься по устаревшим данным |

Выбор зафиксирован не только в коде, но и в тестах: `GetTasksAsync_ShouldNotTouchThePrimary` проверяет, что список берётся только с Replica, а `CreateAsync_ShouldWriteToPrimaryAndReadItBackFromPrimary` — что запись и чтение сразу после неё идут на Primary.

### Доказательство: чей это был запрос

Скрипт `05-api-read-path.sh` включает на обоих экземплярах логирование всех запросов (`log_min_duration_statement = 0`), очищает кэш Redis, вызывает два endpoint'а и смотрит, в чей журнал попал запрос.

<!-- caption: SELECT списка задач в журнале Replica -->
```
2026-09-13 23:10:54.172 UTC [777] LOG:  duration: 0.265 ms  execute <unnamed>:
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id,
       t0.status, t0.title, t0.updated_at, t0.user_id, p.id, u.id, t1.task_id, ...
FROM (
    SELECT t.id, t.created_at, ... FROM tasks AS t
    ORDER BY t.created_at DESC
    LIMIT $1 OFFSET $2
) AS t0 ...
```

<!-- caption: INSERT новой задачи в журнале Primary -->
```
2026-09-13 23:10:54.231 UTC [208] LOG:  duration: 0.399 ms  execute <unnamed>:
INSERT INTO tasks (id, created_at, description, due_date, priority, project_id, status, title, updated_at, user_id)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
DETAIL:  parameters: $1 = '2ddaf2e7-3bc0-4ccf-964a-a08c82f9bb43', ...,
         $8 = 'LR4: task created through API', ...
```

<!-- caption: Где какой запрос оказался -->
| Запрос | Журнал Primary | Журнал Replica |
|---|---|---|
| `GET /api/tasks?pageSize=5` (список) | нет | 6 запросов к `tasks` |
| `POST /api/tasks` (создание) | `INSERT INTO tasks` | 0 |

### Состояние репликации глазами сервиса

Сервис сам показывает, что происходит с репликацией: `GET /api/replication` (роль Admin) и `GET /health/replica`.

<!-- caption: Ответ GET /health/replica -->
```json
{"status":"Healthy","checks":[{"name":"replica","status":"Healthy",
 "description":"The replica is streaming",
 "data":{"replicaConfigured":true,"primaryLsn":"0/70F3B270","replicaReplayLsn":"0/70F3B270",
         "lagBytes":0,"lagSeconds":11.697,"connections":1}}]}
```

Проверка считает Replica отставшей, только если она отстала одновременно по объёму WAL (больше 16 MB) и по времени (больше 30 секунд). Одного времени недостаточно: `pg_last_xact_replay_timestamp()` возвращает время последней применённой транзакции, и в тишине, когда на Primary никто не пишет, это значение стареет само по себе, хотя Replica полностью догнала Primary.

---

## Часть 6. Replication lag

### Опыт 1. Без нагрузки

Скрипт `04-lag.sh` заранее запускает на Replica ожидание строки, затем вставляет её на Primary с `created_at = clock_timestamp()`. Когда строка появляется на Replica, та сравнивает своё текущее время с временем создания строки.

<!-- caption: Задержка появления строки на Replica, пять замеров подряд -->
| Замер | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Задержка, мс | 144.1 | 271.8 | 118.8 | 175.5 | 142.6 |

В эти 120–270 мс входит не только пересылка WAL: сюда попадает фиксация транзакции на самом Primary и запись WAL на диск на Replica. Обе операции в Docker Desktop идут через виртуализированную файловую систему и стоят десятки миллисекунд. На сервере с локальными SSD и сетью внутри одного датацентра такая задержка обычно составляет единицы миллисекунд. Важно другое: нулём она не бывает.

### Опыт 2. Под нагрузкой

На Primary выполняется `UPDATE` задач за последние 6 месяцев (около 240 тысяч строк), параллельно раз в 0.2 секунды снимается отставание.

<!-- caption: Отставание Replica во время массового UPDATE -->
| Время от начала, мс | Отставание, байт | Отставание | replay_lag, мс |
|---|---|---|---|
| 815 | 5 308 448 | 5.1 MB | 279.3 |
| 2 839 | 7 716 904 | 7.4 MB | 248.6 |
| 5 001 | 4 169 760 | 4.0 MB | 309.6 |
| 7 136 | 4 595 776 | 4.4 MB | 301.5 |
| 8 182 | 0 | 0 | 47.6 |
| 9 191 | 96 | 96 байт | 1.5 |

Максимум за прогон — 30.5 MB неприменённого WAL. Пока идёт запись, Replica отстаёт на мегабайты журнала и примерно на 0.3 секунды; через секунду после конца нагрузки отставание снова нулевое.

Отдельно стоит отметить поведение полей `write_lag`, `flush_lag` и `replay_lag`: между записями они не обнуляются, а сохраняют последнее измеренное значение. Поэтому в конце прогона в них остаётся большое число (в одном из прогонов — 7 секунд), хотя `lag_bytes` уже равен нулю. Для мониторинга живого отставания надёжнее сравнивать позиции LSN, что и делает health check сервиса.

### Опыт 3. Поймать устаревшее чтение

Чтобы увидеть момент, когда Primary уже содержит новое значение, а Replica ещё нет, применение WAL на Replica останавливается функцией `pg_wal_replay_pause()`. Приём WAL при этом продолжается: реплика получает журнал, но не применяет его.

<!-- caption: Остановленное применение WAL: Primary и Replica расходятся -->
```
=== Останавливаем применение WAL на Replica: pg_wal_replay_pause()
 pg_wal_replay_pause | paused
---------------------+--------
                     | t

=== Меняем цвет тега на Primary
UPDATE 1

=== Primary отдаёт новое значение, Replica — старое: это replication lag
 instance |    name    |  color
----------+------------+---------
 primary  | lab04-demo | #ff0000

 instance |    name    |  color
----------+------------+---------
 replica  | lab04-demo | #00ff00

  sent_lsn  | replay_lsn | lag_bytes
------------+------------+-----------
 0/AC172068 | 0/AC171FA0 |       200

=== Возобновляем применение WAL
 instance |    name    |  color
----------+------------+---------
 replica  | lab04-demo | #ff0000
```

### То же самое через API

Тот же опыт на уровне сервиса: при остановленном применении WAL создаётся задача через `POST /api/tasks` (Primary принимает её), после чего запрашивается список `GET /api/tasks?pageSize=1&sort=-created_at` (идёт на Replica).

<!-- caption: Устаревший список задач через API -->
```
--- POST /api/tasks (Primary принимает запись)
HTTP 201
--- GET /api/tasks?pageSize=1&sort=-created_at — первая задача списка по версии Replica:
"title":"LR4: task created through API"
--- та же задача на Primary:
LR4: created while replay is paused
--- возобновляем применение WAL и повторяем GET
"title":"LR4: created while replay is paused"
```

Клиент получил ответ «задача создана», но в списке её ещё нет. Это не ошибка сервиса, а следствие асинхронной репликации. Поэтому в TaskManager чтение задачи сразу после создания идёт на Primary, а через Replica читаются только списки и статистика, для которых отставание в доли секунды несущественно.

**Главный вывод.** Репликация не означает мгновенную синхронизацию. Между фиксацией транзакции на Primary и её применением на Replica всегда есть задержка: в покое это сотни миллисекунд в нашей среде, под нагрузкой — десятки мегабайт неприменённого WAL, а при остановке применения она может быть сколь угодно большой.

---

## Что именно масштабирует Read Scaling

Чтобы ответить на контрольный вопрос 7 измерением, одна и та же читающая нагрузка запускалась в двух вариантах: целиком на Primary и поровну между Primary и Replica. Нагрузку создаёт `pgbench` запросом «сколько задач создано в случайном месяце» — он повторяет форму запросов сервиса и читает партицию по `created_at`.

<!-- caption: Читающая нагрузка на общих ядрах хоста (20 CPU на оба контейнера) -->
| Вариант | Клиентов | Запросов в секунду | Средняя задержка, мс |
|---|---|---|---|
| A. Только Primary | 16 | 1460.5 | 11.0 |
| B. Primary | 8 | 720.9 | 11.1 |
| B. Replica | 8 | 716.0 | 11.2 |
| B. Суммарно | 16 | 1436.9 (−1.6 %) | — |
| C. Primary, пока на нём идёт постоянный `UPDATE` | 8 | 679.1 | 11.8 |
| C. Replica, пока Primary занят тем же `UPDATE` | 8 | 637.0 (−6.2 %) | 12.6 |

Прироста нет, и это ожидаемо: оба контейнера делят одни и те же ядра и один диск. Выносить чтение на реплику, которая живёт на том же железе, бессмысленно — суммарная мощность не изменилась. Вариант C показывает и то, что реплика не бесплатна: она сама тратит ресурсы на применение WAL, поэтому под потоком изменений читает даже чуть медленнее Primary.

Чтобы увидеть эффект Read Scaling в чистом виде, каждый экземпляр ограничен четырьмя ядрами — так ведут себя два отдельных сервера (наложение `docker/lab-04-cpu-limit.yml`, скрипт `07-cpu-limited-scaling.sh`):

<!-- caption: Та же нагрузка, когда у каждого сервера свои 4 ядра -->
| Вариант | Клиентов | Запросов в секунду | Средняя задержка, мс |
|---|---|---|---|
| A. Только Primary (4 ядра) | 16 | 271.2 | 59.0 |
| B. Primary (4 ядра) | 8 | 432.6 | 18.5 |
| B. Replica (4 ядра) | 8 | 436.0 | 18.3 |
| B. Суммарно | 16 | **868.6 (+220 %)** | — |

Шестнадцать клиентов на одном четырёхъядерном сервере конкурируют за процессор и дают 271 запрос в секунду при средней задержке 59 мс. Те же шестнадцать клиентов, разложенные по двум серверам, дают 869 запросов в секунду при задержке 18 мс. Сам запрос быстрее не стал: на общих ядрах хоста, где очереди нет, задержка одинаковая в обоих вариантах — около 11 мс. Уменьшилась очередь, а не время выполнения SQL.

**Вывод.** Read Scaling увеличивает не скорость отдельного запроса, а количество чтений, которое система способна обслужить, и только при условии, что у реплики свои вычислительные ресурсы.

---

## Ответы на контрольные вопросы

1. **Чем Primary отличается от Replica?** Primary — единственный экземпляр, который принимает изменения: он выполняет `INSERT`, `UPDATE`, `DELETE`, `CREATE TABLE` и пишет их в свой WAL. Replica — копия Primary, которая непрерывно применяет его WAL и находится в режиме восстановления (`pg_is_in_recovery() = t`). Она обслуживает только чтение: любая попытка записи отклоняется с ошибкой 25006.

2. **Почему запись выполняем на Primary?** Потому что источник истины и порядок изменений должен быть один. Replica физически повторяет содержимое Primary, применяя его журнал; если бы она принимала собственную запись, её файлы разошлись бы с потоком WAL и применить следующую запись журнала стало бы невозможно. Две независимо принимающие запись копии — это уже два разных кластера с конфликтами, которые кто-то должен разрешать.

3. **Как изменение из Primary попадает на Replica?** Изменение фиксируется в WAL на Primary. Процесс `walsender` передаёт поток WAL по сети процессу `walreceiver` на Replica. Replica записывает полученный WAL у себя и сбрасывает на диск, а процесс восстановления применяет записи к файлам данных. После применения изменение видно запросам на Replica. Позиции каждого этапа видны в `pg_stat_replication`: `sent_lsn`, `write_lsn`, `flush_lsn`, `replay_lsn`.

4. **Что такое WAL в контексте репликации?** WAL (Write-Ahead Log) — журнал предзаписи: последовательность записей обо всех изменениях страниц данных. PostgreSQL сначала пишет изменение в WAL и только потом меняет сами файлы данных, поэтому WAL достаточно для восстановления после сбоя. Репликация использует тот же журнал как канал передачи изменений: Replica не выполняет SQL-запросы Primary заново, а применяет готовые физические изменения страниц из WAL.

5. **Что такое replication lag?** Это отставание Replica от Primary: разница между тем, что Primary уже зафиксировал, и тем, что Replica уже применила. Измеряется в байтах WAL (`pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)`) или во времени (`replay_lag`, `now() - pg_last_xact_replay_timestamp()`). В измерениях этой работы отставание без нагрузки составляло сотни миллисекунд, под массовым `UPDATE` доходило до 30.5 MB неприменённого WAL, а при остановленном применении росло неограниченно.

6. **Почему следующий SELECT после INSERT может увидеть старые данные, если отправить его на Replica?** Репликация асинхронная: Primary отвечает клиенту «зафиксировано», как только записал WAL себе на диск, и не ждёт, пока Replica получит и применит эту запись. Между этими моментами проходит время, и запрос, пришедший на Replica в этом промежутке, честно вернёт предыдущее состояние. В работе это воспроизведено дважды: на уровне SQL (Primary отдаёт `#ff0000`, Replica — `#00ff00`) и на уровне API (задача создана, но её ещё нет в списке). Поэтому сценарии read-your-writes направляются на Primary.

7. **Что именно масштабируется при Read Scaling: скорость одного SQL-запроса или способность обслуживать больше чтений?** Способность обслуживать больше чтений. Один и тот же запрос на Replica выполняется столько же времени, сколько на Primary: план и объём данных те же, средняя задержка в измерении была одинаковой — около 11 мс. Растёт суммарная пропускная способность, и только вместе с ресурсами: при ограничении в 4 ядра на сервер разделение нагрузки подняло её с 271 до 869 запросов в секунду, а на общих ядрах хоста прироста не было вовсе.

8. **Почему наличие Replica не отменяет необходимость индексов и оптимизации SQL?** Replica выполняет те же самые запросы по тем же данным и с теми же планами: запрос без индекса, читающий миллион строк, останется таким же медленным, просто эту работу будет делать другой сервер. Кроме того, реплика применяет весь WAL, который порождает Primary, поэтому неоптимальная запись нагружает и её. Реплика добавляет мощности для параллельных чтений, но не уменьшает стоимость отдельного запроса: индексы, партиционирование и разумный SQL из предыдущих работ остаются обязательными.

9. **Расскажите про CAP-теорему.** CAP-теорема утверждает, что распределённая система не может одновременно гарантировать три свойства: Consistency (любое чтение видит последнюю подтверждённую запись), Availability (каждый запрос получает ответ) и Partition tolerance (система продолжает работать при потере связи между узлами). Сеть рвётся независимо от нашего желания, поэтому реальный выбор в момент разрыва идёт между C и A. Схема из этой работы — Primary с асинхронной Replica — это выбор в пользу доступности: если связь между узлами пропадёт, Replica продолжит отвечать, но будет отдавать устаревшие данные, то есть согласованность здесь в конечном счёте (eventual consistency). Настройка `synchronous_commit = remote_apply` смещает выбор в сторону согласованности: Primary ждёт подтверждения от Replica, и при её недоступности запись останавливается — страдает доступность. Расширение PACELC добавляет вторую половину картины: даже без разрывов (Else) приходится выбирать между Latency и Consistency, потому что синхронная репликация стоит задержки на каждом коммите. В TaskManager выбрана асинхронная репликация, а риск устаревшего чтения закрыт маршрутизацией: то, что требует немедленной согласованности, читается с Primary.

---

## Заключение

В работе развёрнута схема PostgreSQL Primary + Replica и настроена асинхронная streaming replication через слот репликации. Реплика поднимается автоматически: при первом запуске `docker compose up -d` её entrypoint снимает базовую копию Primary через `pg_basebackup` и стартует в режиме standby, после чего `pg_stat_replication` на Primary показывает состояние `streaming`.

Проверено, что репликация работает: `INSERT`, `UPDATE` и `DELETE` на Primary появляются на Replica, позиции LSN совпадают. Проверено и обратное: любая запись на Replica отклоняется с ошибкой 25006, а явная транзакция на запись не открывается вовсе.

В сервисе TaskManager чтение списка задач и статистики переведено на Replica через отдельный контекст EF Core и репозиторий только для чтения; запись и чтение сразу после записи остались на Primary. Маршрутизация доказана журналами обоих серверов: `SELECT` списка задач попал в журнал Replica, `INSERT` новой задачи — в журнал Primary.

Измерена задержка репликации: без нагрузки 120–270 мс в этой среде, под массовым `UPDATE` — до 30.5 MB неприменённого WAL. При остановленном применении WAL удалось поймать момент, когда Primary уже отдаёт новое значение, а Replica и построенный на ней список задач — старое. Дополнительный эксперимент показал, что Read Scaling увеличивает пропускную способность чтения (271 → 869 запросов в секунду при разделении нагрузки между двумя четырёхъядерными серверами), но не ускоряет отдельный запрос и не даёт ничего, если реплика делит железо с Primary.
