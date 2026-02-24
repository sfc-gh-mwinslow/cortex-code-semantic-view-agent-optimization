-- ============================================================================
-- TRADE PAYMENT SETTLEMENT ANOMALY DETECTION DEMO
-- Single Setup Script
-- ============================================================================
-- This script creates all objects needed for the anomaly detection demo:
--   1. Database and Schema
--   2. COUNTERPARTIES reference table
--   3. TRADE_SETTLEMENTS fact table with sample data
--   4. SETTLEMENT_ANOMALIES dynamic table (auto-detection)
--   5. SETTLEMENT_ANALYSIS semantic view
--   6. SETTLEMENT_ANALYST Cortex Agent
--
-- Prerequisites:
--   - Role with CREATE DATABASE, CREATE AGENT privileges
--   - A warehouse (script uses DEFAULT_WH, modify if needed)
--
-- Usage:
--   Run this entire script in Snowsight or via SnowSQL
-- ============================================================================

-- Configuration (modify these if needed)
SET WAREHOUSE_NAME = 'COMPUTE_WH';

-- ============================================================================
-- STEP 1: Create Database and Schema
-- ============================================================================
CREATE DATABASE IF NOT EXISTS DB_SETTLEMENT;
CREATE SCHEMA IF NOT EXISTS DB_SETTLEMENT.CURATED;

USE DATABASE DB_SETTLEMENT;
USE SCHEMA CURATED;

-- ============================================================================
-- STEP 2: Create COUNTERPARTIES Reference Table
-- ============================================================================
CREATE OR REPLACE TABLE DB_SETTLEMENT.CURATED.COUNTERPARTIES AS
WITH counterparty_data AS (
    SELECT * FROM VALUES
        ('CP001', 'Goldman Sachs', 'BANK', 'LOW'),
        ('CP002', 'Morgan Stanley', 'BANK', 'LOW'),
        ('CP003', 'JP Morgan Chase', 'BANK', 'LOW'),
        ('CP004', 'Bank of America', 'BANK', 'LOW'),
        ('CP005', 'Citigroup', 'BANK', 'LOW'),
        ('CP006', 'Wells Fargo', 'BANK', 'LOW'),
        ('CP007', 'HSBC', 'BANK', 'LOW'),
        ('CP008', 'Barclays', 'BANK', 'LOW'),
        ('CP009', 'Deutsche Bank', 'BANK', 'MEDIUM'),
        ('CP010', 'Credit Suisse', 'BANK', 'MEDIUM'),
        ('CP011', 'UBS', 'BANK', 'LOW'),
        ('CP012', 'BNP Paribas', 'BANK', 'LOW'),
        ('CP013', 'Societe Generale', 'BANK', 'MEDIUM'),
        ('CP014', 'Royal Bank of Canada', 'BANK', 'LOW'),
        ('CP015', 'TD Securities', 'BANK', 'LOW'),
        ('CP016', 'Charles Schwab', 'BROKER', 'LOW'),
        ('CP017', 'Interactive Brokers', 'BROKER', 'LOW'),
        ('CP018', 'Fidelity Investments', 'BROKER', 'LOW'),
        ('CP019', 'E*TRADE', 'BROKER', 'MEDIUM'),
        ('CP020', 'Robinhood', 'BROKER', 'HIGH'),
        ('CP021', 'Citadel Securities', 'BROKER', 'LOW'),
        ('CP022', 'Virtu Financial', 'BROKER', 'MEDIUM'),
        ('CP023', 'Jane Street', 'BROKER', 'LOW'),
        ('CP024', 'Two Sigma', 'BROKER', 'LOW'),
        ('CP025', 'Susquehanna', 'BROKER', 'MEDIUM'),
        ('CP026', 'State Street', 'CUSTODIAN', 'LOW'),
        ('CP027', 'BNY Mellon', 'CUSTODIAN', 'LOW'),
        ('CP028', 'Northern Trust', 'CUSTODIAN', 'LOW'),
        ('CP029', 'Computershare', 'CUSTODIAN', 'MEDIUM'),
        ('CP030', 'Broadridge', 'CUSTODIAN', 'LOW'),
        ('CP031', 'DTCC', 'CUSTODIAN', 'LOW'),
        ('CP032', 'Euroclear', 'CUSTODIAN', 'LOW'),
        ('CP033', 'Clearstream', 'CUSTODIAN', 'LOW'),
        ('CP034', 'SIX Group', 'CUSTODIAN', 'LOW'),
        ('CP035', 'ASX Settlement', 'CUSTODIAN', 'LOW'),
        ('CP036', 'Nomura', 'BANK', 'MEDIUM'),
        ('CP037', 'Mizuho', 'BANK', 'LOW'),
        ('CP038', 'Sumitomo Mitsui', 'BANK', 'LOW'),
        ('CP039', 'Standard Chartered', 'BANK', 'MEDIUM'),
        ('CP040', 'ING Bank', 'BANK', 'LOW'),
        ('CP041', 'Rabobank', 'BANK', 'LOW'),
        ('CP042', 'Santander', 'BANK', 'MEDIUM'),
        ('CP043', 'BBVA', 'BANK', 'MEDIUM'),
        ('CP044', 'Intesa Sanpaolo', 'BANK', 'MEDIUM'),
        ('CP045', 'UniCredit', 'BANK', 'MEDIUM'),
        ('CP046', 'Jefferies', 'BROKER', 'LOW'),
        ('CP047', 'Cowen', 'BROKER', 'MEDIUM'),
        ('CP048', 'Piper Sandler', 'BROKER', 'LOW'),
        ('CP049', 'Raymond James', 'BROKER', 'LOW'),
        ('CP050', 'Stifel', 'BROKER', 'LOW')
    AS t(counterparty_id, counterparty_name, counterparty_type, risk_rating)
)
SELECT 
    counterparty_id::VARCHAR AS COUNTERPARTY_ID,
    counterparty_name::VARCHAR AS COUNTERPARTY_NAME,
    counterparty_type::VARCHAR AS COUNTERPARTY_TYPE,
    risk_rating::VARCHAR AS RISK_RATING
