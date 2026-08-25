-- =============================================================================
-- RZR GLOBAL LEAD QUALITY ANALYTICS - SQL CASE STUDY REPOSITORY
-- Author: Candidate (Senior Growth / Media Analytics Analyst)
-- Database Dialect: Standard ANSI SQL (Compatible with PostgreSQL / BigQuery / Snowflake / SQL Server)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. SCHEMA & TABLE DEFINITIONS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rzr_leads (
    lead_id VARCHAR(50) PRIMARY KEY,
    lead_created_timestamp TIMESTAMP,
    first_name VARCHAR(100),
    email VARCHAR(255),
    call_status VARCHAR(100),
    widget_name VARCHAR(150),
    publisher_zone_name VARCHAR(100),
    publisher_campaign_name VARCHAR(100),
    address_score INT,
    phone_score INT,
    advertiser_campaign_name VARCHAR(150),
    state VARCHAR(10),
    debt_level VARCHAR(50),
    partner VARCHAR(50),
    referral_domain VARCHAR(255),
    marketing_campaign VARCHAR(150),
    adgroup VARCHAR(150),
    keyword VARCHAR(255),
    search_query TEXT,
    landing_page_url TEXT,
    landing_page_url_parameters TEXT
);

-- -----------------------------------------------------------------------------
-- 1. BASE CLEANSED VIEW (Categorizing 4 Disposition Groups & Dimensions)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_rzr_leads_enriched AS
SELECT
    lead_id,
    lead_created_timestamp,
    DATE_TRUNC('month', lead_created_timestamp) AS lead_month,
    TO_CHAR(lead_created_timestamp, 'YYYY-MM') AS year_month,
    call_status,
    -- Grouping based on Advertiser Business Logic
    CASE 
        WHEN call_status = 'Closed' THEN 'Closed (Won Customer)'
        WHEN call_status IN ('EP Sent', 'EP Received', 'EP Confirmed') THEN 'Good (In-Pipeline)'
        WHEN call_status IN ('Contacted - Doesn''t Qualify', 'Unable to contact - Bad Contact Information', 'Contacted - Invalid Profile') THEN 'Bad (Disqualified/Invalid)'
        ELSE 'Unknown / In-Progress'
    END AS lead_disposition_group,
    
    -- Binary Flags for Aggregation
    CASE WHEN call_status = 'Closed' THEN 1 ELSE 0 END AS is_closed,
    CASE WHEN call_status IN ('EP Sent', 'EP Received', 'EP Confirmed') THEN 1 ELSE 0 END AS is_pipeline_good,
    CASE WHEN call_status IN ('Closed', 'EP Sent', 'EP Received', 'EP Confirmed') THEN 1 ELSE 0 END AS is_good_total,
    CASE WHEN call_status IN ('Contacted - Doesn''t Qualify', 'Unable to contact - Bad Contact Information', 'Contacted - Invalid Profile') THEN 1 ELSE 0 END AS is_bad,
    CASE WHEN call_status IS NULL OR call_status NOT IN ('Closed', 'EP Sent', 'EP Received', 'EP Confirmed', 'Contacted - Doesn''t Qualify', 'Unable to contact - Bad Contact Information', 'Contacted - Invalid Profile') THEN 1 ELSE 0 END AS is_unknown,
    
    -- Traffic Source Classification (Disentangling Google Search vs Google AdSense Content)
    CASE 
        WHEN partner = 'google' THEN 'Google Search'
        WHEN partner = 'Google' THEN 'Google AdSense (Content/Display)'
        WHEN partner = 'yahoo' THEN 'Yahoo Search'
        WHEN partner = 'AdKnowledge' THEN 'AdKnowledge Network'
        WHEN partner = 'Call_Center' THEN 'Inbound Call Center'
        ELSE 'Other Channels'
    END AS traffic_channel,
    
    -- Creative Widget Parsing
    CASE 
        WHEN widget_name LIKE '%CreditSolutions%' THEN 'CreditSolutions'
        WHEN widget_name LIKE '%BlueMeter%' THEN 'BlueMeter'
        WHEN widget_name LIKE '%Head2%' THEN 'Head2'
        WHEN widget_name LIKE '%Head3%' THEN 'Head3'
        WHEN widget_name LIKE '%yellowarrow%' THEN 'YellowArrow'
        WHEN widget_name LIKE '%white%' THEN 'White'
        ELSE 'Standard/Default'
    END AS creative_theme,
    
    CASE 
        WHEN widget_name LIKE '%2DC%' THEN '2-Page (2DC)'
        ELSE '1-Page (1DC)'
    END AS form_paging,
    
    -- Debt Level Grouping
    CASE 
        WHEN debt_level = '7500-10000' THEN '1. Low ($7.5k - $10k)'
        WHEN debt_level IN ('7500-15000', '10001-15000') THEN '2. Mid ($10k - $15k)'
        WHEN debt_level IN ('15001-20000', '20001-30000', '30001-50000') THEN '3. Prime ($15k - $50k)'
        WHEN debt_level IN ('50001-70000', '70001-90000', '90000-100000') THEN '4. High ($50k - $100k)'
        WHEN debt_level = 'More_than_100000' THEN '5. Extreme (>$100k)'
        ELSE '6. Other'
    END AS debt_tier,
    
    -- Misfit / Low-Intent AdGroup Flag
    CASE WHEN adgroup IN ('Student Debt', 'Loan Default') THEN 1 ELSE 0 END AS is_misfit_adgroup,
    
    state,
    address_score,
    phone_score
