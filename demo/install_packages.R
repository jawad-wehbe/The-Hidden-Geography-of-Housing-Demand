##############################################################################
# Installs every R package the pipeline and the demo generators use.
# Run once:  Rscript demo/install_packages.R
# Versions listed in demo/README.md are the ones the demo was tested with;
# current CRAN versions are expected to work.
##############################################################################

packages <- c(
  # data handling
  "here", "dplyr", "tidyr", "readr", "stringr", "purrr", "tibble", "tidyverse", "lubridate",
  "ISOweek", "janitor", "glue", "zoo", "haven", "data.table",
  # files and databases
  "arrow", "duckdb", "DBI",
  # spatial
  "sf", "lwgeom", "stars", "units", "osmdata", "osmextract", "maptiles", "mapview",
  "ncdf4", "ncmeta",
  # regressions and tables
  "fixest", "broom", "multcomp", "survival", "penppml", "knitr",
  # figures and maps
  "ggplot2", "ggrepel", "ggspatial", "ggmap", "patchwork", "scales", "viridis", "RColorBrewer",
  "tmap", "leaflet", "prettymapr", "png", "htmlwidgets", "webshot",
  # parallelism
  "future", "future.apply", "furrr", "future.callr", "progressr"
)

missing <- packages[!packages %in% rownames(installed.packages())]

if (length(missing) == 0) {
  cat("All packages already installed.\n")
} else {
  cat("Installing:", paste(missing, collapse = ", "), "\n")
  install.packages(missing, repos = "https://cloud.r-project.org")
}

still_missing <- packages[!packages %in% rownames(installed.packages())]
if (length(still_missing) > 0) {
  cat("Could not install:", paste(still_missing, collapse = ", "), "\n")
} else {
  cat("Done.\n")
}