FROM counterparty_data;

-- ============================================================================
-- STEP 3: Create TRADE_SETTLEMENTS Table with Sample Data
-- ============================================================================
-- Generates ~10,000 settlements with injected anomalies:
--   - ~50 duplicate payment patterns
--   - ~200 unusual amount anomalies
-- ============================================================================
CREATE OR REPLACE TABLE DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS AS
WITH 
-- Generate base settlement data
base_settlements AS (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS row_num,
        'STL-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 8, '0') AS settlement_id,
        'TRD-' || LPAD(UNIFORM(1, 999999, RANDOM())::VARCHAR, 8, '0') AS trade_id,
        'CP' || LPAD(UNIFORM(1, 50, RANDOM())::VARCHAR, 3, '0') AS counterparty_id,
        CASE UNIFORM(1, 4, RANDOM())
            WHEN 1 THEN 'EQUITY'
            WHEN 2 THEN 'BOND'
            WHEN 3 THEN 'FX'
            ELSE 'DERIVATIVE'
        END AS instrument_type,
        DATEADD('day', -UNIFORM(1, 180, RANDOM()), CURRENT_DATE()) AS trade_date,
        CASE UNIFORM(1, 4, RANDOM())
            WHEN 1 THEN 'USD'
            WHEN 2 THEN 'EUR'
            WHEN 3 THEN 'GBP'
            ELSE 'JPY'
        END AS currency,
        CASE 
            WHEN UNIFORM(1, 4, RANDOM()) = 1 THEN ROUND(UNIFORM(10000, 500000, RANDOM())::FLOAT + UNIFORM(0, 99, RANDOM())/100, 2)
            WHEN UNIFORM(1, 4, RANDOM()) = 2 THEN ROUND(UNIFORM(100000, 5000000, RANDOM())::FLOAT + UNIFORM(0, 99, RANDOM())/100, 2)
            WHEN UNIFORM(1, 4, RANDOM()) = 3 THEN ROUND(UNIFORM(50000, 2000000, RANDOM())::FLOAT + UNIFORM(0, 99, RANDOM())/100, 2)
            ELSE ROUND(UNIFORM(25000, 1000000, RANDOM())::FLOAT + UNIFORM(0, 99, RANDOM())/100, 2)
        END AS expected_amount,
        'REF-' || UNIFORM(100000, 999999, RANDOM())::VARCHAR AS payment_reference,
        UNIFORM(1, 100, RANDOM()) AS anomaly_flag
    FROM TABLE(GENERATOR(ROWCOUNT => 10000))
),

