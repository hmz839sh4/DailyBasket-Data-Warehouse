"""
Runs the whole DailyBasket ETL pipeline: CSV files -> staging -> warehouse -> reporting views -> quality checks.

How to run (from anywhere; the script finds the repository root by itself):
    python3 03_ETL/run_etl.py              # full build: makes a NEW database, then loads it
    python3 03_ETL/run_etl.py --rerun      # load again into the same database (tests safe re-runs)
    python3 03_ETL/run_etl.py --generate   # also make new fake data first

Needs PostgreSQL and psql. Set PGHOST, PGPORT, PGUSER, PGPASSWORD if needed.
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
DB = os.environ.get("DW_DATABASE", "dailybasket_dw")

STEPS = [
    ("03_ETL/00_create_database_and_schemas.sql", "postgres", "Create database and 3 schemas"),
    ("03_ETL/01_staging_schema.sql",              DB,         "Create staging tables"),
    ("03_ETL/02_load_staging.sql",                DB,         "Load CSV files into raw staging"),
    ("03_ETL/03_staging_cleaning.sql",            DB,         "Clean staging data (duplicates, NULLs, text, types)"),
    ("04_Data_Warehouse/04_dw_schema.sql",        DB,         "Create warehouse tables (star schema)"),
    ("03_ETL/05_load_dimensions.sql",             DB,         "Load dimensions (surrogate keys)"),
    ("03_ETL/06_load_facts.sql",                  DB,         "Load facts (business key -> surrogate key)"),
    ("05_Analytics/07_reporting_views.sql",       DB,         "Create reporting views"),
    ("05_Analytics/08_data_quality_checks.sql",   DB,         "Run data quality checks"),
    ("03_ETL/09_export_cleaned_data.sql",         DB,         "Save cleaned data as CSV files"),
]

def run_sql(path, database):
    cmd = ["psql", "-v", "ON_ERROR_STOP=1", "-q", "-d", database, "-f", path]
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr)
        sys.exit("STOP: %s failed" % path)
    return result.stdout

def main():
    rerun = "--rerun" in sys.argv
    if "--generate" in sys.argv:
        subprocess.run([sys.executable, os.path.join(ROOT, "02_Data", "generate_data.py")], check=True)

    steps = STEPS[1:] if rerun else STEPS
    if rerun:
        print("RE-RUN MODE: database is kept. Staging is reloaded. Warehouse must not grow.")

    for i, (path, database, label) in enumerate(steps, 1):
        started = time.time()
        out = run_sql(path, database)
        print("[%d/%d] %-42s %-52s %.1fs" % (i, len(steps), os.path.basename(path), label, time.time() - started))
        if os.path.basename(path).startswith("08_"):
            print(out)

if __name__ == "__main__":
    main()
