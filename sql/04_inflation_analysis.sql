-- ============================================================================
-- Inflation Analysis: WPI, CPI, Interest Rate Lags, Surprise Impact
-- ============================================================================
-- Business Context:
--   Analyze the relationship between WPI, CPI, and interest rates over time.
--   Measure lag correlations, sector volatility to inflation changes, and
--   market response to inflation surprises.
-- ============================================================================

-- --------------------------------------------------------------------------
-- Preliminary: Table inspection and schema modifications
-- --------------------------------------------------------------------------
DESCRIBE facts_wpi;
DESCRIBE facts_interest_rates;
DESCRIBE facts_cpi;

UPDATE facts_interest_rates
SET release_date = STR_TO_DATE(release_date, '%d-%m-%Y');

ALTER TABLE facts_wpi
    MODIFY COLUMN release_date DATE NOT NULL;

ALTER TABLE facts_interest_rates
    MODIFY COLUMN release_date DATE NOT NULL;

ALTER TABLE facts_cpi
    MODIFY COLUMN release_date DATE NOT NULL;

ALTER TABLE facts_wpi ADD PRIMARY KEY (release_date);
ALTER TABLE facts_cpi ADD PRIMARY KEY (release_date);

-- Drop existing objects
DROP VIEW IF EXISTS inflation_with_repo_rates;
DROP VIEW IF EXISTS inflation_rates;
DROP VIEW IF EXISTS inflation_market_returns;
DROP TABLE IF EXISTS sector_returns_by_index_rate_change;

-- --------------------------------------------------------------------------
-- Merged View: WPI with Corresponding Repo Rate
-- --------------------------------------------------------------------------

CREATE VIEW inflation_with_repo_rates AS
SELECT
    rate.release_date,
    rate.actual * 100   AS interest_rate_pct,
    wpi.actual * 100    AS wpi_pct,
    wpi.forecast * 100  AS forecasted_wpi_pct
FROM facts_interest_rates rate
LEFT JOIN facts_wpi wpi
    ON rate.release_date = (
        SELECT MAX(prev_rate.release_date)
        FROM facts_interest_rates prev_rate
        WHERE prev_rate.release_date <= wpi.release_date
    )
WHERE wpi.actual IS NOT NULL
ORDER BY wpi.release_date;

-- --------------------------------------------------------------------------
-- 1. Correlation Between Interest Rates and WPI
-- --------------------------------------------------------------------------

SELECT
    (COUNT(*) * SUM(interest_rate_pct * wpi_pct)
        - SUM(interest_rate_pct) * SUM(wpi_pct))
    / SQRT(
        (COUNT(*) * SUM(POW(interest_rate_pct, 2)) - POW(SUM(interest_rate_pct), 2))
        * (COUNT(*) * SUM(POW(wpi_pct, 2)) - POW(SUM(wpi_pct), 2))
    ) AS interest_wpi_correlation
FROM inflation_with_repo_rates;

-- --------------------------------------------------------------------------
-- 2. Same-Month Join (Rate and Inflation Released Same Month)
-- --------------------------------------------------------------------------

SELECT
    rate.release_date,
    rate.actual * 100       AS interest_rate_pct,
    wpi.release_date        AS wpi_release_date,
    wpi.actual * 100        AS wpi_pct,
    wpi.forecast * 100      AS forecasted_wpi_pct
FROM facts_interest_rates rate
LEFT JOIN facts_wpi wpi
    ON rate.release_date <= wpi.release_date
    AND MONTH(rate.release_date) = MONTH(wpi.release_date)
    AND YEAR(rate.release_date) = YEAR(wpi.release_date)
ORDER BY rate.release_date;

-- --------------------------------------------------------------------------
-- 3. Lag Correlation Analysis: Interest Rate vs WPI Lags (1 to 6 months)
-- --------------------------------------------------------------------------

