import duckdb
import polars as pl
import time
from pathlib import Path

# Start timing
start_time = time.time()

# Paths
processed_db = Path("~/Desktop/Projects/housing_search/produced/nonbots/rightmove_filtered.duckdb").expanduser()
spill_dir    = Path("~/Desktop/Projects/housing_targets/temp/duckdb_spill/").expanduser()
output_dir   = Path("~/Desktop/Projects/housing_targets/temp/nature/").expanduser()

# Connect
con = duckdb.connect(processed_db, read_only=True)
con.execute(f"SET temp_directory='{spill_dir}';")
con.execute("SET memory_limit='200GB';")
con.execute("PRAGMA threads=12;")

# Function to generate and save weekly searches.
# Restricted to "serious" users: those who saved or contacted (emailed) in the
# matching session table.
def process_searches(table_name: str):
    session_table = table_name.replace("search_", "session_")
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
                FROM {session_table}
                WHERE total_search_number_properties_saved > 0
                   OR total_details_page_save_property     > 0
                   OR total_email_sent                     > 0
            )
        GROUP BY search_location_id, search_radius_filter, year, week
        ORDER BY search_location_id, search_radius_filter, year, week
    """

    print(f"Running query for {table_name} (saved or contacted users)...")
    df = con.execute(query).pl()

    output_path = output_dir / f"{table_name}_searches_by_week_saved_or_contacted.parquet"
    df.write_parquet(output_path)
    print(f"Saved: {output_path}")

# Process both tables
process_searches("search_buying")
process_searches("search_letting")

# Done
elapsed = (time.time() - start_time) / 60
print(f"Done in {elapsed:.2f} minutes.")
con.close()