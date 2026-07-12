-- ============================================================================
-- Interest Rates Analysis: Cycles, Market Reaction, Sector Performance
-- ============================================================================
-- Business Context:
--   Analyze how RBI repo rate changes affect equity market returns across
--   sectors, identify rate hike/cut streaks, measure surprise impact,
--   and quantify interest rate sensitivity by sector.
-- ============================================================================

-- --------------------------------------------------------------------------
-- Preliminary: Table inspection and schema modifications
-- --------------------------------------------------------------------------
DESCRIBE facts_interest_rates;

UPDATE facts_interest_rates
SET release_date = STR_TO_DATE(release_date, '%d-%m-%Y');

ALTER TABLE facts_interest_rates
    MODIFY COLUMN release_date DATE NOT NULL;

ALTER TABLE facts_interest_rates
    ADD PRIMARY KEY (release_date);

-- Drop existing objects for re-creation
DROP VIEW IF EXISTS daily_returns;
DROP VIEW IF EXISTS index_returns_by_rate_change;
DROP TABLE IF EXISTS interest_rate_market_return;

-- --------------------------------------------------------------------------
-- 1. Distribution of Rate Cycles (Hike / Cut / No Change)
-- --------------------------------------------------------------------------

WITH previous_rate AS (
    SELECT
        release_date,
        actual          AS current_rate,
        LAG(actual) OVER (ORDER BY release_date) AS previous_rate
    FROM facts_interest_rates
),
rate_actions AS (
    SELECT
        *,
        CASE
            WHEN previous_rate > current_rate THEN 'CUT'
            WHEN previous_rate < current_rate THEN 'HIKE'
            ELSE 'NO_CHANGE'
        END AS rate_action
    FROM previous_rate
)
SELECT
    rate_action,
    COUNT(rate_action)                                                  AS action_count,
    ROUND(COUNT(rate_action) * 100.0 / SUM(COUNT(*)) OVER (), 2)       AS action_pct
FROM rate_actions
GROUP BY rate_action;

-- Observation: Hikes ~23%, Cuts ~21%, No Change ~56%

-- --------------------------------------------------------------------------
-- 2. Longest Consecutive Streaks of Each Rate Action
-- --------------------------------------------------------------------------

WITH previous_rate AS (
    SELECT
        release_date,
        actual AS current_rate,
        LAG(actual) OVER (ORDER BY release_date) AS previous_rate
    FROM facts_interest_rates
),
rate_actions AS (
    SELECT
        *,
        CASE
            WHEN previous_rate > current_rate THEN 'CUT'
            WHEN previous_rate < current_rate THEN 'HIKE'
            ELSE 'NO_CHANGE'
        END AS rate_action
    FROM previous_rate
),
streak_flags AS (
    SELECT
        *,
        CASE
            WHEN rate_action = LAG(rate_action) OVER (ORDER BY release_date)
            THEN 0
            ELSE 1
        END AS is_new_streak
    FROM rate_actions
),
streak_groups AS (
    SELECT
        *,
        SUM(is_new_streak) OVER (ORDER BY release_date) AS streak_group_id
    FROM streak_flags
),
streak_counts AS (
    SELECT
        rate_action,
        streak_group_id,
        COUNT(*)                    AS streak_length_months,
        MIN(release_date)           AS streak_start_date,
        MAX(release_date)           AS streak_end_date
    FROM streak_groups
    GROUP BY rate_action, streak_group_id
),
ranked_streaks AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY rate_action
            ORDER BY streak_length_months DESC
        ) AS rank_by_length
    FROM streak_counts
)
SELECT
    streak_start_date,
    streak_end_date,
    rate_action,
    streak_length_months
FROM ranked_streaks
WHERE rank_by_length = 1;

/*
Longest streaks:
  - Hike : Feb 2011 to Dec 2011
  - Cut  : Nov 2008 to Jun 2009
  - Same : Aug 2020 to Apr 2022
*/

-- --------------------------------------------------------------------------
-- 3. Daily Returns View (for market and all sectors)
-- --------------------------------------------------------------------------

