-- ============================================================================
-- Events Impact Analysis: Sentiment, Volatility, Recovery by Sector
-- ============================================================================
-- Business Context:
--   Assess how major events (financial crises, elections, wars, etc.) impact
--   market returns and sector recovery times, differentiating by sentiment.
-- ============================================================================

-- --------------------------------------------------------------------------
-- Preliminary: Table inspection and schema modifications
-- --------------------------------------------------------------------------
DESCRIBE dim_events;

UPDATE dim_events SET start_date = STR_TO_DATE(start_date, '%d-%m-%Y');
UPDATE dim_events SET end_date   = STR_TO_DATE(end_date, '%d-%m-%Y');

ALTER TABLE dim_events
    MODIFY COLUMN start_date DATE NOT NULL;

ALTER TABLE dim_events
    MODIFY COLUMN end_date DATE NOT NULL;

ALTER TABLE dim_events
    ADD PRIMARY KEY (event_id);

-- Drop existing views
DROP VIEW IF EXISTS events_impact_on_markets;

-- --------------------------------------------------------------------------
-- 1. Market Performance by Event Sentiment
-- --------------------------------------------------------------------------

WITH event_returns AS (
    SELECT
        event.event_id,
        event.sentiment,
        AVG(daily.market_return_pct) AS avg_event_return_pct
    FROM dim_events event
    JOIN daily_returns daily
        ON daily.date BETWEEN event.start_date AND event.end_date
    WHERE daily.market_return_pct IS NOT NULL
    GROUP BY event.event_id, event.sentiment
)
SELECT
    sentiment,
    AVG(avg_event_return_pct) AS overall_avg_return_pct
FROM event_returns
GROUP BY sentiment;

-- Insight: Market reacts more to positive events than negative events.

-- --------------------------------------------------------------------------
-- 2. Market Volatility Around Events (20-day rolling)
-- --------------------------------------------------------------------------

WITH market_log_returns AS (
    SELECT
        date AS trade_date,
        LN(market_index_value / LAG(market_index_value) OVER (ORDER BY date)) AS log_return
    FROM facts_market_indices
),
rolling_volatility AS (
    SELECT
        trade_date,
        log_return,
        STDDEV_SAMP(log_return) OVER (
            ORDER BY trade_date
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        ) AS volatility_20d
    FROM market_log_returns
),
event_volatility AS (
    SELECT
        event.sentiment,
        vol.log_return,
        vol.volatility_20d
    FROM dim_events event
    LEFT JOIN rolling_volatility vol
        ON vol.trade_date = (
            SELECT MIN(latest.trade_date)
            FROM rolling_volatility latest
            WHERE event.start_date <= latest.trade_date
        )
)
SELECT
    sentiment,
    AVG(log_return) * 100             AS avg_log_return_pct,
    MIN(volatility_20d) * 100         AS min_volatility_pct,
    AVG(volatility_20d) * 100         AS avg_volatility_pct,
    MAX(volatility_20d) * 100         AS max_volatility_pct
FROM event_volatility
GROUP BY sentiment;

-- Observation: Market volatility averages 1.2% to 1.65% depending on sentiment.

-- --------------------------------------------------------------------------
-- 3. Event Impact on Markets (180-day window: pre, during, post)
-- --------------------------------------------------------------------------

CREATE VIEW events_impact_on_markets AS
WITH sector_log_returns AS (
    SELECT date AS trade_date,
        'Nifty_Midcap' AS sector_name,
        LN(market_index_value / LAG(market_index_value) OVER (ORDER BY date)) AS log_return
    FROM facts_market_indices
    UNION ALL
    SELECT date, 'Auto',
        LN(nifty_auto_value / LAG(nifty_auto_value) OVER (ORDER BY date))
    FROM facts_market_indices
    UNION ALL
    SELECT date, 'Bank',
        LN(nifty_bank_value / LAG(nifty_bank_value) OVER (ORDER BY date))
    FROM facts_market_indices
    UNION ALL
    SELECT date, 'Energy',
        LN(nifty_energy_value / LAG(nifty_energy_value) OVER (ORDER BY date))
    FROM facts_market_indices
    UNION ALL
    SELECT date, 'Financial Services',
        LN(nifty_financial_services_value / LAG(nifty_financial_services_value) OVER (ORDER BY date))
    FROM facts_market_indices
    UNION ALL
    SELECT date, 'FMCG',
        LN(nifty_fmcg_value / LAG(nifty_fmcg_value) OVER (ORDER BY date))
    FROM facts_market_indices
    UNION ALL
    SELECT date, 'IT',
        LN(nifty_it_value / LAG(nifty_it_value) OVER (ORDER BY date))
    FROM facts_market_indices
    UNION ALL
    SELECT date, 'Metal',
        LN(nifty_metal_value / LAG(nifty_metal_value) OVER (ORDER BY date))
    FROM facts_market_indices
    UNION ALL
    SELECT date, 'Pharma',
        LN(nifty_pharma_value / LAG(nifty_pharma_value) OVER (ORDER BY date))
    FROM facts_market_indices
    UNION ALL
    SELECT date, 'Realty',
        LN(nifty_realty_value / LAG(nifty_realty_value) OVER (ORDER BY date))
    FROM facts_market_indices
),
event_windows AS (
    SELECT
        event.start_date,
        event.sentiment,
        sector.sector_name,
        sector.log_return,
        DATEDIFF(sector.trade_date, event.start_date) AS day_offset
    FROM sector_log_returns sector
    JOIN dim_events event
        ON sector.trade_date
        BETWEEN DATE_SUB(event.start_date, INTERVAL 180 DAY)
        AND DATE_ADD(event.start_date, INTERVAL 180 DAY)
)
SELECT
    sentiment,
    sector_name,
    -- Pre-event windows
    SUM(CASE WHEN day_offset BETWEEN -180 AND -1 THEN log_return ELSE 0 END) * 100 AS pre_180d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN -90  AND -1 THEN log_return ELSE 0 END) * 100 AS pre_90d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN -60  AND -1 THEN log_return ELSE 0 END) * 100 AS pre_60d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN -30  AND -1 THEN log_return ELSE 0 END) * 100 AS pre_30d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN -5   AND -1 THEN log_return ELSE 0 END) * 100 AS pre_5d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN -3   AND -1 THEN log_return ELSE 0 END) * 100 AS pre_3d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN -1   AND -1 THEN log_return ELSE 0 END) * 100 AS pre_1d_return_pct,
    -- Immediate reaction
    SUM(CASE WHEN day_offset = 0 THEN log_return ELSE 0 END) * 100 AS day_0_return_pct,
    -- Post-event windows
    SUM(CASE WHEN day_offset BETWEEN 1   AND 1   THEN log_return ELSE 0 END) * 100 AS post_1d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN 1   AND 3   THEN log_return ELSE 0 END) * 100 AS post_3d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN 1   AND 5   THEN log_return ELSE 0 END) * 100 AS post_5d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN 1   AND 30  THEN log_return ELSE 0 END) * 100 AS post_30d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN 1   AND 60  THEN log_return ELSE 0 END) * 100 AS post_60d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN 1   AND 90  THEN log_return ELSE 0 END) * 100 AS post_90d_return_pct,
    SUM(CASE WHEN day_offset BETWEEN 1   AND 180 THEN log_return ELSE 0 END) * 100 AS post_180d_return_pct