WITH lagged_wpi AS (
    SELECT
        release_date,
        interest_rate_pct,
        wpi_pct,
        LAG(wpi_pct, 1) OVER (ORDER BY release_date) AS wpi_lag_1,
        LAG(wpi_pct, 2) OVER (ORDER BY release_date) AS wpi_lag_2,
        LAG(wpi_pct, 3) OVER (ORDER BY release_date) AS wpi_lag_3,
        LAG(wpi_pct, 4) OVER (ORDER BY release_date) AS wpi_lag_4,
        LAG(wpi_pct, 5) OVER (ORDER BY release_date) AS wpi_lag_5,
        LAG(wpi_pct, 6) OVER (ORDER BY release_date) AS wpi_lag_6
    FROM inflation_with_repo_rates
),
correlation_lag_1 AS (
    SELECT
        'Lag 1' AS lag_label,
        (COUNT(*) * SUM(interest_rate_pct * wpi_lag_1) - SUM(interest_rate_pct) * SUM(wpi_lag_1))
        / SQRT(
            (COUNT(*) * SUM(POW(interest_rate_pct, 2)) - POW(SUM(interest_rate_pct), 2))
            * (COUNT(*) * SUM(POW(wpi_lag_1, 2)) - POW(SUM(wpi_lag_1), 2))
        ) AS correlation
    FROM lagged_wpi WHERE wpi_lag_1 IS NOT NULL
),
correlation_lag_2 AS (
    SELECT
        'Lag 2' AS lag_label,
        (COUNT(*) * SUM(interest_rate_pct * wpi_lag_2) - SUM(interest_rate_pct) * SUM(wpi_lag_2))
        / SQRT(
            (COUNT(*) * SUM(POW(interest_rate_pct, 2)) - POW(SUM(interest_rate_pct), 2))
            * (COUNT(*) * SUM(POW(wpi_lag_2, 2)) - POW(SUM(wpi_lag_2), 2))
        ) AS correlation
    FROM lagged_wpi WHERE wpi_lag_2 IS NOT NULL
),
correlation_lag_3 AS (
    SELECT 'Lag 3', /* same formula */ 0 AS correlation FROM lagged_wpi WHERE FALSE
),
correlation_lag_4 AS (
    SELECT 'Lag 4', /* same formula */ 0 AS correlation FROM lagged_wpi WHERE FALSE
),
correlation_lag_5 AS (
    SELECT 'Lag 5', /* same formula */ 0 AS correlation FROM lagged_wpi WHERE FALSE
),
correlation_lag_6 AS (
    SELECT 'Lag 6', /* same formula */ 0 AS correlation FROM lagged_wpi WHERE FALSE
)
-- Full correlation computation for each lag
SELECT 'Lag 1' AS lag_period,
    (COUNT(*) * SUM(interest_rate_pct * wpi_lag_1) - SUM(interest_rate_pct) * SUM(wpi_lag_1))
    / SQRT(
        (COUNT(*) * SUM(POW(interest_rate_pct, 2)) - POW(SUM(interest_rate_pct), 2))
        * (COUNT(*) * SUM(POW(wpi_lag_1, 2)) - POW(SUM(wpi_lag_1), 2))
    ) AS correlation
FROM lagged_wpi WHERE wpi_lag_1 IS NOT NULL

UNION ALL

SELECT 'Lag 2',
    (COUNT(*) * SUM(interest_rate_pct * wpi_lag_2) - SUM(interest_rate_pct) * SUM(wpi_lag_2))
    / SQRT(
        (COUNT(*) * SUM(POW(interest_rate_pct, 2)) - POW(SUM(interest_rate_pct), 2))
        * (COUNT(*) * SUM(POW(wpi_lag_2, 2)) - POW(SUM(wpi_lag_2), 2))
    )
FROM lagged_wpi WHERE wpi_lag_2 IS NOT NULL

UNION ALL

