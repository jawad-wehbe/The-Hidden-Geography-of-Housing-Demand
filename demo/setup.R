##############################################################################
# DEMO SETUP: installs everything the pipeline needs, from inside R.
#
# Open hidden_geography_of_housing_demand.Rproj in RStudio (so the working directory is the
# repository root), then in the console:
#   source("demo/setup.R")
#
# Installs the R packages (demo/install_packages.R) and the Python packages
# (demo/requirements.txt) into the Python found on this machine. Python itself
# (3.10 or later, from python.org) has to be installed beforehand.
#
# Works on Windows, macOS and Linux. The Python search below is more careful than
# a plain Sys.which() because of Windows (Store alias, installs off the PATH);
# the extra folder search only runs there. Exercised on Windows and Ubuntu.
##############################################################################

############
# R packages
############

source(file.path("demo", "install_packages.R"))

############
# Python packages
############

# Find a working Python 3.10+. Sys.which() alone is not enough on Windows: the
# Store alias python.exe is on the PATH but only prints "Python was not found",
# while a real install from python.org often is not on the PATH at all. So every
# candidate is run with --version and the first one that answers is used.
# To force a particular interpreter, set python_path <- "C:/.../python.exe" before sourcing.

py_version <- function(exe, pre = character(0)) {
  out <- tryCatch(suppressWarnings(system2(exe, c(pre, "--version"), stdout = TRUE, stderr = TRUE)),
                  error = function(e) character(0))
  if (length(out) == 0 || is.null(attr(out, "status")) == FALSE && attr(out, "status") != 0) return(NA)
  v <- regmatches(out[1], regexpr("3\\.[0-9]+", out[1]))
  if (length(v) == 0) NA else as.numeric(sub("3\\.", "", v))
}

candidates <- character(0)
if (exists("python_path")) candidates <- python_path
candidates <- c(candidates, Sys.which(c("python3", "python", "py")))
path_dirs  <- strsplit(Sys.getenv("PATH"), .Platform$path.sep)[[1]]          # every PATH folder, not just the first hit
candidates <- c(candidates, as.vector(outer(path_dirs, c("python3", "python", "python3.exe", "python.exe"), file.path)))
if (.Platform$OS.type == "windows") {
  roots <- c(Sys.getenv("LOCALAPPDATA"), Sys.getenv("PROGRAMFILES"), "C:/", Sys.getenv("USERPROFILE"))
  candidates <- c(candidates,
    Sys.glob(file.path(roots[1], "Programs/Python/Python3*/python.exe")),
    Sys.glob(file.path(roots[2], "Python3*/python.exe")),
    Sys.glob("C:/Python3*/python.exe"),
    Sys.glob(file.path(roots[4], c("anaconda3", "miniconda3", "miniforge3"), "python.exe")),
    Sys.glob(file.path(roots[1], "Python/pythoncore-3*/python.exe")))
}
candidates <- unique(candidates[candidates != "" & file.exists(candidates)])

python <- NA; py_pre <- character(0)
for (cand in candidates) {
  pre <- if (basename(cand) %in% c("py", "py.exe")) "-3" else character(0)
  v <- py_version(cand, pre)
  if (!is.na(v) && v >= 10) { python <- cand; py_pre <- pre; break }
}

if (is.na(python)) {
  stop("No working Python 3.10 or later was found. Install it from https://www.python.org/downloads/ ",
       "(on Windows tick 'Add python.exe to PATH'), restart RStudio and run source('demo/setup.R') again. ",
       "If Python is installed somewhere unusual, run  python_path <- \"full path to python.exe\"  first.")
}

cat("Using Python at", python, "\n")
status <- system2(python, c(py_pre, "-m", "pip", "install", "-r", file.path("demo", "requirements.txt")))

if (status != 0) stop("pip returned an error (see above)")
cat("Setup complete.\n")
