-- ============================================================================
-- Market Risk Analysis: Drawdowns, Recovery, Bull/Bear Cycles & Volatility
-- ============================================================================
-- Business Context:
--   Quantify maximum drawdowns, sector recovery times after crashes, average
--   bull/bear market durations, and volatility patterns across regimes.
-- ============================================================================

-- --------------------------------------------------------------------------
-- 5. Market Drawdown Analysis (biggest peak-to-trough decline)
-- --------------------------------------------------------------------------
-- Drop existing objects to allow re-creation
DROP VIEW IF EXISTS drawdown_analysis;
DROP VIEW IF EXISTS bull_run_duration;
DROP VIEW IF EXISTS bear_market_duration;
DROP TABLE IF EXISTS sector_recovery_days;

CREATE VIEW drawdown_analysis AS
WITH running_peak AS (
    SELECT
        date,
        market_index_value,
        MAX(market_index_value) OVER (ORDER BY date) AS peak_value
    FROM facts_market_indices
    WHERE market_index_value IS NOT NULL
),
drawdowns AS (
    SELECT
        date,
        market_index_value,
        peak_value,
        (market_index_value - peak_value) * 100.0 / peak_value AS drawdown_pct
    FROM running_peak
),
drawdown_peak_groups AS (
    SELECT
        *,
        SUM(
            CASE
                WHEN market_index_value >= peak_value THEN 1
                ELSE 0
            END
        ) OVER (ORDER BY date) AS peak_group_id
    FROM drawdowns
),
drawdown_summary AS (
    SELECT
        MIN(date)                                             AS peak_date,
        MIN(
            CASE
                WHEN market_index_value = trough_value THEN date
            END
        )                                                     AS trough_date,
        MAX(peak_value)                                       AS peak_value,
        MIN(market_index_value)                               AS trough_value,
        MIN(drawdown_pct)                                     AS max_drawdown_pct
    FROM (
        SELECT
            *,
            MIN(market_index_value) OVER (
                PARTITION BY peak_group_id
            ) AS trough_value
        FROM drawdown_peak_groups
    ) grouped
    GROUP BY peak_group_id
    HAVING MIN(drawdown_pct) <= -5
)
SELECT
    peak_date,
    trough_date,
    ROUND(peak_value, 2)              AS peak_value,
    ROUND(trough_value, 2)            AS trough_value,
    ROUND(max_drawdown_pct, 2)        AS drawdown_pct,
    DATEDIFF(trough_date, peak_date)  AS drawdown_duration_days
FROM drawdown_summary
ORDER BY max_drawdown_pct
LIMIT 1;

SELECT * FROM drawdown_analysis;
-- Observation: Peak date: 7 Jan 2008, Trough date: 9 Mar 2009

-- --------------------------------------------------------------------------
-- 6. Recovery Time After Major Drawdown
-- --------------------------------------------------------------------------

SELECT
    drawdown.peak_date,
    drawdown.trough_date,
    MIN(market.date)                                     AS recovery_date,
    DATEDIFF(MIN(market.date), drawdown.trough_date)      AS recovery_days
FROM drawdown_analysis drawdown
JOIN facts_market_indices market
    ON market.date > drawdown.trough_date
    AND market.market_index_value >= drawdown.peak_value
GROUP BY drawdown.peak_date, drawdown.trough_date;

-- Observation: Market took 1,901 days to recover to its pre-crash level.

-- --------------------------------------------------------------------------
-- 7. Sector Recovery Speed After Major Drawdown
-- --------------------------------------------------------------------------