SELECT 'Lag 3',
    (COUNT(*) * SUM(interest_rate_pct * wpi_lag_3) - SUM(interest_rate_pct) * SUM(wpi_lag_3))
    / SQRT(
        (COUNT(*) * SUM(POW(interest_rate_pct, 2)) - POW(SUM(interest_rate_pct), 2))
        * (COUNT(*) * SUM(POW(wpi_lag_3, 2)) - POW(SUM(wpi_lag_3), 2))
    )
FROM lagged_wpi WHERE wpi_lag_3 IS NOT NULL

UNION ALL

SELECT 'Lag 4',
    (COUNT(*) * SUM(interest_rate_pct * wpi_lag_4) - SUM(interest_rate_pct) * SUM(wpi_lag_4))
    / SQRT(
        (COUNT(*) * SUM(POW(interest_rate_pct, 2)) - POW(SUM(interest_rate_pct), 2))
        * (COUNT(*) * SUM(POW(wpi_lag_4, 2)) - POW(SUM(wpi_lag_4), 2))
    )
FROM lagged_wpi WHERE wpi_lag_4 IS NOT NULL

UNION ALL

SELECT 'Lag 5',
    (COUNT(*) * SUM(interest_rate_pct * wpi_lag_5) - SUM(interest_rate_pct) * SUM(wpi_lag_5))
    / SQRT(
        (COUNT(*) * SUM(POW(interest_rate_pct, 2)) - POW(SUM(interest_rate_pct), 2))
        * (COUNT(*) * SUM(POW(wpi_lag_5, 2)) - POW(SUM(wpi_lag_5), 2))
    )
FROM lagged_wpi WHERE wpi_lag_5 IS NOT NULL

UNION ALL

SELECT 'Lag 6',
    (COUNT(*) * SUM(interest_rate_pct * wpi_lag_6) - SUM(interest_rate_pct) * SUM(wpi_lag_6))
    / SQRT(
        (COUNT(*) * SUM(POW(interest_rate_pct, 2)) - POW(SUM(interest_rate_pct), 2))
        * (COUNT(*) * SUM(POW(wpi_lag_6, 2)) - POW(SUM(wpi_lag_6), 2))
    )
FROM lagged_wpi WHERE wpi_lag_6 IS NOT NULL;

/*
Observation:
  Correlation between WPI and interest rates increases with more lag:
  - Lag 1: ~3.65%
  - Lag 4: ~10%
  - Lag 7: ~17%
*/

-- --------------------------------------------------------------------------
-- CPI & WPI Joint View
-- --------------------------------------------------------------------------

CREATE VIEW inflation_rates AS
SELECT
    cpi.release_date,
    ROUND(cpi.actual, 2) * 100    AS cpi_pct,
    ROUND(cpi.forecast, 2) * 100  AS forecasted_cpi_pct,
    ROUND(wpi.actual, 2) * 100    AS wpi_pct
FROM facts_cpi cpi
LEFT JOIN facts_wpi wpi
    ON wpi.release_date = (
        SELECT MAX(latest_wpi.release_date)
        FROM facts_wpi latest_wpi
        WHERE latest_wpi.release_date <= cpi.release_date
    )
WHERE cpi.actual IS NOT NULL
ORDER BY cpi.release_date;

SELECT * FROM inflation_rates;

-- --------------------------------------------------------------------------
-- 4. Lag Correlation: WPI vs CPI (0 to 6 months lag)
-- --------------------------------------------------------------------------

WITH lagged_cpi AS (
    SELECT
        release_date,
        wpi_pct,
        cpi_pct,
        LAG(cpi_pct, 1) OVER (ORDER BY release_date) AS cpi_lag_1,
        LAG(cpi_pct, 2) OVER (ORDER BY release_date) AS cpi_lag_2,
        LAG(cpi_pct, 3) OVER (ORDER BY release_date) AS cpi_lag_3,
        LAG(cpi_pct, 4) OVER (ORDER BY release_date) AS cpi_lag_4,
        LAG(cpi_pct, 5) OVER (ORDER BY release_date) AS cpi_lag_5,
        LAG(cpi_pct, 6) OVER (ORDER BY release_date) AS cpi_lag_6
    FROM inflation_rates
)
SELECT 'Lag 0' AS lag_period,
    (COUNT(*) * SUM(wpi_pct * cpi_pct) - SUM(wpi_pct) * SUM(cpi_pct))
    / SQRT(
        (COUNT(*) * SUM(POW(wpi_pct, 2)) - POW(SUM(wpi_pct), 2))
        * (COUNT(*) * SUM(POW(cpi_pct, 2)) - POW(SUM(cpi_pct), 2))
    ) AS wpi_cpi_correlation
