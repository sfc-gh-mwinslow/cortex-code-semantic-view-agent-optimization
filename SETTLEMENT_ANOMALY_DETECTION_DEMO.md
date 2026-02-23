# Trade Payment Settlement Anomaly Detection Demo

This demo showcases Snowflake's capabilities for detecting anomalies in trade payment settlements using Dynamic Tables, Semantic Views, and Cortex Agents.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DB_SETTLEMENT.CURATED                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐     ┌─────────────────────┐                           │
│  │  COUNTERPARTIES │     │  TRADE_SETTLEMENTS  │                           │
│  │    (Table)      │     │      (Table)        │                           │
│  │                 │     │                     │                           │
│  │  50 firms:      │     │  10,047 records:    │                           │
│  │  - Banks        │◄────│  - Settlement data  │                           │
│  │  - Brokers      │     │  - Expected amounts │                           │
│  │  - Custodians   │     │  - Actual amounts   │                           │
│  └─────────────────┘     └──────────┬──────────┘                           │
│                                     │                                       │
│                                     ▼                                       │
│                    ┌────────────────────────────────┐                      │
│                    │    SETTLEMENT_ANOMALIES        │                      │
│                    │      (Dynamic Table)           │                      │
│                    │                                │                      │
│                    │  Auto-detects:                 │                      │
│                    │  - Duplicate payments (94)     │                      │
│                    │  - Unusual amounts (452)       │                      │
│                    │                                │                      │
│                    │  Refreshes every 1 hour        │                      │
│                    └────────────────┬───────────────┘                      │
│                                     │                                       │
│                                     ▼                                       │
│                    ┌────────────────────────────────┐                      │
│                    │     SETTLEMENT_ANALYSIS        │                      │
│                    │      (Semantic View)           │                      │
│                    │                                │                      │
│                    │  Enables natural language      │                      │
│                    │  queries across all tables     │                      │
│                    └────────────────┬───────────────┘                      │
│                                     │                                       │
│                                     ▼                                       │
│                    ┌────────────────────────────────┐                      │
│                    │     SETTLEMENT_ANALYST         │                      │
│                    │      (Cortex Agent)            │                      │
│                    │                                │                      │
│                    │  AI assistant for anomaly      │                      │
│                    │  investigation & analysis      │                      │
│                    └────────────────────────────────┘                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Objects Created

### 1. Database & Schema

```sql
CREATE DATABASE DB_SETTLEMENT;
CREATE SCHEMA DB_SETTLEMENT.CURATED;
```

### 2. COUNTERPARTIES Table

Reference data for 50 trading counterparties.

| Column | Type | Description |
|--------|------|-------------|
| COUNTERPARTY_ID | VARCHAR | Unique ID (CP001-CP050) |
| COUNTERPARTY_NAME | VARCHAR | Company name |
| COUNTERPARTY_TYPE | VARCHAR | BANK, BROKER, CUSTODIAN |
| RISK_RATING | VARCHAR | LOW, MEDIUM, HIGH |

**Sample counterparties:** Goldman Sachs, Morgan Stanley, JP Morgan Chase, Citadel Securities, State Street, etc.

### 3. TRADE_SETTLEMENTS Table

Main fact table with ~10,000 trade settlement records.

| Column | Type | Description |
|--------|------|-------------|
| SETTLEMENT_ID | VARCHAR | Unique settlement ID |
| TRADE_ID | VARCHAR | Trade reference |
| COUNTERPARTY_ID | VARCHAR | FK to counterparties |
| INSTRUMENT_TYPE | VARCHAR | EQUITY, BOND, FX, DERIVATIVE |
| TRADE_DATE | DATE | Execution date |
| EXPECTED_SETTLEMENT_DATE | DATE | T+1 or T+2 |
| ACTUAL_SETTLEMENT_DATE | DATE | Actual settlement |
| CURRENCY | VARCHAR | USD, EUR, GBP, JPY |
| EXPECTED_AMOUNT | NUMBER | Expected payment |
| ACTUAL_AMOUNT | NUMBER | Actual payment |
| PAYMENT_REFERENCE | VARCHAR | Wire reference |
| SETTLEMENT_STATUS | VARCHAR | SETTLED, PENDING, FAILED |

