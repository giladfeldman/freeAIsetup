# MetaScience setup: make R use a working pandoc (pandoc turns R Markdown / Quarto output into HTML).
# Problem it solves: the first "pandoc" on PATH can be broken for this account, for example a
# shortcut to a copy inside ANOTHER user's folder. rmarkdown then stops with
# "invalid version specification". Fix: put Quarto's own pandoc first, for R only, through this
# user's ~/.Renviron. Nothing is changed when the pandoc R finds already works. Safe to run again.
# Usage: Rscript fix_pandoc.R <quarto bin folder>
args <- commandArgs(TRUE)
quarto_bin <- if (length(args)) args[1] else ""

works <- function(p) {
  if (!nzchar(p)) return(FALSE)
  out <- tryCatch(suppressWarnings(system2(p, "--version", stdout = TRUE, stderr = TRUE)),
                  error = function(e) "")
  length(out) > 0 && grepl("^pandoc(\\.exe)? [0-9]", out[1])
}

p <- unname(Sys.which("pandoc"))
if (!nzchar(p)) { cat("OK no pandoc on PATH; Quarto uses its own\n"); quit(status = 0) }
if (works(p))   { cat("OK pandoc works:", p, "\n"); quit(status = 0) }

found <- list.files(file.path(quarto_bin, "tools"), pattern = "^pandoc(\\.exe)?$",
                    recursive = TRUE, full.names = TRUE)
found <- found[vapply(found, works, logical(1))]
if (!length(found)) {
  cat("FAIL the pandoc on PATH is broken (", p, ") and Quarto's own pandoc was not found under ",
      quarto_bin, "\n", sep = "")
  quit(status = 1)
}
dir <- gsub("\\\\", "/", dirname(found[1]))
f <- path.expand("~/.Renviron")
marker <- "# MetaScience setup: R uses Quarto's pandoc (the first pandoc on PATH is broken for this account)"
old <- if (file.exists(f)) readLines(f, warn = FALSE) else character()
if (!any(old == marker)) {
  writeLines(c(old, "", marker, sprintf('PATH="%s%s${PATH}"', dir, .Platform$path.sep)), f)
}
cat("FIXED broken pandoc at ", p, "; R now uses ", found[1], " (line added to ", f, ")\n", sep = "")