FROM lagged_cpi WHERE cpi_pct IS NOT NULL

UNION ALL

SELECT 'Lag 1',
    (COUNT(*) * SUM(wpi_pct * cpi_lag_1) - SUM(wpi_pct) * SUM(cpi_lag_1))
    / SQRT(
        (COUNT(*) * SUM(POW(wpi_pct, 2)) - POW(SUM(wpi_pct), 2))
        * (COUNT(*) * SUM(POW(cpi_lag_1, 2)) - POW(SUM(cpi_lag_1), 2))
    )
FROM lagged_cpi WHERE cpi_lag_1 IS NOT NULL

UNION ALL

SELECT 'Lag 2',
    (COUNT(*) * SUM(wpi_pct * cpi_lag_2) - SUM(wpi_pct) * SUM(cpi_lag_2))
    / SQRT(
        (COUNT(*) * SUM(POW(wpi_pct, 2)) - POW(SUM(wpi_pct), 2))
        * (COUNT(*) * SUM(POW(cpi_lag_2, 2)) - POW(SUM(cpi_lag_2), 2))
    )
FROM lagged_cpi WHERE cpi_lag_2 IS NOT NULL

UNION ALL

SELECT 'Lag 3',
    (COUNT(*) * SUM(wpi_pct * cpi_lag_3) - SUM(wpi_pct) * SUM(cpi_lag_3))
    / SQRT(
        (COUNT(*) * SUM(POW(wpi_pct, 2)) - POW(SUM(wpi_pct), 2))
        * (COUNT(*) * SUM(POW(cpi_lag_3, 2)) - POW(SUM(cpi_lag_3), 2))
    )
FROM lagged_cpi WHERE cpi_lag_3 IS NOT NULL

UNION ALL

SELECT 'Lag 4',
    (COUNT(*) * SUM(wpi_pct * cpi_lag_4) - SUM(wpi_pct) * SUM(cpi_lag_4))
    / SQRT(
        (COUNT(*) * SUM(POW(wpi_pct, 2)) - POW(SUM(wpi_pct), 2))
        * (COUNT(*) * SUM(POW(cpi_lag_4, 2)) - POW(SUM(cpi_lag_4), 2))
    )
FROM lagged_cpi WHERE cpi_lag_4 IS NOT NULL

UNION ALL

SELECT 'Lag 5',
    (COUNT(*) * SUM(wpi_pct * cpi_lag_5) - SUM(wpi_pct) * SUM(cpi_lag_5))
    / SQRT(
        (COUNT(*) * SUM(POW(wpi_pct, 2)) - POW(SUM(wpi_pct), 2))
        * (COUNT(*) * SUM(POW(cpi_lag_5, 2)) - POW(SUM(cpi_lag_5), 2))
    )
FROM lagged_cpi WHERE cpi_lag_5 IS NOT NULL

UNION ALL

SELECT 'Lag 6',
    (COUNT(*) * SUM(wpi_pct * cpi_lag_6) - SUM(wpi_pct) * SUM(cpi_lag_6))
    / SQRT(
        (COUNT(*) * SUM(POW(wpi_pct, 2)) - POW(SUM(wpi_pct), 2))
        * (COUNT(*) * SUM(POW(cpi_lag_6, 2)) - POW(SUM(cpi_lag_6), 2))
    )
FROM lagged_cpi WHERE cpi_lag_6 IS NOT NULL;

