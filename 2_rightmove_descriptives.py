import pandas as pd
import duckdb 
from pathlib import Path
import matplotlib.pyplot as plt
import subprocess
import numpy as np

# Paths
db_path = Path("~/Desktop/Projects/housing_search/produced/nonbots/rightmove_filtered.duckdb").expanduser()
spill_dir = "/home/jawad/Desktop/Projects/housing_search/temp/duckdb_spill/"


# Path to old duckdb (used only to get the listings)
old_rightmove_path = Path("~/Desktop/Raw_Data/Rightmove/rightmove_processed.duckdb").expanduser()

#output table results

output_dir = Path("/home/jawad/Desktop/Projects/housing_targets/output/tables/nature_cities/")

# search location lookup path

location_lookup_path = Path("/home/jawad/Desktop/Raw_Data/Rightmove/search_location_lookup.csv")

#######################
# Read in the data
########################

location_lookup = pd.read_csv(location_lookup_path)

# Filter rows where type is one of the desired values
filtered_location = location_lookup[location_lookup['type'].isin(['outcode', 'region', 'station'])]

location_ids = filtered_location[['search_location_id']]


#############################################################
# Need to filter to non postcode locations
##############################################################

############################
# Letting
#############################

# SQL TEMPLATE
sql_template = """
WITH filtered AS (
    SELECT *
    FROM search_letting
    WHERE session_date >= DATE '2023-05-31'
      AND session_date <  DATE '2024-05-31'
      AND search_location_id IN (
          SELECT search_location_id FROM filtered_locations
      )
      {extra_condition}
)

SELECT COUNT(DISTINCT user_id_num) AS total_distinct_searchers
FROM filtered;
"""

# CONDITIONS ( The restrictions to create serious users)
conditions = {
    "date_only": "", 
    "emailed": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_letting
          WHERE total_email_sent > 0
      )
    """,
    "saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_letting
          WHERE (
              total_search_number_properties_saved > 0
              OR total_details_page_save_property > 0
          )
      )
    """,
    "emailed_and_saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_letting
          WHERE 
              total_email_sent > 0
              AND (
                  total_search_number_properties_saved > 0
                  OR total_details_page_save_property > 0
              )
      )
    """
}

# RUN ALL QUERIES WITH SEPARATE CONNECTIONS
results_letting = {}

for label, condition in conditions.items():

    # Build SQL
    sql = sql_template.format(extra_condition=condition)

    # PRINT SQL BEFORE RUNNING IT
    print(sql)

    # Connect for this iteration only
    db = duckdb.connect(database=str(db_path), read_only=True)
    db.execute(f"SET temp_directory='{spill_dir}';")
    db.execute("PRAGMA threads=12;")
    db.execute("SET memory_limit='250GB';")
    db.register("filtered_locations", location_ids)

    # Run query
    df = db.execute(sql).fetchdf()
    results_letting[label] = df.iloc[0, 0]

    # Disconnect immediately
    db.close()

# PRINT RESULTS
for label, count in results_letting.items():
    print(f"{label}: {count}")


############################
# BUYING
#############################

# SQL TEMPLATE
sql_template = """
WITH filtered AS (
    SELECT *
    FROM search_buying
    WHERE session_date >= DATE '2023-05-31'
      AND session_date <  DATE '2024-05-31'
      AND search_location_id IN (
          SELECT search_location_id FROM filtered_locations
      )
      {extra_condition}
)

SELECT COUNT(DISTINCT user_id_num) AS total_distinct_searchers
FROM filtered;
"""

# CONDITIONS ( The restrictions to create serious users)
conditions = {
    "date_only": "", 
    "emailed": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_buying
          WHERE total_email_sent > 0
      )
    """,
    "saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_buying
          WHERE (
              total_search_number_properties_saved > 0
              OR total_details_page_save_property > 0
          )
      )
    """,
    "emailed_and_saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_buying
          WHERE 
              total_email_sent > 0
              AND (
                  total_search_number_properties_saved > 0
                  OR total_details_page_save_property > 0
              )
      )
    """
}

