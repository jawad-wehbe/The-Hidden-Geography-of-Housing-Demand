import duckdb
import polars as pl
import time
from pathlib import Path
import sys
from pathlib import Path
_p = Path(__file__).resolve().parent
while not (_p / ".here").exists():
    _p = _p.parent
sys.path.insert(0, str(_p))
from config import *   # CONFIG: all data roots come from config.py (real or demo mode)

# Start timing
start_time = time.time()

# Resources
DUCKDB_THREADS = N_THREADS   # CONFIG
# DUCKDB_MEMORY now comes from config.py   # CONFIG

# Filter
CONTACTED_FILTER = "total_email_sent > 0"

# Paths
processed_db = SEARCH_FILTERED_DB   # CONFIG
output_dir = PROJECT_ROOT / "temp/hidden_geography_of_housing_demand"   # CONFIG
output_dir.mkdir(parents=True, exist_ok=True)
# Connect
con = duckdb.connect(processed_db, read_only=True)
con.execute(f"SET threads = {DUCKDB_THREADS}")
con.execute(f"SET memory_limit = '{DUCKDB_MEMORY}'")

# Function to generate and save weekly searches
def process_searches(table_name: str):
    query = f"""
        SELECT 
            search_location_id,
            search_radius_filter,
            YEAR(session_date) AS year,
            WEEK(session_date) AS week,
            COUNT(*) AS num_searches
        FROM {table_name}
        WHERE 
            (
                (search_location_id BETWEEN 1 AND 99999)
                OR (search_location_id BETWEEN 100001 AND 999999)
                OR (search_location_id BETWEEN 9000001 AND 9999999)
            )
            AND user_id_num IN (
                SELECT DISTINCT user_id_num
                FROM {table_name}
                WHERE {CONTACTED_FILTER}
            )
        GROUP BY search_location_id, search_radius_filter, year, week
        ORDER BY search_location_id, search_radius_filter, year, week
    """
    
    print(f"Running query for {table_name}...")
    df = con.execute(query).pl()
    
    output_path = output_dir / f"{table_name}_searches_by_week_contacted.parquet"
    df.write_parquet(output_path)
    print(f"Saved: {output_path}")

# Process both tables
process_searches("search_buying")
process_searches("search_letting")

# Done
elapsed = (time.time() - start_time) / 60
print(f"Done in {elapsed:.2f} minutes.")

con.close()