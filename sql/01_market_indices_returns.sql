-- ============================================================================
-- Market Indices Analysis: Monthly & Yearly Returns, Regime Analysis
-- ============================================================================
-- Business Context:
--   This script analyzes Nifty Midcap 150 and sector indices to compute
--   periodic returns, identify best-performing sectors per year, classify
--   market regimes (bull/bear), and measure regime streak durations.
-- ============================================================================

-- --------------------------------------------------------------------------
-- Preliminary: Table inspection and schema modifications
-- --------------------------------------------------------------------------
SHOW TABLES;

DESCRIBE facts_market_indices;

ALTER TABLE facts_market_indices
    MODIFY COLUMN date DATE NOT NULL;

ALTER TABLE facts_market_indices
    ADD PRIMARY KEY (date);

-- Drop views to allow re-creation
DROP VIEW IF EXISTS monthly_returns;
DROP VIEW IF EXISTS yearly_returns;
DROP VIEW IF EXISTS regime_data;
DROP VIEW IF EXISTS regime_data_monthly;
DROP VIEW IF EXISTS regime_streaks_length;
DROP VIEW IF EXISTS regime_streaks_length_monthly;

-- ============================================================================
-- 1. Monthly Returns per Sector
-- ============================================================================

CREATE VIEW monthly_returns AS
WITH monthly_trading_days AS (
    SELECT
        YEAR(date)  AS year,
        MONTH(date) AS month,
        MIN(date)   AS first_trading_date,
        MAX(date)   AS last_trading_date
    FROM facts_market_indices
    GROUP BY YEAR(date), MONTH(date)
),
monthly_performance AS (
    SELECT
        trading_days.year,
        trading_days.month,
        (last_day.market_index_value
            - first_day.market_index_value)
            / first_day.market_index_value              AS market_return,
        (last_day.nifty_auto_value
            - first_day.nifty_auto_value)
            / first_day.nifty_auto_value                 AS auto_return,
        (last_day.nifty_bank_value
            - first_day.nifty_bank_value)
            / first_day.nifty_bank_value                 AS bank_return,
        (last_day.nifty_energy_value
            - first_day.nifty_energy_value)
            / first_day.nifty_energy_value               AS energy_return,
        (last_day.nifty_financial_services_value
            - first_day.nifty_financial_services_value)
            / first_day.nifty_financial_services_value   AS financial_services_return,
        (last_day.nifty_fmcg_value
            - first_day.nifty_fmcg_value)
            / first_day.nifty_fmcg_value                 AS fmcg_return,
        (last_day.nifty_it_value
            - first_day.nifty_it_value)
            / first_day.nifty_it_value                   AS it_return,
        (last_day.nifty_metal_value
            - first_day.nifty_metal_value)
            / first_day.nifty_metal_value                AS metal_return,
        (last_day.nifty_pharma_value
            - first_day.nifty_pharma_value)
            / first_day.nifty_pharma_value               AS pharma_return,
        (last_day.nifty_realty_value
            - first_day.nifty_realty_value)
            / first_day.nifty_realty_value               AS realty_return
    FROM monthly_trading_days trading_days
    JOIN facts_market_indices first_day
        ON first_day.date = trading_days.first_trading_date
    JOIN facts_market_indices last_day
        ON last_day.date = trading_days.last_trading_date
)
SELECT *
FROM monthly_performance
ORDER BY year, month;

-- Average monthly returns across the entire period
SELECT
    AVG(market_return)             * 100  AS avg_monthly_market_return_pct,
    AVG(auto_return)                       AS avg_monthly_auto_return,
    AVG(bank_return)                       AS avg_monthly_bank_return,
    AVG(energy_return)                     AS avg_monthly_energy_return,
    AVG(financial_services_return)         AS avg_monthly_financial_services_return,
    AVG(fmcg_return)                       AS avg_monthly_fmcg_return,
    AVG(it_return)                         AS avg_monthly_it_return,
    AVG(metal_return)                      AS avg_monthly_metal_return,
    AVG(pharma_return)                     AS avg_monthly_pharma_return,
    AVG(realty_return)                     AS avg_monthly_realty_return
FROM monthly_returns;

-- ============================================================================
-- 2. Yearly Returns per Sector
-- ============================================================================

