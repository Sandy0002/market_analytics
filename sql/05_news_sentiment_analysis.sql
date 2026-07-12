-- ============================================================================
-- News Sentiment Analysis: Market Reaction, Volatility, Event Windows
-- ============================================================================
-- Business Context:
--   Quantify how news sentiment (positive/negative) drives market returns and
--   volatility across sectors, and measure pre/post-event window behavior.
-- ============================================================================

-- --------------------------------------------------------------------------
-- Preliminary: Table inspection and schema modifications
-- --------------------------------------------------------------------------
DESCRIBE dim_news;

UPDATE dim_news SET start_date = STR_TO_DATE(start_date, '%d-%m-%Y');
UPDATE dim_news SET end_date   = STR_TO_DATE(end_date, '%d-%m-%Y');

ALTER TABLE dim_news
    MODIFY COLUMN start_date DATE NOT NULL;

ALTER TABLE dim_news
    MODIFY COLUMN end_date DATE NOT NULL;

ALTER TABLE dim_news
    ADD PRIMARY KEY (news_id);

-- --------------------------------------------------------------------------
-- 1. Market Performance by News Sentiment (Yearly Aggregation)
-- --------------------------------------------------------------------------

WITH news_event_returns AS (
    SELECT
        news.news_id,
        news.year,
        news.sentiment,
        AVG(daily.market_return_pct) AS avg_event_return_pct
    FROM dim_news news
    JOIN daily_returns daily
        ON daily.date BETWEEN news.start_date AND news.end_date
    WHERE daily.market_return_pct IS NOT NULL
    GROUP BY news.news_id, news.year, news.sentiment
)
SELECT
    year,
    sentiment,
    MAX(avg_event_return_pct)   AS best_performance_pct,
    AVG(avg_event_return_pct)   AS avg_performance_pct,
    MIN(avg_event_return_pct)   AS worst_performance_pct
FROM news_event_returns
GROUP BY year, sentiment
ORDER BY year, sentiment;

-- --------------------------------------------------------------------------
-- 2. Does Market React More to Negative News Than Positive?
-- --------------------------------------------------------------------------

WITH news_event_returns AS (
    SELECT
        news.news_id,
        news.sentiment,
        AVG(daily.market_return_pct) AS avg_event_return_pct
    FROM dim_news news
    JOIN daily_returns daily
        ON daily.date BETWEEN news.start_date AND news.end_date
    WHERE daily.market_return_pct IS NOT NULL
    GROUP BY news.news_id, news.sentiment
)
SELECT
    sentiment,
    AVG(avg_event_return_pct) AS overall_avg_return_pct
FROM news_event_returns
GROUP BY sentiment;

-- Insight: Market reacts more strongly to negative news than positive news.

-- --------------------------------------------------------------------------
-- 3. Market Volatility Around News Events (20-day rolling)
-- --------------------------------------------------------------------------