CREATE TABLE sector_recovery_days AS
WITH sector_recovery AS (
    SELECT
        peak_date,
        trough_date,
        'AUTO' AS sector_name,
        (
            SELECT MIN(m2.date)
            FROM facts_market_indices m2
            WHERE m2.nifty_auto_value >= (
                SELECT peak_val.nifty_auto_value
                FROM facts_market_indices peak_val
                WHERE peak_val.date = drawdown.peak_date
            )
            AND m2.date > drawdown.trough_date
        ) AS sector_recovery_date
    FROM drawdown_analysis drawdown

    UNION ALL
    SELECT peak_date, trough_date, 'BANK',
        (SELECT MIN(m2.date) FROM facts_market_indices m2
         WHERE m2.nifty_bank_value >= (SELECT p.nifty_bank_value FROM facts_market_indices p WHERE p.date = drawdown.peak_date)
           AND m2.date > drawdown.trough_date)
    FROM drawdown_analysis drawdown

    UNION ALL
    SELECT peak_date, trough_date, 'ENERGY',
        (SELECT MIN(m2.date) FROM facts_market_indices m2
         WHERE m2.nifty_energy_value >= (SELECT p.nifty_energy_value FROM facts_market_indices p WHERE p.date = drawdown.peak_date)
           AND m2.date > drawdown.trough_date)
    FROM drawdown_analysis drawdown

    UNION ALL
    SELECT peak_date, trough_date, 'FINANCIAL_SERVICES',
        (SELECT MIN(m2.date) FROM facts_market_indices m2
         WHERE m2.nifty_financial_services_value >= (SELECT p.nifty_financial_services_value FROM facts_market_indices p WHERE p.date = drawdown.peak_date)
           AND m2.date > drawdown.trough_date)
    FROM drawdown_analysis drawdown

    UNION ALL
    SELECT peak_date, trough_date, 'FMCG',
        (SELECT MIN(m2.date) FROM facts_market_indices m2
         WHERE m2.nifty_fmcg_value >= (SELECT p.nifty_fmcg_value FROM facts_market_indices p WHERE p.date = drawdown.peak_date)
           AND m2.date > drawdown.trough_date)
    FROM drawdown_analysis drawdown

    UNION ALL
    SELECT peak_date, trough_date, 'IT',
        (SELECT MIN(m2.date) FROM facts_market_indices m2
         WHERE m2.nifty_it_value >= (SELECT p.nifty_it_value FROM facts_market_indices p WHERE p.date = drawdown.peak_date)
           AND m2.date > drawdown.trough_date)
    FROM drawdown_analysis drawdown

    UNION ALL
    SELECT peak_date, trough_date, 'METAL',
        (SELECT MIN(m2.date) FROM facts_market_indices m2
         WHERE m2.nifty_metal_value >= (SELECT p.nifty_metal_value FROM facts_market_indices p WHERE p.date = drawdown.peak_date)
           AND m2.date > drawdown.trough_date)
    FROM drawdown_analysis drawdown

    UNION ALL
    SELECT peak_date, trough_date, 'PHARMA',
        (SELECT MIN(m2.date) FROM facts_market_indices m2
         WHERE m2.nifty_pharma_value >= (SELECT p.nifty_pharma_value FROM facts_market_indices p WHERE p.date = drawdown.peak_date)
           AND m2.date > drawdown.trough_date)
    FROM drawdown_analysis drawdown

    UNION ALL
    SELECT peak_date, trough_date, 'REALTY',
        (SELECT MIN(m2.date) FROM facts_market_indices m2
         WHERE m2.nifty_realty_value >= (SELECT p.nifty_realty_value FROM facts_market_indices p WHERE p.date = drawdown.peak_date)
           AND m2.date > drawdown.trough_date)
    FROM drawdown_analysis drawdown
)
SELECT
    sector_name,
    ROUND(
        MIN(
            CASE
                WHEN sector_recovery_date IS NOT NULL
                    THEN DATEDIFF(sector_recovery_date, trough_date)
                ELSE NULL
            END
        ), 1
    ) AS recovery_days
FROM sector_recovery
GROUP BY sector_name
ORDER BY recovery_days ASC;

SELECT * FROM sector_recovery_days;

/*
Observations:
  - Market Index : 1,901 days
  - FMCG         : 140 days
  - Auto         : 141 days
  - IT           : 168 days
  - Pharma       : 200 days
  - Bank         : 511 days
  - Fin Services : 549 days
  - Metal        : 4,445 days
  - Realty       : Not recovered (never reclaimed its Jan 2008 peak)
  - Energy       : Data not available for the period
*/