CREATE VIEW daily_returns AS
WITH lagged_values AS (
    SELECT
        *,
        LAG(market_index_value)               OVER (ORDER BY date) AS prev_market,
        LAG(nifty_auto_value)                 OVER (ORDER BY date) AS prev_auto,
        LAG(nifty_bank_value)                 OVER (ORDER BY date) AS prev_bank,
        LAG(nifty_energy_value)               OVER (ORDER BY date) AS prev_energy,
        LAG(nifty_financial_services_value)   OVER (ORDER BY date) AS prev_financial_services,
        LAG(nifty_fmcg_value)                 OVER (ORDER BY date) AS prev_fmcg,
        LAG(nifty_it_value)                   OVER (ORDER BY date) AS prev_it,
        LAG(nifty_metal_value)                OVER (ORDER BY date) AS prev_metal,
        LAG(nifty_pharma_value)               OVER (ORDER BY date) AS prev_pharma,
        LAG(nifty_realty_value)               OVER (ORDER BY date) AS prev_realty
    FROM facts_market_indices
)
SELECT
    date,
    (market_index_value - prev_market) * 100.0
        / NULLIF(prev_market, 0)                AS market_return_pct,
    (nifty_auto_value - prev_auto) * 100.0
        / NULLIF(prev_auto, 0)                  AS auto_return_pct,
    (nifty_bank_value - prev_bank) * 100.0
        / NULLIF(prev_bank, 0)                  AS bank_return_pct,
    (nifty_energy_value - prev_energy) * 100.0
        / NULLIF(prev_energy, 0)                AS energy_return_pct,
    (nifty_financial_services_value - prev_financial_services) * 100.0
        / NULLIF(prev_financial_services, 0)    AS financial_services_return_pct,
    (nifty_fmcg_value - prev_fmcg) * 100.0
        / NULLIF(prev_fmcg, 0)                  AS fmcg_return_pct,
    (nifty_it_value - prev_it) * 100.0
        / NULLIF(prev_it, 0)                    AS it_return_pct,
    (nifty_metal_value - prev_metal) * 100.0
        / NULLIF(prev_metal, 0)                 AS metal_return_pct,
    (nifty_pharma_value - prev_pharma) * 100.0
        / NULLIF(prev_pharma, 0)                AS pharma_return_pct,
    (nifty_realty_value - prev_realty) * 100.0
        / NULLIF(prev_realty, 0)                AS realty_return_pct
FROM lagged_values;

-- Average daily market return
SELECT AVG(market_return_pct) AS avg_daily_market_return_pct FROM daily_returns;

-- --------------------------------------------------------------------------
-- 4. Market Returns Between Rate Decisions
-- --------------------------------------------------------------------------

CREATE TABLE interest_rate_market_return AS
SELECT
    rate.release_date,
    rate.actual,
    rate.forecast,
    AVG(market.market_return_pct)               AS avg_market_return_pct,
    AVG(market.auto_return_pct)                 AS avg_auto_return_pct,
    AVG(market.bank_return_pct)                 AS avg_bank_return_pct,
    AVG(market.energy_return_pct)               AS avg_energy_return_pct,
    AVG(market.financial_services_return_pct)   AS avg_financial_services_return_pct,
    AVG(market.fmcg_return_pct)                 AS avg_fmcg_return_pct,
    AVG(market.it_return_pct)                   AS avg_it_return_pct,
    AVG(market.metal_return_pct)                AS avg_metal_return_pct,
    AVG(market.pharma_return_pct)               AS avg_pharma_return_pct,
    AVG(market.realty_return_pct)               AS avg_realty_return_pct
FROM facts_interest_rates rate
LEFT JOIN daily_returns market
    ON market.date >= rate.release_date
    AND market.date < (
        SELECT MIN(next_rate.release_date)
        FROM facts_interest_rates next_rate
        WHERE next_rate.release_date > rate.release_date
    )
GROUP BY rate.release_date, rate.actual, rate.forecast
ORDER BY rate.release_date;

-- --------------------------------------------------------------------------
-- 5. Sectors Outperforming During Rate Hikes
-- --------------------------------------------------------------------------

