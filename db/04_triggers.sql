-- =====================================================================
-- 04_triggers.sql — 6 разнотипных триггеров (минимум 5 по методичке)
-- Применяется после 03_functions.sql.
-- =====================================================================
-- Типы триггеров:
--   1. Проверка допустимости значений (retail >= purchase)
--   2. Контроль бизнес-инварианта (нельзя отгрузить больше, чем на складе)
--   3. Валидация формата (ИНН 10/12 цифр, телефон ≥ 10 цифр)
--   4. Автоматическое логирование (изменения зарплаты → employee_salary_log)
--   5. Защита ссылочной целостности (нельзя удалить препарат со связями)
--   6. Проверка границ значений (дата операции не в будущем)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Триггер 1: розничная цена не меньше закупочной
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_drugs_price_check()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.retail_price < NEW.purchase_price THEN
        RAISE EXCEPTION
            'Розничная цена (%) не может быть ниже закупочной (%). Препарат: "%"',
            NEW.retail_price, NEW.purchase_price, NEW.drug_name;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_drugs_price_check ON drugs;
CREATE TRIGGER trg_drugs_price_check
    BEFORE INSERT OR UPDATE OF purchase_price, retail_price ON drugs
    FOR EACH ROW EXECUTE FUNCTION trg_fn_drugs_price_check();

-- ---------------------------------------------------------------------
-- Триггер 2: контроль остатков при отгрузке
-- Нельзя отгрузить в филиал больше, чем числится на складе
-- (склад = сумма принятого − сумма уже отгруженного).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_dispatch_stock_check()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_supplied    INTEGER;
    v_dispatched  INTEGER;
    v_current     INTEGER;
    v_drug_name   VARCHAR;
BEGIN
    -- Защита от race condition при параллельной отгрузке одного препарата.
    -- pg_advisory_xact_lock берёт транзакционную advisory-блокировку
    -- по id препарата: другие транзакции, пытающиеся отгрузить тот же
    -- препарат, будут ждать до COMMIT/ROLLBACK. Это проще FOR UPDATE
    -- (несовместимого с агрегатами) и эффективнее SERIALIZABLE.
    PERFORM pg_advisory_xact_lock(NEW.id_drug::BIGINT);

    -- сумма поступлений на склад
    SELECT COALESCE(SUM(quantity), 0) INTO v_supplied
    FROM warehouse_supply_items WHERE id_drug = NEW.id_drug;

    -- сумма ранее отгруженных (при UPDATE — исключаем текущую строку)
    SELECT COALESCE(SUM(quantity), 0) INTO v_dispatched
    FROM pharmacy_dispatch_items
    WHERE id_drug = NEW.id_drug
      AND (TG_OP = 'INSERT' OR id_dispatch_item <> NEW.id_dispatch_item);

    v_current := v_supplied - v_dispatched;

    IF v_current < NEW.quantity THEN
        SELECT drug_name INTO v_drug_name FROM drugs WHERE id_drug = NEW.id_drug;
        RAISE EXCEPTION
            'Недостаточно препарата "%" на складе: доступно % ед., запрошено % ед.',
            v_drug_name, v_current, NEW.quantity;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dispatch_stock_check ON pharmacy_dispatch_items;
CREATE TRIGGER trg_dispatch_stock_check
    BEFORE INSERT OR UPDATE ON pharmacy_dispatch_items
    FOR EACH ROW EXECUTE FUNCTION trg_fn_dispatch_stock_check();

-- ---------------------------------------------------------------------
-- Триггер 3: формат ИНН (10 или 12 цифр) и телефона у поставщиков
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_supplier_format_check()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_phone_digits TEXT;
BEGIN
    -- ИНН: строго 10 цифр (юрлицо) или 12 цифр (ИП)
    IF NEW.inn IS NULL OR NEW.inn !~ '^(\d{10}|\d{12})$' THEN
        RAISE EXCEPTION
            'Некорректный формат ИНН "%". Должно быть ровно 10 или 12 цифр',
            NEW.inn;
    END IF;

    -- Телефон: содержит не менее 10 цифр (допускаем +, скобки, дефисы, пробелы)
    v_phone_digits := regexp_replace(COALESCE(NEW.phone, ''), '\D', '', 'g');
    IF length(v_phone_digits) < 10 THEN
        RAISE EXCEPTION
            'Номер телефона "%" должен содержать минимум 10 цифр', NEW.phone;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_supplier_format_check ON suppliers;
