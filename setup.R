# --- ディレクトリの構成を作る（無いものだけ作り、あるものは飛ばす）（README.md「構成」）---

# --- このファイルのあるフォルダ（リポジトリの根）で動く（README.md「構成」）---
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
if (length(script) == 1L) setwd(dirname(normalizePath(script)))

# --- 作るディレクトリ（テンプレートと同じ構成）（README.md「構成」）---
DIRS <- c(
  ".githooks", ".vscode", "R", "configs",
  "data", "data/external", "data/interim", "data/processed", "data/raw", "data/raw/dummy",
  "docs", "docs/definition", "models", "notebooks",
  "outputs/figures", "outputs/metrics", "outputs/reports", "outputs/repro", "outputs/tables",
  "tests/testthat", "tools"
)

# --- 新しく作ったときに .gitkeep を置くディレクトリ（中身を Git で追跡しない骨格）（README.md「構成」）---
KEEP <- c(
  "configs", "data/external", "data/interim", "data/processed", "data/raw", "data/raw/dummy",
  "docs/definition", "models",
  "outputs/figures", "outputs/metrics", "outputs/reports", "outputs/repro", "outputs/tables"
)

# --- 無いディレクトリだけを作り、作ったもの・飛ばしたものを出す（README.md「構成」）---
created <- 0L
for (dir in DIRS) {
  if (dir.exists(dir)) {
    cat(sprintf("[setup] 既にあるので飛ばす: %s\n", dir))
    next
  }
  if (file.exists(dir)) stop(sprintf("%s はディレクトリではないファイルです。名前を変えてから、やり直してください。", dir))
  dir.create(dir, recursive = TRUE)
  if (dir %in% KEEP) file.create(file.path(dir, ".gitkeep"))
  cat(sprintf("[setup] 作った: %s\n", dir))
  created <- created + 1L
}
cat(sprintf("[setup] 作った %d 個・飛ばした %d 個\n", created, length(DIRS) - created))

# --- .env が無ければ .env.example を写す（既にあれば写さない）（REPRODUCIBILITY.md 2 節）---
if (file.exists(".env")) {
  cat("[setup] 既にあるので飛ばす: .env\n")
} else if (file.exists(".env.example")) {
  file.copy(".env.example", ".env")
  cat("[setup] 作った: .env（.env.example を写した。TZ の時刻帯を確かめる）\n")
}