/*
Correlation decay with lag:
  - Lag 0: ~44%
  - Lag 1: ~42%
  - Lag 2: ~39%
  - Lag 3: ~36%
  - Lag 4: ~32%
  - Lag 5: ~29%
  - Lag 6: ~28%

  Strongest correlation is at Lag 0, confirming WPI impact on CPI is immediate.
*/

-- --------------------------------------------------------------------------
-- 5. Inflation Surprise Analysis (CPI vs Forecast) & Market Reaction
-- --------------------------------------------------------------------------

CREATE VIEW inflation_market_returns AS
SELECT
    cpi.release_date,
    cpi.actual         AS cpi,
    cpi.forecast       AS forecasted_cpi,
    daily_returns.*
FROM facts_cpi cpi
LEFT JOIN daily_returns
    ON daily_returns.date = (
        SELECT MIN(next_day.date)
        FROM daily_returns next_day
        WHERE cpi.release_date <= next_day.date
    )
WHERE daily_returns.date IS NOT NULL
ORDER BY cpi.release_date;

-- Market reaction to CPI surprises
WITH previous_inflation AS (
    SELECT
        *,
        LAG(cpi) OVER (ORDER BY release_date) AS previous_cpi
    FROM inflation_market_returns
),
surprises AS (
    SELECT *
    FROM previous_inflation
    WHERE
        (previous_cpi > forecasted_cpi AND cpi > previous_cpi)       -- Expected cut but hiked
        OR (previous_cpi > forecasted_cpi AND cpi = previous_cpi)    -- Expected cut but no change
        OR (previous_cpi > forecasted_cpi AND cpi < forecasted_cpi)  -- Expected cut but cut more
        OR (previous_cpi < forecasted_cpi AND cpi < previous_cpi)    -- Expected hike but cut
        OR (previous_cpi < forecasted_cpi AND cpi = previous_cpi)    -- Expected hike but no change
        OR (previous_cpi < forecasted_cpi AND cpi > forecasted_cpi)  -- Expected hike but hiked more
)
SELECT
    CASE
        WHEN (previous_cpi > forecasted_cpi) AND (cpi > previous_cpi)     THEN 'Expected Cut -> Hiked'
        WHEN (previous_cpi > forecasted_cpi) AND (cpi = previous_cpi)     THEN 'Expected Cut -> No Change'
        WHEN (previous_cpi > forecasted_cpi) AND (cpi < forecasted_cpi)   THEN 'Expected Cut -> Cut More'
        WHEN (previous_cpi < forecasted_cpi) AND (cpi < previous_cpi)     THEN 'Expected Hike -> Cut'
        WHEN (previous_cpi < forecasted_cpi) AND (cpi = previous_cpi)     THEN 'Expected Hike -> No Change'
        WHEN (previous_cpi < forecasted_cpi) AND (cpi > forecasted_cpi)   THEN 'Expected Hike -> Hiked More'
    END AS surprise_type,
    MIN(market_return_pct)  AS min_market_return_pct,
    AVG(market_return_pct)  AS avg_market_return_pct,
    MAX(market_return_pct)  AS max_market_return_pct
FROM surprises
GROUP BY surprise_type;

-- --------------------------------------------------------------------------
-- 6. Sector Returns Around Inflation Announcements (60-day windows)
-- --------------------------------------------------------------------------

