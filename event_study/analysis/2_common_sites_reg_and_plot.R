library(arrow)
library(dplyr)
library(broom)     
library(tidyr)     
library(stringr)   
library(ggplot2)
library(fixest)


# paths
ed_path <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/analysis/ed_reg_dataset.parquet"
sd_path <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/analysis/sd_reg_dataset.parquet"
fig_dir <- "~/Desktop/Projects/housing_targets/output/figures/ttwa_controls_regression_plots/"

##################################################################################
# VIP: Due to computation constraints given the size of each regression data set: 
# 1- We chose the sites common in both data sets
# 2- We restrict the event window to 44 weeks post treatment
##################################################################################

# load datasets
ed_df <- read_parquet(ed_path)
sd_df <- read_parquet(sd_path)



# Find common construction_site_ids
common_sites <- intersect(
  unique(ed_df$construction_site_id),
  unique(sd_df$construction_site_id)
)

# remove the ed dataset just for ram purposes
rm(ed_df)
gc()

#----------------------------------------------------------------------
# Regression for buying using sd on this filtered sample
#---------------------------------------------------------------------


# filter the buying data
stacked_df <- sd_df %>% filter(construction_site_id %in% common_sites)

rm(sd_df)
gc()

# drop unnecessary weeks

stacked_df <- stacked_df %>% 
  filter(rel_yw <= 44) %>% 
  select(-Treated_52, -Treated_51, -Treated_50, -Treated_49, -Treated_48, -Treated_47, -Treated_45, -Treated_46)


# create log searches and FE identifiers

stacked_df <- stacked_df %>%
  mutate(
    ln_buying_searches  = log(buying_searches),
    ln_letting_searches = log(letting_searches),
    shockweek_id = paste0(construction_site_id, "_", year, "_", week),
    oa_stack_id = paste0(oa_code, "_", construction_site_id)
  ) %>%
  select(-Treated_m5, -treated_today)

# remove things for ram
stacked_df <- stacked_df %>%
  mutate(across(starts_with("Treated_"), as.logical)) %>%
  select(-construction_site_id, -oa_code, -year,-week,-assigned_lsoa,-assigned_msoa,-assigned_la,-assigned_ttwa, -Group)

gc()

# drop more columns not needed

stacked_df <-stacked_df %>%
  select(-buying_searches, -letting_searches, -site_size, -rel_yw, -ln_letting_searches)

gc()

# count the rows

cat("Buying regression rows (stacked_df):", nrow(stacked_df), "\n")

# Dummy names
treat_vars <- stacked_df %>% select(starts_with("Treated_")) %>% names()

# Formulas for each outcome
fml_buying  <- as.formula(paste0("ln_buying_searches ~ ", paste(treat_vars, collapse = " + "), " | oa_stack_id + shockweek_id"))


# Run Regressions 
buying_res  <- feols(fml_buying,  data = stacked_df, cluster = ~oa_stack_id)

# tidy results
buying_tidy <- tidy(buying_res) %>%
  filter(str_detect(term, "^Treated_")) %>%
  select(term, estimate, std.error)

# release ram

rm(buying_res)
gc()

# cleaning names and creating relative week

buying_tidy <- buying_tidy %>%
  mutate(
    # Remove 'Treated_' and any trailing TRUE/FALSE
    term_clean = str_remove_all(term, "Treated_|TRUE|FALSE"),
    # If it starts with 'm', make it negative
    rel_week = case_when(
      str_detect(term_clean, "^m") ~ -as.integer(str_remove(term_clean, "^m")),
      TRUE ~ as.integer(term_clean)
    ),
    se = std.error,
    search_type = "buying"
  ) %>%
  select(rel_week, estimate, se, search_type) %>%
  arrange(rel_week)


# Calculate CI columns 
results <- buying_tidy %>%
  mutate(
    estimate = estimate * 100,
    se = se * 100,
    lower = estimate - 1.96 * se,
    upper = estimate + 1.96 * se
  )

# Create a reference row for week -5
ref_row <- tibble(
  rel_week = -5,
  estimate = 0,
  se = 0,
  lower = 0,
  upper = 0,
  search_type = "buying"
)

# Bind the new row to your existing results
results <- bind_rows(results, ref_row)


# Plot Buying
buying_plot <- ggplot(
  results %>% filter(search_type == "buying"),
  aes(x = rel_week, y = estimate)
) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
  geom_line(color = "#08306B", size = 1.2) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "black", size = 1) +
  annotate(
    "text", 
    x = 0, 
    y = max_y + 0.05,      # Small buffer above the plot line
    label = "Construction start week of first plot",
    vjust = 0,             # Align bottom of text to y
    size = 5              # Adjust text size as you wish
  ) +
  labs(
    x = "Weeks",
    y = "Percent change in searches (%)"
  ) +
  scale_x_continuous(
    breaks = sort(unique(c(-26, -5, 0, seq(-20, 40, by = 5), 44)))
  ) +
  scale_y_continuous(
    breaks = seq(-1, 1.8, by = 0.2)  
  ) +
  theme_bw(base_size = 17) +
  theme(
    plot.title = element_text(face = "bold", size = 21, hjust = 0.5),
    axis.title.x = element_text(face = "bold", size = 15),
    axis.title.y = element_text(face = "bold", size = 15),
    axis.text.x = element_text(face = "bold", size = 16),
    axis.text.y = element_text(face = "bold", size = 16),
    axis.line = element_line(size = 1.3, color = "black"),
    axis.ticks = element_line(size = 1.3, color = "black"),
    panel.grid = element_blank()
  )

print(buying_plot)

#  Buying plot
ggsave(
  filename = file.path(fig_dir, "sd_filtered_pooled_buying.png"),
  plot = buying_plot,
  width = 8, height = 6, dpi = 320
)
