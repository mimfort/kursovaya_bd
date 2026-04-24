-- =====================================================================
-- 03_functions.sql — 10 хранимых функций (запросы 5.1 – 5.10 из первой части)
-- Применяется после 02_seed.sql.
-- =====================================================================
-- Все функции, имеющие входные параметры, валидируют их и при некорректном
-- вводе выбрасывают RAISE EXCEPTION с понятным сообщением на русском
-- (SQLSTATE P0001 — стандартный код plpgsql raise_exception). Backend
-- переводит такой код в HTTP 400 с текстом ошибки из MESSAGE.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5.1 Информация о препаратах определённой группы
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_drugs_by_group(p_group_name TEXT)
RETURNS TABLE (
    drug_name          VARCHAR,
    manufacturer_name  VARCHAR,
    purpose_name       VARCHAR,
    unit               VARCHAR,
    purchase_price     NUMERIC,
    retail_price       NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_group_id INT;
BEGIN
    IF p_group_name IS NULL OR btrim(p_group_name) = '' THEN
        RAISE EXCEPTION 'Название группы не может быть пустым';
    END IF;

    SELECT id_group INTO v_group_id
    FROM drug_groups
    WHERE lower(group_name) = lower(btrim(p_group_name));

    IF v_group_id IS NULL THEN
        RAISE EXCEPTION 'Группа препаратов "%" не найдена в справочнике', p_group_name;
    END IF;

    RETURN QUERY
    SELECT  d.drug_name, m.manufacturer_name, p.purpose_name,
            d.unit,      d.purchase_price,    d.retail_price
    FROM    drugs d
    JOIN    manufacturers  m ON m.id_manufacturer = d.id_manufacturer
    JOIN    drug_purposes  p ON p.id_purpose      = d.id_purpose
    WHERE   d.id_group = v_group_id
    ORDER BY d.drug_name;
END;
$$;
COMMENT ON FUNCTION get_drugs_by_group(TEXT) IS
    'Запрос 5.1: препараты указанной группы (параметр: название группы)';

-- ---------------------------------------------------------------------
-- 5.2 Препараты в заданном интервале розничных цен
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_drugs_by_price_range(
    p_min_price NUMERIC,
    p_max_price NUMERIC
)
RETURNS TABLE (
    drug_name          VARCHAR,
    manufacturer_name  VARCHAR,
    group_name         VARCHAR,
    purpose_name       VARCHAR,
    retail_price       NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    IF p_min_price IS NULL OR p_max_price IS NULL THEN
        RAISE EXCEPTION 'Обе границы интервала цен должны быть заданы';
    END IF;
    IF p_min_price < 0 OR p_max_price < 0 THEN
        RAISE EXCEPTION 'Цены не могут быть отрицательными (получено: min=%, max=%)',
                        p_min_price, p_max_price;
    END IF;
    IF p_max_price < p_min_price THEN
        RAISE EXCEPTION 'Верхняя граница интервала (%) меньше нижней (%)',
                        p_max_price, p_min_price;
    END IF;

    RETURN QUERY
    SELECT  d.drug_name, m.manufacturer_name, g.group_name, p.purpose_name, d.retail_price
    FROM    drugs d
    JOIN    manufacturers  m ON m.id_manufacturer = d.id_manufacturer
    JOIN    drug_groups    g ON g.id_group        = d.id_group
    JOIN    drug_purposes  p ON p.id_purpose      = d.id_purpose
    WHERE   d.retail_price BETWEEN p_min_price AND p_max_price
    ORDER BY d.retail_price, d.drug_name;
END;
$$;
COMMENT ON FUNCTION get_drugs_by_price_range(NUMERIC, NUMERIC) IS
    'Запрос 5.2: препараты в заданном интервале цен';

-- ---------------------------------------------------------------------
-- 5.3 Препараты одного производителя
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_drugs_by_manufacturer(p_manufacturer_name TEXT)
RETURNS TABLE (
    drug_name       VARCHAR,
    group_name      VARCHAR,
    purpose_name    VARCHAR,
    unit            VARCHAR,
    retail_price    NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_manufacturer_id INT;
BEGIN
    IF p_manufacturer_name IS NULL OR btrim(p_manufacturer_name) = '' THEN
        RAISE EXCEPTION 'Название производителя не может быть пустым';
    END IF;

    SELECT id_manufacturer INTO v_manufacturer_id
    FROM manufacturers
    WHERE lower(manufacturer_name) = lower(btrim(p_manufacturer_name));

    IF v_manufacturer_id IS NULL THEN
        RAISE EXCEPTION 'Производитель "%" не найден в справочнике', p_manufacturer_name;
    END IF;

    RETURN QUERY
    SELECT  d.drug_name, g.group_name, p.purpose_name, d.unit, d.retail_price
    FROM    drugs d
    JOIN    drug_groups    g ON g.id_group   = d.id_group
    JOIN    drug_purposes  p ON p.id_purpose = d.id_purpose
    WHERE   d.id_manufacturer = v_manufacturer_id
    ORDER BY d.drug_name;
END;
$$;
COMMENT ON FUNCTION get_drugs_by_manufacturer(TEXT) IS
    'Запрос 5.3: препараты одного производителя';

-- ---------------------------------------------------------------------
-- 5.4 Препараты, переданные в конкретную аптеку (за всё время)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_drugs_dispatched_to_pharmacy(p_pharmacy_name TEXT)
RETURNS TABLE (
    drug_name           VARCHAR,
    group_name          VARCHAR,
    manufacturer_name   VARCHAR,
    total_quantity      BIGINT,
    first_dispatch_date DATE,
    last_dispatch_date  DATE
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_pharmacy_id INT;
BEGIN
    IF p_pharmacy_name IS NULL OR btrim(p_pharmacy_name) = '' THEN
        RAISE EXCEPTION 'Название аптеки не может быть пустым';
    END IF;

    SELECT id_pharmacy INTO v_pharmacy_id
    FROM pharmacies
    WHERE lower(pharmacy_name) = lower(btrim(p_pharmacy_name));

    IF v_pharmacy_id IS NULL THEN
        RAISE EXCEPTION 'Филиал аптеки "%" не найден', p_pharmacy_name;
    END IF;

    RETURN QUERY
    SELECT  d.drug_name,
            g.group_name,
            m.manufacturer_name,
            SUM(pdi.quantity)::BIGINT AS total_quantity,
            MIN(pd.dispatch_date)     AS first_dispatch_date,
            MAX(pd.dispatch_date)     AS last_dispatch_date
    FROM    pharmacy_dispatches      pd
    JOIN    pharmacy_dispatch_items  pdi ON pdi.id_dispatch    = pd.id_dispatch
    JOIN    drugs                    d   ON d.id_drug          = pdi.id_drug
    JOIN    drug_groups              g   ON g.id_group         = d.id_group
    JOIN    manufacturers            m   ON m.id_manufacturer  = d.id_manufacturer
    WHERE   pd.id_pharmacy = v_pharmacy_id
    GROUP BY d.drug_name, g.group_name, m.manufacturer_name
    ORDER BY total_quantity DESC, d.drug_name;
END;
$$;
COMMENT ON FUNCTION get_drugs_dispatched_to_pharmacy(TEXT) IS
    'Запрос 5.4: препараты, переданные в конкретную аптеку';

-- ---------------------------------------------------------------------
-- 5.5 Препараты, поставляемые данным поставщиком
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_drugs_by_supplier(p_supplier_name TEXT)
RETURNS TABLE (
    drug_name          VARCHAR,
    manufacturer_name  VARCHAR,
    total_supplied     BIGINT,
    first_supply_date  DATE,
    last_supply_date   DATE,
    supplies_count     BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_supplier_id INT;
BEGIN
    IF p_supplier_name IS NULL OR btrim(p_supplier_name) = '' THEN
        RAISE EXCEPTION 'Название поставщика не может быть пустым';
    END IF;

    SELECT id_supplier INTO v_supplier_id
    FROM suppliers
    WHERE lower(supplier_name) = lower(btrim(p_supplier_name));

    IF v_supplier_id IS NULL THEN
        RAISE EXCEPTION 'Поставщик "%" не найден в справочнике', p_supplier_name;
    END IF;

    RETURN QUERY
    SELECT  d.drug_name,
            m.manufacturer_name,
            SUM(wsi.quantity)::BIGINT         AS total_supplied,
            MIN(ws.supply_date)               AS first_supply_date,
            MAX(ws.supply_date)               AS last_supply_date,
            COUNT(DISTINCT ws.id_supply)::BIGINT AS supplies_count
    FROM    warehouse_supplies       ws
    JOIN    warehouse_supply_items   wsi ON wsi.id_supply       = ws.id_supply
    JOIN    drugs                    d   ON d.id_drug           = wsi.id_drug
    JOIN    manufacturers            m   ON m.id_manufacturer   = d.id_manufacturer
    WHERE   ws.id_supplier = v_supplier_id
    GROUP BY d.drug_name, m.manufacturer_name
    ORDER BY total_supplied DESC, d.drug_name;
END;
$$;
COMMENT ON FUNCTION get_drugs_by_supplier(TEXT) IS
    'Запрос 5.5: препараты, поставляемые данным поставщиком';

-- ---------------------------------------------------------------------
-- 5.6 Принятые и переданные препараты и их количества за период
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_movements_by_period(
    p_start DATE,
    p_end   DATE
)
RETURNS TABLE (
    drug_name       VARCHAR,
    group_name      VARCHAR,
    supplied_qty    BIGINT,
    dispatched_qty  BIGINT,
    balance_change  BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    IF p_start IS NULL OR p_end IS NULL THEN
        RAISE EXCEPTION 'Обе даты (начало и конец периода) должны быть заданы';
    END IF;
    IF p_end < p_start THEN
        RAISE EXCEPTION 'Конец периода (%) раньше начала (%)', p_end, p_start;
    END IF;
    IF p_start > CURRENT_DATE THEN
        RAISE EXCEPTION 'Начало периода (%) находится в будущем', p_start;
    END IF;

    RETURN QUERY
    WITH supplied AS (
        SELECT wsi.id_drug, SUM(wsi.quantity) AS qty
        FROM   warehouse_supplies     ws
        JOIN   warehouse_supply_items wsi ON wsi.id_supply = ws.id_supply
        WHERE  ws.supply_date BETWEEN p_start AND p_end
        GROUP BY wsi.id_drug
    ),
    dispatched AS (
        SELECT pdi.id_drug, SUM(pdi.quantity) AS qty
        FROM   pharmacy_dispatches       pd
        JOIN   pharmacy_dispatch_items   pdi ON pdi.id_dispatch = pd.id_dispatch
        WHERE  pd.dispatch_date BETWEEN p_start AND p_end
        GROUP BY pdi.id_drug
    )
    SELECT  d.drug_name,
            g.group_name,
            COALESCE(s.qty, 0)::BIGINT AS supplied_qty,
            COALESCE(x.qty, 0)::BIGINT AS dispatched_qty,
            (COALESCE(s.qty, 0) - COALESCE(x.qty, 0))::BIGINT AS balance_change
    FROM    drugs d
    JOIN    drug_groups g ON g.id_group = d.id_group
    LEFT    JOIN supplied   s ON s.id_drug = d.id_drug
    LEFT    JOIN dispatched x ON x.id_drug = d.id_drug
    WHERE   s.qty IS NOT NULL OR x.qty IS NOT NULL
    ORDER BY d.drug_name;
END;
$$;
COMMENT ON FUNCTION get_movements_by_period(DATE, DATE) IS
    'Запрос 5.6: движение препаратов (поставки и отгрузки) за период';

-- ---------------------------------------------------------------------
-- 5.7 Средняя цена реализации 10 наиболее популярных препаратов
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_top10_avg_retail_price()
RETURNS TABLE (
    drug_name          VARCHAR,
    manufacturer_name  VARCHAR,
    total_sold         BIGINT,
    avg_sale_price     NUMERIC,
    current_retail_price NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT  d.drug_name,
            m.manufacturer_name,
            SUM(s.quantity)::BIGINT              AS total_sold,
            ROUND(AVG(s.sale_price), 2)          AS avg_sale_price,
            d.retail_price                       AS current_retail_price
    FROM    pharmacy_sales s
    JOIN    drugs d          ON d.id_drug = s.id_drug
    JOIN    manufacturers m  ON m.id_manufacturer = d.id_manufacturer
    GROUP BY d.drug_name, m.manufacturer_name, d.retail_price
    ORDER BY total_sold DESC, avg_sale_price DESC
    LIMIT 10;
END;
$$;
COMMENT ON FUNCTION get_top10_avg_retail_price() IS
    'Запрос 5.7: средняя цена реализации 10 самых популярных препаратов';

-- ---------------------------------------------------------------------
-- 5.8 [СЛОЖНЫЙ] Поставщик с максимальным разнообразием препаратов
--     за последний год
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_top_supplier_last_year()
RETURNS TABLE (
    supplier_name      VARCHAR,
    city_name          VARCHAR,
    distinct_drugs     BIGINT,
    total_units        BIGINT,
    total_value        NUMERIC,
    supplies_count     BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_period_start DATE := CURRENT_DATE - INTERVAL '1 year';
BEGIN
    RETURN QUERY
    SELECT  sup.supplier_name,
            c.city_name,
            COUNT(DISTINCT wsi.id_drug)::BIGINT   AS distinct_drugs,
            SUM(wsi.quantity)::BIGINT             AS total_units,
            ROUND(SUM(wsi.quantity * d.purchase_price), 2) AS total_value,
            COUNT(DISTINCT ws.id_supply)::BIGINT  AS supplies_count
    FROM    warehouse_supplies       ws
    JOIN    warehouse_supply_items   wsi ON wsi.id_supply     = ws.id_supply
    JOIN    drugs                    d   ON d.id_drug         = wsi.id_drug
    JOIN    suppliers                sup ON sup.id_supplier   = ws.id_supplier
    JOIN    cities                   c   ON c.id_city         = sup.id_city
    WHERE   ws.supply_date >= v_period_start
    GROUP BY sup.supplier_name, c.city_name
    ORDER BY distinct_drugs DESC, total_units DESC
    LIMIT 1;
END;
$$;
COMMENT ON FUNCTION get_top_supplier_last_year() IS
    'Запрос 5.8 (сложный): топ-поставщик за последний год по разнообразию препаратов';

-- ---------------------------------------------------------------------
-- 5.9 [СЛОЖНЫЙ] Топ-3 препарата по продажам в каждом филиале за 6 месяцев
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_top3_drugs_by_pharmacy_last_6m()
RETURNS TABLE (
    pharmacy_name   VARCHAR,
    rank_in_pharmacy INT,
    drug_name       VARCHAR,
    group_name      VARCHAR,
    total_sold      BIGINT,
    total_revenue   NUMERIC
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_period_start DATE := CURRENT_DATE - INTERVAL '6 months';
BEGIN
    RETURN QUERY
    WITH sales_agg AS (
        SELECT  ph.id_pharmacy,
                ph.pharmacy_name,
                d.id_drug,
                d.drug_name,
                g.group_name,
                SUM(s.quantity)               AS qty,
                SUM(s.quantity * s.sale_price) AS revenue
        FROM    pharmacy_sales s
        JOIN    pharmacies   ph ON ph.id_pharmacy = s.id_pharmacy
        JOIN    drugs        d  ON d.id_drug      = s.id_drug
        JOIN    drug_groups  g  ON g.id_group     = d.id_group
        WHERE   s.sale_date >= v_period_start
        GROUP BY ph.id_pharmacy, ph.pharmacy_name, d.id_drug, d.drug_name, g.group_name
    ),
    ranked AS (
        SELECT  sa.*,
                ROW_NUMBER() OVER (PARTITION BY sa.id_pharmacy ORDER BY sa.qty DESC, sa.drug_name) AS rnk
        FROM    sales_agg sa
    )
    SELECT  r.pharmacy_name,
            r.rnk::INT,
            r.drug_name,
            r.group_name,
            r.qty::BIGINT,
            ROUND(r.revenue, 2) AS total_revenue
    FROM    ranked r
    WHERE   r.rnk <= 3
    ORDER BY r.pharmacy_name, r.rnk;
END;
$$;
COMMENT ON FUNCTION get_top3_drugs_by_pharmacy_last_6m() IS
    'Запрос 5.9 (сложный): топ-3 препарата по продажам в каждой аптеке за последние 6 месяцев';

-- ---------------------------------------------------------------------
-- 5.10 [СЛОЖНЫЙ] Препараты с остатком ниже заданного порога
--      Остаток = суммарно принято на склад − суммарно отгружено в филиалы
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_low_stock_drugs(p_threshold INT)
RETURNS TABLE (
    drug_name           VARCHAR,
    group_name          VARCHAR,
    manufacturer_name   VARCHAR,
    total_supplied      BIGINT,
    total_dispatched    BIGINT,
    current_stock       BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    IF p_threshold IS NULL THEN
        RAISE EXCEPTION 'Пороговое значение остатка должно быть задано';
    END IF;
    IF p_threshold < 0 THEN
        RAISE EXCEPTION 'Пороговое значение не может быть отрицательным (получено: %)', p_threshold;
    END IF;

    RETURN QUERY
    WITH supplied AS (
        SELECT id_drug, SUM(quantity) AS qty
        FROM   warehouse_supply_items
        GROUP BY id_drug
    ),
    dispatched AS (
        SELECT id_drug, SUM(quantity) AS qty
        FROM   pharmacy_dispatch_items
        GROUP BY id_drug
    )
    SELECT  d.drug_name,
            g.group_name,
            m.manufacturer_name,
            COALESCE(s.qty, 0)::BIGINT  AS total_supplied,
            COALESCE(x.qty, 0)::BIGINT  AS total_dispatched,
            (COALESCE(s.qty, 0) - COALESCE(x.qty, 0))::BIGINT AS current_stock
    FROM    drugs d
    JOIN    drug_groups    g ON g.id_group        = d.id_group
    JOIN    manufacturers  m ON m.id_manufacturer = d.id_manufacturer
    LEFT    JOIN supplied   s ON s.id_drug = d.id_drug
    LEFT    JOIN dispatched x ON x.id_drug = d.id_drug
    WHERE   (COALESCE(s.qty, 0) - COALESCE(x.qty, 0)) < p_threshold
    ORDER BY current_stock, d.drug_name;
END;
$$;
COMMENT ON FUNCTION get_low_stock_drugs(INT) IS
    'Запрос 5.10 (сложный): препараты с остатком на складе ниже заданного порога';

-- =====================================================================
-- ФУНКЦИИ АНАЛИТИКИ (данные для графиков Plotly)
-- Все агрегации выполняются СУБД, приложение — только транспорт.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Выручка по филиалам (для столбчатой диаграммы)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_revenue_by_pharmacy()
RETURNS TABLE (
    pharmacy_name  VARCHAR,
    city_name      VARCHAR,
    revenue        NUMERIC,
    items_sold     BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT  ph.pharmacy_name,
            c.city_name,
            SUM(s.quantity * s.sale_price)::NUMERIC(12,2) AS revenue,
            SUM(s.quantity)::BIGINT                       AS items_sold
    FROM    pharmacy_sales s
    JOIN    pharmacies ph ON ph.id_pharmacy = s.id_pharmacy
    JOIN    cities     c  ON c.id_city      = ph.id_city
    GROUP BY ph.pharmacy_name, c.city_name
    ORDER BY revenue DESC;
END;
$$;
COMMENT ON FUNCTION get_revenue_by_pharmacy() IS
    'Аналитика: суммарная выручка по филиалам (для столбчатой диаграммы)';

-- ---------------------------------------------------------------------
-- Доли продаж по группам препаратов (для круговой диаграммы)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_sales_share_by_group()
RETURNS TABLE (
    group_name  VARCHAR,
    revenue     NUMERIC,
    items_sold  BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT  g.group_name,
            SUM(s.quantity * s.sale_price)::NUMERIC(12,2) AS revenue,
            SUM(s.quantity)::BIGINT                       AS items_sold
    FROM    pharmacy_sales s
    JOIN    drugs       d ON d.id_drug  = s.id_drug
    JOIN    drug_groups g ON g.id_group = d.id_group
    GROUP BY g.group_name
    ORDER BY revenue DESC;
END;
$$;
COMMENT ON FUNCTION get_sales_share_by_group() IS
    'Аналитика: доли продаж по группам препаратов (для круговой диаграммы)';

-- ---------------------------------------------------------------------
-- Динамика продаж по месяцам (для линейного графика)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_sales_trend_by_month()
RETURNS TABLE (
    month          TEXT,
    revenue        NUMERIC,
    items_sold     BIGINT,
    sales_count    BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT  to_char(date_trunc('month', s.sale_date), 'YYYY-MM') AS month,
            SUM(s.quantity * s.sale_price)::NUMERIC(12,2)        AS revenue,
            SUM(s.quantity)::BIGINT                              AS items_sold,
            COUNT(DISTINCT s.id_sale)::BIGINT                    AS sales_count
    FROM    pharmacy_sales s
    GROUP BY 1
    ORDER BY 1;
END;
$$;
COMMENT ON FUNCTION get_sales_trend_by_month() IS
    'Аналитика: помесячная динамика выручки (для линейного графика)';

-- ---------------------------------------------------------------------
-- Продажи: филиалы × группы препаратов (для heatmap)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_heatmap_pharmacy_group()
RETURNS TABLE (
    pharmacy_name  VARCHAR,
    group_name     VARCHAR,
    items_sold     BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT  ph.pharmacy_name,
            g.group_name,
            SUM(s.quantity)::BIGINT AS items_sold
    FROM    pharmacy_sales s
    JOIN    pharmacies  ph ON ph.id_pharmacy = s.id_pharmacy
    JOIN    drugs       d  ON d.id_drug      = s.id_drug
    JOIN    drug_groups g  ON g.id_group     = d.id_group
    GROUP BY ph.pharmacy_name, g.group_name
    ORDER BY ph.pharmacy_name, g.group_name;
END;
$$;
COMMENT ON FUNCTION get_heatmap_pharmacy_group() IS
    'Аналитика: таблица «филиал × группа» для тепловой карты';