FROM event_windows
GROUP BY sentiment, sector_name;

-- --------------------------------------------------------------------------
-- 4. Overall Impact of Sentiment on Market (180-day horizon)
-- --------------------------------------------------------------------------

SELECT
    sentiment,
    AVG(pre_180d_return_pct)  AS avg_pre_180day_return_pct,
    AVG(pre_90d_return_pct)   AS avg_pre_90day_return_pct,
    AVG(pre_60d_return_pct)   AS avg_pre_60day_return_pct,
    AVG(pre_30d_return_pct)   AS avg_pre_30day_return_pct,
    AVG(pre_5d_return_pct)    AS avg_pre_5day_return_pct,
    AVG(pre_3d_return_pct)    AS avg_pre_3day_return_pct,
    AVG(pre_1d_return_pct)    AS avg_pre_1day_return_pct,
    AVG(day_0_return_pct)      AS avg_announcement_return_pct,
    AVG(post_1d_return_pct)    AS avg_post_1day_return_pct,
    AVG(post_3d_return_pct)    AS avg_post_3day_return_pct,
    AVG(post_5d_return_pct)    AS avg_post_5day_return_pct,
    AVG(post_30d_return_pct)   AS avg_post_30day_return_pct,
    AVG(post_60d_return_pct)   AS avg_post_60day_return_pct,
    AVG(post_90d_return_pct)   AS avg_post_90day_return_pct,
    AVG(post_180d_return_pct)  AS avg_post_180day_return_pct
FROM events_impact_on_markets
GROUP BY sentiment;

/*
Observations:
  1. Sentiment drives returns.
  2. Negative events impact markets for >3 months on average.
  3. Full recovery takes approximately 6 months.
*/

-- --------------------------------------------------------------------------
-- 5. Recovery Speed by Sector (180-day horizon)
-- --------------------------------------------------------------------------

SELECT
    sentiment,
    sector_name,
    AVG(pre_180d_return_pct)  AS avg_pre_180day_return_pct,
    AVG(pre_90d_return_pct)   AS avg_pre_90day_return_pct,
    AVG(pre_60d_return_pct)   AS avg_pre_60day_return_pct,
    AVG(pre_30d_return_pct)   AS avg_pre_30day_return_pct,
    AVG(pre_5d_return_pct)    AS avg_pre_5day_return_pct,
    AVG(pre_3d_return_pct)    AS avg_pre_3day_return_pct,
    AVG(pre_1d_return_pct)    AS avg_pre_1day_return_pct,
    AVG(day_0_return_pct)      AS avg_announcement_return_pct,
    AVG(post_1d_return_pct)    AS avg_post_1day_return_pct,
    AVG(post_3d_return_pct)    AS avg_post_3day_return_pct,
    AVG(post_5d_return_pct)    AS avg_post_5day_return_pct,
    AVG(post_30d_return_pct)   AS avg_post_30day_return_pct,
    AVG(post_60d_return_pct)   AS avg_post_60day_return_pct,
    AVG(post_90d_return_pct)   AS avg_post_90day_return_pct,
    AVG(post_180d_return_pct)  AS avg_post_180day_return_pct
FROM events_impact_on_markets
GROUP BY sentiment, sector_name
ORDER BY sentiment, sector_name;

/*
Recovery speed by sector:
  - Fastest recovering: Energy, FMCG, Pharma
  - Slowest recovering: Realty, Bank, Financial Services, IT (partly due to AI boom)
*/
