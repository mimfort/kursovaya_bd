"""
Эндпоинты для страницы «Аналитика».

Все агрегации выполняются на стороне PostgreSQL через хранимые функции
(get_revenue_by_pharmacy, get_sales_share_by_group, get_sales_trend_by_month,
get_heatmap_pharmacy_group). Backend — тонкий транспорт, без SQL в Python.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_session

router = APIRouter(prefix="/analytics", tags=["analytics"])


def session_by_role(x_role: str = Header("admin")) -> Session:
    try:
        yield from get_session(x_role)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


def _call_fn(session: Session, fn_sql: str) -> dict:
    rows = session.execute(text(fn_sql)).mappings().all()
    return {"rows": [dict(r) for r in rows], "count": len(rows)}


@router.get("/revenue-by-pharmacy", summary="Выручка по филиалам")
def revenue_by_pharmacy(session: Session = Depends(session_by_role)):
    return _call_fn(session, "SELECT * FROM get_revenue_by_pharmacy()")


@router.get("/sales-share-by-group", summary="Доли продаж по группам препаратов")
def sales_share_by_group(session: Session = Depends(session_by_role)):
    return _call_fn(session, "SELECT * FROM get_sales_share_by_group()")


@router.get("/sales-trend-by-month", summary="Динамика продаж по месяцам")
def sales_trend_by_month(session: Session = Depends(session_by_role)):
    return _call_fn(session, "SELECT * FROM get_sales_trend_by_month()")


@router.get("/heatmap-pharmacy-group", summary="Heatmap: филиалы × группы препаратов")
def heatmap_pharmacy_group(session: Session = Depends(session_by_role)):
    return _call_fn(session, "SELECT * FROM get_heatmap_pharmacy_group()")
