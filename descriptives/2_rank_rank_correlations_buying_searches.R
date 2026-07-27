library(arrow)
library(dplyr)

rm(list = ls())
gc()

# Paths
base_dir       <- path.expand("~/Desktop/Projects/housing_targets/produced/nature/nonbots")
all_path       <- file.path(base_dir, "all",                 "oa_weekly_search.parquet")
saved_path     <- file.path(base_dir, "saved",               "oa_weekly_search.parquet")
contacted_path <- file.path(base_dir, "contacted",           "oa_weekly_search.parquet")
both_path      <- file.path(base_dir, "contacted_and_saved", "oa_weekly_search.parquet")

# Collapse each weekly panel to one total per OA
all_df <- read_parquet(all_path) %>%
  group_by(oa_code) %>%
  summarise(all = sum(buying_searches), .groups = "drop")

saved_df <- read_parquet(saved_path) %>%
  group_by(oa_code) %>%
  summarise(saved = sum(buying_searches), .groups = "drop")

contacted_df <- read_parquet(contacted_path) %>%
  group_by(oa_code) %>%
  summarise(contacted = sum(buying_searches), .groups = "drop")

both_df <- read_parquet(both_path) %>%
  group_by(oa_code) %>%
  summarise(both = sum(buying_searches), .groups = "drop")

# Inner join the four
df <- all_df %>%
  inner_join(saved_df,     by = "oa_code") %>%
  inner_join(contacted_df, by = "oa_code") %>%
  inner_join(both_df,      by = "oa_code")

cat("OAs in all four samples:", nrow(df), "\n")

# Ranks
df$rank_all       <- rank(df$all)
df$rank_saved     <- rank(df$saved)
df$rank_contacted <- rank(df$contacted)
df$rank_both      <- rank(df$both)

# Correlations
rank_cols <- df[, c("rank_all", "rank_saved", "rank_contacted", "rank_both")]
print(round(cor(rank_cols), 3))

cat("\n")
cat(sprintf("All non-bot users                vs Saved a property                 %.3f\n", cor(df$rank_all,       df$rank_saved)))
cat(sprintf("All non-bot users                vs Contacted estate agent           %.3f\n", cor(df$rank_all,       df$rank_contacted)))
cat(sprintf("All non-bot users                vs Saved and contacted estate agent %.3f\n", cor(df$rank_all,       df$rank_both)))
cat(sprintf("Contacted estate agent           vs Saved and contacted estate agent %.3f\n", cor(df$rank_contacted, df$rank_both)))
cat(sprintf("Contacted estate agent           vs Saved a property                 %.3f\n", cor(df$rank_contacted, df$rank_saved)))
cat(sprintf("Saved and contacted estate agent vs Saved a property                 %.3f\n", cor(df$rank_both,      df$rank_saved)))