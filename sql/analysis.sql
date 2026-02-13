-- =========================================================
-- DonorSearch SQL case (учебный)
-- Запросы + короткие выводы (без воды)
-- =========================================================

-- ---------------------------------------------------------
-- 1) Топ регионов по числу зарегистрированных доноров
-- ---------------------------------------------------------
SELECT
    region,
    COUNT(id) AS donor_count
FROM donorsearch.user_anon_data
GROUP BY region
ORDER BY donor_count DESC
LIMIT 5;

-- Вывод: лидируют крупные города; заметная доля пользователей без заполненного региона (data quality).
-- Дальше: посчитать долю пустого region и предложить валидацию/обязательность заполнения.


-- ---------------------------------------------------------
-- 2) Динамика количества донаций по месяцам (2022–2023)
-- ---------------------------------------------------------
SELECT
    DATE_TRUNC('month', donation_date) AS month,
    COUNT(id) AS donation_count
FROM donorsearch.donation_anon
WHERE donation_date >= '2022-01-01'
  AND donation_date <  '2024-01-01'
GROUP BY month
ORDER BY month;

-- Вывод: видна сезонность (пики весной) и периоды снижения активности в середине/конце года.
-- Дальше: сравнить 2022 vs 2023 по YoY (месяц к месяцу) и выделить месяцы с наибольшими изменениями.


-- ---------------------------------------------------------
-- 3) Самые активные доноры по подтверждённым донациям
-- ---------------------------------------------------------
SELECT
    id,
    confirmed_donations
FROM donorsearch.user_anon_data
ORDER BY confirmed_donations DESC
LIMIT 10;

-- Вывод: есть небольшой пул очень активных доноров (ключевой сегмент для удержания).
-- Дальше: проверить вклад топ-N доноров в общий объём подтверждённых донаций.


-- ---------------------------------------------------------
-- 4) Бонусы и активность доноров (корреляция, не причинность)
-- ---------------------------------------------------------
WITH donor_activity AS (
    SELECT
        u.id,
        u.confirmed_donations,
        COALESCE(b.user_bonus_count, 0) AS user_bonus_count
    FROM donorsearch.user_anon_data u
    LEFT JOIN donorsearch.user_anon_bonus b
        ON u.id = b.user_id
)
SELECT
    CASE WHEN user_bonus_count > 0 THEN 'Бонусы есть' ELSE 'Бонусов нет' END AS bonus_status,
    COUNT(id) AS donors_cnt,
    AVG(confirmed_donations) AS avg_confirmed_donations
FROM donor_activity
GROUP BY 1;

-- Вывод: доноры с бонусами в среднем активнее; возможен эффект отбора.
-- Дальше: сравнить активность одного и того же донора до/после первого бонуса.


-- ---------------------------------------------------------
-- 5) Каналы привлечения (соцсети): сколько доноров и средняя активность
-- Условие: учитываем только доноров с >= 1 подтверждённой донацией
-- ---------------------------------------------------------
SELECT
    CASE
        WHEN autho_vk THEN 'VK'
        WHEN autho_ok THEN 'OK'
        WHEN autho_tg THEN 'Telegram'
        WHEN autho_yandex THEN 'Yandex'
        WHEN autho_google THEN 'Google'
        ELSE 'No social auth'
    END AS channel,
    COUNT(id) AS donors_cnt,
    AVG(confirmed_donations) AS avg_confirmed_donations
FROM donorsearch.user_anon_data
WHERE confirmed_donations > 0
GROUP BY 1
ORDER BY donors_cnt DESC;

-- Вывод: каналы отличаются по масштабу и средней активности доноров.
-- Дальше: посчитать долю повторных доноров (confirmed_donations >= 2) по каналам.


-- ---------------------------------------------------------
-- 6) Повторные доноры: сравнение по “частоте донаций” + проверка качества дат
-- ---------------------------------------------------------
WITH donor_activity AS (
    SELECT
        user_id,
        COUNT(*) AS total_donations,
        MIN(donation_date) AS first_donation_dt,
        MAX(donation_date) AS last_donation_dt,
        (MAX(donation_date) - MIN(donation_date)) AS activity_duration_days
    FROM donorsearch.donation_anon
    GROUP BY user_id
    HAVING COUNT(*) > 1
)
SELECT
    CASE
        WHEN total_donations BETWEEN 2 AND 3 THEN '2-3'
        WHEN total_donations BETWEEN 4 AND 5 THEN '4-5'
        ELSE '6+'
    END AS freq_group,
    COUNT(user_id) AS donors_cnt,
    AVG(total_donations) AS avg_donations,
    AVG(activity_duration_days) AS avg_activity_duration_days
FROM donor_activity
GROUP BY 1
ORDER BY 1;

-- Вывод: повторные доноры — важный сегмент; в данных встречаются аномальные длительности активности (признак проблем с датами).
-- Дальше: отфильтровать некорректные даты/диапазоны и пересчитать метрики удержания/частоты.


-- ---------------------------------------------------------
-- 7) План vs факт: доля выполненных планов по типу донации
-- ---------------------------------------------------------
WITH planned_donations AS (
    SELECT DISTINCT user_id, donation_date, donation_type
    FROM donorsearch.donation_plan
),
actual_donations AS (
    SELECT DISTINCT user_id, donation_date
    FROM donorsearch.donation_anon
),
planned_vs_actual AS (
    SELECT
        pd.user_id,
        pd.donation_date AS planned_date,
        pd.donation_type,
        CASE WHEN ad.user_id IS NOT NULL THEN 1 ELSE 0 END AS completed
    FROM planned_donations pd
    LEFT JOIN actual_donations ad
        ON pd.user_id = ad.user_id
       AND pd.donation_date = ad.donation_date
)
SELECT
    donation_type,
    COUNT(*) AS total_planned,
    SUM(completed) AS completed_cnt,
    ROUND(SUM(completed) * 100.0 / COUNT(*), 2) AS completion_rate_pct
FROM planned_vs_actual
GROUP BY donation_type
ORDER BY completion_rate_pct DESC;

-- Вывод: доля выполнения планов низкая, различается по типу донации.
-- Дальше: разложить completion_rate по месяцам и по сегментам доноров (новые/повторные).
