#!/usr/bin/env Rscript
# --- コミット前の検査の本体（CHECKS.md 1 節）---

# --- 警告はその場で出し、文字は UTF-8 として扱う（CHECKS.md 1 節）---
options(warn = 1)
invisible(tryCatch(Sys.setlocale("LC_CTYPE", "C.UTF-8"), warning = function(w) NULL,
                   error = function(e) NULL))

# --- 引数: 中身の場所・作業ツリーの根・対象の一覧（CHECKS.md 1 節）---
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop("使い方: Rscript tools/precommit_checks.R <内容の場所> <作業ツリーの根> <対象の一覧>")
}
content_root <- args[1]
work_root <- args[2]
paths <- readLines(args[3], warn = FALSE, encoding = "UTF-8")
paths <- paths[nzchar(paths)]

# --- 大きさの上限（2 MB）（CHECKS.md 1 節）---
max_bytes <- 2048 * 1024

# --- 秘密鍵の目印（CHECKS.md 1 節）---
key_patterns <- c(
  sprintf("BEGIN %sPRIVATE KEY", c("RSA ", "DSA ", "EC ", "OPENSSH ", "", "ENCRYPTED ", "PGP ",
                                   "SSH2 ENCRYPTED ")),
  paste0("PuTTY-User-Key-", "File-2"),
  paste("BEGIN OpenVPN Static", "key V1")
)

# --- よく知られたトークンの形（CHECKS.md 1 節）---
token_patterns <- c(
  "AWS のアクセスキー" = "(?:A3T[A-Z0-9]|ABIA|ACCA|AKIA|ASIA)[0-9A-Z]{16}",
  "AWS のシークレットキー" =
    "(?i)aws.{0,20}?(?:key|pwd|pw|password|pass|token).{0,20}?['\"][0-9a-zA-Z/+]{40}['\"]",
  "Artifactory のトークン" = "(?m)(?:\\s|=|:|\"|^)AKC[a-zA-Z0-9]{10,}(?:\\s|\"|$)",
  "Artifactory のパスワード" = "(?m)(?:\\s|=|:|\"|^)AP[0-9A-F][a-zA-Z0-9]{8,}(?:\\s|\"|$)",
  "Azure のストレージキー" = "AccountKey=[a-zA-Z0-9+/=]{88}",
  "URL に埋め込んだパスワード" = "://[^:/?#\\[\\]@!$&'()*+,;=\\s]+:[^:/?#\\[\\]@!$&'()*+,;=\\s]+@",
  "Discord のトークン" = "[MNO][a-zA-Z0-9_-]{23,25}\\.[a-zA-Z0-9_-]{6}\\.[a-zA-Z0-9_-]{27}",
  "GitHub のトークン" = "(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{36}|github_pat_[A-Za-z0-9_]{82}",
  "GitLab のトークン" = paste0(
    "(?:(?:glpat|gldt|glft|glsoat|glrt)-[A-Za-z0-9_-]{20,50}|GR1348941[A-Za-z0-9_-]{20,50}|",
    "glcbt-(?:[0-9a-fA-F]{2}_)?[A-Za-z0-9_-]{20,50}|glimt-[A-Za-z0-9_-]{25}|",
    "glptt-[A-Za-z0-9_-]{40}|glagent-[A-Za-z0-9_-]{50,1024}|gloas-[A-Za-z0-9_-]{64})(?!\\w)"
  ),
  "JWT" = "eyJ[A-Za-z0-9_=-]+\\.eyJ[A-Za-z0-9_=-]+",
  "Mailchimp のキー" = "[0-9a-z]{32}-us[0-9]{1,2}",
  "npm のトークン" = "//.+/:_authToken=\\s*(?:npm_.+|[A-Fa-f0-9-]{36})",
  "OpenAI のキー" = "sk-[A-Za-z0-9_-]*[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}",
  "PyPI のトークン" = "pypi-(?:AgEIcHlwaS5vcmc|AgENdGVzdC5weXBpLm9yZw)[A-Za-z0-9_-]{70,}",
  "SendGrid のキー" = "SG\\.[a-zA-Z0-9_-]{22}\\.[a-zA-Z0-9_-]{43}",
  "Slack のトークン" = "(?i)xox(?:a|b|p|o|s|r)-(?:[0-9]+-)+[a-z0-9]+",
  "Slack の Webhook" =
    "https://hooks\\.slack\\.com/services/T[a-zA-Z0-9_]+/B[a-zA-Z0-9_]+/[a-zA-Z0-9_]+",
  "Square のキー" = "sq0csp-[0-9A-Za-z\\\\_-]{43}",
  "Stripe のキー" = "(?:r|s)k_live_[0-9a-zA-Z]{24}",
  "Telegram のトークン" = "(?m)^[0-9]{8,10}:[0-9A-Za-z_-]{35}$",
  "Twilio のキー" = "(?:AC|SK)[a-z0-9]{32}"
)