**Data characteristics:**
- Date range: Last 6 months
- ~47 injected duplicate payment patterns
- ~200 injected unusual amount anomalies

### 4. SETTLEMENT_ANOMALIES Dynamic Table

Automatically detects anomalies with hourly refresh.

| Column | Type | Description |
|--------|------|-------------|
| ANOMALY_ID | VARCHAR | MD5 hash ID |
| SETTLEMENT_ID | VARCHAR | Reference to settlement |
| ANOMALY_TYPE | VARCHAR | DUPLICATE_SUSPECTED, AMOUNT_ANOMALY |
| SEVERITY | VARCHAR | HIGH, MEDIUM, LOW |
| DETAILS | VARIANT | JSON with anomaly specifics |

**Detection Logic:**

**Duplicate Payments:**
- Same counterparty
- Same payment reference
- Amount within 2% variance
- Within 5-day window

**Unusual Amounts:**
- Deviation > 5% from expected amount
- OR z-score > 3 standard deviations from counterparty average
- Severity based on deviation: >25% = HIGH, >10% = MEDIUM, else LOW

### 5. SETTLEMENT_ANALYSIS Semantic View

Enables natural language queries with:
- **3 tables** joined with relationships
- **Synonyms** for natural language understanding
- **Calculated facts** (amount_variance, variance_pct)
- **Pre-defined metrics** (total_expected, anomaly_count, etc.)
- **AI instructions** for SQL generation

### 6. SETTLEMENT_ANALYST Cortex Agent

AI assistant configured with:
- Orchestration instructions for settlement analysis
- Tool: `query_settlements` linked to semantic view
- Response formatting guidelines

---

## How It Works Together

### Data Flow

1. **Source Data** → `TRADE_SETTLEMENTS` and `COUNTERPARTIES` tables store raw settlement data

2. **Anomaly Detection** → `SETTLEMENT_ANOMALIES` dynamic table continuously scans for:
   - Duplicate payment patterns (matching references, amounts, counterparties)
   - Unusual amount deviations (statistical outliers)

3. **Semantic Layer** → `SETTLEMENT_ANALYSIS` semantic view:
   - Joins all three tables
   - Defines business-friendly names and synonyms
   - Enables natural language querying

4. **AI Interface** → `SETTLEMENT_ANALYST` Cortex Agent:
   - Interprets user questions
   - Generates SQL via Cortex Analyst
   - Returns formatted insights

### Anomaly Detection Statistics

| Anomaly Type | Severity | Count |
|--------------|----------|-------|
| AMOUNT_ANOMALY | HIGH | 202 |
| AMOUNT_ANOMALY | LOW | 250 |
| DUPLICATE_SUSPECTED | MEDIUM | 94 |
| **Total** | | **546** |

**Total Exposure (High Severity):** $216.6M

---

## Demo Flow

### Setup (if starting fresh)

```bash
# Start Cortex Code
cortex

# Verify connection
show me my current role and database
```

### Demo Script

#### Part 1: Show the Data Foundation

```sql
-- View settlement data sample
SELECT * FROM DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS LIMIT 5;

-- View counterparties
SELECT * FROM DB_SETTLEMENT.CURATED.COUNTERPARTIES LIMIT 10;

-- Show anomaly detection is automatic
SELECT anomaly_type, severity, COUNT(*) 
FROM DB_SETTLEMENT.CURATED.SETTLEMENT_ANOMALIES 
GROUP BY anomaly_type, severity;
```

#### Part 2: Natural Language Queries with Cortex Analyst

```bash
# Query 1: Duplicate payments
cortex analyst query "Show me suspected duplicate payments" --view=DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYSIS

# Query 2: Counterparty analysis
cortex analyst query "Which counterparties have the most anomalies?" --view=DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYSIS

# Query 3: Exposure analysis
cortex analyst query "What is the total dollar exposure from high severity anomalies?" --view=DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYSIS

# Query 4: Specific counterparty
cortex analyst query "Find all anomalies for Goldman Sachs" --view=DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYSIS

# Query 5: Time-based analysis
cortex analyst query "Show me anomalies from the last 7 days by type" --view=DB_SETTLEMENT.CURATED.SETTLEMENT_ANALYSIS
```