-- Add settlement dates and status
settlements_with_dates AS (
    SELECT 
        settlement_id,
        trade_id,
        counterparty_id,
        instrument_type,
        trade_date,
        CASE 
            WHEN instrument_type = 'FX' THEN DATEADD('day', 1, trade_date)
            ELSE DATEADD('day', 2, trade_date)
        END AS expected_settlement_date,
        currency,
        expected_amount,
        -- Inject amount anomalies for ~2% of records
        CASE 
            WHEN anomaly_flag <= 1 THEN ROUND(expected_amount * UNIFORM(1.5, 3.0, RANDOM())::FLOAT, 2)
            WHEN anomaly_flag = 2 THEN ROUND(expected_amount * UNIFORM(0.3, 0.7, RANDOM())::FLOAT, 2)
            ELSE ROUND(expected_amount * UNIFORM(0.99, 1.01, RANDOM())::FLOAT, 2)
        END AS actual_amount,
        payment_reference,
        CASE 
            WHEN anomaly_flag <= 3 THEN 'FAILED'
            WHEN anomaly_flag <= 8 THEN 'PENDING'
            ELSE 'SETTLED'
        END AS settlement_status,
        anomaly_flag,
        row_num
    FROM base_settlements
),

-- Add actual settlement dates
settlements_complete AS (
    SELECT 
        settlement_id,
        trade_id,
        counterparty_id,
        instrument_type,
        trade_date,
        expected_settlement_date,
        CASE 
            WHEN settlement_status = 'PENDING' THEN NULL
            WHEN settlement_status = 'FAILED' THEN NULL
            ELSE DATEADD('day', UNIFORM(0, 2, RANDOM()), expected_settlement_date)
        END AS actual_settlement_date,
        currency,
        expected_amount,
        actual_amount,
        payment_reference,
        settlement_status,
        anomaly_flag,
        row_num
    FROM settlements_with_dates
),

-- Create duplicate records (~50 duplicates)
duplicate_settlements AS (
    SELECT 
        'STL-DUP-' || LPAD(ROW_NUMBER() OVER (ORDER BY settlement_id)::VARCHAR, 5, '0') AS settlement_id,
        trade_id,
        counterparty_id,
        instrument_type,
        trade_date,
        expected_settlement_date,
        DATEADD('day', UNIFORM(1, 5, RANDOM()), actual_settlement_date) AS actual_settlement_date,
        currency,
        expected_amount,
        ROUND(actual_amount * UNIFORM(0.99, 1.01, RANDOM())::FLOAT, 2) AS actual_amount,
        payment_reference,
        'SETTLED' AS settlement_status
    FROM settlements_complete
    WHERE row_num <= 50 AND settlement_status = 'SETTLED'
)

-- Combine original and duplicate records
SELECT 
    settlement_id,
    trade_id,
    counterparty_id,
    instrument_type,
    trade_date,
    expected_settlement_date,
    actual_settlement_date,
    currency,
    expected_amount,
    actual_amount,
    payment_reference,
    settlement_status
FROM settlements_complete

UNION ALL

SELECT * FROM duplicate_settlements;

-- ============================================================================
-- STEP 4: Create SETTLEMENT_ANOMALIES Dynamic Table
-- ============================================================================
-- Automatically detects two types of anomalies:
--   1. DUPLICATE_SUSPECTED: Same counterparty, payment ref, similar amount within 5 days
--   2. AMOUNT_ANOMALY: Deviation >5% from expected OR z-score >3
-- ============================================================================
CREATE OR REPLACE DYNAMIC TABLE DB_SETTLEMENT.CURATED.SETTLEMENT_ANOMALIES
    TARGET_LAG = '1 hour'
    WAREHOUSE = $WAREHOUSE_NAME
AS
WITH 
-- Calculate statistics per counterparty and instrument for z-score
counterparty_stats AS (
    SELECT 
        counterparty_id,
        instrument_type,
        AVG(actual_amount) AS avg_amount,
        STDDEV(actual_amount) AS stddev_amount
    FROM DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS
    WHERE settlement_status = 'SETTLED'
    GROUP BY counterparty_id, instrument_type
    HAVING COUNT(*) >= 5
),