CREATE TABLE sector_returns_by_index_rate_change AS
WITH previous_inflation AS (
    SELECT
        *,
        LAG(cpi) OVER (ORDER BY release_date) AS previous_cpi
    FROM inflation_market_returns
),
inflation_events AS (
    SELECT
        *,
        CASE
            WHEN cpi > previous_cpi THEN 'HIKE'
            WHEN cpi < previous_cpi THEN 'CUT'
            ELSE 'NO_CHANGE'
        END AS rate_action
    FROM previous_inflation
),
daily_sector_returns AS (
    SELECT date, market_return_pct           AS return_pct, 'Nifty_Midcap' AS sector_name FROM daily_returns
    UNION ALL
    SELECT date, auto_return_pct             , 'Auto'          FROM daily_returns
    UNION ALL
    SELECT date, bank_return_pct             , 'Bank'          FROM daily_returns
    UNION ALL
    SELECT date, energy_return_pct           , 'Energy'        FROM daily_returns
    UNION ALL
    SELECT date, financial_services_return_pct, 'Financial Services' FROM daily_returns
    UNION ALL
    SELECT date, fmcg_return_pct             , 'FMCG'          FROM daily_returns
    UNION ALL
    SELECT date, it_return_pct               , 'IT'            FROM daily_returns
    UNION ALL
    SELECT date, metal_return_pct            , 'Metal'         FROM daily_returns
    UNION ALL
    SELECT date, pharma_return_pct           , 'Pharma'        FROM daily_returns
    UNION ALL
    SELECT date, realty_return_pct           , 'Realty'        FROM daily_returns
),
event_windows AS (
    SELECT
        event.release_date,
        event.rate_action,
        sector.sector_name,
        sector.date,
        sector.return_pct,
        DATEDIFF(sector.date, event.release_date) AS day_offset
    FROM inflation_events event
    JOIN daily_sector_returns sector
        ON sector.date BETWEEN DATE_SUB(event.release_date, INTERVAL 60 DAY)
                           AND DATE_ADD(event.release_date, INTERVAL 60 DAY)
),
aggregated_events AS (
    SELECT
        rate_action,
        sector_name,
        SUM(CASE WHEN day_offset BETWEEN -60 AND -1 THEN return_pct ELSE 0 END) AS pre_60d_return_pct,
        SUM(CASE WHEN day_offset BETWEEN -30 AND -1 THEN return_pct ELSE 0 END) AS pre_30d_return_pct,
        SUM(CASE WHEN day_offset BETWEEN -5  AND -1 THEN return_pct ELSE 0 END) AS pre_5d_return_pct,
        SUM(CASE WHEN day_offset = 0              THEN return_pct ELSE 0 END) AS day_0_return_pct,
        SUM(CASE WHEN day_offset BETWEEN 1   AND 5  THEN return_pct ELSE 0 END) AS post_5d_return_pct,
        SUM(CASE WHEN day_offset BETWEEN 1   AND 30 THEN return_pct ELSE 0 END) AS post_30d_return_pct,
        SUM(CASE WHEN day_offset BETWEEN 1   AND 60 THEN return_pct ELSE 0 END) AS post_60d_return_pct
    FROM event_windows
    GROUP BY rate_action, sector_name
)
SELECT
    rate_action,
    sector_name,
    AVG(pre_60d_return_pct)    AS avg_pre_60day_return_pct,
    AVG(pre_30d_return_pct)    AS avg_pre_30day_return_pct,
    AVG(pre_5d_return_pct)     AS avg_pre_5day_return_pct,
    AVG(day_0_return_pct)       AS avg_announcement_return_pct,
    AVG(post_5d_return_pct)     AS avg_post_5day_return_pct,
    AVG(post_30d_return_pct)    AS avg_post_30day_return_pct,
    AVG(post_60d_return_pct)    AS avg_post_60day_return_pct
FROM aggregated_events
GROUP BY rate_action, sector_name
ORDER BY sector_name, rate_action;

SELECT * FROM sector_returns_by_index_rate_change LIMIT 1;

-- --------------------------------------------------------------------------
-- 7. Sector Volatility to Inflation Rate Changes
-- --------------------------------------------------------------------------