CREATE VIEW yearly_returns AS
WITH yearly_trading_days AS (
    SELECT
        YEAR(date)  AS year,
        MIN(date)   AS first_trading_date,
        MAX(date)   AS last_trading_date
    FROM facts_market_indices
    GROUP BY YEAR(date)
),
yearly_performance AS (
    SELECT
        trading_days.year,
        (last_day.market_index_value
            - first_day.market_index_value)
            / first_day.market_index_value              AS market_return,
        (last_day.nifty_auto_value
            - first_day.nifty_auto_value)
            / first_day.nifty_auto_value                 AS auto_return,
        (last_day.nifty_bank_value
            - first_day.nifty_bank_value)
            / first_day.nifty_bank_value                 AS bank_return,
        (last_day.nifty_energy_value
            - first_day.nifty_energy_value)
            / first_day.nifty_energy_value               AS energy_return,
        (last_day.nifty_financial_services_value
            - first_day.nifty_financial_services_value)
            / first_day.nifty_financial_services_value   AS financial_services_return,
        (last_day.nifty_fmcg_value
            - first_day.nifty_fmcg_value)
            / first_day.nifty_fmcg_value                 AS fmcg_return,
        (last_day.nifty_it_value
            - first_day.nifty_it_value)
            / first_day.nifty_it_value                   AS it_return,
        (last_day.nifty_metal_value
            - first_day.nifty_metal_value)
            / first_day.nifty_metal_value                AS metal_return,
        (last_day.nifty_pharma_value
            - first_day.nifty_pharma_value)
            / first_day.nifty_pharma_value               AS pharma_return,
        (last_day.nifty_realty_value
            - first_day.nifty_realty_value)
            / first_day.nifty_realty_value               AS realty_return
    FROM yearly_trading_days trading_days
    JOIN facts_market_indices first_day
        ON first_day.date = trading_days.first_trading_date
    JOIN facts_market_indices last_day
        ON last_day.date = trading_days.last_trading_date
)
SELECT *
FROM yearly_performance
ORDER BY year;

-- ============================================================================
-- 3. Best Performing Index per Year
-- ============================================================================

WITH all_sector_returns AS (
    SELECT
        YEAR(date) AS year,
        'Market Index'        AS sector_name,
        market_return         AS annual_return
    FROM yearly_returns

    UNION ALL
    SELECT YEAR(date), 'Nifty Auto',             auto_return             FROM yearly_returns
    UNION ALL
    SELECT YEAR(date), 'Nifty Bank',             bank_return             FROM yearly_returns
    UNION ALL
    SELECT YEAR(date), 'Nifty Energy',           energy_return           FROM yearly_returns
    UNION ALL
    SELECT YEAR(date), 'Nifty Financial Services', financial_services_return FROM yearly_returns
    UNION ALL
    SELECT YEAR(date), 'Nifty FMCG',             fmcg_return             FROM yearly_returns
    UNION ALL
    SELECT YEAR(date), 'Nifty IT',               it_return               FROM yearly_returns
    UNION ALL
    SELECT YEAR(date), 'Nifty Metal',            metal_return            FROM yearly_returns
    UNION ALL
    SELECT YEAR(date), 'Nifty Pharma',           pharma_return           FROM yearly_returns
    UNION ALL
    SELECT YEAR(date), 'Nifty Realty',           realty_return           FROM yearly_returns
),
ranked_returns AS (
    SELECT
        year,
        sector_name,
        ROUND(annual_return, 2) AS annual_return_pct,
        ROW_NUMBER() OVER (
            PARTITION BY year
            ORDER BY annual_return DESC
        ) AS rank_in_year
    FROM all_sector_returns
    WHERE annual_return IS NOT NULL
)
SELECT
    year,
    sector_name AS best_performing_sector,
    annual_return_pct
FROM ranked_returns
WHERE rank_in_year = 1
ORDER BY year;

-- ============================================================================
-- 4. Market Regime Classification (Daily & Monthly)
-- ============================================================================

-- Daily regime based on daily return
CREATE VIEW regime_data AS
WITH daily_returns AS (
    SELECT
        date,
        market_index_value,
        (market_index_value - LAG(market_index_value) OVER (ORDER BY date))
            / LAG(market_index_value) OVER (ORDER BY date) AS daily_return
    FROM facts_market_indices
)
SELECT
    date,
    market_index_value,
    daily_return,
    CASE
        WHEN daily_return < 0 THEN 'DOVISH'
        WHEN daily_return > 0 THEN 'HAWKISH'
        ELSE 'NEUTRAL'
    END AS regime