-- Detect unusual amount anomalies
amount_anomalies AS (
    SELECT 
        t.settlement_id,
        'AMOUNT_ANOMALY' AS anomaly_type,
        CASE 
            WHEN ABS(t.actual_amount - t.expected_amount) / NULLIF(t.expected_amount, 0) > 0.25 THEN 'HIGH'
            WHEN ABS(t.actual_amount - t.expected_amount) / NULLIF(t.expected_amount, 0) > 0.1 THEN 'MEDIUM'
            ELSE 'LOW'
        END AS severity,
        OBJECT_CONSTRUCT(
            'expected_amount', t.expected_amount,
            'actual_amount', t.actual_amount,
            'deviation_pct', ROUND((t.actual_amount - t.expected_amount) / NULLIF(t.expected_amount, 0) * 100, 2),
            'z_score', CASE 
                WHEN s.stddev_amount > 0 THEN ROUND((t.actual_amount - s.avg_amount) / s.stddev_amount, 2)
                ELSE NULL 
            END,
            'counterparty_id', t.counterparty_id,
            'instrument_type', t.instrument_type
        ) AS details
    FROM DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS t
    LEFT JOIN counterparty_stats s 
        ON t.counterparty_id = s.counterparty_id 
        AND t.instrument_type = s.instrument_type
    WHERE 
        ABS(t.actual_amount - t.expected_amount) / NULLIF(t.expected_amount, 0) > 0.05
        OR (s.stddev_amount > 0 AND ABS(t.actual_amount - s.avg_amount) / s.stddev_amount > 3)
),

-- Detect duplicate payment patterns
duplicate_anomalies AS (
    SELECT 
        t1.settlement_id,
        'DUPLICATE_SUSPECTED' AS anomaly_type,
        CASE 
            WHEN COUNT(*) > 2 THEN 'HIGH'
            ELSE 'MEDIUM'
        END AS severity,
        OBJECT_CONSTRUCT(
            'original_settlement_ids', ARRAY_AGG(DISTINCT t2.settlement_id),
            'payment_reference', t1.payment_reference,
            'counterparty_id', t1.counterparty_id,
            'amount_variance_pct', ROUND(STDDEV(t2.actual_amount) / NULLIF(AVG(t2.actual_amount), 0) * 100, 2),
            'date_span_days', DATEDIFF('day', MIN(t2.actual_settlement_date), MAX(t2.actual_settlement_date))
        ) AS details
    FROM DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS t1
    JOIN DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS t2
        ON t1.counterparty_id = t2.counterparty_id
        AND t1.payment_reference = t2.payment_reference
        AND t1.settlement_id != t2.settlement_id
        AND ABS(t1.actual_amount - t2.actual_amount) / NULLIF(t1.actual_amount, 0) < 0.02
        AND ABS(DATEDIFF('day', t1.actual_settlement_date, t2.actual_settlement_date)) <= 5
    WHERE t1.settlement_status = 'SETTLED'
    GROUP BY t1.settlement_id, t1.payment_reference, t1.counterparty_id
)

-- Combine all anomalies
SELECT 
    MD5(settlement_id || '-' || anomaly_type) AS anomaly_id,
    settlement_id,
    anomaly_type,
    severity,
    details
FROM amount_anomalies

UNION ALL

SELECT 
    MD5(settlement_id || '-' || anomaly_type) AS anomaly_id,
    settlement_id,
    anomaly_type,
    severity,
    details
FROM duplicate_anomalies;

