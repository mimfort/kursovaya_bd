"""
Эндпоинты для 10 запросов курсовой (5.1–5.10).
Все они вызывают соответствующие хранимые функции PostgreSQL.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, ValidationError
from sqlalchemy import text
from sqlalchemy.orm import Session

from app import schemas
from app.database import get_session


def _validate(model_cls: type[BaseModel], **kwargs) -> BaseModel:
    """Валидация входа Pydantic-моделью с переводом ошибки в HTTP 400."""
    try:
        return model_cls(**kwargs)
    except ValidationError as e:
        detail = "; ".join(err.get("msg", str(err)) for err in e.errors())
        raise HTTPException(status_code=400, detail=detail)

router = APIRouter(prefix="/queries", tags=["queries"])


def session_by_role(x_role: str = Header("admin")) -> Session:
    try:
        yield from get_session(x_role)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


def _call(session: Session, sql: str, params: dict[str, Any] | None = None) -> dict:
    """Выполняет SQL, возвращает list[dict] + count. Исключения PG
    пробрасываются; их ловит глобальный handler в main.py."""
    result = session.execute(text(sql), params or {}).mappings().all()
    rows = [dict(r) for r in result]
    return {"rows": rows, "count": len(rows)}


# ---------------------------------------------------------------------
# 5.1 — препараты указанной группы
# ---------------------------------------------------------------------
@router.get("/drugs-by-group", summary="5.1 Препараты определённой группы")
def drugs_by_group(group_name: str, session: Session = Depends(session_by_role)):
    _validate(schemas.GroupNameIn, group_name=group_name)
    return _call(session, "SELECT * FROM get_drugs_by_group(:g)", {"g": group_name})


# ---------------------------------------------------------------------
# 5.2 — препараты в заданном интервале цен
# ---------------------------------------------------------------------
@router.get("/drugs-by-price-range", summary="5.2 Препараты в интервале цен")
def drugs_by_price_range(
    min_price: float, max_price: float,
    session: Session = Depends(session_by_role),
):
    _validate(schemas.PriceRangeIn, min_price=min_price, max_price=max_price)
    # CAST — иначе PostgreSQL получает double precision и не находит
    # функцию с (NUMERIC, NUMERIC) (синтаксис ::NUMERIC ломается в
    # SQLAlchemy text(), где : — префикс параметра).
    return _call(
        session,
        "SELECT * FROM get_drugs_by_price_range(CAST(:mn AS NUMERIC), CAST(:mx AS NUMERIC))",
        {"mn": min_price, "mx": max_price},
    )


# ---------------------------------------------------------------------
# 5.3 — препараты одного производителя
# ---------------------------------------------------------------------
@router.get("/drugs-by-manufacturer", summary="5.3 Препараты одного производителя")
def drugs_by_manufacturer(
    manufacturer_name: str, session: Session = Depends(session_by_role),
):
    _validate(schemas.ManufacturerNameIn, manufacturer_name=manufacturer_name)
    return _call(
        session,
        "SELECT * FROM get_drugs_by_manufacturer(:m)",
        {"m": manufacturer_name},
    )


# ---------------------------------------------------------------------
# 5.4 — препараты, переданные в конкретную аптеку
# ---------------------------------------------------------------------
@router.get("/drugs-dispatched-to-pharmacy", summary="5.4 Препараты в аптеке")
def drugs_dispatched_to_pharmacy(
    pharmacy_name: str, session: Session = Depends(session_by_role),
):
    _validate(schemas.PharmacyNameIn, pharmacy_name=pharmacy_name)
    return _call(
        session,
        "SELECT * FROM get_drugs_dispatched_to_pharmacy(:p)",
        {"p": pharmacy_name},
    )


# ---------------------------------------------------------------------
# 5.5 — препараты, поставляемые данным поставщиком
# ---------------------------------------------------------------------
@router.get("/drugs-by-supplier", summary="5.5 Препараты от поставщика")
def drugs_by_supplier(
    supplier_name: str, session: Session = Depends(session_by_role),
):
    _validate(schemas.SupplierNameIn, supplier_name=supplier_name)
    return _call(
        session,
        "SELECT * FROM get_drugs_by_supplier(:s)",
        {"s": supplier_name},
    )


# ---------------------------------------------------------------------
# 5.6 — движения препаратов за период
# ---------------------------------------------------------------------
@router.get("/movements-by-period", summary="5.6 Движения препаратов за период")
def movements_by_period(
    start_date: str, end_date: str,
    session: Session = Depends(session_by_role),
):
    from datetime import date as _date
    try:
        sd, ed = _date.fromisoformat(start_date), _date.fromisoformat(end_date)
    except ValueError:
        raise HTTPException(400, "Даты должны быть в формате YYYY-MM-DD")
    _validate(schemas.PeriodIn, start_date=sd, end_date=ed)
    return _call(
        session,
        "SELECT * FROM get_movements_by_period(:s, :e)",
        {"s": start_date, "e": end_date},
    )


# ---------------------------------------------------------------------
# 5.7 — топ-10 популярных препаратов со средней ценой
# ---------------------------------------------------------------------
@router.get("/top10-avg-retail-price", summary="5.7 Топ-10 по средней цене")
def top10_avg_retail_price(session: Session = Depends(session_by_role)):
    return _call(session, "SELECT * FROM get_top10_avg_retail_price()")


# ---------------------------------------------------------------------
# 5.8 — поставщик с макс разнообразием за последний год
# ---------------------------------------------------------------------
@router.get("/top-supplier-last-year", summary="5.8 Топ-поставщик за год")
def top_supplier_last_year(session: Session = Depends(session_by_role)):
    return _call(session, "SELECT * FROM get_top_supplier_last_year()")


# ---------------------------------------------------------------------
# 5.9 — топ-3 препарата в каждом филиале за 6 месяцев
# ---------------------------------------------------------------------
@router.get("/top3-drugs-by-pharmacy", summary="5.9 Топ-3 препарата по филиалам")
def top3_drugs_by_pharmacy(session: Session = Depends(session_by_role)):
    return _call(session, "SELECT * FROM get_top3_drugs_by_pharmacy_last_6m()")


# ---------------------------------------------------------------------
# 5.10 — препараты с низким остатком
# ---------------------------------------------------------------------
@router.get("/low-stock-drugs", summary="5.10 Препараты с низким остатком")
def low_stock_drugs(
    threshold: int,
    session: Session = Depends(session_by_role),
):
    _validate(schemas.ThresholdIn, threshold=threshold)
    return _call(
        session,
        "SELECT * FROM get_low_stock_drugs(:t)",
        {"t": threshold},
    )