-- --------------------------------------------------------------------------
-- 8. Bull Market Duration (recovery from trough to new all-time high)
-- --------------------------------------------------------------------------

CREATE VIEW bull_run_duration AS
WITH running_peak AS (
    SELECT
        date,
        market_index_value,
        MAX(market_index_value) OVER (ORDER BY date) AS peak_value
    FROM facts_market_indices
),
bear_troughs AS (
    SELECT
        rp.date           AS trough_date,
        rp.market_index_value AS trough_value,
        rp.peak_value,
        (
            SELECT MIN(peak_date.date)
            FROM facts_market_indices peak_date
            WHERE peak_date.market_index_value = rp.peak_value
              AND peak_date.date <= rp.date
        ) AS peak_date
    FROM running_peak rp
    WHERE (rp.market_index_value - rp.peak_value) / rp.peak_value <= -0.20
),
first_bear_trough AS (
    SELECT
        peak_date,
        MIN(trough_date) AS trough_date
    FROM bear_troughs
    GROUP BY peak_date
),
bull_markets AS (
    SELECT
        bear.peak_date,
        bear.trough_date,
        (
            SELECT MIN(market.date)
            FROM facts_market_indices market
            WHERE market.date > bear.trough_date
              AND market.market_index_value > (
                  SELECT peak_val.market_index_value
                  FROM facts_market_indices peak_val
                  WHERE peak_val.date = bear.peak_date
              )
        ) AS new_all_time_high_date
    FROM first_bear_trough bear
)
SELECT
    peak_date               AS previous_peak_date,
    trough_date             AS bull_market_start_date,
    new_all_time_high_date  AS bull_market_end_date,
    DATEDIFF(new_all_time_high_date, trough_date) AS bull_market_duration_days
FROM bull_markets
WHERE new_all_time_high_date IS NOT NULL
ORDER BY trough_date;

-- Average bull run duration
SELECT
    AVG(bull_market_duration_days) AS avg_bull_run_duration_days
FROM bull_run_duration;

-- Observation: Average bull run ~874.5 days.

-- --------------------------------------------------------------------------
-- 9. Bear Market Duration
-- --------------------------------------------------------------------------

CREATE VIEW bear_market_duration AS
WITH running_peak AS (
    SELECT
        date,
        market_index_value,
        MAX(market_index_value) OVER (ORDER BY date) AS peak_value
    FROM facts_market_indices
    WHERE market_index_value IS NOT NULL
),
drawdowns AS (
    SELECT
        date,
        market_index_value,
        peak_value,
        (market_index_value - peak_value) * 100.0 / peak_value AS drawdown_pct
    FROM running_peak
),
bear_peak_groups AS (
    SELECT
        *,
        SUM(
            CASE
                WHEN market_index_value = peak_value THEN 1
                ELSE 0
            END
        ) OVER (ORDER BY date) AS peak_group_id
    FROM drawdowns
),
bear_markets AS (
    SELECT
        peak_group_id,
        MIN(date) AS peak_date,
        MIN(
            CASE
                WHEN market_index_value = (
                    SELECT MIN(sub.market_index_value)
                    FROM bear_peak_groups sub
                    WHERE sub.peak_group_id = main.peak_group_id
                )
                THEN date
            END
        ) AS trough_date,
        MAX(peak_value)           AS peak_value,
        MIN(market_index_value)   AS trough_value,
        MIN(drawdown_pct)         AS max_drawdown_pct
    FROM bear_peak_groups main
    GROUP BY peak_group_id
    HAVING MIN(drawdown_pct) <= -20
)
SELECT
    peak_date                           AS bear_market_start_date,
    trough_date                         AS bear_market_end_date,
    ROUND(peak_value, 2)                AS peak_value,
    ROUND(trough_value, 2)              AS trough_value,
    ROUND(max_drawdown_pct, 2)          AS max_drawdown_pct,
    DATEDIFF(trough_date, peak_date)    AS bear_duration_days,
    ROUND(DATEDIFF(trough_date, peak_date) / 365.25, 2) AS bear_duration_years
FROM bear_markets
ORDER BY peak_date;

