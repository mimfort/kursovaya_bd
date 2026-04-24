"""
Страница «Запросы» — 10 форм для 10 хранимых функций (5.1-5.10).
Для каждой: описание, поля ввода, подсказки по формату, обработка ошибок.
"""
from __future__ import annotations

import os
from datetime import date

import pandas as pd
import requests
import streamlit as st

BACKEND_URL = os.getenv("BACKEND_URL", "http://backend:8000")

st.set_page_config(page_title="Запросы", layout="wide")
st.title("Запросы к БД")

role = st.session_state.get("role", "admin")
headers = {"X-Role": role}
st.caption(f"Активная роль: **{role}**")


def _call(path: str, params: dict | None = None) -> tuple[bool, dict]:
    """Вызов API; возвращает (ok, json). В случае ошибки текст detail — в json['detail']."""
    try:
        r = requests.get(f"{BACKEND_URL}{path}", params=params or {},
                         headers=headers, timeout=20)
        if r.ok:
            return True, r.json()
        try:
            detail = r.json().get("detail", r.text)
        except Exception:
            detail = r.text
        return False, {"status": r.status_code, "detail": detail}
    except Exception as exc:
        return False, {"status": 0, "detail": str(exc)}


def _render_result(ok: bool, payload: dict) -> None:
    if not ok:
        st.error(f"Ошибка [{payload['status']}]: {payload['detail']}")
        return
    if payload["count"] == 0:
        st.info("По запросу ничего не найдено.")
        return
    st.success(f"Получено строк: {payload['count']}")
    st.dataframe(pd.DataFrame(payload["rows"]), use_container_width=True, hide_index=True)


tab_names = [
    "5.1 По группе", "5.2 По цене", "5.3 По производителю",
    "5.4 По аптеке", "5.5 По поставщику", "5.6 Движения",
    "5.7 Топ-10", "5.8 Топ-поставщик", "5.9 Топ-3 филиалов", "5.10 Низкий остаток",
]
tabs = st.tabs(tab_names)

# ---------------------------------------------------------------------
# 5.1
# ---------------------------------------------------------------------
with tabs[0]:
    st.markdown("**5.1 Препараты определённой группы**")
    st.caption("Примеры групп: Антибиотики, Анальгетики, Витамины, Антигистаминные.")
    g = st.text_input("Название группы", value="Антибиотики", key="q1")
    if st.button("Выполнить", key="b1"):
        _render_result(*_call("/queries/drugs-by-group", {"group_name": g}))

# ---------------------------------------------------------------------
# 5.2
# ---------------------------------------------------------------------
with tabs[1]:
    st.markdown("**5.2 Препараты в интервале цен (розничных)**")
    c1, c2 = st.columns(2)
    with c1:
        mn = st.number_input("Нижняя граница, ₽", 0.0, 100000.0, 50.0, step=10.0, key="q2min")
    with c2:
        mx = st.number_input("Верхняя граница, ₽", 0.0, 100000.0, 300.0, step=10.0, key="q2max")
    if st.button("Выполнить", key="b2"):
        _render_result(*_call("/queries/drugs-by-price-range",
                              {"min_price": mn, "max_price": mx}))

# ---------------------------------------------------------------------
# 5.3
# ---------------------------------------------------------------------
with tabs[2]:
    st.markdown("**5.3 Препараты одного производителя**")
    st.caption("Примеры: Фармстандарт, Bayer, Novartis, Sun Pharma.")
    m = st.text_input("Название производителя", value="Фармстандарт", key="q3")
    if st.button("Выполнить", key="b3"):
        _render_result(*_call("/queries/drugs-by-manufacturer", {"manufacturer_name": m}))

# ---------------------------------------------------------------------
# 5.4
# ---------------------------------------------------------------------
with tabs[3]:
    st.markdown("**5.4 Препараты, переданные в конкретную аптеку**")
    st.caption("Примеры: Аптека №1, Здоровье, Первая помощь, Фармакон.")
    p = st.text_input("Название аптеки", value="Аптека №1", key="q4")
    if st.button("Выполнить", key="b4"):
        _render_result(*_call("/queries/drugs-dispatched-to-pharmacy",
                              {"pharmacy_name": p}))

# ---------------------------------------------------------------------
# 5.5
# ---------------------------------------------------------------------
with tabs[4]:
    st.markdown("**5.5 Препараты от поставщика**")
    st.caption('Пример: ООО "ФармТорг", ЗАО "МедСнаб".')
    s = st.text_input("Название поставщика", value='ООО "ФармТорг"', key="q5")
    if st.button("Выполнить", key="b5"):
        _render_result(*_call("/queries/drugs-by-supplier", {"supplier_name": s}))

# ---------------------------------------------------------------------
# 5.6
# ---------------------------------------------------------------------
with tabs[5]:
    st.markdown("**5.6 Движения препаратов (приём/отгрузка) за период**")
    c1, c2 = st.columns(2)
    with c1:
        sd = st.date_input("Начало", value=date(2025, 1, 1), key="q6s")
    with c2:
        ed = st.date_input("Конец",  value=date(2026, 4, 1), key="q6e")
    if st.button("Выполнить", key="b6"):
        _render_result(*_call("/queries/movements-by-period",
                              {"start_date": sd.isoformat(), "end_date": ed.isoformat()}))

# ---------------------------------------------------------------------
# 5.7
# ---------------------------------------------------------------------
with tabs[6]:
    st.markdown("**5.7 Средняя цена 10 самых продаваемых препаратов**")
    if st.button("Выполнить", key="b7"):
        _render_result(*_call("/queries/top10-avg-retail-price"))

# ---------------------------------------------------------------------
# 5.8
# ---------------------------------------------------------------------
with tabs[7]:
    st.markdown("**5.8 Поставщик с макс. разнообразием препаратов за последний год**")
    st.caption("Сложный запрос: агрегация DISTINCT по препаратам, сумма закупочной стоимости.")
    if st.button("Выполнить", key="b8"):
        _render_result(*_call("/queries/top-supplier-last-year"))

# ---------------------------------------------------------------------
# 5.9
# ---------------------------------------------------------------------
with tabs[8]:
    st.markdown("**5.9 Топ-3 препарата по продажам в каждом филиале за 6 месяцев**")
    st.caption("Сложный запрос: оконная функция ROW_NUMBER() с PARTITION BY.")
    if st.button("Выполнить", key="b9"):
        _render_result(*_call("/queries/top3-drugs-by-pharmacy"))

# ---------------------------------------------------------------------
# 5.10
# ---------------------------------------------------------------------
with tabs[9]:
    st.markdown("**5.10 Препараты с остатком ниже порога**")
    st.caption("Остаток = сумма поступлений на склад − сумма отгруженного в филиалы.")
    t = st.number_input("Порог остатка (ед.)", 0, 100000, 250, step=10, key="q10")
    if st.button("Выполнить", key="b10"):
        _render_result(*_call("/queries/low-stock-drugs", {"threshold": t}))