CREATE TRIGGER trg_supplier_format_check
    BEFORE INSERT OR UPDATE ON suppliers
    FOR EACH ROW EXECUTE FUNCTION trg_fn_supplier_format_check();

-- ---------------------------------------------------------------------
-- Триггер 4: автоматический лог изменений зарплаты сотрудников
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_employee_salary_log()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.salary IS DISTINCT FROM NEW.salary THEN
        INSERT INTO employee_salary_log (id_employee, old_salary, new_salary)
        VALUES (NEW.id_employee, OLD.salary, NEW.salary);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employee_salary_log ON employees;
CREATE TRIGGER trg_employee_salary_log
    AFTER UPDATE OF salary ON employees
    FOR EACH ROW EXECUTE FUNCTION trg_fn_employee_salary_log();

-- ---------------------------------------------------------------------
-- Триггер 5: запрет удаления препарата, по которому были поставки,
-- отгрузки или продажи (более дружелюбная ошибка, чем FK RESTRICT)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_drug_delete_check()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_supply_cnt    INTEGER;
    v_dispatch_cnt  INTEGER;
    v_sale_cnt      INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_supply_cnt
    FROM warehouse_supply_items WHERE id_drug = OLD.id_drug;

    SELECT COUNT(*) INTO v_dispatch_cnt
    FROM pharmacy_dispatch_items WHERE id_drug = OLD.id_drug;

    SELECT COUNT(*) INTO v_sale_cnt
    FROM pharmacy_sales WHERE id_drug = OLD.id_drug;

    IF v_supply_cnt + v_dispatch_cnt + v_sale_cnt > 0 THEN
        RAISE EXCEPTION
            'Нельзя удалить препарат "%": по нему есть % поставок, % отгрузок, % продаж',
            OLD.drug_name, v_supply_cnt, v_dispatch_cnt, v_sale_cnt;
    END IF;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_drug_delete_check ON drugs;
CREATE TRIGGER trg_drug_delete_check
    BEFORE DELETE ON drugs
    FOR EACH ROW EXECUTE FUNCTION trg_fn_drug_delete_check();

-- ---------------------------------------------------------------------
-- Триггер 6: дата операции не в будущем
-- (один общий триггер-функция на три таблицы — поставки, отгрузки, продажи)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_operation_date_check()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_op_date DATE;
    v_field   TEXT;
BEGIN
    -- В зависимости от таблицы достаём нужное поле
    CASE TG_TABLE_NAME
        WHEN 'warehouse_supplies'   THEN v_op_date := NEW.supply_date;    v_field := 'supply_date';
        WHEN 'pharmacy_dispatches'  THEN v_op_date := NEW.dispatch_date;  v_field := 'dispatch_date';
        WHEN 'pharmacy_sales'       THEN v_op_date := NEW.sale_date;      v_field := 'sale_date';
    END CASE;

    IF v_op_date > CURRENT_DATE THEN
        RAISE EXCEPTION
            'Дата операции (%) в таблице "%" находится в будущем. Текущая дата: %',
            v_op_date, TG_TABLE_NAME, CURRENT_DATE;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_supply_date_check    ON warehouse_supplies;
DROP TRIGGER IF EXISTS trg_dispatch_date_check  ON pharmacy_dispatches;
DROP TRIGGER IF EXISTS trg_sale_date_check      ON pharmacy_sales;

CREATE TRIGGER trg_supply_date_check
    BEFORE INSERT OR UPDATE ON warehouse_supplies
    FOR EACH ROW EXECUTE FUNCTION trg_fn_operation_date_check();

CREATE TRIGGER trg_dispatch_date_check
    BEFORE INSERT OR UPDATE ON pharmacy_dispatches
    FOR EACH ROW EXECUTE FUNCTION trg_fn_operation_date_check();

CREATE TRIGGER trg_sale_date_check
    BEFORE INSERT OR UPDATE ON pharmacy_sales
    FOR EACH ROW EXECUTE FUNCTION trg_fn_operation_date_check();
