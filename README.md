# DailyBasket Data Warehouse (DWBI Final Project)

**Team:** Hamza Abbas (L24-2500) and Sadeem Arshad (L24-2502)

DailyBasket is a grocery retail chain. It sells through stores, a website and a mobile app.
This project builds a data warehouse (star schema) in PostgreSQL that answers 12 business questions
about sales, customers, stock and promotions.

| Phase | Work | Status |
|---|---|---|
| Phase 1 | Business analysis and dimensional design | Done |
| Phase 2 | PostgreSQL warehouse, ETL, data quality | Done |
| Phase 3 | OLAP queries and Power BI dashboard | Next |

## Folder structure

```
DWBI-Final-Project
|-- 01_Project_Documentation   Phase 1 PDFs, star schema diagram, data dictionary (Excel)
|-- 02_Data
|   |-- generate_data.py       makes the fake source data (dirty on purpose)
|   |-- raw_data/              9 source CSV files
|   `-- cleaned_data/          the same data after cleaning
|-- 03_ETL                     SQL scripts + run_etl.py + the 2 Phase 2 reports
|   `-- reports/               Data_Cleaning_Report.pdf, Data_Quality_Report.pdf, run log
|-- 04_Data_Warehouse          star schema (6 dimensions, 3 fact tables)
|-- 05_Analytics               reporting views + data quality checks (OLAP comes in Phase 3)
|-- 06_Dashboard               Power BI file (Phase 3)
`-- README.md
```

## Phase 2 deliverables and where to find them

| Deliverable | File |
|---|---|
| PostgreSQL database SQL script | `03_ETL/00_create_database_and_schemas.sql` |
| Staging schema SQL | `03_ETL/01_staging_schema.sql` |
| DW schema SQL | `04_Data_Warehouse/04_dw_schema.sql` |
| ETL scripts (SQL and Python) | `03_ETL/02_load_staging.sql`, `03_ETL/03_staging_cleaning.sql`, `03_ETL/run_etl.py`, `02_Data/generate_data.py` |
| Dimension load script | `03_ETL/05_load_dimensions.sql` |
| Fact load script | `03_ETL/06_load_facts.sql` |
| Data cleaning report (PDF) | `03_ETL/reports/Data_Cleaning_Report.pdf` |
| Data quality report (PDF) | `03_ETL/reports/Data_Quality_Report.pdf` |
| Reporting views and quality checks | `05_Analytics/07_reporting_views.sql`, `05_Analytics/08_data_quality_checks.sql` |

## The architecture

```
Source CSV files  ->  project_staging  ->  project_dw  ->  project_reporting
 (02_Data/raw_data)   raw tables (stg_*)    6 dimensions    11 views + dq_results
                      clean tables          3 fact tables
                      (stg_*_clean)
```

- Dimensions load first. Facts load second.
- Facts store **surrogate keys**. The order file only has business keys, so the load joins to each dimension to get the surrogate key.
- Raw staging tables are never changed. Every removed row is saved with its reason in `project_staging.etl_rejected_rows`.
- Every load is safe to run again (`UNIQUE` constraints and `ON CONFLICT`). The warehouse does not grow on a re-run.

## Data size

| Table | Rows |
|---|---|
| dim_date | 1,096 |
| dim_customer | 600 |
| dim_product | 160 |
| dim_region | 40 |
| dim_promotion | 31 (30 promotions + "No Promotion") |
| dim_channel | 3 (the business has 3 channels) |
| fact_sales | 13,094 |
| fact_inventory_snapshot | 16,615 |
| fact_promotion_event | 3,844 |

## How to run it

You need PostgreSQL (with the `psql` command), and Python 3.

```bash
# 1. go to the repository root folder
cd DWBI-Final-Project

# 2. tell psql how to connect (change these to your own)
export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD=your_password

# 3. build everything (makes a new database called dailybasket_dw)
python3 03_ETL/run_etl.py

# 4. run it again to prove a re-run is safe
python3 03_ETL/run_etl.py --rerun
```

On Windows PowerShell use `$env:PGHOST="localhost"` style instead of `export`.

To run the steps by hand, run these files in this order with `psql -d dailybasket_dw -f <file>`
(the first one connects to the `postgres` database):

`00` -> `01` -> `02` -> `03` -> `04` -> `05` -> `06` -> `07` -> `08` (and `09` to export cleaned CSVs).

To rebuild the two PDF reports: `pip install reportlab matplotlib "psycopg[binary]"` then `python3 03_ETL/build_reports.py`.

## Data quality result

72 automatic checks (completeness, accuracy, integrity). All pass. Details are in
`03_ETL/reports/Data_Quality_Report.pdf`.
