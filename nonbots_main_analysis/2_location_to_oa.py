from pathlib import Path
import duckdb
import subprocess
import time
import polars as pl
import sys

# Output directory and batch script path
output_dir = Path("~/Desktop/Projects/housing_targets/temp/nature/").expanduser()
script_dir = Path("~/Desktop/Projects/housing_targets/code/fergie_backup/code_housing_target/nature/nonbots/all/").expanduser()
sb_dir = Path("~/Desktop/Projects/housing_targets/temp/nature/search_buying_searches_by_week.parquet").expanduser()
sl_dir = Path("~/Desktop/Projects/housing_targets/temp/nature/search_letting_searches_by_week.parquet").expanduser()
#script_dir = Path("c:/Users/Nikhil Datta/Dropbox/_work/Academic Research/Urban/Search Projects/Datawork/code/search_on_build_shock")
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
input_dir = Path("~/Desktop/Projects/housing_targets/temp/nature/").expanduser()
output_path = Path("~/Desktop/Projects/housing_targets/produced/nature/nonbots/all/oa_weekly_search.parquet").expanduser()
#output_path.parent.mkdir(parents=True, exist_ok=True)

# Collect all weekly CSV file paths
csv_files = sorted(input_dir.glob("oa_weekly_search_w*.csv"))

# Read and concatenate all CSVs
df = pl.concat([pl.read_csv(f) for f in csv_files], how="vertical", rechunk=True)

# Save as Parquet
df.write_parquet(output_path)
print(f"✅ Combined dataset saved to {output_path}")