FROM rzr_leads;

-- =============================================================================
-- QUESTION 1: LEAD QUALITY TRENDS OVER TIME & PIPELINE LAG
-- =============================================================================
SELECT
    year_month,
    COUNT(*) AS total_leads,
    SUM(is_closed) AS closed_leads,
    ROUND(AVG(is_closed) * 100.0, 2) AS closed_rate_pct,
    SUM(is_pipeline_good) AS pipeline_good_leads,
    ROUND(AVG(is_pipeline_good) * 100.0, 2) AS pipeline_good_rate_pct,
    SUM(is_good_total) AS total_good_leads,
    ROUND(AVG(is_good_total) * 100.0, 2) AS total_good_rate_pct,
    SUM(is_bad) AS bad_leads,
    ROUND(AVG(is_bad) * 100.0, 2) AS bad_rate_pct,
    SUM(is_unknown) AS unknown_leads,
    ROUND(AVG(is_unknown) * 100.0, 2) AS unknown_rate_pct
FROM v_rzr_leads_enriched
GROUP BY year_month
ORDER BY year_month;

-- =============================================================================
-- QUESTION 2: DRIVERS OF LEAD QUALITY (SEGMENTATION QUERIES)
-- =============================================================================

-- 2.1 Performance by Consumer Debt Tier
SELECT
    debt_tier,
    COUNT(*) AS lead_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS volume_share_pct,
    SUM(is_closed) AS closed_count,
    ROUND(AVG(is_closed) * 100.0, 2) AS closed_rate_pct,
    ROUND(AVG(is_good_total) * 100.0, 2) AS good_rate_pct,
    ROUND(AVG(is_bad) * 100.0, 2) AS bad_rate_pct
FROM v_rzr_leads_enriched
GROUP BY debt_tier
ORDER BY debt_tier;

-- 2.2 Performance by Traffic Channel (Search vs Display Content)
SELECT
    traffic_channel,
    COUNT(*) AS lead_count,
    SUM(is_closed) AS closed_count,
    ROUND(AVG(is_closed) * 100.0, 2) AS closed_rate_pct,
    ROUND(AVG(is_good_total) * 100.0, 2) AS good_rate_pct,
    ROUND(AVG(is_bad) * 100.0, 2) AS bad_rate_pct
FROM v_rzr_leads_enriched
GROUP BY traffic_channel
ORDER BY closed_rate_pct DESC;

-- 2.3 Top & Bottom Performing AdGroups (Volume >= 50 leads)
SELECT
    COALESCE(adgroup, 'Unknown/Direct') AS adgroup_name,
    COUNT(*) AS lead_count,
    SUM(is_closed) AS closed_count,
    ROUND(AVG(is_closed) * 100.0, 2) AS closed_rate_pct,
    ROUND(AVG(is_good_total) * 100.0, 2) AS good_rate_pct
FROM v_rzr_leads_enriched
GROUP BY adgroup
HAVING COUNT(*) >= 50
ORDER BY closed_rate_pct DESC;

-- 2.4 Performance by Creative Widget Theme & Format
SELECT
    creative_theme,
    form_paging,
    COUNT(*) AS lead_count,
    SUM(is_closed) AS closed_count,
    ROUND(AVG(is_closed) * 100.0, 2) AS closed_rate_pct,
    ROUND(AVG(is_good_total) * 100.0, 2) AS good_rate_pct,
    ROUND(AVG(is_bad) * 100.0, 2) AS bad_rate_pct
FROM v_rzr_leads_enriched
GROUP BY creative_theme, form_paging
ORDER BY closed_rate_pct DESC;