# RUN ALL QUERIES WITH SEPARATE CONNECTIONS
results_buying = {}

for label, condition in conditions.items():

    # Build SQL
    sql = sql_template.format(extra_condition=condition)

    # PRINT SQL BEFORE RUNNING IT
    print(sql)

    # Connect for this iteration only
    db = duckdb.connect(database=str(db_path), read_only=True)
    db.execute(f"SET temp_directory='{spill_dir}';")
    db.execute("PRAGMA threads=12;")
    db.execute("SET memory_limit='250GB';")
    db.register("filtered_locations", location_ids)

    # Run query
    df = db.execute(sql).fetchdf()
    results_buying[label] = df.iloc[0, 0]

    # Disconnect immediately
    db.close()

# PRINT RESULTS
for label, count in results_buying.items():
    print(f"{label}: {count}")



#########################################################
# Combine both buying and letting and run the same query on distinct users across both
##########################################################



# SQL TEMPLATE
sql_template = """
WITH filtered AS (
    -- all LETTING users
    SELECT user_id_num
    FROM search_letting
    WHERE session_date >= DATE '2023-05-31'
      AND session_date <  DATE '2024-05-31'
      AND search_location_id IN (
          SELECT search_location_id FROM filtered_locations
      )

    UNION

    -- all BUYING users
    SELECT user_id_num
    FROM search_buying
    WHERE session_date >= DATE '2023-05-31'
      AND session_date <  DATE '2024-05-31'
      AND search_location_id IN (
          SELECT search_location_id FROM filtered_locations
      )
      
)

SELECT COUNT(DISTINCT user_id_num) AS total_distinct_searchers
FROM filtered
WHERE 1=1
{extra_condition};
"""


# CONDITIONS ( The restrictions to create serious users)
conditions = {
    "date_only": "", 
    "emailed": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM (
              SELECT user_id_num, total_email_sent
              FROM session_buying
              UNION ALL
              SELECT user_id_num, total_email_sent
              FROM session_letting
          ) t
          WHERE total_email_sent > 0
      )
    """,
    "saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM (
              SELECT user_id_num,
                     total_search_number_properties_saved,
                     total_details_page_save_property
              FROM session_buying
              UNION ALL
              SELECT user_id_num,
                     total_search_number_properties_saved,
                     total_details_page_save_property
              FROM session_letting
          ) t
          WHERE total_search_number_properties_saved > 0 OR total_details_page_save_property > 0
      )
    """,
    "emailed_and_saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM (
              SELECT user_id_num,
                     total_email_sent,
                     total_search_number_properties_saved,
                     total_details_page_save_property
              FROM session_buying
              UNION ALL
              SELECT user_id_num,
                     total_email_sent,
                     total_search_number_properties_saved,
                     total_details_page_save_property 
              FROM session_letting
          ) t
          WHERE total_email_sent > 0
            AND (total_search_number_properties_saved > 0 OR total_details_page_save_property > 0)
      )
    """
}


# RUN ALL QUERIES WITH SEPARATE CONNECTIONS
results_combined = {}

for label, condition in conditions.items():

    # Build SQL
    sql = sql_template.format(extra_condition=condition)

    # PRINT SQL BEFORE RUNNING IT
    print(sql)

    # Connect for this iteration only
    db = duckdb.connect(database=str(db_path), read_only=True)
    db.execute(f"SET temp_directory='{spill_dir}';")
    db.execute("PRAGMA threads=12;")
    db.execute("SET memory_limit='250GB';")
    db.register("filtered_locations", location_ids)

    # Run query
    df = db.execute(sql).fetchdf()
    results_combined[label] = df.iloc[0, 0]

    # Disconnect immediately
    db.close()

# PRINT RESULTS
for label, count in results_combined.items():
    print(f"{label}: {count}")

##################################################################
##################################################################
# Now count total searches across samples (basically just replace distinct users above with just all rows)
##################################################################
##################################################################

#######################
# Letting
#######################
# SQL TEMPLATE
sql_template = """
WITH filtered AS (
    SELECT *
    FROM search_letting
    WHERE session_date >= DATE '2023-05-31'
      AND session_date <  DATE '2024-05-31'
      AND search_location_id IN (
          SELECT search_location_id FROM filtered_locations
      )
      {extra_condition}
)

