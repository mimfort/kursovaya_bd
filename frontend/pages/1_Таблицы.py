"""
Страница «Таблицы» — просмотр всех 16 таблиц БД
(15 по схеме первой части + служебная employee_salary_log).
"""
from __future__ import annotations

import os

import pandas as pd
import requests
import streamlit as st

BACKEND_URL = os.getenv("BACKEND_URL", "http://backend:8000")

st.set_page_config(page_title="Таблицы БД", layout="wide")
st.title("Таблицы базы данных")

role = st.session_state.get("role", "admin")
headers = {"X-Role": role}

# Человекочитаемые подписи (UI на русском — id и поля в БД на английском)
TABLE_LABELS = {
    "countries":               "Страны (countries)",
    "cities":                  "Города (cities)",
    "drug_groups":             "Группы препаратов (drug_groups)",
    "drug_purposes":           "Назначения препаратов (drug_purposes)",
    "positions":               "Должности (positions)",
    "manufacturers":           "Производители (manufacturers)",
    "drugs":                   "Препараты (drugs)",
    "suppliers":               "Поставщики (suppliers)",
    "pharmacies":              "Филиалы аптек (pharmacies)",
    "employees":               "Сотрудники (employees)",
    "warehouse_supplies":      "Поставки на склад — заголовки",
    "warehouse_supply_items":  "Поставки на склад — позиции",
    "pharmacy_dispatches":     "Отгрузки в филиалы — заголовки",
    "pharmacy_dispatch_items": "Отгрузки в филиалы — позиции",
    "pharmacy_sales":          "Розничные продажи (pharmacy_sales)",
    "employee_salary_log":     "Лог изменений зарплат (служебная)",
}

try:
    r = requests.get(f"{BACKEND_URL}/tables", headers=headers, timeout=5)
    r.raise_for_status()
    available = r.json()["tables"]
except Exception as exc:
    st.error(f"Не удалось получить список таблиц: {exc}")
    st.stop()

col1, col2 = st.columns([2, 1])
with col1:
    table = st.selectbox(
        "Таблица",
        options=[t for t in TABLE_LABELS if t in available],
        format_func=lambda t: TABLE_LABELS.get(t, t),
    )
with col2:
    limit = st.number_input("Показать строк", 10, 5000, 500, step=50)

try:
    r = requests.get(
        f"{BACKEND_URL}/tables/{table}",
        params={"limit": limit},
        headers=headers, timeout=10,
    )
    if r.status_code == 403:
        st.error(f"Роль «{role}» не имеет доступа к таблице «{table}».")
        st.stop()
    r.raise_for_status()
    data = r.json()
except Exception as exc:
    st.error(f"Ошибка запроса: {exc}")
    st.stop()

st.caption(f"Роль: **{role}** · строк получено: **{data['count']}**")
df = pd.DataFrame(data["rows"])
if df.empty:
    st.info("Таблица пуста или нет прав на чтение её колонок.")
else:
    st.dataframe(df, use_container_width=True, hide_index=True)