FROM daily_returns
ORDER BY date;

-- Monthly regime based on monthly return
CREATE VIEW regime_data_monthly AS
WITH monthly_returns_with_lag AS (
    SELECT
        date,
        market_return,
        (market_return - LAG(market_return) OVER (ORDER BY date))
            / LAG(market_return) OVER (ORDER BY date) AS monthly_return_change
    FROM monthly_returns
)
SELECT
    date,
    market_return,
    monthly_return_change,
    CASE
        WHEN monthly_return_change < 0 THEN 'DOVISH'
        WHEN monthly_return_change > 0 THEN 'HAWKISH'
        ELSE 'NEUTRAL'
    END AS regime
FROM monthly_returns_with_lag
ORDER BY date;

-- ============================================================================
-- 5. Regime Streak Lengths (Consecutive months in same regime)
-- ============================================================================

CREATE VIEW regime_streaks_length_monthly AS
WITH regime_change_flags AS (
    SELECT
        date,
        regime,
        CASE
            WHEN LAG(regime) OVER (ORDER BY date) = regime
            THEN 0
            ELSE 1
        END AS is_new_streak
    FROM regime_data_monthly
),
streak_groups AS (
    SELECT
        date,
        regime,
        SUM(is_new_streak) OVER (ORDER BY date) AS streak_group_id
    FROM regime_change_flags
)
SELECT
    regime,
    MIN(date)      AS streak_start_date,
    MAX(date)      AS streak_end_date,
    COUNT(*)       AS streak_length_months
FROM streak_groups
GROUP BY regime, streak_group_id
ORDER BY streak_start_date;

-- ============================================================================
-- 6. Longest Bull and Bear Streaks
-- ============================================================================

SELECT *
FROM regime_streaks_length_monthly
WHERE
    (regime = 'HAWKISH'
     AND streak_length_months = (
         SELECT MAX(streak_length_months)
         FROM regime_streaks_length_monthly
         WHERE regime = 'HAWKISH'
     ))
UNION
SELECT *
FROM regime_streaks_length_monthly
WHERE
    (regime = 'DOVISH'
     AND streak_length_months = (
         SELECT MAX(streak_length_months)
         FROM regime_streaks_length_monthly
         WHERE regime = 'DOVISH'
     ));

-- Observation:
--   Market was consistently dovish from Feb 2011 to Mar 2012 as the bull run
--   ended and there was a slowdown.

-- ============================================================================
-- 7. Sectors that Outperformed During the Dovish Period (Feb 2011 - Mar 2012)
-- ============================================================================

SELECT
    sector,
    monthly_return
FROM (
    SELECT date, 'AUTO'               AS sector, auto_return             AS monthly_return FROM monthly_returns
    UNION ALL
    SELECT date, 'BANK'               AS sector, bank_return             AS monthly_return FROM monthly_returns
    UNION ALL
    SELECT date, 'ENERGY'             AS sector, energy_return           AS monthly_return FROM monthly_returns
    UNION ALL
    SELECT date, 'FINANCIAL_SERVICES' AS sector, financial_services_return AS monthly_return FROM monthly_returns
    UNION ALL
    SELECT date, 'FMCG'               AS sector, fmcg_return             AS monthly_return FROM monthly_returns
    UNION ALL
    SELECT date, 'IT'                 AS sector, it_return               AS monthly_return FROM monthly_returns
    UNION ALL
    SELECT date, 'METAL'              AS sector, metal_return            AS monthly_return FROM monthly_returns
    UNION ALL
    SELECT date, 'PHARMA'             AS sector, pharma_return           AS monthly_return FROM monthly_returns
    UNION ALL
    SELECT date, 'REALTY'             AS sector, realty_return           AS monthly_return FROM monthly_returns
) sector_performance
WHERE date BETWEEN '2011-02-01' AND '2012-03-31'
ORDER BY monthly_return DESC
LIMIT 3;

-- Observation:
--   During this period the sectors that recovered fastest were:
--   - Realty, Metal, Bank
