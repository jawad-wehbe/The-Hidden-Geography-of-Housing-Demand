from pathlib import Path
import duckdb
import subprocess
import time
import polars as pl
import sys
import sys
from pathlib import Path
_p = Path(__file__).resolve().parent
while not (_p / ".here").exists():
    _p = _p.parent
sys.path.insert(0, str(_p))
from config import *   # CONFIG: all data roots come from config.py (real or demo mode)

# Output directory and batch script path
output_dir = PROJECT_ROOT / "temp/hidden_geography_of_housing_demand"   # CONFIG
script_dir = Path(__file__).resolve().parent # REMEMBER THE BATCH SCRIPT NEED TO BE IN SAME FOLDER AS DRIVER FOR THIS TO RUN
sb_dir = PROJECT_ROOT / "temp/hidden_geography_of_housing_demand/search_buying_searches_by_week_saved_or_contacted.parquet"   # CONFIG
sl_dir = PROJECT_ROOT / "temp/hidden_geography_of_housing_demand/search_letting_searches_by_week_saved_or_contacted.parquet"   # CONFIG
# Get all (year, week) pairs
con = duckdb.connect(database=":memory:")
con.execute(f"CREATE VIEW buying AS  SELECT * FROM read_parquet('{sb_dir.as_posix()}')")
con.execute(f"CREATE VIEW letting AS SELECT * FROM read_parquet('{sl_dir.as_posix()}')")

weeks = con.execute("""
    SELECT DISTINCT year, week
    FROM (
        SELECT year, week FROM buying
        UNION
        SELECT year, week FROM letting
    )
    ORDER BY year, week
""").fetchall()
con.close()

# Start total timer
total_start = time.time()
print("🔁 Starting serial execution:")

# Run each batch
for year, week in weeks:
    print(f"▶ Year={year}, Week={week:02}...")
    start = time.time()

    result = subprocess.run(
        [
            "python",
            "2_location_to_oa_batch.py",
            str(year),
            str(week)
        ],
        cwd=script_dir
    )

    elapsed = time.time() - start
    if result.returncode != 0:
        print(f"❌ Failed: Year={year}, Week={week:02} ({elapsed:.1f}s)")
    else:
        print(f"✅ Done: Year={year}, Week={week:02} ({elapsed:.1f}s)")

# Total time
total_elapsed = time.time() - total_start
print(f"\n⏱️ All done in {total_elapsed / 60:.1f} minutes.")

#############################
# COmbine all datasets
#############################

# Define input and output paths
input_dir = PROJECT_ROOT / "temp/hidden_geography_of_housing_demand"   # CONFIG
output_path = PROJECT_ROOT / "produced/hidden_geography_of_housing_demand/nonbots/saved_or_contacted/oa_weekly_search.parquet"   # CONFIG
#output_path.parent.mkdir(parents=True, exist_ok=True)

# Collect all weekly CSV file paths
csv_files = sorted(input_dir.glob("oa_weekly_search_saved_or_contacted_w*.csv"))

# Read and concatenate all CSVs
df = pl.concat([pl.read_csv(f) for f in csv_files], how="vertical", rechunk=True)

# Save as Parquet
df.write_parquet(output_path)
print(f"✅ Combined dataset saved to {output_path}")