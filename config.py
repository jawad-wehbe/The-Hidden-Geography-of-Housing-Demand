##############################################################################
# config.py  -  single place where every data path is rooted (Python twin of config.R)
#
# Imported at the top of every Python script with:
#     import sys
#     from pathlib import Path
#     p = Path(__file__).resolve().parent
#     while not (p / ".here").exists():
#         p = p.parent
#     sys.path.insert(0, str(p))
#     from config import *
#
# Two modes, chosen automatically (same rule as config.R):
#   real run : ~/Desktop/Projects/housing_targets exists
#   demo run : it does not, or the environment variable HOUSING_DEMO is "1"
##############################################################################

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent          # the folder that holds .here

REAL_PROJECT_ROOT = Path("~/Desktop/Projects/housing_targets").expanduser()

USE_DEMO = os.environ.get("HOUSING_DEMO") == "1" or not REAL_PROJECT_ROOT.is_dir()

if USE_DEMO:
    RAW_ROOT      = REPO_ROOT / "demo" / "data" / "Raw_Data"
    PROJECT_ROOT  = REPO_ROOT / "demo" / "data" / "housing_targets"
    SEARCH_ROOT   = REPO_ROOT / "demo" / "data" / "housing_search"
    N_THREADS     = 2
    DUCKDB_MEMORY = "4GB"
    # the search data: folder of raw search inputs and the two DuckDB files
    SEARCH_RAW_DIR      = RAW_ROOT / "search"
    SEARCH_FILTERED_DB  = SEARCH_ROOT / "produced" / "nonbots" / "search_filtered.duckdb"
    SEARCH_PROCESSED_DB = SEARCH_RAW_DIR / "search_processed.duckdb"
else:
    RAW_ROOT      = Path("~/Desktop/Raw_Data").expanduser()
    PROJECT_ROOT  = REAL_PROJECT_ROOT
    SEARCH_ROOT   = Path("~/Desktop/Projects/housing_search").expanduser()
    N_THREADS     = 12
    DUCKDB_MEMORY = "200GB"
    # the real search data are named in config_local.py, which is not distributed:
    # it must define SEARCH_RAW_DIR, SEARCH_FILTERED_DB and SEARCH_PROCESSED_DB
    _config_local = REPO_ROOT / "config_local.py"
    if not _config_local.exists():
        raise FileNotFoundError(f"Real mode needs {_config_local} defining SEARCH_RAW_DIR, SEARCH_FILTERED_DB and SEARCH_PROCESSED_DB")
    exec(_config_local.read_text())

SHAPEFILES_ROOT = RAW_ROOT / "Shapefiles"
DUCKDB_SPILL    = PROJECT_ROOT / "temp" / "duckdb_spill"

print(f"config.py: {'DEMO' if USE_DEMO else 'REAL'} mode\n"
      f"  RAW_ROOT     = {RAW_ROOT}\n"
      f"  PROJECT_ROOT = {PROJECT_ROOT}\n"
      f"  SEARCH_ROOT  = {SEARCH_ROOT}")
