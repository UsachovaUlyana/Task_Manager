-- Читающий запрос для pgbench: сколько задач создано в случайном месяце.
-- Повторяет форму запросов сервиса: фильтр по created_at (ключ партиционирования из ЛР №3).
\set m random(1, 24)
SELECT count(*) FROM tasks
WHERE created_at >= date_trunc('month', now()) - make_interval(months => :m)
  AND created_at <  date_trunc('month', now()) - make_interval(months => :m - 1);
