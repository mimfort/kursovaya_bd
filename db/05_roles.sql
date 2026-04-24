-- =====================================================================
-- 05_roles.sql — Роли и разграничение прав доступа
-- Применяется после 04_triggers.sql.
-- =====================================================================
-- Трое пользователей по ТЗ:
--   1. pharmacy_warehouseman — кладовщик: оформляет поставки/отгрузки,
--      смотрит препараты и остатки; НЕ видит финансовые и лицензионные
--      данные поставщиков (inn, license_number, address).
--   2. pharmacy_director     — директор: читает всё, управляет поставщиками
--      и филиалами, анализирует; не может менять схему.
--   3. pharmacy_admin        — администратор БД: полный доступ.
--      Эта роль уже существует (POSTGRES_USER из docker-compose является
--      суперпользователем, который создал все объекты), поэтому здесь мы
--      её только упоминаем, а не пересоздаём.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Создание ролей (идемпотентно через DO-блок)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pharmacy_warehouseman') THEN
        CREATE ROLE pharmacy_warehouseman LOGIN PASSWORD 'warehouseman_pass';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pharmacy_director') THEN
        CREATE ROLE pharmacy_director     LOGIN PASSWORD 'director_pass';
    END IF;
END$$;

COMMENT ON ROLE pharmacy_warehouseman IS 'Кладовщик склада';
COMMENT ON ROLE pharmacy_director     IS 'Директор аптечной сети';

-- ---------------------------------------------------------------------
-- На всякий случай сбрасываем ранее выданные привилегии (для идемпотентности)
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM pharmacy_warehouseman, pharmacy_director;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM pharmacy_warehouseman, pharmacy_director;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM pharmacy_warehouseman, pharmacy_director;
REVOKE ALL ON SCHEMA public                  FROM pharmacy_warehouseman, pharmacy_director;

-- ---------------------------------------------------------------------
-- КРИТИЧНО: PostgreSQL по умолчанию выдаёт EXECUTE всем функциям
-- псевдо-роли PUBLIC. Нужно это отобрать, иначе кладовщик сможет
-- вызвать финансовую аналитику директора.
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- ---------------------------------------------------------------------
-- Базовый USAGE на схему public
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO pharmacy_warehouseman, pharmacy_director;

-- =====================================================================
-- РОЛЬ 1: pharmacy_warehouseman (КЛАДОВЩИК)
-- =====================================================================

-- 1.1 Справочники — только чтение
GRANT SELECT ON countries, cities, drug_groups, drug_purposes,
                positions, manufacturers, pharmacies
      TO pharmacy_warehouseman;

-- 1.2 Препараты — только чтение (цены видит, т.к. оформляет приёмку)
GRANT SELECT ON drugs TO pharmacy_warehouseman;

-- 1.3 Поставщики — column-level GRANT: БЕЗ inn, license_number, address
--     (финансовые/лицензионные поля по ТЗ кладовщику не положены)
GRANT SELECT (id_supplier, supplier_name, id_city,
              contact_last_name, contact_first_name, contact_patronymic, phone)
      ON suppliers TO pharmacy_warehouseman;

-- 1.4 Сотрудники — только свои ФИО и должность; зарплаты не видит.
GRANT SELECT (id_employee, last_name, first_name, patronymic, id_position, phone)
      ON employees TO pharmacy_warehouseman;

-- 1.5 Операционные таблицы — чтение + оформление поставок и отгрузок
GRANT SELECT, INSERT ON warehouse_supplies, warehouse_supply_items,
                        pharmacy_dispatches, pharmacy_dispatch_items
      TO pharmacy_warehouseman;

-- 1.6 Продажи — только чтение (продажи оформляет филиал аптеки)
GRANT SELECT ON pharmacy_sales TO pharmacy_warehouseman;

-- 1.7 Sequences для INSERT-ов в операционные таблицы
GRANT USAGE, SELECT ON
      warehouse_supplies_id_supply_seq,
      warehouse_supply_items_id_supply_item_seq,
      pharmacy_dispatches_id_dispatch_seq,
      pharmacy_dispatch_items_id_dispatch_item_seq
      TO pharmacy_warehouseman;

-- 1.8 Функции — разрешены только те, что связаны с его работой
--     (препараты, остатки, движения; финансовая аналитика — нет)
GRANT EXECUTE ON FUNCTION
      get_drugs_by_group(TEXT),
      get_drugs_by_price_range(NUMERIC, NUMERIC),
      get_drugs_by_manufacturer(TEXT),
      get_drugs_dispatched_to_pharmacy(TEXT),
      get_drugs_by_supplier(TEXT),
      get_movements_by_period(DATE, DATE),
      get_low_stock_drugs(INT)
      TO pharmacy_warehouseman;

-- =====================================================================
-- РОЛЬ 2: pharmacy_director (ДИРЕКТОР)
-- =====================================================================

-- 2.1 Чтение всех таблиц (включая журнал зарплат — он руководитель)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO pharmacy_director;

-- 2.2 Управление поставщиками и филиалами (договоры, сеть аптек)
GRANT INSERT, UPDATE, DELETE ON suppliers, pharmacies TO pharmacy_director;

-- 2.3 Редактирование номенклатуры препаратов (цены, добавление/снятие)
GRANT INSERT, UPDATE, DELETE ON drugs TO pharmacy_director;

-- 2.4 Редактирование справочников
GRANT INSERT, UPDATE, DELETE ON
      countries, cities, drug_groups, drug_purposes,
      positions, manufacturers
      TO pharmacy_director;

-- 2.5 Sequences — для INSERT-ов в управляемые таблицы
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO pharmacy_director;

-- 2.6 Все функции — директор делает аналитику
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO pharmacy_director;

-- =====================================================================
-- РОЛЬ 3: pharmacy_admin — уже существует (POSTGRES_USER), полный доступ.
-- =====================================================================
-- Дополнительно ничего не делаем: как владелец БД он имеет все права
-- на свои объекты. Для наглядности — комментарий.
COMMENT ON DATABASE pharmacy_warehouse IS
    'БД «Аптечный склад» (курсовая ГУАП, вариант 7). Владелец: pharmacy_admin.';

-- ---------------------------------------------------------------------
-- Гарантия, что будущие таблицы/функции тоже получат правильные права
-- (default privileges — применяются к объектам, которые будут созданы
-- текущим пользователем pharmacy_admin в схеме public).
-- ---------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT SELECT ON TABLES TO pharmacy_director;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT EXECUTE ON FUNCTIONS TO pharmacy_director;