-- Average bear run duration
SELECT
    AVG(bear_duration_days) AS avg_bear_run_duration_days
FROM bear_market_duration;

-- Observation: Average bear run ~409 days.

-- --------------------------------------------------------------------------
-- 10. Volatility Across Market Regimes (200-day SMA classification)
-- --------------------------------------------------------------------------

WITH daily_returns AS (
    SELECT
        date,
        market_index_value,
        (market_index_value - LAG(market_index_value) OVER (ORDER BY date))
            / LAG(market_index_value) OVER (ORDER BY date) * 100 AS daily_return_pct
    FROM facts_market_indices
    WHERE market_index_value IS NOT NULL
),
sma_200_calc AS (
    SELECT
        date,
        market_index_value,
        daily_return_pct,
        AVG(market_index_value) OVER (
            ORDER BY date
            ROWS BETWEEN 199 PRECEDING AND CURRENT ROW
        ) AS sma_200
    FROM daily_returns
),
regime_classification AS (
    SELECT
        date,
        market_index_value,
        daily_return_pct,
        CASE
            WHEN market_index_value > sma_200 * 1.05 THEN 'STRONG_BULL'
            WHEN market_index_value > sma_200           THEN 'BULL'
            WHEN market_index_value < sma_200 * 0.95 THEN 'STRONG_BEAR'
            WHEN market_index_value < sma_200           THEN 'BEAR'
            ELSE 'NEUTRAL'
        END AS regime
    FROM sma_200_calc
    WHERE sma_200 IS NOT NULL
),
volatility_by_regime AS (
    SELECT
        regime,
        COUNT(*)                                AS trading_days,
        ROUND(AVG(daily_return_pct), 4)         AS avg_daily_return_pct,
        ROUND(STDDEV(daily_return_pct), 4)      AS daily_return_stddev_pct,
        ROUND(STDDEV(daily_return_pct) * SQRT(252), 4) AS annualized_volatility_pct,
        ROUND(MIN(daily_return_pct), 4)         AS min_daily_return_pct,
        ROUND(MAX(daily_return_pct), 4)         AS max_daily_return_pct
    FROM regime_classification
    WHERE daily_return_pct IS NOT NULL
    GROUP BY regime
)
SELECT
    regime,
    trading_days,
    avg_daily_return_pct,
    daily_return_stddev_pct,
    annualized_volatility_pct,
    min_daily_return_pct,
    max_daily_return_pct
FROM volatility_by_regime
ORDER BY annualized_volatility_pct DESC;

-- --------------------------------------------------------------------------
-- 11. Bull vs Bear Time Split (Proportion of market in each regime)
-- --------------------------------------------------------------------------

WITH sma_200_calc AS (
    SELECT
        date,
        market_index_value,
        AVG(market_index_value) OVER (
            ORDER BY date
            ROWS BETWEEN 199 PRECEDING AND CURRENT ROW
        ) AS sma_200
    FROM facts_market_indices
    WHERE market_index_value IS NOT NULL
),
regime_classification AS (
    SELECT
        date,
        market_index_value,
        CASE
            WHEN market_index_value > sma_200 THEN 'BULL'
            WHEN market_index_value < sma_200 THEN 'BEAR'
            ELSE 'NEUTRAL'
        END AS regime
    FROM sma_200_calc
    WHERE sma_200 IS NOT NULL
),
regime_counts AS (
    SELECT
        regime,
        COUNT(*) AS trading_days
    FROM regime_classification
    GROUP BY regime
),
total_trading_days AS (
    SELECT SUM(trading_days) AS grand_total
    FROM regime_counts
)
SELECT
    regime_counts.regime,
    regime_counts.trading_days,
    ROUND(regime_counts.trading_days * 100.0 / total_trading_days.grand_total, 2) AS pct_of_total_time,
    ROUND(regime_counts.trading_days / 252.0, 2) AS approx_years
FROM regime_counts
CROSS JOIN total_trading_days
ORDER BY pct_of_total_time DESC;

-- Observation:
--   ~68% of time market is in bull regime
--   ~32% of time market is in bear regime