-- ============================================================================
-- STEP 5: Create SETTLEMENT_ANALYSIS Semantic View
-- ============================================================================
CREATE OR REPLACE SEMANTIC VIEW DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYSIS
TABLES (
    settlements AS DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS
        PRIMARY KEY (SETTLEMENT_ID)
        WITH SYNONYMS = ('trades', 'payments', 'transactions', 'settlement data')
        COMMENT = 'Trade payment settlements with expected and actual amounts. Contains ~10K records across counterparties like Goldman Sachs, Morgan Stanley, JP Morgan, etc.',
    
    counterparties AS DB_SETTLEMENT.CURATED.COUNTERPARTIES
        PRIMARY KEY (COUNTERPARTY_ID)
        WITH SYNONYMS = ('firms', 'banks', 'brokers', 'custodians', 'trading partners')
        COMMENT = 'Counterparty reference data including banks, brokers, and custodians',
    
    anomalies AS DB_SETTLEMENT.CURATED.SETTLEMENT_ANOMALIES
        PRIMARY KEY (ANOMALY_ID)
        WITH SYNONYMS = ('issues', 'problems', 'alerts', 'exceptions', 'flags')
        COMMENT = 'Detected anomalies including duplicate payments and unusual amounts'
)
RELATIONSHIPS (
    settlement_to_counterparty AS settlements (COUNTERPARTY_ID) REFERENCES counterparties,
    anomaly_to_settlement AS anomalies (SETTLEMENT_ID) REFERENCES settlements
)
FACTS (
    settlements.expected_amount AS EXPECTED_AMOUNT 
        WITH SYNONYMS = ('expected payment', 'anticipated amount', 'planned amount'),
    settlements.actual_amount AS ACTUAL_AMOUNT 
        WITH SYNONYMS = ('actual payment', 'paid amount', 'received amount'),
    settlements.amount_variance AS (ACTUAL_AMOUNT - EXPECTED_AMOUNT)
        WITH SYNONYMS = ('difference', 'variance', 'discrepancy'),
    settlements.variance_pct AS ((ACTUAL_AMOUNT - EXPECTED_AMOUNT) / NULLIF(EXPECTED_AMOUNT, 0) * 100)
        WITH SYNONYMS = ('percentage difference', 'variance percentage')
)
DIMENSIONS (
    settlements.settlement_id AS SETTLEMENT_ID 
        WITH SYNONYMS = ('settlement reference', 'stl id'),
    settlements.trade_id AS TRADE_ID 
        WITH SYNONYMS = ('trade reference', 'trd id'),
    settlements.counterparty_id AS COUNTERPARTY_ID,
    settlements.instrument_type AS INSTRUMENT_TYPE 
        WITH SYNONYMS = ('asset type', 'product type', 'instrument'),
    settlements.trade_date AS TRADE_DATE 
        WITH SYNONYMS = ('execution date', 'traded on'),
    settlements.expected_settlement_date AS EXPECTED_SETTLEMENT_DATE 
        WITH SYNONYMS = ('due date', 'target date'),
    settlements.actual_settlement_date AS ACTUAL_SETTLEMENT_DATE 
        WITH SYNONYMS = ('settled on', 'payment date'),
    settlements.currency AS CURRENCY 
        WITH SYNONYMS = ('ccy', 'denomination'),
    settlements.payment_reference AS PAYMENT_REFERENCE 
        WITH SYNONYMS = ('wire reference', 'payment ref'),
    settlements.settlement_status AS SETTLEMENT_STATUS 
        WITH SYNONYMS = ('status', 'state'),
    counterparties.counterparty_name AS COUNTERPARTY_NAME 
        WITH SYNONYMS = ('firm name', 'company name', 'bank name'),
    counterparties.counterparty_type AS COUNTERPARTY_TYPE 
        WITH SYNONYMS = ('firm type', 'entity type'),
    counterparties.risk_rating AS RISK_RATING 
        WITH SYNONYMS = ('risk level', 'risk score'),
    anomalies.anomaly_type AS ANOMALY_TYPE 
        WITH SYNONYMS = ('issue type', 'alert type', 'problem type'),
    anomalies.severity AS SEVERITY
        WITH SYNONYMS = ('priority', 'importance', 'anomaly severity'),
    anomalies.details AS DETAILS 
        WITH SYNONYMS = ('issue details', 'alert info', 'anomaly details')
)
METRICS (
    settlements.total_expected AS SUM(settlements.expected_amount)
        WITH SYNONYMS = ('total expected payments'),
    settlements.total_actual AS SUM(settlements.actual_amount)
        WITH SYNONYMS = ('total actual payments'),
    settlements.total_variance AS SUM(settlements.actual_amount - settlements.expected_amount)
        WITH SYNONYMS = ('total discrepancy'),
    settlements.avg_settlement_amount AS AVG(settlements.actual_amount)
        WITH SYNONYMS = ('average payment'),
    settlements.settlement_count AS COUNT(settlements.settlement_id)
        WITH SYNONYMS = ('number of settlements', 'trade count'),
    anomalies.anomaly_count AS COUNT(anomalies.anomaly_id)
        WITH SYNONYMS = ('number of issues', 'alert count', 'problem count'),
    anomalies.high_severity_count AS COUNT_IF(anomalies.severity = 'HIGH')
        WITH SYNONYMS = ('critical issues', 'high priority count')
)
AI_SQL_GENERATION 'When users ask about anomalies, join settlements to anomalies via SETTLEMENT_ID. For duplicate payment queries, filter anomaly_type = DUPLICATE_SUSPECTED. For unusual amounts, filter anomaly_type = AMOUNT_ANOMALY. Counterparty names like Goldman Sachs, Morgan Stanley, JP Morgan are in the counterparties table. Use COUNTERPARTY_NAME for user-friendly output.'
AI_QUESTION_CATEGORIZATION 'This semantic view handles questions about: trade payment settlements, anomaly detection (duplicates and unusual amounts), counterparty analysis, settlement status tracking, and payment variance analysis.';