#### Part 3: Explore Anomaly Details

```sql
-- View duplicate payment details
SELECT 
    a.settlement_id,
    c.counterparty_name,
    s.actual_amount,
    a.severity,
    a.details:payment_reference::VARCHAR AS payment_ref,
    a.details:date_span_days::INT AS days_apart
FROM DB_SETTLEMENT.CURATED.SETTLEMENT_ANOMALIES a
JOIN DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS s ON a.settlement_id = s.settlement_id
JOIN DB_SETTLEMENT.CURATED.COUNTERPARTIES c ON s.counterparty_id = c.counterparty_id
WHERE a.anomaly_type = 'DUPLICATE_SUSPECTED'
LIMIT 10;

-- View unusual amount details
SELECT 
    a.settlement_id,
    c.counterparty_name,
    a.details:expected_amount::NUMBER(18,2) AS expected,
    a.details:actual_amount::NUMBER(18,2) AS actual,
    a.details:deviation_pct::NUMBER(10,2) AS deviation_pct,
    a.severity
FROM DB_SETTLEMENT.CURATED.SETTLEMENT_ANOMALIES a
JOIN DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS s ON a.settlement_id = s.settlement_id
JOIN DB_SETTLEMENT.CURATED.COUNTERPARTIES c ON s.counterparty_id = c.counterparty_id
WHERE a.anomaly_type = 'AMOUNT_ANOMALY' AND a.severity = 'HIGH'
ORDER BY a.details:deviation_pct DESC
LIMIT 10;
```

#### Part 4: Business Insights

```sql
-- Anomalies by counterparty type
SELECT 
    c.counterparty_type,
    a.anomaly_type,
    COUNT(*) as anomaly_count,
    SUM(s.actual_amount) as total_exposure
FROM DB_SETTLEMENT.CURATED.SETTLEMENT_ANOMALIES a
JOIN DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS s ON a.settlement_id = s.settlement_id
JOIN DB_SETTLEMENT.CURATED.COUNTERPARTIES c ON s.counterparty_id = c.counterparty_id
GROUP BY c.counterparty_type, a.anomaly_type
ORDER BY total_exposure DESC;

-- High-risk counterparties with anomalies
SELECT 
    c.counterparty_name,
    c.risk_rating,
    COUNT(*) as anomaly_count
FROM DB_SETTLEMENT.CURATED.SETTLEMENT_ANOMALIES a
JOIN DB_SETTLEMENT.CURATED.TRADE_SETTLEMENTS s ON a.settlement_id = s.settlement_id
JOIN DB_SETTLEMENT.CURATED.COUNTERPARTIES c ON s.counterparty_id = c.counterparty_id
WHERE c.risk_rating IN ('MEDIUM', 'HIGH')
GROUP BY c.counterparty_name, c.risk_rating
ORDER BY anomaly_count DESC
LIMIT 10;
```

---

## Sample Demo Questions

| Question | What It Shows |
|----------|---------------|
| "How many duplicate payments are there?" | Basic anomaly count |
| "Which counterparties have the most anomalies?" | Risk concentration analysis |
| "What is the total exposure from high severity anomalies?" | Financial impact |
| "Show me anomalies for Deutsche Bank" | Counterparty drill-down |
| "What's the average deviation percentage for amount anomalies?" | Statistical analysis |
| "List settlements with amount variance over 50%" | Threshold-based filtering |
| "How many anomalies by instrument type?" | Segmentation analysis |

---

## Key Takeaways

1. **Dynamic Tables** automatically detect anomalies without manual ETL jobs
2. **Semantic Views** enable business users to query data in natural language
3. **Cortex Agents** provide an AI-powered interface for investigation
4. **Real-time Detection** - anomalies are flagged within the target lag window (1 hour)
5. **Scalable** - same pattern works for millions of settlements

---

## Cleanup

```sql
-- Remove all demo objects
DROP DATABASE IF EXISTS DB_SETTLEMENT CASCADE;
```

```bash
# Remove agent workspace
rm -rf DB_SETTLEMENT_CURATED_SETTLEMENT_ANALYST/
```

---

*Built with Cortex Code - Trade Payment Settlement Anomaly Detection Demo*
