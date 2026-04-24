"""
FastAPI-приложение для курсовой «Аптечный склад».

Маршруты:
    /tables/*     — просмотр 16 таблиц БД
    /queries/*    — 10 хранимых функций (5.1–5.10)
    /analytics/*  — агрегации для графиков страницы «Аналитика»
    /health       — проверка живости
    /docs         — интерактивный Swagger UI
"""
from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import ValidationError
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from app.database import get_engine
from app.routers import analytics, queries, tables

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("pharmacy-api")

app = FastAPI(
    title="Аптечный склад API",
    description=(
        "Курсовая работа по БД, ГУАП кафедра 41, вариант 7. "
        "Все содержательные запросы реализованы через вызовы хранимых "
        "функций PostgreSQL."
    ),
    version="1.0.0",
)

# Для Streamlit (docker-сеть + localhost)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(tables.router)
app.include_router(queries.router)
app.include_router(analytics.router)


# ---------------------------------------------------------------------
# Pydantic ValidationError из прикладных схем — 400 с читаемым сообщением
# ---------------------------------------------------------------------
@app.exception_handler(ValidationError)
async def _pydantic_validation_handler(request: Request, exc: ValidationError) -> JSONResponse:
    details = "; ".join(err.get("msg", str(err)) for err in exc.errors())
    return JSONResponse(status_code=400, content={"detail": details})


# ---------------------------------------------------------------------
# Глобальная обработка ошибок PostgreSQL
# ---------------------------------------------------------------------
@app.exception_handler(DBAPIError)
async def _dbapi_error_handler(request: Request, exc: DBAPIError) -> JSONResponse:
    """
    Хранимые функции и триггеры при невалидных входах выбрасывают
    RAISE EXCEPTION (SQLSTATE P0001, класс '42' для permission_denied).
    Переводим это в HTTP 400/403 с читаемым текстом на русском.
    """
    orig = getattr(exc, "orig", None)
    sqlstate = getattr(orig, "sqlstate", None) or ""
    diag = getattr(orig, "diag", None)
    message = getattr(diag, "message_primary", None) or str(orig) or str(exc)

    # 42501 — insufficient_privilege (RBAC)
    if sqlstate == "42501":
        status = 403
    # P0001 — raise_exception (наши RAISE в функциях/триггерах)
    elif sqlstate.startswith("P0") or sqlstate.startswith("23"):
        status = 400
    else:
        status = 500
        log.exception("DB error (sqlstate=%s): %s", sqlstate, message)

    return JSONResponse(status_code=status, content={"detail": message})


# ---------------------------------------------------------------------
# Проверка живости (для healthcheck в docker-compose)
# ---------------------------------------------------------------------
@app.get("/health", tags=["system"])
def health() -> dict:
    engine = get_engine("admin")
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return {"status": "ok"}


@app.get("/", tags=["system"])
def root() -> dict:
    return {
        "service": "pharmacy-warehouse-api",
        "docs": "/docs",
        "endpoints": ["/tables", "/queries", "/analytics", "/health"],
    }
