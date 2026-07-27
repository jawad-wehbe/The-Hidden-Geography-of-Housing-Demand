##############################################################
# 1_rightmove_descriptives.py
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - rightmove_filtered.duckdb. The non-bot filtered Rightmove database, providing search_buying,
#   search_letting, session_buying, and session_letting (~/Desktop/Projects/housing_search/produced/nonbots).
# - rightmove_processed.duckdb. The original Rightmove database, used only for the listings table.
# - search_location_lookup.csv. The lookup used to keep only outcode, region, and station locations.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Build one summary-statistics table of Rightmove search activity over the year from 31 May 2023 to
# 31 May 2024, split by buying, letting, and the two combined, and by four user filters (all users,
# users who emailed an agent, users who saved a property, and users who did both).
# 1. Count distinct searchers for each market and filter.
# 2. Count total searches (the same queries but counting rows rather than distinct users).
# 3. Count distinct listings for sales, rental, and combined from the original listings table.
# 4. Count distinct search locations used in each market.
# 5. Compute average time per session and average searches per session, and average sessions per
#    user and average searches per user, for buying, letting, and combined.
# 6. Assemble every figure into one table, format the numbers with thousands separators, and write
#    it to LaTeX.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/output/tables/nature/summary_table.tex


##############################################################
# 2_rank_rank_correlations_buying_searches.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - oa_weekly_search.parquet from the all sample, produced by nonbots_main_analysis
#   (housing_targets/produced/nature/nonbots/all).
# - oa_weekly_search.parquet from the saved, contacted, and contacted_and_saved samples, each
#   produced by the corresponding subfolder below.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Check whether restricting to more serious searchers changes which OAs look like high-demand
# areas, by comparing how the four samples rank OAs on total buying searches.
# 1. Read each of the four weekly panels and collapse it to one total of buying searches per OA.
# 2. Inner join the four totals, so only OAs observed in every sample are kept, and report how many
#    OAs survive.
# 3. Rank OAs within each sample and compute the correlation matrix across the four rankings.
# 4. Print each pairwise rank-rank correlation with a readable label.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - None written to disk. The correlation matrix and the pairwise correlations are printed to the
#   console.


##############################################################
# 2.1 Serious searches samples: saved / contacted / contacted_and_saved
##############################################################
# The three subfolders each hold the same three scripts as the search panel construction in
# nonbots_main_analysis. They differ only in which users are kept and in the suffix and output
# folder used for the files they write:
#
#   saved                Users who saved at least one property
#                        (total_search_number_properties_saved > 0
#                         OR total_details_page_save_property > 0)
#                        Suffix: _saved
#                        Panel:  produced/nature/nonbots/saved/oa_weekly_search.parquet
#
#   contacted            Users who sent at least one email to an agent (total_email_sent > 0)
#                        Suffix: _contacted
#                        Panel:  produced/nature/nonbots/contacted/oa_weekly_search.parquet
#
#   contacted_and_saved  Users who did both
#                        Suffix: _contacted_and_saved
#                        Panel:  produced/nature/nonbots/contacted_and_saved/oa_weekly_search.parquet
#
# In the descriptions below, {sample} is the subfolder and {suffix} is its file suffix.


##############################################################
# 1_search_by_location.py
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - rightmove_filtered.duckdb. The non-bot filtered Rightmove database, providing search_buying and
#   search_letting and the matching session tables used to define the sample
#   (~/Desktop/Projects/housing_search/produced/nonbots).
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Build the weekly count of searches per search location for this subfolder's user sample, for
# buying and for letting separately.
# 1. Open the filtered database read-only and set the DuckDB thread and memory limits.
# 2. For each of search_buying and search_letting, keep only searches whose search_location_id
#    falls in the three retained ranges, which drops the postcode-level location ids.
# 3. Restrict to users who meet this subfolder's condition, taken from the matching session table.
# 4. Count searches by search location, radius filter, year, and week.
# 5. Write one Parquet file per market to the temp folder.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/temp/nature/search_buying_searches_by_week{suffix}.parquet
# - housing_targets/temp/nature/search_letting_searches_by_week{suffix}.parquet


##############################################################
# 2_location_to_oa.py
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - The two weekly search Parquet files written by 1_search_by_location.py.
# - The weekly OA CSVs written by 2_location_to_oa_batch.py.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Driver script. Run the OA mapping one week at a time, then stitch the weeks back together into a
# single panel. The batch script must sit in the same folder as this one.
# 1. Read the buying and letting weekly files and collect every distinct year and week pair across
#    the two.
# 2. Loop over those pairs in order, calling 2_location_to_oa_batch.py once per week and reporting
#    the runtime and whether each call succeeded.
# 3. Read back every weekly CSV for this sample and concatenate them.
# 4. Write the combined panel as one Parquet file.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/{sample}/oa_weekly_search.parquet


##############################################################
# 2_location_to_oa_batch.py
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - locationid_rad_to_OA.parq. The crosswalk giving, for each search location and radius, the share
#   of that search area falling in each OA (~/Desktop/Raw_Data/Rightmove).
# - The two weekly search Parquet files written by 1_search_by_location.py.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Convert one week of location-level searches into OA-level searches. Called once per year and week
# by the driver, taking the year and week as command line arguments.
# 1. Register the crosswalk and the two weekly search files as DuckDB views.
# 2. Filter buying and letting to the requested year and week and join each onto the crosswalk by
#    search location and radius filter.
# 3. Apportion each search to OAs by multiplying the count by the OA share, treating locations with
#    no searches that week as zero.
# 4. Sum to one row per OA for that week and write it as a CSV.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/temp/nature/oa_weekly_search{suffix}_w{week}_{year}.csv