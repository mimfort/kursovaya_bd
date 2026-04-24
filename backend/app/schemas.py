"""
Pydantic-схемы для валидации входа в API и типизации ответов.
Модели БД не описываем — всё проходит через хранимые функции.
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, Field, field_validator


# ---------------------------------------------------------------------
# Запросы (5.1–5.10) — входные параметры
# ---------------------------------------------------------------------

class GroupNameIn(BaseModel):
    group_name: str = Field(..., min_length=1, max_length=100,
                            description="Название группы препаратов (например, 'Антибиотики')")


class PriceRangeIn(BaseModel):
    min_price: Decimal = Field(..., ge=0, description="Нижняя граница розничной цены")
    max_price: Decimal = Field(..., ge=0, description="Верхняя граница розничной цены")

    @field_validator("max_price")
    @classmethod
    def _max_ge_min(cls, v: Decimal, info):
        if "min_price" in info.data and v < info.data["min_price"]:
            raise ValueError("Верхняя граница меньше нижней")
        return v


class ManufacturerNameIn(BaseModel):
    manufacturer_name: str = Field(..., min_length=1, max_length=150)


class PharmacyNameIn(BaseModel):
    pharmacy_name: str = Field(..., min_length=1, max_length=200)


class SupplierNameIn(BaseModel):
    supplier_name: str = Field(..., min_length=1, max_length=200)


class PeriodIn(BaseModel):
    start_date: date
    end_date:   date

    @field_validator("end_date")
    @classmethod
    def _end_ge_start(cls, v: date, info):
        if "start_date" in info.data and v < info.data["start_date"]:
            raise ValueError("Конец периода раньше начала")
        return v


class ThresholdIn(BaseModel):
    threshold: int = Field(..., ge=0, description="Порог остатка на складе")


# ---------------------------------------------------------------------
# Ответы — универсальные обёртки (строки хранимых функций произвольны
# по структуре, поэтому отдаём list[dict] без жёсткой схемы).
# ---------------------------------------------------------------------

class RowsResponse(BaseModel):
    rows: list[dict[str, Any]]
    count: int


class ErrorResponse(BaseModel):
    detail: str
