-- =====================================================================
-- 01_schema.sql — Схема БД «Аптечный склад» (вариант №7, курсовая ГУАП)
-- Порядок применения: 01_schema.sql → 02_seed.sql → 03_functions.sql
--                   → 04_triggers.sql → 05_roles.sql
-- =====================================================================
-- База содержит 16 таблиц:
--   • 5 справочников (countries, cities, drug_groups, drug_purposes, positions)
--   • 5 основных сущностей (manufacturers, drugs, suppliers, pharmacies, employees)
--   • 4 операционные таблицы «заголовок — позиции»
--       (warehouse_supplies, warehouse_supply_items,
--        pharmacy_dispatches, pharmacy_dispatch_items)
--   • 1 таблица розничных продаж (pharmacy_sales)
--   • 1 служебная таблица логов зарплат (employee_salary_log) — для триггера шага 4
-- Все таблицы нормализованы до 3НФ.
-- =====================================================================

-- На случай повторного применения скрипта (вне docker-entrypoint-initdb.d):
-- DROP TABLE в обратном порядке зависимостей.
DROP TABLE IF EXISTS pharmacy_sales             CASCADE;
DROP TABLE IF EXISTS pharmacy_dispatch_items    CASCADE;
DROP TABLE IF EXISTS pharmacy_dispatches        CASCADE;
DROP TABLE IF EXISTS warehouse_supply_items     CASCADE;
DROP TABLE IF EXISTS warehouse_supplies         CASCADE;
DROP TABLE IF EXISTS employee_salary_log        CASCADE;
DROP TABLE IF EXISTS employees                  CASCADE;
DROP TABLE IF EXISTS pharmacies                 CASCADE;
DROP TABLE IF EXISTS suppliers                  CASCADE;
DROP TABLE IF EXISTS drugs                      CASCADE;
DROP TABLE IF EXISTS manufacturers              CASCADE;
DROP TABLE IF EXISTS positions                  CASCADE;
DROP TABLE IF EXISTS drug_purposes              CASCADE;
DROP TABLE IF EXISTS drug_groups                CASCADE;
DROP TABLE IF EXISTS cities                     CASCADE;
DROP TABLE IF EXISTS countries                  CASCADE;

-- =====================================================================
-- 1. СПРАВОЧНИКИ
-- =====================================================================

