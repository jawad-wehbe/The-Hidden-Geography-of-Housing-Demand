library(readr)
library(dplyr)
library(ggplot2)

############
# Paths
############

results_dir <- "/home/jawad/Desktop/Projects/housing_targets/produced/nature/nonbots/regression_results/"

fig_dir <- "/home/jawad/Desktop/Projects/housing_targets/output/figures/nature/nonbots/"

# y-axis labels keyed by spec name (nm), matching the original specs tables
ylab_lookup <- c(
  log_search = "% change in searches\n per 100m² greenspace",
  ihs_trans  = "% change in transactions\n per 100m² greenspace",
  log_price  = "% change in price\n per 100m² greenspace"
)

# the specs that were actually run (uncommented) in each frequency
spec_names <- c("log_search", "ihs_trans", "log_price")

# shared theme (your requested configuration)
es_theme <- theme_classic() +
  theme(
    plot.title   = element_text(face = "bold", size = 21, hjust = 0.5),
    axis.title.x = element_text(face = "bold", size = 30),
    axis.title.y = element_text(face = "bold", size = 28),
    axis.text.x  = element_text(face = "bold", size = 34),
    axis.text.y  = element_text(face = "bold", size = 34),
    axis.line    = element_line(size = 1.3, color = "black"),
    axis.ticks   = element_line(size = 1.3, color = "black"),
    panel.grid   = element_blank()
  )

# per-frequency configuration
freq_config <- list(
  weekly = list(
    relcol   = "rel_week",
    xlab     = "Weeks",
    breaks   = seq(-60, 201, by = 20),
    infile   = function(nm) paste0("greenspace_weekly_",  nm, "_eventstudy.csv"),
    outfile  = function(nm) paste0("greenspace_weekly_",  nm, "_oafe_ttwaxywfe_lsoaxweekfe.png")
  ),
  monthly = list(
    relcol   = "rel_month",
    xlab     = "Months",
    breaks   = seq(-12, 46, by = 4),
    infile   = function(nm) paste0("greenspace_monthly_", nm, "_eventstudy.csv"),
    outfile  = function(nm) paste0("greenspace_monthly_", nm, "_oafe_ttwaxymfe_lsoaxmonthfe.png")
  )
)

################################################################
# read results back in and re-plot
################################################################

for (freq in names(freq_config)) {
  
  cfg    <- freq_config[[freq]]
  relcol <- cfg$relcol
  
  for (nm in spec_names) {
    
    fpath <- file.path(results_dir, cfg$infile(nm))
    
    if (!file.exists(fpath)) {
      message("Skipping (not found): ", fpath)
      next
    }
    
    ylab <- ylab_lookup[[nm]]
    
    # read the saved estimates (no reference row) and add it back at rel = -1
    ev <- read_csv(fpath, show_col_types = FALSE)
    
    ref_row <- tibble(
      !!relcol := -1,
      estimate = 0, lower = 0, upper = 0,
      transform = nm
    )
    
    df_nm <- bind_rows(ev, ref_row) %>% arrange(.data[[relcol]])
    
    # plot
    p <- ggplot(df_nm, aes(x = .data[[relcol]], y = estimate)) +
      geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
      geom_line(color = "#08306B", linewidth = 1.2) +
      geom_vline(xintercept = 0, linetype = "dashed", linewidth = 1) +
      geom_hline(yintercept = 0, linetype = "dashed", linewidth = 1) +
      labs(x = cfg$xlab, y = ylab) +
      scale_x_continuous(breaks = cfg$breaks) +
      es_theme
    
    print(p)
    
    ggsave(
      filename = file.path(fig_dir, cfg$outfile(nm)),
      plot = p, width = 18, height = 7, units = "in", dpi = 300
    )
    
    message("Saved: ", cfg$outfile(nm))
  }
}

