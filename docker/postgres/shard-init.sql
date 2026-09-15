-- ЛР №5: схема шарда. Каждый шард — отдельный независимый PostgreSQL с таблицей задач.
-- Выполняется автоматически при первом запуске контейнера (docker-entrypoint-initdb.d).
--
-- Пользователи, проекты и теги остаются в основной базе сервиса, поэтому внешних ключей
-- на них здесь нет: целостность между базами PostgreSQL проверить не может.

CREATE TABLE tasks (
    id          UUID         NOT NULL,
    user_id     UUID         NOT NULL,   -- shard key: все задачи пользователя лежат на одном шарде
    project_id  UUID,
    title       VARCHAR(300) NOT NULL,
    description TEXT,
    status      INTEGER      NOT NULL,
    priority    INTEGER      NOT NULL,
    due_date    TIMESTAMPTZ,
    created_at  TIMESTAMPTZ  NOT NULL,
    updated_at  TIMESTAMPTZ  NOT NULL,
    -- Ключ шардирования входит в первичный ключ: запись однозначно адресуется парой (user_id, id)
    PRIMARY KEY (user_id, id)
);

-- Главный запрос к шарду: задачи пользователя, новые сверху
CREATE INDEX idx_tasks_user_id_created_at ON tasks (user_id, created_at DESC);
