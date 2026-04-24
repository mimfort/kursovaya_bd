"""
Подключение к PostgreSQL.

Все запросы идут через вызовы хранимых функций (`SELECT * FROM fn(...)`).
SQLAlchemy используется ИСКЛЮЧИТЕЛЬНО как транспорт — без ORM-запросов.
Это требование методички курсовой работы.

Роли: pharmacy_admin (суперюзер БД, по умолчанию), pharmacy_director,
pharmacy_warehouseman. Переключение между ролями делается созданием
отдельного engine с нужными логином/паролем.
"""
from __future__ import annotations

import os
from functools import lru_cache
from typing import Iterator

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker


# ---------------------------------------------------------------------
# Параметры подключения к БД — берутся из переменных окружения
# (в docker-compose прокинуты из .env).
# ---------------------------------------------------------------------
def _dsn(user: str, password: str) -> str:
    host = os.getenv("POSTGRES_HOST", "db")
    port = os.getenv("POSTGRES_PORT", "5432")
    db   = os.getenv("POSTGRES_DB",   "pharmacy_warehouse")
    return f"postgresql+psycopg://{user}:{password}@{host}:{port}/{db}"


# Учётные данные трёх ролей
ROLE_CREDENTIALS: dict[str, tuple[str, str]] = {
    "admin":        (os.getenv("POSTGRES_USER", "pharmacy_admin"),
                     os.getenv("POSTGRES_PASSWORD", "")),
    "director":     ("pharmacy_director",     "director_pass"),
    "warehouseman": ("pharmacy_warehouseman", "warehouseman_pass"),
}


@lru_cache(maxsize=8)
def get_engine(role: str = "admin") -> Engine:
    """Кешируемый engine per-role. Ленивая инициализация."""
    if role not in ROLE_CREDENTIALS:
        raise ValueError(f"Неизвестная роль: {role!r}. "
                         f"Доступны: {list(ROLE_CREDENTIALS)}")
    user, password = ROLE_CREDENTIALS[role]
    return create_engine(
        _dsn(user, password),
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=5,
        future=True,
    )


def get_session(role: str = "admin") -> Iterator[Session]:
    """FastAPI dependency — выдаёт сессию и гарантированно закрывает."""
    engine = get_engine(role)
    factory = sessionmaker(bind=engine, expire_on_commit=False)
    with factory() as session:
        yield session
