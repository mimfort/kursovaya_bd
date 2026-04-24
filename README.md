# Информационная система «Аптечный склад»

Курсовая работа по дисциплине «Базы данных», ГУАП, кафедра 41, вариант №7.
Автор: Задорожный А. В., гр. 4319.

Система ведёт учёт поставок на склад, отгрузок в филиалы аптек и
розничных продаж. Вся бизнес-логика — хранимые функции, триггеры и роли
PostgreSQL; приложение выступает тонким транспортом.

Пояснительная записка: [docs/Пояснительная записка.docx](docs/Пояснительная%20записка.docx).

## Стек

| Слой         | Технология                                               |
|--------------|----------------------------------------------------------|
| СУБД         | PostgreSQL 16 (Docker)                                   |
| Backend      | FastAPI + SQLAlchemy 2.x (только транспорт) + psycopg 3  |
| Frontend     | Streamlit + Plotly                                       |
| Оркестрация  | docker-compose                                           |

Все запросы к БД выполняются через вызовы хранимых функций
(`SELECT * FROM имя_функции(...)`). SQLAlchemy ORM не используется —
это требование методички.

## Быстрый старт

```bash
cp .env.example .env
docker compose up -d --build
docker compose ps                     # дождаться (healthy) у всех трёх
```

Доступные адреса:

| Сервис     | URL                                |
|------------|------------------------------------|
| Streamlit  | <http://localhost:8501>            |
| FastAPI    | <http://localhost:8000>            |
| Swagger UI | <http://localhost:8000/docs>       |
| PostgreSQL | `localhost:5433` (хост → Docker)   |

Порт БД на хосте — 5433 (чтобы не конфликтовать с локально установленным
PostgreSQL на 5432). Внутри docker-сети backend обращается к базе по имени
`db:5432`.

## Структура проекта

```
bd_kursovaya/
├── docker-compose.yml
├── .env.example
├── db/                           # SQL-скрипты, применяются при первом старте
│   ├── 01_schema.sql             # 16 таблиц, индексы, check-constraints
│   ├── 02_seed.sql               # тестовые данные
│   ├── 03_functions.sql          # 10 функций запросов + 4 аналитики
│   ├── 04_triggers.sql           # 6 разнотипных триггеров
│   └── 05_roles.sql              # 3 роли + GRANT/REVOKE
├── backend/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app/
│       ├── main.py               # FastAPI, exception handlers
│       ├── database.py           # engine per-role, get_session
│       ├── schemas.py            # Pydantic-валидация входа
│       └── routers/
│           ├── tables.py         # /tables/{name}
│           ├── queries.py        # /queries/* — 10 запросов
│           └── analytics.py      # /analytics/* — 4 графика
├── frontend/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── streamlit_app.py
│   └── pages/
│       ├── 1_Таблицы.py
│       ├── 2_Запросы.py
│       └── 3_Аналитика.py
└── docs/
    └── Пояснительная записка.docx
```

## Подключение к БД напрямую

```bash
# Администратор БД — полный доступ
docker compose exec db psql -U pharmacy_admin -d pharmacy_warehouse

# Директор — чтение всего + управление поставщиками и филиалами
docker compose exec -e PGPASSWORD=director_pass db \
    psql -U pharmacy_director -d pharmacy_warehouse

# Кладовщик — ограниченный доступ (без inn, license_number, salary)
docker compose exec -e PGPASSWORD=warehouseman_pass db \
    psql -U pharmacy_warehouseman -d pharmacy_warehouse

# С хоста
psql -h localhost -p 5433 -U pharmacy_admin -d pharmacy_warehouse
```

## Переключение роли в интерфейсе

В левой панели Streamlit — выбор роли: «Администратор БД», «Директор»,
«Кладовщик». При смене роли фронт добавляет в HTTP-запрос заголовок
`X-Role`, backend открывает сессию под соответствующим пользователем БД.
Если у роли нет прав — пользователь видит сообщение вида
`permission denied for table ...`.

## Пересоздание БД с нуля

```bash
docker compose down -v          # удалит volume с данными
docker compose up -d --build    # пересоздаст и применит SQL-скрипты
```

## Полная остановка

```bash
docker compose down        # остановить контейнеры, данные в volume сохранить
docker compose down -v     # снести всё, включая данные
```

## Что реализовано

| Требование методички                       | Где                                               |
|--------------------------------------------|---------------------------------------------------|
| 15 таблиц в 3НФ                            | `db/01_schema.sql` + 1 служебная `employee_salary_log` |
| Seed-данные (≥20 записей в операционных)   | `db/02_seed.sql` — 25 поставок / 25 отгрузок / 57 продаж |
| 10 хранимых функций (7 простых + 3 сложных)| `db/03_functions.sql`                             |
| Валидация через `RAISE EXCEPTION`          | все функции с параметрами                         |
| ≥5 разнотипных триггеров                   | 6 штук в `db/04_triggers.sql`                     |
| 3 роли с GRANT/REVOKE                      | `db/05_roles.sql` + column-level у suppliers/employees |
| Backend-эндпоинты                          | `backend/app/routers/`                            |
| Streamlit: «Таблицы», «Запросы», «Аналитика» | `frontend/pages/`                               |
| ≥3 графика разного типа                    | 4 графика Plotly: столбчатый, круговой, линейный, heatmap |
| Обработка ошибок, подсказки формата        | Pydantic → HTTP 400, `RAISE` → HTTP 400           |
| Список источников (≥20)                    | 22 позиции в пояснительной записке                |