# --- 秘密情報らしい名前に書いた値（名前 = 値・名前 <- 値・YAML の 名前: 値。名前は引用符や [ ] で囲んでもよい）（CHECKS.md 1 節）---
secret_assignment <- paste0(
  "(?i)(?:^|[^\\w.])[\\w.]*(?:access|api|auth|key|credential|creds|passw(?:or)?d|secret|token)",
  "[\\w.]*[\"']?\\]?\\s*(?:=|<-|:)\\s*[\"']?([\\w.=+/-]{10,150})"
)

# --- 記録の流れを握る関数（REPRODUCIBILITY.md 2 節）---
flow_functions <- c("repro_run", "repro_finish", "repro_fail")

# --- 指摘と、直したものを集める（CHECKS.md 1 節）---
problems <- character(0)
fixed <- character(0)
note <- function(...) assign("problems", c(problems, sprintf(...)), envir = globalenv())

# --- 構文を見るパッケージ（無ければ、その形式の構文を飛ばして知らせる）（CHECKS.md 1 節）---
has_package <- vapply(c("yaml", "jsonlite"), requireNamespace, logical(1), quietly = TRUE)
skipped <- character(0)

# --- ファイルをバイト列のまま読む（CHECKS.md 1 節）---
read_raw <- function(path) readBin(path, what = "raw", n = file.info(path)$size)
# --- NUL が無ければテキストとみなす（CHECKS.md 1 節）---
is_text <- function(raw) !any(raw == as.raw(0L))
# --- エラーの 1 行目だけを取る（CHECKS.md 1 節）---
first_line <- function(message) sub("\n.*$", "", message)

# --- 文字の散らばり（シャノンのエントロピー。1 文字あたりのビット数）（CHECKS.md 1 節）---
entropy <- function(value) {
  counts <- table(strsplit(value, "", fixed = TRUE)[[1]])
  shares <- counts / sum(counts)
  -sum(shares * log2(shares))
}