SELECT COUNT(*) AS total_searches
FROM filtered;
"""

# CONDITIONS ( The restrictions to create serious users)
conditions = {
    "date_only": "", 
    "emailed": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_letting
          WHERE total_email_sent > 0
      )
    """,
    "saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_letting
          WHERE (
              total_search_number_properties_saved > 0
              OR total_details_page_save_property > 0
          )
      )
    """,
    "emailed_and_saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_letting
          WHERE 
              total_email_sent > 0
              AND (
                  total_search_number_properties_saved > 0
                  OR total_details_page_save_property > 0
              )
      )
    """
}

# RUN ALL QUERIES WITH SEPARATE CONNECTIONS
searches_results_letting = {}

for label, condition in conditions.items():

    # Build SQL
    sql = sql_template.format(extra_condition=condition)

    # PRINT SQL BEFORE RUNNING IT
    print(sql)

    # Connect for this iteration only
    db = duckdb.connect(database=str(db_path), read_only=True)
    db.execute(f"SET temp_directory='{spill_dir}';")
    db.execute("PRAGMA threads=12;")
    db.execute("SET memory_limit='250GB';")
    db.register("filtered_locations", location_ids)

    # Run query
    df = db.execute(sql).fetchdf()
    searches_results_letting[label] = df.iloc[0, 0]

    # Disconnect immediately
    db.close()

# PRINT RESULTS
for label, count in searches_results_letting.items():
    print(f"{label}: {count}")


#################################
# Buying
##################################

# SQL TEMPLATE
sql_template = """
WITH filtered AS (
    SELECT *
    FROM search_buying
    WHERE session_date >= DATE '2023-05-31'
      AND session_date <  DATE '2024-05-31'
      AND search_location_id IN (
          SELECT search_location_id FROM filtered_locations
      )
      {extra_condition}
)

SELECT COUNT(*) AS total_searches
FROM filtered;
"""

# CONDITIONS ( The restrictions to create serious users)
conditions = {
    "date_only": "", 
    "emailed": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_buying
          WHERE total_email_sent > 0
      )
    """,
    "saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_buying
          WHERE (
              total_search_number_properties_saved > 0
              OR total_details_page_save_property > 0
          )
      )
    """,
    "emailed_and_saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM session_buying
          WHERE 
              total_email_sent > 0
              AND (
                  total_search_number_properties_saved > 0
                  OR total_details_page_save_property > 0
              )
      )
    """
}

# RUN ALL QUERIES WITH SEPARATE CONNECTIONS
searches_results_buying = {}

for label, condition in conditions.items():

    # Build SQL
    sql = sql_template.format(extra_condition=condition)

    # PRINT SQL BEFORE RUNNING IT
    print(sql)

    # Connect for this iteration only
    db = duckdb.connect(database=str(db_path), read_only=True)
    db.execute(f"SET temp_directory='{spill_dir}';")
    db.execute("PRAGMA threads=12;")
    db.execute("SET memory_limit='250GB';")
    db.register("filtered_locations", location_ids)

    # Run query
    df = db.execute(sql).fetchdf()
    searches_results_buying[label] = df.iloc[0, 0]

    # Disconnect immediately
    db.close()

# PRINT RESULTS
for label, count in searches_results_buying.items():
    print(f"{label}: {count}")


#######################################################################################
# Combine both buying and letting and run the same query on distinct users across both
#######################################################################################

# SQL TEMPLATE
sql_template = """
WITH filtered AS (
    -- all LETTING users
    SELECT user_id_num
    FROM search_letting
    WHERE session_date >= DATE '2023-05-31'
      AND session_date <  DATE '2024-05-31'
      AND search_location_id IN (
          SELECT search_location_id FROM filtered_locations
      )

    UNION ALL

    -- all BUYING users
    SELECT user_id_num
    FROM search_buying
    WHERE session_date >= DATE '2023-05-31'
      AND session_date <  DATE '2024-05-31'
      AND search_location_id IN (
          SELECT search_location_id FROM filtered_locations
      )
      
)