-- ============================================================================
-- STEP 6: Create SETTLEMENT_ANALYST Cortex Agent
-- ============================================================================
CREATE OR REPLACE AGENT DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYST
  FROM SPECIFICATION
  $$
  models:
    orchestration: claude-3-5-sonnet

  instructions:
    response: |
      Provide clear, actionable insights about settlement anomalies. When showing anomaly data, always include the counterparty name, settlement amounts, and severity level. Format numbers appropriately and highlight high-severity issues.
    orchestration: |
      ## Your Capabilities
      - Query trade payment settlements and their status
      - Identify duplicate payment suspects based on matching payment references, counterparties, and amounts
      - Find unusual amount anomalies where actual payments deviate significantly from expected amounts
      - Analyze anomaly patterns by counterparty, instrument type, and time period
      - Calculate settlement metrics and exposure analysis
      
      ## Guidelines
      1. When users ask about anomalies, always specify the anomaly type (DUPLICATE_SUSPECTED or AMOUNT_ANOMALY)
      2. For duplicate payment queries, look for settlements with matching payment references within short time windows
      3. For unusual amounts, report both the absolute deviation and percentage deviation from expected
      4. Include counterparty names in results for better readability
      5. When showing anomaly details, parse the JSON DETAILS column to show relevant information
      6. For exposure calculations, sum the actual_amount of flagged settlements
      
      ## Response Format
      - Lead with a direct answer to the user's question
      - Include relevant context (counterparty, dates, severity)
      - Format currency values with appropriate precision
      - When listing anomalies, show settlement_id, counterparty_name, amount, and severity
      
  tools:
    - tool_spec:
        type: cortex_analyst_text_to_sql
        name: SettlementAnalyst

  tool_resources:
    SettlementAnalyst:
      semantic_view: DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYSIS
  $$;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Verify all objects were created
SELECT 'COUNTERPARTIES' AS object_name, COUNT(*) AS record_count FROM DB_SETTLEMENT.CURATED.COUNTERPARTIES
UNION ALL
SELECT 'TRADE_SETTLEMENTS', COUNT(*) FROM DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS
UNION ALL
SELECT 'SETTLEMENT_ANOMALIES', COUNT(*) FROM DB_SETTLEMENT.CURATED.SETTLEMENT_ANOMALIES;

-- Show anomaly breakdown
SELECT 
    anomaly_type, 
    severity, 
    COUNT(*) AS count 
FROM DB_SETTLEMENT.CURATED.SETTLEMENT_ANOMALIES 
GROUP BY anomaly_type, severity 
ORDER BY anomaly_type, severity;

-- Show top counterparties by anomaly count
SELECT 
    c.counterparty_name,
    COUNT(a.anomaly_id) AS anomaly_count
FROM DB_SETTLEMENT.CURATED.SETTLEMENT_ANOMALIES a
JOIN DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS s ON a.settlement_id = s.settlement_id
JOIN DB_SETTLEMENT.CURATED.COUNTERPARTIES c ON s.counterparty_id = c.counterparty_id
GROUP BY c.counterparty_name
ORDER BY anomaly_count DESC
LIMIT 10;

-- ============================================================================
-- DEMO READY!
-- ============================================================================
-- Test with Cortex Analyst:
--   cortex analyst query "Show me duplicate payments" --view=DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYSIS
--   cortex analyst query "Which counterparties have the most anomalies?" --view=DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYSIS
--   cortex analyst query "What is the total exposure from high severity anomalies?" --view=DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYSIS
-- ============================================================================
