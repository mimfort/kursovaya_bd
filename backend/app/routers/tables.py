"""
Эндпоинты для просмотра содержимого всех 15 таблиц БД.

Запросы делаются через обычный SELECT * FROM <table> ORDER BY id — для
просмотра это допустимо (хранимые функции нужны только для содержательных
запросов и аналитики по ТЗ).
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_session

router = APIRouter(prefix="/tables", tags=["tables"])


# Белый список таблиц и их колонок сортировки — защита от SQL-инъекции,
# т.к. имя таблицы нельзя передать через параметр text().
_TABLES: dict[str, str] = {
    "countries":               "id_country",
    "cities":                  "id_city",
    "drug_groups":             "id_group",
    "drug_purposes":           "id_purpose",
    "positions":               "id_position",
    "manufacturers":           "id_manufacturer",
    "drugs":                   "id_drug",
    "suppliers":               "id_supplier",
    "pharmacies":              "id_pharmacy",
    "employees":               "id_employee",
    "warehouse_supplies":      "id_supply",
    "warehouse_supply_items":  "id_supply_item",
    "pharmacy_dispatches":     "id_dispatch",
    "pharmacy_dispatch_items": "id_dispatch_item",
    "pharmacy_sales":          "id_sale",
    "employee_salary_log":     "id_log",
}


def session_by_role(x_role: str = Header("admin")) -> Session:
    """Заголовок X-Role выбирает роль подключения (admin|director|warehouseman)."""
    try:
        yield from get_session(x_role)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("", summary="Список доступных таблиц")
def list_tables() -> dict[str, list[str]]:
    return {"tables": list(_TABLES.keys())}


@router.get("/{table_name}", summary="Содержимое таблицы")
def read_table(
    table_name: str,
    limit:  int = Query(500, ge=1, le=5000),
    offset: int = Query(0,   ge=0),
    session: Session = Depends(session_by_role),
):
    if table_name not in _TABLES:
        raise HTTPException(404, f"Таблица '{table_name}' не существует")
    order_col = _TABLES[table_name]
    # table_name и order_col прошли валидацию по белому списку — безопасно
    sql = text(f'SELECT * FROM "{table_name}" ORDER BY "{order_col}" LIMIT :lim OFFSET :off')
    rows = session.execute(sql, {"lim": limit, "off": offset}).mappings().all()
    return {"rows": [dict(r) for r in rows], "count": len(rows)}