# --- 秘密情報らしい名前に書いた値を探す（CHECKS.md 1 節）---
secret_values <- function(text, quoted) {
  lines <- strsplit(text, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
  lines <- lines[!grepl("^\\s*#", lines, useBytes = TRUE)]
  pattern <- if (quoted) sub("?([", "([", secret_assignment, fixed = TRUE) else secret_assignment
  found <- regmatches(lines, gregexec(pattern, lines, perl = TRUE, useBytes = TRUE))
  values <- unlist(lapply(found, function(x) if (length(x) > 0L) x[2, ] else character(0)))
  values <- values[!grepl("^[A-Za-z_.-]+$", values)]
  values[vapply(values, entropy, numeric(1)) >= 3.5]
}

# --- 空白だけの行か（CHECKS.md 1 節）---
blank <- function(line, strip_trailing) {
  grepl(if (strip_trailing) "^[ \t\r]*$" else "^\r?$", line, useBytes = TRUE)
}
# --- 行末の空白と末尾の空行を直した中身を作る（CHECKS.md 1 節）---
tidy <- function(text, strip_trailing) {
  lines <- strsplit(text, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
  if (strip_trailing) lines <- sub("[ \t]+$", "", lines, useBytes = TRUE)
  while (length(lines) > 0L && blank(lines[length(lines)], strip_trailing)) {
    lines <- lines[-length(lines)]
  }
  paste0(paste(lines, collapse = "\n"), "\n")
}

# --- ファイルごとに検査する（CHECKS.md 1 節）---
for (path in paths) {
  file <- file.path(content_root, path)
  if (!file.exists(file) || dir.exists(file)) next
  # --- 大きさ（CHECKS.md 1 節）---
  size <- file.info(file)$size
  if (size > max_bytes) {
    note("%s: %.1f MB（上限 2 MB）。データや成果物なら追跡しない（.gitignore を確認）",
         path, size / 1024^2)
    next
  }

  # --- 空のファイルとバイナリは、大きさだけを見る（CHECKS.md 1 節）---
  if (size == 0) next
  raw <- read_raw(file)
  if (!is_text(raw)) next

  # --- 中身を UTF-8 の文字列にする（CHECKS.md 1 節）---
  text <- rawToChar(raw)
  Encoding(text) <- "UTF-8"

  # --- 秘密鍵らしき文字列（CHECKS.md 1 節）---
  hit <- key_patterns[vapply(key_patterns, grepl, logical(1), x = text, fixed = TRUE,
                             useBytes = TRUE)]
  if (length(hit) > 0L) note("%s: 秘密鍵らしき内容があります（%s）", path, hit[1])

  # --- よく知られたトークン（CHECKS.md 1 節）---
  token <- names(token_patterns)[vapply(token_patterns, grepl, logical(1), x = text, perl = TRUE,
                                        useBytes = TRUE)]
  if (length(token) > 0L) {
    note("%s: %sらしき文字列があります。値を消し、そのトークンを無効にしてください（push 済みなら漏れたものとして扱う）",
         path, token[1])
  }

  # --- .Rprofile・.env.example・R のコード・ノートブック・YAML の、秘密情報らしい名前の値（CHECKS.md 1 節）---
  ext <- tolower(tools::file_ext(path))
  code <- basename(path) == ".Rprofile" || ext %in% c("r", "qmd", "rmd")
  if ((code || basename(path) == ".env.example" ||
         ext %in% c("yaml", "yml", "cff")) &&
        length(secret_values(text, quoted = code)) > 0L) {
    note("%s: 秘密情報らしい名前に値が書かれています。値は .env（Git で追跡しない）に書き、R からは readRenviron(\".env\") で読んでください",
         path)
  }

  # --- R・YAML（CITATION.cff を含む）・JSON の構文（CHECKS.md 1 節）---
  if (ext == "r") {
    err <- tryCatch({
      suppressWarnings(parse(text = text, keep.source = FALSE))
      NULL
    }, error = conditionMessage)
    if (!is.null(err)) note("%s: R の構文エラー: %s", path, first_line(err))

    # --- R/ の関数から、記録の流れの関数を呼んでいないか（REPRODUCIBILITY.md 2 節）---
    if (is.null(err) && grepl("^R/[^/]+$", path) && basename(path) != "repro.R") {
      data <- utils::getParseData(parse(text = text, keep.source = TRUE))
      called <- unique(data$text[data$token == "SYMBOL_FUNCTION_CALL" &
                                   data$text %in% flow_functions])
      if (length(called) > 0L) {
        note(paste0("%s: %s を呼んでいます。repro_run()・repro_finish()・repro_fail() は入口",
                    "のノートブックに直接書き、R/ の関数からは呼ばないでください"),
             path, paste0(called, "()", collapse = "・"))
      }
    }
  } else if (ext %in% c("yaml", "yml", "cff") && !has_package[["yaml"]]) {
    skipped <- union(skipped, "YAML（yaml が無い）")
  } else if (ext == "json" && !has_package[["jsonlite"]]) {
    skipped <- union(skipped, "JSON（jsonlite が無い）")
  } else if (ext %in% c("yaml", "yml", "cff")) {
    err <- tryCatch({
      suppressWarnings(yaml::yaml.load(text))
      NULL
    }, error = conditionMessage)
    if (!is.null(err)) note("%s: YAML として読めません: %s", path, first_line(err))
  } else if (ext == "json") {
    err <- tryCatch({
      jsonlite::fromJSON(text, simplifyVector = FALSE)
      NULL
    }, error = conditionMessage)
    if (!is.null(err)) note("%s: JSON として読めません: %s", path, first_line(err))
  }

  # --- 行末の空白と末尾の改行（ステージと同じなら直す）（CHECKS.md 1 節）---
  strip_trailing <- !ext %in% c("md", "csv", "csv2", "csvy", "tsv", "psv", "dat", "fwf")
  wanted <- tidy(text, strip_trailing)
  if (!identical(charToRaw(wanted), raw)) {
    lines <- strsplit(text, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
    what <- if (raw[length(raw)] != as.raw(10L)) {
      "末尾に改行が無い"
    } else if (strip_trailing && any(grepl("[ \t]+$", lines, useBytes = TRUE))) {
      "行末に空白がある"
    } else {
      "末尾の空行が多い"
    }
    work <- file.path(work_root, path)
    same <- file.exists(work) && identical(read_raw(work), raw)
    if (same) {
      writeBin(charToRaw(wanted), work)
      fixed <- c(fixed, sprintf("%s（%s）", path, what))
    } else {
      note("%s: %s。作業ツリーに未ステージの変更があるので直していません", path, what)
    }
  }
}

# --- 直したものと指摘を並べ、あれば止める（CHECKS.md 1 節）---
if (length(skipped) > 0L) {
  cat("[pre-commit] 構文を見ていない形式があります: ", paste(skipped, collapse = "・"), "\n",
      sep = "", file = stderr())
}
if (length(fixed) > 0L) {
  cat("[pre-commit] 直しました（git add してからもう一度 commit してください）:\n", file = stderr())
  for (item in fixed) cat("  - ", item, "\n", sep = "", file = stderr())
}
if (length(problems) > 0L) {
  cat("[pre-commit] 直す必要があります:\n", file = stderr())
  for (item in problems) cat("  - ", item, "\n", sep = "", file = stderr())
}
if (length(fixed) > 0L || length(problems) > 0L) quit(status = 1L)
cat(sprintf("[pre-commit] %d ファイルの検査に通りました\n", length(paths)))