SELECT COUNT(*) AS total_searches
FROM filtered
WHERE 1=1
{extra_condition};
"""


# CONDITIONS (The restrictions to create serious users)
conditions = {
    "date_only": "", 
    "emailed": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM (
              SELECT user_id_num, total_email_sent
              FROM session_buying
              UNION ALL
              SELECT user_id_num, total_email_sent
              FROM session_letting
          ) t
          WHERE total_email_sent > 0
      )
    """,
    "saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM (
              SELECT user_id_num,
                     total_search_number_properties_saved,
                     total_details_page_save_property
              FROM session_buying
              UNION ALL
              SELECT user_id_num,
                     total_search_number_properties_saved,
                     total_details_page_save_property
              FROM session_letting
          ) t
          WHERE total_search_number_properties_saved > 0 OR total_details_page_save_property > 0
      )
    """,
    "emailed_and_saved": """
      AND user_id_num IN (
          SELECT DISTINCT user_id_num
          FROM (
              SELECT user_id_num,
                     total_email_sent,
                     total_search_number_properties_saved,
                     total_details_page_save_property
              FROM session_buying
              UNION ALL
              SELECT user_id_num,
                     total_email_sent,
                     total_search_number_properties_saved,
                     total_details_page_save_property 
              FROM session_letting
          ) t
          WHERE total_email_sent > 0
            AND (total_search_number_properties_saved > 0 OR total_details_page_save_property > 0)
      )
    """
}


# RUN ALL QUERIES WITH SEPARATE CONNECTIONS
search_results_combined = {}

for label, condition in conditions.items():

    # Build SQL
    sql = sql_template.format(extra_condition=condition)

    # PRINT SQL BEFORE RUNNING IT
    print(sql)

    # Connect for this iteration only
    db = duckdb.connect(database=str(db_path), read_only=True)
    db.execute(f"SET temp_directory='{spill_dir}';")
    db.execute("PRAGMA threads=12;")
    db.execute("SET memory_limit='250GB';")
    db.register("filtered_locations", location_ids)

    # Run query
    df = db.execute(sql).fetchdf()
    search_results_combined[label] = df.iloc[0, 0]

    # Disconnect immediately
    db.close()

# PRINT RESULTS
for label, count in search_results_combined.items():
    print(f"{label}: {count}")

##########################################################################
##########################################################################
# Count listings in each market
##########################################################################
##########################################################################

# sales
with duckdb.connect(old_rightmove_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")

    listings = con.execute("""
        SELECT COUNT(DISTINCT Listing_ID) AS distinct_listings
        FROM listings
        WHERE trans_type = 'Sale'
          AND change_date >= DATE '2023-05-30'
          AND change_date <  DATE '2024-05-30';
    """).df()

print(listings)

# rental
with duckdb.connect(old_rightmove_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")

    listings_rental = con.execute("""
        SELECT COUNT(DISTINCT Listing_ID) AS distinct_listings
        FROM listings
        WHERE trans_type = 'Rent'
          AND change_date >= DATE '2023-05-30'
          AND change_date <  DATE '2024-05-30';
    """).df()

print(listings_rental)

# combined

with duckdb.connect(old_rightmove_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")

    listings_combined= con.execute("""
        SELECT COUNT(DISTINCT Listing_ID) AS distinct_listings
        FROM listings
        WHERE change_date >= DATE '2023-05-30'
          AND change_date <  DATE '2024-05-30';
    """).df()

print(listings_combined)

# Combine into one table
results = pd.DataFrame({
    "Category": ["Sales", "Rental", "Combined"],
    "Distinct Listings": [listings, listings_rental, listings_combined]
})

print(results)
##########################################################################
##########################################################################
# Get the distinct search location frequencies in each market and combined
##########################################################################
##########################################################################

# sales
with duckdb.connect(db_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")
    con.register("filtered_locations", location_ids)

    df = con.execute("""
    SELECT 
        search_location_id, 
        search_radius_filter
    FROM(
        SELECT DISTINCT search_location_id, search_radius_filter
        FROM search_buying
        WHERE session_date >= DATE '2023-05-30'
          AND session_date <  DATE '2024-05-30'
          AND search_location_id IN (
            SELECT search_location_id FROM filtered_locations
             )
    );
    """).df()




# sales
with duckdb.connect(db_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")
    con.register("filtered_locations", location_ids)


    df = con.execute("""
    SELECT COUNT (*) AS unique_locations
    FROM(
        SELECT DISTINCT search_location_id, search_radius_filter 
        FROM search_buying
        WHERE session_date >= DATE '2023-05-30'
          AND session_date <  DATE '2024-05-30'
          AND search_location_id IN (
              SELECT search_location_id FROM filtered_locations
             )
    );
    """).df()

print(df)

# RENTAL
with duckdb.connect(db_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")
    con.register("filtered_locations", location_ids)


    df_rental = con.execute("""
    SELECT COUNT(*) AS unique_locations
    FROM(
        SELECT DISTINCT search_location_id, search_radius_filter 
        FROM search_letting
        WHERE session_date >= DATE '2023-05-30'
          AND session_date <  DATE '2024-05-30'
          AND search_location_id IN (
            SELECT search_location_id FROM filtered_locations
             )
    );
    """).df()

print(df_rental)


# combined 

with duckdb.connect(db_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")
    con.register("filtered_locations", location_ids)

    df_combined = con.execute("""
        SELECT COUNT(*) AS unique_locations
        FROM (
            SELECT DISTINCT search_location_id, search_radius_filter
            FROM search_letting
            WHERE session_date >= DATE '2023-05-30'
              AND session_date <  DATE '2024-05-30'
              AND search_location_id IN (
                SELECT search_location_id FROM filtered_locations
                )
            

            UNION

            SELECT DISTINCT search_location_id, search_radius_filter
            FROM search_buying
            WHERE session_date >= DATE '2023-05-30'
              AND session_date <  DATE '2024-05-30'
              AND search_location_id IN (
                 SELECT search_location_id FROM filtered_locations
                )
        );
    """).df()

print(df_combined)

###################################################################################
###################################################################################
# Now getting the average stats
###################################################################################
###################################################################################

# Session averages
with duckdb.connect(db_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")

    session_df = con.execute("""
        SELECT 
            AVG(time_in_secs / 60.0)   AS avg_time_per_session_mins,
            AVG(total_is_search)       AS avg_searches_per_session
        FROM session_buying
        WHERE session_date >= DATE '2023-05-30'
          AND session_date <  DATE '2024-05-30'
          AND time_in_secs > 5;   -- remove short/low-quality sessions
    """).df()

print(session_df)


# User averages

with duckdb.connect(db_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")
    con.register("filtered_locations", location_ids)

    user_df = con.execute("""
        WITH filtered AS (
            SELECT *
            FROM search_buying
            WHERE session_date >= DATE '2023-05-30'
              AND session_date <  DATE '2024-05-30'
              AND search_location_id IN (
                 SELECT search_location_id FROM filtered_locations
                )
        ),
        user_stats AS (
            SELECT 
                user_id_num,
                COUNT(DISTINCT session_id_num) AS sessions_per_user,
                COUNT(*) AS searches_per_user
            FROM filtered
            GROUP BY user_id_num
        )
        SELECT
            AVG(sessions_per_user) AS avg_sessions_per_user,
            AVG(searches_per_user) AS avg_searches_per_user
        FROM user_stats;
    """).df()

print(user_df)

###############
# Letting
###############

# Session averages
with duckdb.connect(db_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")

    letting_session_df = con.execute("""
        SELECT
            AVG(time_in_secs / 60.0)   AS avg_time_per_session_mins,
            AVG(total_is_search)       AS avg_searches_per_session
        FROM session_letting
        WHERE session_date >= DATE '2023-05-30'
          AND session_date <  DATE '2024-05-30'
          AND time_in_secs > 5;   -- filter out very short sessions
    """).df()

print(letting_session_df)


# User averages

with duckdb.connect(db_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")
    con.register("filtered_locations", location_ids)

    letting_user_df = con.execute("""
        WITH filtered AS (
            SELECT *
            FROM search_letting
            WHERE session_date >= DATE '2023-05-30'
              AND session_date <  DATE '2024-05-30'
              AND search_location_id IN (
                SELECT search_location_id FROM filtered_locations
                )
        ),
        user_stats AS (
            SELECT 
                user_id_num,
                COUNT(DISTINCT session_id_num) AS sessions_per_user,
                COUNT(*) AS searches_per_user
            FROM filtered
            GROUP BY user_id_num
        )
        SELECT
            AVG(sessions_per_user) AS avg_sessions_per_user,
            AVG(searches_per_user) AS avg_searches_per_user
        FROM user_stats;
    """).df()

print(letting_user_df)



###############################
# COMBINED Letting and Buying
###############################

# Session averages
with duckdb.connect(db_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")

    combined_session_df = con.execute("""
        WITH all_sessions AS (
            SELECT 
                user_id_num,
                session_id_num,
                session_date,
                time_in_secs / 60.0 AS time_in_mins,   -- convert HERE
                total_is_search
            FROM session_letting
            WHERE session_date >= DATE '2023-05-30'
              AND session_date <  DATE '2024-05-30'
              AND time_in_secs > 5

            UNION ALL

            SELECT 
                user_id_num,
                session_id_num,
                session_date,
                time_in_secs / 60.0 AS time_in_mins,   -- convert HERE
                total_is_search
            FROM session_buying
            WHERE session_date >= DATE '2023-05-30'
              AND session_date <  DATE '2024-05-30'
              AND time_in_secs > 5
        )

        SELECT
            AVG(time_in_mins)     AS avg_time_per_session_mins,
            AVG(total_is_search)  AS avg_searches_per_session
        FROM all_sessions;
    """).df()

print(combined_session_df)



# User averages

with duckdb.connect(db_path, read_only=True) as con:
    con.execute(f"SET temp_directory='{spill_dir}';")
    con.execute("SET memory_limit='250GB';")
    con.execute("PRAGMA threads=12;")
    con.register("filtered_locations", location_ids)

    combined_user_df = con.execute("""
        WITH filtered AS (
            SELECT 
                user_id_num,
                session_id_num,
                session_date
            FROM search_letting
            WHERE session_date >= DATE '2023-05-30'
              AND session_date <  DATE '2024-05-30'
              AND search_location_id IN (
                 SELECT search_location_id FROM filtered_locations
                )

            UNION ALL

            SELECT 
                user_id_num,
                session_id_num,
                session_date
            FROM search_buying
            WHERE session_date >= DATE '2023-05-30'
              AND session_date <  DATE '2024-05-30'
              AND search_location_id IN (
                SELECT search_location_id FROM filtered_locations
                )
        ),

        user_stats AS (
            SELECT 
                user_id_num,
                COUNT(DISTINCT session_id_num) AS sessions_per_user,
                COUNT(*) AS searches_per_user
            FROM filtered
            GROUP BY user_id_num
        )

        SELECT
            AVG(sessions_per_user) AS avg_sessions_per_user,
            AVG(searches_per_user) AS avg_searches_per_user
        FROM user_stats;
    """).df()

print(combined_user_df)


# Helper function: safe extract
def val(df):
    return df.iloc[0, 0] if hasattr(df, "iloc") else df

# Initialize table rows
rows = []
label_map = {
    "All": "date_only",
    "emailed": "emailed",
    "saved": "saved",
    "emailed and saved": "emailed_and_saved"   # if needed
}

###############################################
# 1. DISTINCT USERS
###############################################
for label in ["All", "emailed", "saved", "emailed and saved"]:
    key = label_map[label]
    rows.append({
        "Metric": f"Distinct Users ({label})",
        "Buying": results_buying.get(key, np.nan),
        "Letting": results_letting.get(key, np.nan),
        "Combined": results_combined.get(key, np.nan),
    })

###############################################
# 2. TOTAL SEARCHES
###############################################
for label in ["All", "emailed", "saved", "emailed and saved"]:
    key = label_map[label]
    rows.append({
        "Metric": f"Total Searches ({label})",
        "Buying": searches_results_buying.get(key, np.nan),
        "Letting": searches_results_letting.get(key, np.nan),
        "Combined": search_results_combined.get(key, np.nan),
    })

###############################################
# 3. LISTINGS
###############################################
rows.append({
    "Metric": "Listings",
    "Buying": val(listings),               # sales
    "Letting": val(listings_rental),       # rental
    "Combined": val(listings_combined),    # combined
})

###############################################
# 4. UNIQUE SEARCH LOCATIONS
###############################################
rows.append({
    "Metric": "Unique Search Locations",
    "Buying": val(df), 
    "Letting": val(df_rental),
    "Combined": val(df_combined),
})

###############################################
# 5. SESSION AVERAGES
###############################################
rows.append({
    "Metric": "Avg Time Per Session (mins)",
    "Buying": session_df["avg_time_per_session_mins"].iloc[0],
    "Letting": letting_session_df["avg_time_per_session_mins"].iloc[0],
    "Combined": combined_session_df["avg_time_per_session_mins"].iloc[0],
})

rows.append({
    "Metric": "Avg Searches Per Session",
    "Buying": session_df["avg_searches_per_session"].iloc[0],
    "Letting": letting_session_df["avg_searches_per_session"].iloc[0],
    "Combined": combined_session_df["avg_searches_per_session"].iloc[0],
})

###############################################
# 6. USER AVERAGES
###############################################
rows.append({
    "Metric": "Avg Sessions Per User",
    "Buying": user_df["avg_sessions_per_user"].iloc[0],
    "Letting": letting_user_df["avg_sessions_per_user"].iloc[0],
    "Combined": combined_user_df["avg_sessions_per_user"].iloc[0],
})

rows.append({
    "Metric": "Avg Searches Per User",
    "Buying": user_df["avg_searches_per_user"].iloc[0],
    "Letting": letting_user_df["avg_searches_per_user"].iloc[0],
    "Combined": combined_user_df["avg_searches_per_user"].iloc[0],
})

###############################################
# BUILD FINAL TABLE
###############################################
final_table = pd.DataFrame(rows)


# Round and format with commas
final_table[["Buying", "Letting", "Combined"]] = (
    final_table[["Buying", "Letting", "Combined"]]
    .round(0)
    .astype("Int64")
    .applymap(lambda x: f"{x:,}" if pd.notnull(x) else "")
)

# set output path
latex_path = output_dir / "summary_table.tex"

# save it
final_table.to_latex(latex_path, index=False)