CREATE VIEW index_returns_by_rate_change AS
WITH rate_changes AS (
    SELECT
        *,
        LAG(actual) OVER (ORDER BY release_date) AS previous_rate,
        (actual - LAG(actual) OVER (ORDER BY release_date)) * 10000 AS basis_points_change
    FROM interest_rate_market_return
),
unpivoted_returns AS (
    SELECT
        release_date,
        actual,
        previous_rate,
        basis_points_change,
        'Nifty_Midcap'        AS sector_name,
        avg_market_return_pct AS index_return_pct
    FROM rate_changes

    UNION ALL
    SELECT release_date, actual, previous_rate, basis_points_change, 'Auto',   avg_auto_return_pct FROM rate_changes
    UNION ALL
    SELECT release_date, actual, previous_rate, basis_points_change, 'Bank',   avg_bank_return_pct FROM rate_changes
    UNION ALL
    SELECT release_date, actual, previous_rate, basis_points_change, 'Energy', avg_energy_return_pct FROM rate_changes
    UNION ALL
    SELECT release_date, actual, previous_rate, basis_points_change, 'Financial Services', avg_financial_services_return_pct FROM rate_changes
    UNION ALL
    SELECT release_date, actual, previous_rate, basis_points_change, 'FMCG',   avg_fmcg_return_pct FROM rate_changes
    UNION ALL
    SELECT release_date, actual, previous_rate, basis_points_change, 'IT',     avg_it_return_pct FROM rate_changes
    UNION ALL
    SELECT release_date, actual, previous_rate, basis_points_change, 'Metal',  avg_metal_return_pct FROM rate_changes
    UNION ALL
    SELECT release_date, actual, previous_rate, basis_points_change, 'Pharma', avg_pharma_return_pct FROM rate_changes
    UNION ALL
    SELECT release_date, actual, previous_rate, basis_points_change, 'Realty', avg_realty_return_pct FROM rate_changes
),
ranked_sectors AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY release_date, basis_points_change
            ORDER BY index_return_pct DESC
        ) AS rank_by_return
    FROM unpivoted_returns
)
SELECT
    release_date,
    actual,
    previous_rate,
    basis_points_change,
    sector_name,
    index_return_pct
FROM ranked_sectors
WHERE rank_by_return = 1;

-- Top sectors during rate hikes
SELECT
    sector_name,
    COUNT(sector_name) AS occurrence_count
FROM index_returns_by_rate_change
WHERE actual > previous_rate
GROUP BY sector_name
ORDER BY occurrence_count DESC;

/*
Sectors performing best during hikes:
  - FMCG
  - Pharma
  - Auto
  - Realty
*/

-- --------------------------------------------------------------------------
-- 6. Sectors Outperforming During Rate Cuts
-- --------------------------------------------------------------------------

SELECT
    sector_name,
    COUNT(sector_name) AS occurrence_count
FROM index_returns_by_rate_change
WHERE actual < previous_rate
GROUP BY sector_name
ORDER BY occurrence_count DESC;

/*
Sectors performing best during cuts:
  - Realty
  - IT
  - Auto
  - Metal
*/

-- --------------------------------------------------------------------------
-- 7. Impact Magnitude: Are Cuts More Impactful Than Hikes?
-- --------------------------------------------------------------------------

SELECT
    CASE
        WHEN actual > previous_rate THEN 'HIKE'
        WHEN actual < previous_rate THEN 'CUT'
        ELSE 'NO_CHANGE'
    END AS rate_action,
    COUNT(*)                                      AS total_events,
    ROUND(AVG(index_return_pct), 2)               AS avg_return_pct,
    ROUND(MIN(index_return_pct), 2)               AS min_return_pct,
    ROUND(MAX(index_return_pct), 2)               AS max_return_pct,
    ROUND(STDDEV(index_return_pct), 2)            AS return_volatility_pct
FROM index_returns_by_rate_change
GROUP BY rate_action
ORDER BY avg_return_pct DESC;

-- Insight: Cuts generate higher average returns than hikes.

-- --------------------------------------------------------------------------
-- 8. Interest Rate Sensitivity by Sector
-- --------------------------------------------------------------------------

SELECT
    sector_name,
    AVG(index_return_pct / NULLIF(basis_points_change, 0)) AS rate_sensitivity
FROM index_returns_by_rate_change
GROUP BY sector_name
ORDER BY rate_sensitivity DESC;

-- --------------------------------------------------------------------------
-- 9. Market Overreaction Analysis (5-day window around rate decisions)
-- --------------------------------------------------------------------------