-- 2.5 Top Performing States (Volume >= 30 leads)
SELECT
    state,
    COUNT(*) AS lead_count,
    SUM(is_closed) AS closed_count,
    ROUND(AVG(is_closed) * 100.0, 2) AS closed_rate_pct,
    ROUND(AVG(is_good_total) * 100.0, 2) AS good_rate_pct
FROM v_rzr_leads_enriched
GROUP BY state
HAVING COUNT(*) >= 30
ORDER BY closed_rate_pct DESC;

-- =============================================================================
-- QUESTION 3: SCENARIO MODELING & CPL FINANCIAL OPTIMIZATION SIMULATION
-- =============================================================================
WITH baseline_kpis AS (
    SELECT 
        COUNT(*) AS base_leads,
        SUM(is_closed) AS base_closed,
        AVG(is_closed) AS base_closed_rate,
        30.0 AS base_cpl,
        COUNT(*) * 30.0 AS base_revenue
    FROM v_rzr_leads_enriched
),
scenario_aggregations AS (
    -- Baseline
    SELECT
        '0. Baseline (As-Is Portfolio)' AS scenario_name,
        COUNT(*) AS total_leads,
        SUM(is_closed) AS closed_leads,
        AVG(is_closed) AS closed_rate,
        30.0 AS negotiated_cpl,
        COUNT(*) * 30.0 AS total_revenue
    FROM v_rzr_leads_enriched
    
    UNION ALL
    
    -- Scenario 1: Eliminate Student Debt & Loan Default AdGroups
    SELECT
        '1. Eliminate Student Debt & Loan Default',
        COUNT(*),
        SUM(is_closed),
        AVG(is_closed),
        36.0,
        COUNT(*) * 36.0
    FROM v_rzr_leads_enriched
    WHERE is_misfit_adgroup = 0
    
    UNION ALL
    
    -- Scenario 2: Disqualify Low Debt (< $10,000)
    SELECT
        '2. Filter Low Debt (< $10k)',
        COUNT(*),
        SUM(is_closed),
        AVG(is_closed),
        36.0,
        COUNT(*) * 36.0
    FROM v_rzr_leads_enriched
    WHERE debt_tier != '1. Low ($7.5k - $10k)'
    
    UNION ALL
    
    -- Scenario 3: Cut Misfit AdGroups + Low Debt (< $10k)
    SELECT
        '3. Cut Misfit Keywords + Low Debt (< $10k)',
        COUNT(*),
        SUM(is_closed),
        AVG(is_closed),
        36.0,
        COUNT(*) * 36.0
    FROM v_rzr_leads_enriched
    WHERE is_misfit_adgroup = 0 
      AND debt_tier != '1. Low ($7.5k - $10k)'
      
    UNION ALL
    
    -- Scenario 4: Eliminate Google AdSense Display Content
    SELECT
        '4. Cut Google AdSense Content Network',
        COUNT(*),
        SUM(is_closed),
        AVG(is_closed),
        36.0,
        COUNT(*) * 36.0
    FROM v_rzr_leads_enriched
    WHERE traffic_channel != 'Google AdSense (Content/Display)'
    
    UNION ALL
    
    -- Scenario 5: Multi-Lever Optimization (Cut Keywords + Low Debt + Extreme Debt >$100k)
    SELECT
        '5. Strategic Multi-Lever Filtering',
        COUNT(*),
        SUM(is_closed),
        AVG(is_closed),
        36.0,
        COUNT(*) * 36.0
    FROM v_rzr_leads_enriched
    WHERE is_misfit_adgroup = 0 
      AND debt_tier NOT IN ('1. Low ($7.5k - $10k)', '5. Extreme (>$100k)')
)
SELECT
    s.scenario_name,
    s.total_leads,
    ROUND(s.total_leads * 100.0 / b.base_leads, 1) AS volume_retained_pct,
    s.closed_leads,
    ROUND(s.closed_leads * 100.0 / b.base_closed, 1) AS closed_retained_pct,
    ROUND(s.closed_rate * 100.0, 2) AS lead_quality_rate_pct,
    CASE WHEN s.closed_rate >= 0.0960 THEN 'MET (>= 9.60%)' ELSE 'MISSED (< 9.60%)' END AS quality_target_status,
    s.negotiated_cpl,
    s.total_revenue,
    ROUND(s.total_revenue - b.base_revenue, 2) AS revenue_net_impact,
    ROUND((s.total_revenue - b.base_revenue) * 100.0 / b.base_revenue, 2) AS revenue_growth_pct
FROM scenario_aggregations s
CROSS JOIN baseline_kpis b;