-- Таблица 1 — Страны
CREATE TABLE countries (
    id_country    SERIAL PRIMARY KEY,
    country_name  VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE  countries IS 'Справочник стран (производители, города, поставщики)';
COMMENT ON COLUMN countries.country_name IS 'Название страны';

-- Таблица 2 — Города
CREATE TABLE cities (
    id_city     SERIAL PRIMARY KEY,
    city_name   VARCHAR(100) NOT NULL,
    id_country  INTEGER      NOT NULL
        REFERENCES countries(id_country) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_cities_name_country UNIQUE (city_name, id_country)
);
COMMENT ON TABLE cities IS 'Справочник городов; у города есть страна';

-- Таблица 3 — Группы препаратов
CREATE TABLE drug_groups (
    id_group    SERIAL PRIMARY KEY,
    group_name  VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE drug_groups IS 'Справочник групп препаратов (Антибиотики, Витамины и т.д.)';

-- Таблица 4 — Назначения препаратов
CREATE TABLE drug_purposes (
    id_purpose    SERIAL PRIMARY KEY,
    purpose_name  VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE drug_purposes IS 'Справочник назначений (жаропонижающее, обезболивающее и т.д.)';

-- Таблица 5 — Должности
CREATE TABLE positions (
    id_position    SERIAL PRIMARY KEY,
    position_name  VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE positions IS 'Справочник должностей сотрудников склада';

-- =====================================================================
-- 2. ОСНОВНЫЕ СУЩНОСТИ
-- =====================================================================

-- Таблица 6 — Производители
CREATE TABLE manufacturers (
    id_manufacturer    SERIAL PRIMARY KEY,
    manufacturer_name  VARCHAR(150) NOT NULL UNIQUE,
    id_country         INTEGER      NOT NULL
        REFERENCES countries(id_country) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE manufacturers IS 'Производители лекарственных препаратов';

-- Таблица 7 — Препараты
CREATE TABLE drugs (
    id_drug          SERIAL PRIMARY KEY,
    drug_name        VARCHAR(200) NOT NULL,
    id_manufacturer  INTEGER      NOT NULL
        REFERENCES manufacturers(id_manufacturer) ON UPDATE CASCADE ON DELETE RESTRICT,
    id_purpose       INTEGER      NOT NULL
        REFERENCES drug_purposes(id_purpose) ON UPDATE CASCADE ON DELETE RESTRICT,
    id_group         INTEGER      NOT NULL
        REFERENCES drug_groups(id_group) ON UPDATE CASCADE ON DELETE RESTRICT,
    unit             VARCHAR(20)  NOT NULL DEFAULT 'шт.',
    purchase_price   NUMERIC(10,2) NOT NULL,
    retail_price     NUMERIC(10,2) NOT NULL,
    CONSTRAINT chk_drugs_purchase_price_nonneg CHECK (purchase_price >= 0),
    CONSTRAINT chk_drugs_retail_price_nonneg   CHECK (retail_price   >= 0),
    -- retail >= purchase гарантируется триггером шага 4 (требование методички),
    -- здесь дублируется как дешёвая страховка:
    CONSTRAINT chk_drugs_retail_ge_purchase    CHECK (retail_price >= purchase_price),
    CONSTRAINT uq_drugs_name_manufacturer      UNIQUE (drug_name, id_manufacturer)
);
COMMENT ON TABLE drugs IS 'Препараты на складе (номенклатура)';

-- Таблица 8 — Поставщики
CREATE TABLE suppliers (
    id_supplier          SERIAL PRIMARY KEY,
    supplier_name        VARCHAR(200) NOT NULL,
    id_city              INTEGER      NOT NULL
        REFERENCES cities(id_city) ON UPDATE CASCADE ON DELETE RESTRICT,
    address              VARCHAR(200) NOT NULL,
    contact_last_name    VARCHAR(50)  NOT NULL,
    contact_first_name   VARCHAR(50)  NOT NULL,
    contact_patronymic   VARCHAR(50),
    phone                VARCHAR(30)  NOT NULL,
    inn                  VARCHAR(12)  NOT NULL UNIQUE,
    license_number       VARCHAR(50)  NOT NULL UNIQUE
    -- Формат ИНН (10 или 12 цифр) и формат телефона — проверяются триггером шага 4.
);
COMMENT ON TABLE suppliers IS 'Поставщики препаратов на склад';

-- Таблица 9 — Филиалы аптек
CREATE TABLE pharmacies (
    id_pharmacy     SERIAL PRIMARY KEY,
    pharmacy_name   VARCHAR(200) NOT NULL,
    id_city         INTEGER      NOT NULL
        REFERENCES cities(id_city) ON UPDATE CASCADE ON DELETE RESTRICT,
    address         VARCHAR(200) NOT NULL,
    phone           VARCHAR(30)  NOT NULL
);
COMMENT ON TABLE pharmacies IS 'Филиалы аптек, в которые отгружаются препараты со склада';

-- Таблица 10 — Работники склада
CREATE TABLE employees (
    id_employee    SERIAL PRIMARY KEY,
    last_name      VARCHAR(50)   NOT NULL,
    first_name     VARCHAR(50)   NOT NULL,
    patronymic     VARCHAR(50),
    passport_data  VARCHAR(20)   NOT NULL UNIQUE,
    id_position    INTEGER       NOT NULL
        REFERENCES positions(id_position) ON UPDATE CASCADE ON DELETE RESTRICT,
    phone          VARCHAR(30)   NOT NULL,
    salary         NUMERIC(10,2) NOT NULL,
    CONSTRAINT chk_employees_salary_positive CHECK (salary > 0)
);
COMMENT ON TABLE employees IS 'Сотрудники аптечного склада';

-- =====================================================================
-- 3. ОПЕРАЦИОННЫЕ ТАБЛИЦЫ
-- =====================================================================

-- Таблица 11 — Поставки на склад (заголовок)
CREATE TABLE warehouse_supplies (
    id_supply      SERIAL PRIMARY KEY,
    id_supplier    INTEGER     NOT NULL
        REFERENCES suppliers(id_supplier) ON UPDATE CASCADE ON DELETE RESTRICT,
    id_employee    INTEGER     NOT NULL
        REFERENCES employees(id_employee) ON UPDATE CASCADE ON DELETE RESTRICT,
    supply_date    DATE        NOT NULL,
    batch_number   VARCHAR(30) NOT NULL
    -- Запрет на дату в будущем — триггер шага 4.
);
COMMENT ON TABLE warehouse_supplies IS 'Заголовки поставок на склад от поставщиков';

-- Таблица 12 — Позиции поставки (many-to-many между supplies и drugs)
CREATE TABLE warehouse_supply_items (
    id_supply_item  SERIAL PRIMARY KEY,
    id_supply       INTEGER NOT NULL
        REFERENCES warehouse_supplies(id_supply) ON UPDATE CASCADE ON DELETE CASCADE,
    id_drug         INTEGER NOT NULL
        REFERENCES drugs(id_drug) ON UPDATE CASCADE ON DELETE RESTRICT,
    quantity        INTEGER NOT NULL,
    CONSTRAINT chk_wsi_quantity_positive CHECK (quantity > 0)
);
COMMENT ON TABLE warehouse_supply_items IS 'Позиции поставки: какие препараты и в каком количестве';

-- Таблица 13 — Отгрузки в филиалы (заголовок)
CREATE TABLE pharmacy_dispatches (
    id_dispatch    SERIAL PRIMARY KEY,
    id_pharmacy    INTEGER NOT NULL
        REFERENCES pharmacies(id_pharmacy) ON UPDATE CASCADE ON DELETE RESTRICT,
    id_employee    INTEGER NOT NULL
        REFERENCES employees(id_employee) ON UPDATE CASCADE ON DELETE RESTRICT,
    dispatch_date  DATE    NOT NULL
);
COMMENT ON TABLE pharmacy_dispatches IS 'Заголовки отгрузок со склада в филиалы аптек';

-- Таблица 14 — Позиции отгрузки
CREATE TABLE pharmacy_dispatch_items (
    id_dispatch_item  SERIAL PRIMARY KEY,
    id_dispatch       INTEGER NOT NULL
        REFERENCES pharmacy_dispatches(id_dispatch) ON UPDATE CASCADE ON DELETE CASCADE,
    id_drug           INTEGER NOT NULL
        REFERENCES drugs(id_drug) ON UPDATE CASCADE ON DELETE RESTRICT,
    quantity          INTEGER NOT NULL,
    CONSTRAINT chk_pdi_quantity_positive CHECK (quantity > 0)
    -- Контроль остатков (нельзя отгрузить больше, чем на складе) — триггер шага 4.
);
COMMENT ON TABLE pharmacy_dispatch_items IS 'Позиции отгрузки в филиал: какие препараты и сколько';

-- =====================================================================
-- 4. УЧЁТ ПРОДАЖ
-- =====================================================================

-- Таблица 15 — Розничные продажи в аптеках
CREATE TABLE pharmacy_sales (
    id_sale      SERIAL PRIMARY KEY,
    id_pharmacy  INTEGER       NOT NULL
        REFERENCES pharmacies(id_pharmacy) ON UPDATE CASCADE ON DELETE RESTRICT,
    id_drug      INTEGER       NOT NULL
        REFERENCES drugs(id_drug) ON UPDATE CASCADE ON DELETE RESTRICT,
    quantity     INTEGER       NOT NULL,
    sale_date    DATE          NOT NULL,
    sale_price   NUMERIC(10,2) NOT NULL,
    CONSTRAINT chk_sales_quantity_positive CHECK (quantity > 0),
    CONSTRAINT chk_sales_price_positive    CHECK (sale_price > 0)
);
COMMENT ON TABLE pharmacy_sales IS 'Розничные продажи препаратов в филиалах аптек';

-- =====================================================================
-- 5. СЛУЖЕБНАЯ ТАБЛИЦА ДЛЯ ЛОГА ЗАРПЛАТ (используется триггером шага 4)
-- =====================================================================

CREATE TABLE employee_salary_log (
    id_log         SERIAL PRIMARY KEY,
    id_employee    INTEGER NOT NULL
        REFERENCES employees(id_employee) ON UPDATE CASCADE ON DELETE CASCADE,
    old_salary     NUMERIC(10,2) NOT NULL,
    new_salary     NUMERIC(10,2) NOT NULL,
    changed_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by     TEXT          NOT NULL DEFAULT CURRENT_USER
);
COMMENT ON TABLE employee_salary_log IS 'Лог изменений зарплат сотрудников (заполняется триггером)';

-- =====================================================================
-- 6. ИНДЕКСЫ (на внешние ключи, которые часто используются в JOIN)
-- =====================================================================
-- PostgreSQL НЕ создаёт индексы на FK автоматически — добавим вручную.

CREATE INDEX idx_cities_country               ON cities(id_country);
CREATE INDEX idx_manufacturers_country        ON manufacturers(id_country);
CREATE INDEX idx_drugs_manufacturer           ON drugs(id_manufacturer);
CREATE INDEX idx_drugs_purpose                ON drugs(id_purpose);
CREATE INDEX idx_drugs_group                  ON drugs(id_group);
CREATE INDEX idx_suppliers_city               ON suppliers(id_city);
CREATE INDEX idx_pharmacies_city              ON pharmacies(id_city);
CREATE INDEX idx_employees_position           ON employees(id_position);
CREATE INDEX idx_ws_supplier                  ON warehouse_supplies(id_supplier);
CREATE INDEX idx_ws_employee                  ON warehouse_supplies(id_employee);
CREATE INDEX idx_ws_date                      ON warehouse_supplies(supply_date);
CREATE INDEX idx_wsi_supply                   ON warehouse_supply_items(id_supply);
CREATE INDEX idx_wsi_drug                     ON warehouse_supply_items(id_drug);
CREATE INDEX idx_pd_pharmacy                  ON pharmacy_dispatches(id_pharmacy);
CREATE INDEX idx_pd_employee                  ON pharmacy_dispatches(id_employee);
CREATE INDEX idx_pd_date                      ON pharmacy_dispatches(dispatch_date);
CREATE INDEX idx_pdi_dispatch                 ON pharmacy_dispatch_items(id_dispatch);
CREATE INDEX idx_pdi_drug                     ON pharmacy_dispatch_items(id_drug);
CREATE INDEX idx_sales_pharmacy               ON pharmacy_sales(id_pharmacy);
CREATE INDEX idx_sales_drug                   ON pharmacy_sales(id_drug);
CREATE INDEX idx_sales_date                   ON pharmacy_sales(sale_date);
CREATE INDEX idx_salary_log_employee          ON employee_salary_log(id_employee);
