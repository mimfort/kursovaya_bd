"""
Главная страница Streamlit-приложения «Аптечный склад».
Боковая панель — выбор роли (передаётся в API через X-Role).
"""
from __future__ import annotations

import os

import requests
import streamlit as st

BACKEND_URL = os.getenv("BACKEND_URL", "http://backend:8000")

st.set_page_config(
    page_title="Аптечный склад",
    layout="wide",
)

# -----------------------------------------------------------------
# Боковая панель — выбор роли
# -----------------------------------------------------------------
if "role" not in st.session_state:
    st.session_state.role = "admin"

ROLE_LABELS = {
    "admin":        "Администратор БД (полный доступ)",
    "director":     "Директор (читает всё, управляет)",
    "warehouseman": "Кладовщик (ограниченный доступ)",
}

with st.sidebar:
    st.markdown("## Роль пользователя")
    role = st.radio(
        "Под какой ролью подключаться к БД:",
        options=list(ROLE_LABELS.keys()),
        format_func=lambda r: ROLE_LABELS[r],
        index=list(ROLE_LABELS).index(st.session_state.role),
    )
    st.session_state.role = role
    st.caption(f"Backend: `{BACKEND_URL}`")

    # Индикатор доступности API
    try:
        r = requests.get(f"{BACKEND_URL}/health", timeout=2)
        if r.ok:
            st.success("API доступен")
        else:
            st.error(f"API вернул {r.status_code}")
    except Exception as exc:
        st.error(f"API недоступен: {exc}")

# -----------------------------------------------------------------
# Содержимое главной
# -----------------------------------------------------------------
st.title("Информационная система «Аптечный склад»")
st.markdown(
    """
Курсовая работа по дисциплине «Базы данных», ГУАП, кафедра 41, вариант №7.

**Архитектура:**
- **БД** — PostgreSQL 16. Вся бизнес-логика в хранимых функциях и триггерах.
- **Backend** — FastAPI. SQLAlchemy используется только как транспорт
  (требование методички — все запросы через `SELECT * FROM fn(...)`).
- **Frontend** — Streamlit + Plotly.

### Страницы

- **Таблицы** — просмотр всех 16 таблиц БД (15 по схеме + служебная employee_salary_log для журнала зарплат).
- **Запросы** — 10 хранимых функций (запросы 5.1–5.10 из первой части курсовой).
- **Аналитика** — графики: выручка по филиалам, доли групп, динамика продаж, heatmap.

### Разграничение прав

Выберите роль в левой панели — API будет обращаться к БД от её имени.
Под кладовщиком попытка вызвать, например, финансовую аналитику директора
вернёт HTTP 403.
"""
)
