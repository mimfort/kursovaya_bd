"""
Страница «Аналитика» — интерактивные графики Plotly.
По ТЗ: минимум 3 графика разного типа, с подписью «кому полезен» и выводами.
"""
from __future__ import annotations

import os

import pandas as pd
import plotly.express as px
import requests
import streamlit as st

BACKEND_URL = os.getenv("BACKEND_URL", "http://backend:8000")

st.set_page_config(page_title="Аналитика", layout="wide")
st.title("Аналитика продаж аптечного склада")

role = st.session_state.get("role", "admin")
headers = {"X-Role": role}
st.caption(f"Роль: **{role}** · все агрегации выполняются на стороне PostgreSQL")


def fetch(path: str) -> pd.DataFrame | None:
    try:
        r = requests.get(f"{BACKEND_URL}{path}", headers=headers, timeout=15)
        if r.status_code == 403:
            st.warning(f"Роль «{role}» не имеет прав на «{path}».")
            return None
        r.raise_for_status()
        return pd.DataFrame(r.json()["rows"])
    except Exception as exc:
        st.error(f"Ошибка: {exc}")
        return None


# ---------------------------------------------------------------------
# График 1 — столбчатая диаграмма: выручка по филиалам
# ---------------------------------------------------------------------
st.header("1. Выручка по филиалам аптек")
df1 = fetch("/analytics/revenue-by-pharmacy")
if df1 is not None and not df1.empty:
    fig1 = px.bar(
        df1, x="pharmacy_name", y="revenue", color="city_name",
        hover_data=["items_sold"],
        labels={"pharmacy_name": "Филиал", "revenue": "Выручка, ₽",
                "city_name": "Город", "items_sold": "Продано единиц"},
        title="Суммарная выручка по филиалам",
    )
    st.plotly_chart(fig1, use_container_width=True)
    st.info(
        "**Кому полезен:** директору и экономисту для сравнения эффективности "
        "филиалов. **Вывод:** разброс выручки между филиалами показывает, какие "
        "точки — лидеры сети, а какие требуют внимания (пересмотра ассортимента, "
        "маркетинга или кадров)."
    )

# ---------------------------------------------------------------------
# График 2 — круговая диаграмма: доли продаж по группам
# ---------------------------------------------------------------------
st.header("2. Структура продаж по группам препаратов")
df2 = fetch("/analytics/sales-share-by-group")
if df2 is not None and not df2.empty:
    fig2 = px.pie(
        df2, names="group_name", values="revenue",
        title="Доля выручки по группам препаратов",
        hover_data=["items_sold"],
    )
    fig2.update_traces(textposition="inside", textinfo="percent+label")
    st.plotly_chart(fig2, use_container_width=True)
    st.info(
        "**Кому полезен:** менеджеру по закупкам и маркетологу для понимания, "
        "какие группы приносят основную выручку. **Вывод:** группы-лидеры заслуживают "
        "приоритетного пополнения склада; нишевые группы можно рассматривать "
        "в контексте сезонности и маржинальности."
    )

# ---------------------------------------------------------------------
# График 3 — линейный график: динамика продаж по месяцам
# ---------------------------------------------------------------------
st.header("3. Динамика продаж по месяцам")
df3 = fetch("/analytics/sales-trend-by-month")
if df3 is not None and not df3.empty:
    fig3 = px.line(
        df3, x="month", y="revenue", markers=True,
        labels={"month": "Месяц", "revenue": "Выручка, ₽"},
        title="Помесячная выручка сети аптек",
    )
    fig3.update_traces(hovertemplate="Месяц: %{x}<br>Выручка: %{y:.2f} ₽")
    st.plotly_chart(fig3, use_container_width=True)
    st.info(
        "**Кому полезен:** директору для мониторинга бизнес-трендов. "
        "**Вывод:** рост выручки в последние месяцы говорит об активизации продаж; "
        "если видна сезонность — планировать поставки нужно с учётом "
        "прогнозируемых пиков."
    )

# ---------------------------------------------------------------------
# График 4 (бонус) — heatmap филиалов × групп
# ---------------------------------------------------------------------
st.header("4. Heatmap: продажи по филиалам и группам препаратов")
df4 = fetch("/analytics/heatmap-pharmacy-group")
if df4 is not None and not df4.empty:
    pivot = df4.pivot_table(index="pharmacy_name", columns="group_name",
                            values="items_sold", fill_value=0)
    fig4 = px.imshow(
        pivot,
        labels=dict(x="Группа препаратов", y="Филиал", color="Продано, ед."),
        aspect="auto", color_continuous_scale="Blues",
        title="Какие группы в каких филиалах продаются активнее",
    )
    st.plotly_chart(fig4, use_container_width=True)
    st.info(
        "**Кому полезен:** категорийному менеджеру для профилирования филиалов. "
        "**Вывод:** в каждом филиале есть «сильные» группы — можно формировать "
        "локальный ассортимент индивидуально под спрос, а не одинаковыми поставками."
    )