WITH market_log_returns AS (
    SELECT
        date            AS trade_date,
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
news_volatility AS (
    SELECT
        news.sentiment,
        vol.log_return,
        vol.volatility_20d
    FROM dim_news news
    LEFT JOIN rolling_volatility vol
        ON vol.trade_date = (
            SELECT MIN(latest_vol.trade_date)
            FROM rolling_volatility latest_vol
            WHERE news.start_date <= latest_vol.trade_date
        )
)
SELECT
    sentiment,
    AVG(log_return) * 100             AS avg_log_return_pct,
    MIN(volatility_20d) * 100         AS min_volatility_20d_pct,
    AVG(volatility_20d) * 100         AS avg_volatility_20d_pct,
    MAX(volatility_20d) * 100         AS max_volatility_20d_pct,
    COUNT(*)                          AS news_count
FROM news_volatility
GROUP BY sentiment;

-- --------------------------------------------------------------------------
-- 4. Sector-Level Volatility Around News Events
-- --------------------------------------------------------------------------

WITH sector_log_returns AS (
    SELECT
        date AS trade_date,
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
rolling_volatility AS (
    SELECT
        trade_date,
        sector_name,
        log_return,
        STDDEV_SAMP(log_return) OVER (
            PARTITION BY sector_name
            ORDER BY trade_date
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        ) AS volatility_20d
    FROM sector_log_returns
),
news_sector_volatility AS (
    SELECT
        news.sentiment,
        vol.sector_name,
        vol.log_return,
        vol.volatility_20d
    FROM dim_news news
    LEFT JOIN rolling_volatility vol
        ON vol.trade_date = (
            SELECT MIN(latest.trade_date)
            FROM rolling_volatility latest
            WHERE news.start_date <= latest.trade_date
              AND latest.sector_name = vol.sector_name
        )
)
SELECT
    sentiment,
    sector_name,
    AVG(log_return) * 100             AS avg_log_return_pct,
    MIN(volatility_20d) * 100         AS min_volatility_pct,
    AVG(volatility_20d) * 100         AS avg_volatility_pct,
    MAX(volatility_20d) * 100         AS max_volatility_pct
FROM news_sector_volatility
GROUP BY sentiment, sector_name
ORDER BY sector_name, sentiment;

/*
Volatility observations:
  - Min volatility   : ~0.5%
  - Avg volatility   : ~1.5%
  - Max volatility   : up to ~6.5%
  - Most stable      : Pharma
  - Most volatile    : Auto, Bank, IT, Metal
*/

-- --------------------------------------------------------------------------
-- 5. Returns Around News Events (5-day window: pre, during, post)
-- --------------------------------------------------------------------------

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
        news.start_date,
        news.sentiment,
        sector.sector_name,
        sector.log_return,
        DATEDIFF(sector.trade_date, news.start_date) AS day_offset
    FROM sector_log_returns sector
    JOIN dim_news news
        ON sector.trade_date
        BETWEEN DATE_SUB(news.start_date, INTERVAL 5 DAY)
        AND DATE_ADD(news.start_date, INTERVAL 5 DAY)
),
aggregated AS (
    SELECT
        sentiment,
        sector_name,
        SUM(CASE WHEN day_offset BETWEEN -5 AND -1 THEN log_return ELSE 0 END) * 100 AS pre_5d_return_pct,
        SUM(CASE WHEN day_offset BETWEEN -3 AND -1 THEN log_return ELSE 0 END) * 100 AS pre_3d_return_pct,
        SUM(CASE WHEN day_offset BETWEEN -1 AND -1 THEN log_return ELSE 0 END) * 100 AS pre_1d_return_pct,
        SUM(CASE WHEN day_offset = 0              THEN log_return ELSE 0 END) * 100 AS day_0_return_pct,
        SUM(CASE WHEN day_offset BETWEEN 1  AND 1  THEN log_return ELSE 0 END) * 100 AS post_1d_return_pct,
        SUM(CASE WHEN day_offset BETWEEN 1  AND 3  THEN log_return ELSE 0 END) * 100 AS post_3d_return_pct,
        SUM(CASE WHEN day_offset BETWEEN 1  AND 5  THEN log_return ELSE 0 END) * 100 AS post_5d_return_pct
    FROM event_windows
    GROUP BY sentiment, sector_name
)
SELECT
    sentiment,
    sector_name,
    AVG(pre_5d_return_pct)  AS avg_pre_5day_return_pct,
    AVG(pre_3d_return_pct)  AS avg_pre_3day_return_pct,
    AVG(pre_1d_return_pct)  AS avg_pre_1day_return_pct,
    AVG(day_0_return_pct)    AS avg_announcement_return_pct,
    AVG(post_1d_return_pct)  AS avg_post_1day_return_pct,
    AVG(post_3d_return_pct)  AS avg_post_3day_return_pct,
    AVG(post_5d_return_pct)  AS avg_post_5day_return_pct
FROM aggregated
GROUP BY sentiment, sector_name
ORDER BY sector_name, sentiment;