WITH rate_events AS (
    SELECT
        *,
        CASE
            WHEN actual > previous_rate THEN 'HIKE'
            WHEN actual < previous_rate THEN 'CUT'
            ELSE 'NO_CHANGE'
        END AS rate_action
    FROM index_returns_by_rate_change
),
daily_sector_returns AS (
    SELECT date, market_return_pct           AS return_pct, 'Nifty_Midcap' AS sector_name FROM daily_returns
    UNION ALL
    SELECT date, auto_return_pct             AS return_pct, 'Auto'          FROM daily_returns
    UNION ALL
    SELECT date, bank_return_pct             AS return_pct, 'Bank'          FROM daily_returns
    UNION ALL
    SELECT date, energy_return_pct           AS return_pct, 'Energy'        FROM daily_returns
    UNION ALL
    SELECT date, financial_services_return_pct AS return_pct, 'Financial Services' FROM daily_returns
    UNION ALL
    SELECT date, fmcg_return_pct             AS return_pct, 'FMCG'          FROM daily_returns
    UNION ALL
    SELECT date, it_return_pct               AS return_pct, 'IT'            FROM daily_returns
    UNION ALL
    SELECT date, metal_return_pct            AS return_pct, 'Metal'         FROM daily_returns
    UNION ALL
    SELECT date, pharma_return_pct           AS return_pct, 'Pharma'        FROM daily_returns
    UNION ALL
    SELECT date, realty_return_pct           AS return_pct, 'Realty'        FROM daily_returns
),
event_windows AS (
    SELECT
        event.release_date,
        event.rate_action,
        sector.sector_name,
        sector.date             AS trading_date,
        sector.return_pct,
        DATEDIFF(sector.date, event.release_date) AS day_offset
    FROM rate_events event
    JOIN daily_sector_returns sector
        ON sector.date BETWEEN DATE_SUB(event.release_date, INTERVAL 5 DAY)
                           AND DATE_ADD(event.release_date, INTERVAL 5 DAY)
),
aggregated_events AS (
    SELECT
        rate_action,
        sector_name,
        SUM(CASE WHEN day_offset = 0            THEN return_pct ELSE 0 END) AS day_0_return_pct,
        SUM(CASE WHEN day_offset BETWEEN 1 AND 5  THEN return_pct ELSE 0 END) AS post_1_5_return_pct,
        SUM(CASE WHEN day_offset BETWEEN -5 AND -1 THEN return_pct ELSE 0 END) AS pre_5_1_return_pct
    FROM event_windows
    GROUP BY rate_action, sector_name
)
SELECT
    rate_action,
    sector_name,
    AVG(pre_5_1_return_pct)    AS avg_pre_5day_return_pct,
    AVG(day_0_return_pct)       AS avg_announcement_day_return_pct,
    AVG(post_1_5_return_pct)    AS avg_post_5day_return_pct
FROM aggregated_events
GROUP BY rate_action, sector_name
ORDER BY sector_name, rate_action;

-- --------------------------------------------------------------------------
-- 10. Market Response to Rate Surprises (Forecast vs Actual)
-- --------------------------------------------------------------------------

WITH previous_rates AS (
    SELECT
        *,
        LAG(actual) OVER (ORDER BY release_date) AS previous_rate
    FROM interest_rate_market_return
),
surprises AS (
    SELECT *
    FROM previous_rates
    WHERE
        -- Expected cut but got hike
        (previous_rate > forecast AND actual > previous_rate)
        -- Expected cut but no change
        OR (previous_rate > forecast AND actual = previous_rate)
        -- Expected cut but cut even more
        OR (previous_rate > forecast AND actual < forecast)
        -- Expected hike but got cut
        OR (previous_rate < forecast AND actual < previous_rate)
        -- Expected hike but no change
        OR (previous_rate < forecast AND actual = previous_rate)
        -- Expected hike but hiked even more
        OR (previous_rate < forecast AND actual > forecast)
)
SELECT
    CASE
        WHEN (previous_rate > forecast) AND (actual > previous_rate)  THEN 'Expected Cut -> Hiked'
        WHEN (previous_rate > forecast) AND (actual = previous_rate)  THEN 'Expected Cut -> No Change'
        WHEN (previous_rate > forecast) AND (actual < forecast)       THEN 'Expected Cut -> Cut More'
        WHEN (previous_rate < forecast) AND (actual < previous_rate)  THEN 'Expected Hike -> Cut'
        WHEN (previous_rate < forecast) AND (actual = previous_rate)  THEN 'Expected Hike -> No Change'
        WHEN (previous_rate < forecast) AND (actual > forecast)       THEN 'Expected Hike -> Hiked More'
    END AS surprise_type,
    AVG(avg_market_return_pct) * 100 AS avg_market_return_bps
FROM surprises
GROUP BY surprise_type;
