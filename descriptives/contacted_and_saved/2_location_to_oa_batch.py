import duckdb
import polars as pl
import sys
from pathlib import Path
import sys
from pathlib import Path
_p = Path(__file__).resolve().parent
while not (_p / ".here").exists():
    _p = _p.parent
sys.path.insert(0, str(_p))
from config import *   # CONFIG: all data roots come from config.py (real or demo mode)

# Resources
DUCKDB_THREADS = N_THREADS   # CONFIG
# DUCKDB_MEMORY now comes from config.py   # CONFIG

# Read args
year = int(sys.argv[1])
week = int(sys.argv[2])

# Paths
oa_map_path = SEARCH_RAW_DIR / "locationid_rad_to_OA.parq"   # CONFIG
buying_path = sb_dir = PROJECT_ROOT / "temp/hidden_geography_of_housing_demand/search_buying_searches_by_week_both.parquet"   # CONFIG
letting_path = PROJECT_ROOT / "temp/hidden_geography_of_housing_demand/search_letting_searches_by_week_both.parquet"   # CONFIG
output_dir = PROJECT_ROOT / "temp/hidden_geography_of_housing_demand"   # CONFIG
out_path = output_dir / f"oa_weekly_search_both_w{week:02}_{year}.csv"


# Connect
con = duckdb.connect(database=":memory:")
con.execute(f"SET threads = {DUCKDB_THREADS}")
con.execute(f"SET memory_limit = '{DUCKDB_MEMORY}'")
con.execute(f"CREATE VIEW location_to_oa AS SELECT * FROM read_parquet('{oa_map_path}')")
con.execute(f"CREATE VIEW buying AS SELECT * FROM read_parquet('{buying_path}')")
con.execute(f"CREATE VIEW letting AS SELECT * FROM read_parquet('{letting_path}')")

# Query
query = f"""
    SELECT 
        oa_code,
        year,
        week,
        SUM(COALESCE(share * num_searches_buying, 0)) AS buying_searches,
        SUM(COALESCE(share * num_searches_letting, 0)) AS letting_searches
    FROM location_to_oa
    LEFT JOIN (
        SELECT search_location_id, search_radius_filter, year, week, num_searches AS num_searches_buying
        FROM buying
        WHERE year = {year} AND week = {week}
    ) USING (search_location_id, search_radius_filter)
    LEFT JOIN (
        SELECT search_location_id, search_radius_filter, year, week, num_searches AS num_searches_letting
        FROM letting
        WHERE year = {year} AND week = {week}
    ) USING (search_location_id, search_radius_filter, year, week)
    WHERE year = {year} AND week = {week}
    GROUP BY oa_code, year, week
    ORDER BY oa_code
"""

df = con.execute(query).pl()
df.write_csv(out_path)