WITH previous_inflation AS (
    SELECT *, LAG(cpi) OVER (ORDER BY release_date) AS previous_cpi
    FROM inflation_market_returns
),
inflation_events AS (
    SELECT *,
        CASE
            WHEN cpi > previous_cpi THEN 'HIKE'
            WHEN cpi < previous_cpi THEN 'CUT'
            ELSE 'NO_CHANGE'
        END AS rate_action
    FROM previous_inflation
),
daily_sector_returns AS (
    SELECT date, market_return_pct           AS return_pct, 'Nifty_Midcap' AS sector_name FROM daily_returns
    UNION ALL
    SELECT date, auto_return_pct,              'Auto'          FROM daily_returns
    UNION ALL
    SELECT date, bank_return_pct,              'Bank'          FROM daily_returns
    UNION ALL
    SELECT date, energy_return_pct,            'Energy'        FROM daily_returns
    UNION ALL
    SELECT date, financial_services_return_pct,'Financial Services' FROM daily_returns
    UNION ALL
    SELECT date, fmcg_return_pct,              'FMCG'          FROM daily_returns
    UNION ALL
    SELECT date, it_return_pct,                'IT'            FROM daily_returns
    UNION ALL
    SELECT date, metal_return_pct,             'Metal'         FROM daily_returns
    UNION ALL
    SELECT date, pharma_return_pct,            'Pharma'        FROM daily_returns
    UNION ALL
    SELECT date, realty_return_pct,            'Realty'        FROM daily_returns
),
event_windows AS (
    SELECT
        event.release_date,
        event.rate_action,
        sector.sector_name,
        sector.date,
        sector.return_pct,
        DATEDIFF(sector.date, event.release_date) AS day_offset
    FROM inflation_events event
    JOIN daily_sector_returns sector
        ON sector.date BETWEEN DATE_SUB(event.release_date, INTERVAL 60 DAY)
                           AND DATE_ADD(event.release_date, INTERVAL 60 DAY)
),
aggregated_volatility AS (
    SELECT
        release_date,
        rate_action,
        sector_name,
        STDDEV(CASE WHEN day_offset BETWEEN -60 AND -1 THEN return_pct END) AS vol_pre_60d,
        STDDEV(CASE WHEN day_offset BETWEEN -30 AND -1 THEN return_pct END) AS vol_pre_30d,
        STDDEV(CASE WHEN day_offset BETWEEN -5  AND -1 THEN return_pct END) AS vol_pre_5d,
        MAX(CASE WHEN day_offset = 0              THEN return_pct END)       AS vol_day_0,
        STDDEV(CASE WHEN day_offset BETWEEN 1   AND 5  THEN return_pct END) AS vol_post_5d,
        STDDEV(CASE WHEN day_offset BETWEEN 1   AND 30 THEN return_pct END) AS vol_post_30d,
        STDDEV(CASE WHEN day_offset BETWEEN 1   AND 60 THEN return_pct END) AS vol_post_60d
    FROM event_windows
    GROUP BY release_date, rate_action, sector_name
)
SELECT
    rate_action,
    sector_name,
    ROUND(AVG(vol_pre_60d), 2)  AS avg_vol_pre_60day_pct,
    ROUND(AVG(vol_pre_30d), 2)  AS avg_vol_pre_30day_pct,
    ROUND(AVG(vol_pre_5d), 2)   AS avg_vol_pre_5day_pct,
    ROUND(AVG(vol_day_0), 2)     AS avg_vol_announcement_pct,
    ROUND(AVG(vol_post_5d), 2)   AS avg_vol_post_5day_pct,
    ROUND(AVG(vol_post_30d), 2)  AS avg_vol_post_30day_pct,
    ROUND(AVG(vol_post_60d), 2)  AS avg_vol_post_60day_pct
FROM aggregated_volatility
GROUP BY rate_action, sector_name
ORDER BY sector_name, rate_action;

/*
Sector volatility observations:
  - Auto  : ~1.2% avg volatility
  - Bank  : Volatility decreases toward announcement day then rises
  - Energy: ~1.1% volatility
  - Financial Services: Higher volatility 5 days before no-change decisions
  - FMCG  : ~2% volatility on no-change announcement days
  - IT    : ~1.2% volatility
  - Metal : ~1.6% volatility; higher when no change expected
  - Pharma: ~0.7% volatility (least sensitive)
  - Realty: ~1.7% volatility (highly sensitive to rate changes)
*/
