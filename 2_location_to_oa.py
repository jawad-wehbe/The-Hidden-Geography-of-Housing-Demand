from pathlib import Path
import duckdb
import subprocess
import time


# Output directory and batch script path
output_dir = Path("~/Desktop/Projects/housing_targets/temp/search_on_build_shock/").expanduser()
script_dir = Path("~/Desktop/Projects/housing_targets/code/search_on_build_shock/").expanduser()
sb_dir = Path("~/Desktop/Projects/housing_targets/temp/search_on_build_shock/search_buying_searches_by_week.parquet").expanduser()
sl_dir = Path("~/Desktop/Projects/housing_targets/temp/search_on_build_shock/search_letting_searches_by_week.parquet").expanduser()


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
print(" Starting serial execution:")

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
        print(f" Failed: Year={year}, Week={week:02} ({elapsed:.1f}s)")
    else:
        print(f" Done: Year={year}, Week={week:02} ({elapsed:.1f}s)")

# Total time
total_elapsed = time.time() - total_start
print(f"\n⏱️ All done in {total_elapsed / 60:.1f} minutes.")
