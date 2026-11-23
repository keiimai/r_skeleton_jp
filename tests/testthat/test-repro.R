# --- 記録層のテスト（REPRODUCIBILITY.md 2 節）---

# --- 乱数種を固定すると sample.kind と normal.kind も戻る（REPRODUCIBILITY.md 2 節）---
test_that("repro_set_seed が RNGkind の sample.kind と normal.kind まで固定する", {
  repro_set_seed(42L)
  first_sample <- sample.int(1000L, 5L)
  first_normal <- stats::rnorm(3L)
  suppressWarnings(RNGkind(sample.kind = "Rounding", normal.kind = "Box-Muller"))
  repro_set_seed(42L)
  expect_identical(sample.int(1000L, 5L), first_sample)
  expect_identical(stats::rnorm(3L), first_normal)
  expect_equal(RNGkind()[2], "Inversion")
})

# --- 環境のスナップショットにスレッド数・時間帯・ロケールなどが入る（REPRODUCIBILITY.md 2 節）---
test_that("環境スナップショットが決定性に関わる変数を記録し、renv.lock が無ければその SHA-256 は NA", {
  snapshot <- repro_environment_snapshot()
  expect_named(snapshot$env, c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
                               "TZ", "LANG", "LC_ALL"))
  expect_true(is.na(snapshot$renv_lock_sha256))
  expect_length(snapshot$rng$kind, 3L)
  versions <- unlist(snapshot[c("r_version", "blas", "lapack", "lapack_version")])
  expect_length(Filter(nzchar, versions), 4L)
})

# --- イメージの中では、ビルドの記録を取り込む（REPRODUCIBILITY.md 2 節）---
test_that("イメージの中では、環境スナップショットがビルドの記録をそのまま取り込む", {
  skip_if_not(file.exists("/opt/build-info.json"), "イメージの外（ビルドの記録が無い）")
  expect_identical(repro_environment_snapshot()$build_info,
                   jsonlite::read_json("/opt/build-info.json"))
})

# --- 書かれていないキーは既定値になり、知らないキーと null は残る（REPRODUCIBILITY.md 2 節）---
test_that("書かれていないキーは既定値に落ち、記録層が知らないキーと null で上書きしたキーは消えない", {
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(c("seed: 7", "analysis:", "  outcome: death", "  models: [a, b]",
               "repro:", "  quiet: null"), path)
  cfg <- repro_config_load(path)
  expect_equal(cfg[c("seed", "experiment_name")], list(seed = 7L, experiment_name = "default"))
  expect_equal(cfg$analysis, list(outcome = "death", models = c("a", "b")))
  expect_equal(cfg$repro, list(enabled = TRUE, quiet = NULL))
  writeLines("", path)
  expect_identical(repro_config_load(path), repro_config_defaults())
})

# --- 整数でない種は読み込みで止める（REPRODUCIBILITY.md 2 節）---
test_that("seed は整数でなければ（大きすぎても）読み込みで止まり、42.0 は整数として読む", {
  path <- withr::local_tempfile(fileext = ".yaml")
  for (line in c("seed: 1.5", "seed: \"42\"", "seed: null", "seed: 3000000000.0")) {
    writeLines(line, path)
    expect_error(repro_config_load(path), "の seed は整数にしてください", fixed = TRUE, info = line)
  }
  writeLines("seed: 42.0", path)
  expect_identical(repro_config_load(path)$seed, 42L)
})

# --- 論理値になる語は、引用符が無ければキーでも値でも止め、ほかは読む（REPRODUCIBILITY.md 4 節）---
test_that("論理値になる語の引用符の無いキーと値は止まり、true・false・引用符付き・日本語・1.0e-6 は読め、1e-6 は警告する", {
  path <- withr::local_tempfile(fileext = ".yaml")
  stops <- list("n: 5", c("analysis:", "  on: 1"), c("No: 1", "OFF: 2"),
                "yname: y", "flag: yes", "mode: Off", "answer: N")
  for (lines in stops) {
    writeLines(lines, path)
    expect_error(repro_read_yaml(path), "引用符の無い", fixed = TRUE,
                 info = paste(lines, collapse = " / "))
  }
  writeLines(c("analysis:", "  True: 1"), path)
  expect_error(repro_read_yaml(path), "キーに y・n・yes・no・on・off・true・false", fixed = TRUE)
  writeLines("a: [1, 2", path)
  expect_error(repro_read_yaml(path))
  writeLines(enc2utf8(c("yname: \"y\"", "on_off: true", "other: False", "\"n\": 5", "tol: 1.0e-6",
                        "label: 死亡")), path, useBytes = TRUE)
  expect_identical(repro_read_yaml(path), list(yname = "y", on_off = TRUE, other = FALSE, n = 5L,
                                               tol = 1e-6, label = enc2utf8("死亡")))
  writeLines(c("a: 1e-6", "b: \"2E3\""), path)
  expect_warning(read <- repro_read_yaml(path), "1e-6・2E3 は、YAML では数ではなく文字", fixed = TRUE)
  expect_identical(read, list(a = "1e-6", b = "2E3"))
})

# --- テスト用の空のプロジェクトを一時ディレクトリに作る（REPRODUCIBILITY.md 2 節）---
local_repro_project <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", .local_envir = env)
  withr::local_dir(root, .local_envir = env)
  cfg <- repro_config_defaults()
  cfg$experiment_name <- "unit"
  cfg$repro$quiet <- TRUE
  cfg
}

# --- 記録 JSON が 1 つ残り、始めた時点から各欄と設定が入り、設定全体を読み直せ、無い入力は警告して null で残る（REPRODUCIBILITY.md 2 節）---
test_that("記録 JSON が 1 つ残り、始めた時点から各欄と設定が入り、設定全体を読み直せ、無い入力は警告して null で残り、フォルダは止まり、quiet なら表示しない", {
  cfg <- local_repro_project()
  expect_error(repro_run(cfg, inputs = "."), "はフォルダです", fixed = TRUE)
  cfg$analysis <- list(label = "死亡", models = c("a", "b"), alpha = 0.123456789012)
  input <- "input.csv"
  writeLines(c("a,b", "1,2"), input)
  expect_no_message(expect_warning(state <- repro_run(cfg, inputs = c(input, "missing.csv")),
                                   "missing.csv", fixed = TRUE))
  running <- jsonlite::fromJSON(state$meta_path, simplifyVector = FALSE)
  repro_finish(state)

  payload <- jsonlite::fromJSON(state$meta_path, simplifyVector = FALSE)
  expect_equal(c(running$status, payload$status), c("running", "success"))
  expect_equal(c(running$schema_version, payload$schema_version), c(1L, 1L))
  expect_equal(payload$inputs[[1]]$path, input)
  expect_equal(nchar(payload$inputs[[1]]$sha256), 64L)
  expect_null(payload$inputs[[2]]$sha256)
  expect_equal(payload[c("run_id", "data_mode", "seed", "git_commit", "git_dirty")],
               list(run_id = state$run_id, data_mode = "dummy", seed = 42L, git_commit = NULL,
                    git_dirty = NULL))
  stable <- c("run_id", "seed", "data_mode", "git_commit", "git_dirty", "inputs", "environment")
  expect_equal(running[stable], payload[stable])
  expect_null(running$finished_at)
  expect_match(payload$started_at, "[+-][0-9]{4}$")
  expect_match(payload$finished_at, "[+-][0-9]{4}$")
  expect_true(nzchar(payload$environment$r_version))
  expect_setequal(list.files("outputs/repro", recursive = TRUE),
                  file.path(state$run_id, paste0(state$run_id, c("_run.json", ".config.yaml"))))
  config <- file.path("outputs/repro", state$run_id, paste0(state$run_id, ".config.yaml"))
  expect_equal(c(running$config, payload$config), c(config, config))
  expect_identical(repro_config_load(config), cfg)
})

# --- 成果物の SHA-256 と大きさ。無いものは警告して外し、渡していないものは載らない（REPRODUCIBILITY.md 2 節）---
test_that("成果物はパスごとに SHA-256 と大きさが残り、無いファイルとフォルダは警告して外し、読んでいないファイルは載らず、実行 ID の無い名前は警告する", {
  cfg <- local_repro_project()
  state <- repro_run(cfg)
  output <- paste0("outputs/tables/", state$run_id, "_t.csv")
  writeLines(c("a,b", "1,2"), output)
  state$artifacts <- c(output, "outputs/tables/missing.csv", "outputs/tables")
  expect_warning(repro_finish(state), "outputs/tables/missing.csv・outputs/tables", fixed = TRUE)

  payload <- jsonlite::fromJSON(state$meta_path, simplifyVector = FALSE)
  expect_length(payload$inputs, 0L)
  expect_equal(payload$artifacts, list(list(
    path = output, sha256 = digest::digest(output, algo = "sha256", file = TRUE),
    bytes = file.info(output)$size
  )))
  expect_equal(suppressMessages(repro_runs())$n_artifacts, 1L)
  state$artifacts <- output
  expect_no_warning(repro_finish(state))
  state$artifacts <- "outputs/tables/t.csv"
  file.copy(output, state$artifacts)
  expect_warning(repro_finish(state), "実行 ID が付いていません", fixed = TRUE)
})

# --- 描画が失敗した記録は failed になり、その実行 ID の途中の成果物は partial/ に移る（REPRODUCIBILITY.md 2 節）---
test_that("失敗した描画の記録は failed になり、実行 ID の付いた途中の成果物だけが partial/ に移る", {
  cfg <- local_repro_project()
  state <- repro_run(cfg)
  id <- state$run_id
  dir.create(file.path("outputs/figures", id))
  made <- c(paste0("outputs/tables/", id, "_t.csv"), file.path("outputs/figures", id, "a.txt"))
  for (file in c(made, "outputs/tables/other.csv")) writeLines("x", file)
  .repro_mark_failed(id)
  record <- jsonlite::read_json(state$meta_path)
  expect_identical(record$status, "failed")
  expect_match(record$error, "途中の成果物 2 件を partial/ に移した", fixed = TRUE)
  partial <- file.path(dirname(state$meta_path), "partial")
  expect_true(all(file.exists(file.path(partial, sub("^outputs/", "", made)))))
  expect_true(file.exists("outputs/tables/other.csv"))
})

# --- success で終えた後の描画の失敗も failed にし、移すものが無ければ変えない（REPRODUCIBILITY.md 2 節）---
test_that("success の記録も描画が落ちれば failed（終わりの時刻は残す）。二度目と記録の無い ID では変えない", {
  cfg <- local_repro_project()
  state <- repro_run(cfg)
  repro_finish(state)
  finished <- jsonlite::read_json(state$meta_path)$finished_at
  .repro_mark_failed(state$run_id)
  record <- jsonlite::read_json(state$meta_path)
  expect_identical(record[c("status", "error", "finished_at")],
                   list(status = "failed", error = "repro_render() が失敗した（HTML は無い）",
                        finished_at = finished))
  before <- readLines(state$meta_path)
  .repro_mark_failed(state$run_id)
  expect_identical(readLines(state$meta_path), before)
  expect_null(.repro_mark_failed("no_such_run"))
})

# --- 数値は丸めずに書く（REPRODUCIBILITY.md 2 節）---
test_that("記録と台帳の数値は、小さな値も桁の多い値も丸まらない", {
  cfg <- local_repro_project()
  state <- repro_run(cfg)
  state$ledger <- list(p_value = 1.2e-5, estimate = 4.37382441673398)
  repro_finish(state)
  payload <- jsonlite::fromJSON(state$meta_path, simplifyVector = FALSE)
  expect_equal(payload$ledger$estimate, 4.37382441673398)
  expect_equal(suppressMessages(repro_runs())$p_value, 1.2e-5)
})

# --- run_id の作り方（描画中は .qmd 名）と REPRO_RUN_ID の扱い（既にある記録には重ねない）。時刻は TZ（REPRODUCIBILITY.md 2 節）---
test_that("run_id は <日時>_<名前>_<4 桁>。R の乱数を変えず、記録があれば引き直し、REPRO_RUN_ID は記録が無ければ優先する", {
  cfg <- local_repro_project()
  withr::local_envvar(REPRO_RUN_ID = NA)
  withr::local_envvar(TZ = NA)
  expect_match(.repro_timestamp(), "[+]0900$")
  repro_set_seed(42L)
  expected <- stats::runif(3L)
  repro_set_seed(42L)
  first <- repro_run(cfg)
  second <- repro_run(cfg)
  expect_identical(stats::runif(3L), expected)
  repro_finish(first)
  repro_finish(second)
  expect_match(first$run_id, "^[0-9]{8}_[0-9]{6}_unit_[0-9]{4}$")
  expect_false(identical(first$run_id, second$run_id))
  for (name in list(NULL, "", "a/b", c("a", "b"))) {
    expect_error(repro_run(modifyList(cfg, list(experiment_name = name), keep.null = TRUE)),
                 "/ を含まない 1 つの名前", fixed = TRUE)
  }
  expect_length(Sys.glob("outputs/repro/*/*_run.json"), 2L)
  writeLines(c("```{r}", "writeLines(repro_finish(repro_run(cfg))$run_id, 'id.txt')", "```"),
             "step_a.Rmd")
  knitr::knit("step_a.Rmd", quiet = TRUE, envir = environment())
  expect_match(readLines("id.txt"), "^[0-9]{8}_[0-9]{6}_step_a_[0-9]{4}$")
  withr::local_envvar(REPRO_RUN_ID = "given_run")
  state <- repro_run(cfg)
  repro_finish(state)
  expect_equal(state$run_id, "given_run")
  expect_true(file.exists("outputs/repro/given_run/given_run_run.json"))
  expect_error(repro_run(cfg), "REPRO_RUN_ID=given_run の記録が既にあります", fixed = TRUE)
  withr::local_envvar(REPRO_RUN_ID = "a/b")
  expect_error(repro_run(cfg), "REPRO_RUN_ID は、記録のファイル名の頭に使うので", fixed = TRUE)
  frozen <- as.POSIXct("2026-09-26 09:30:00", tz = "Asia/Tokyo")
  pid <- 0L
  list2env(list(Sys.time = function() frozen, Sys.getpid = function() pid <<- pid + 1L),
           globalenv())
  withr::defer(rm("Sys.time", "Sys.getpid", envir = globalenv()))
  dir.create("outputs/repro/20260926_093000_unit_0001")
  file.create("outputs/repro/20260926_093000_unit_0001/20260926_093000_unit_0001_run.json")
  expect_equal(.repro_new_run_id("unit", "outputs/repro"), "20260926_093000_unit_0002")
  withr::local_envvar(TZ = "UTC")
  expect_equal(.repro_timestamp(), "2026-09-26T00:30:00+0000")
  expect_equal(.repro_new_run_id("unit", "outputs/repro"), "20260926_003000_unit_0003")
  withr::local_envvar(TZ = "JST-9")
  expect_error(.repro_timestamp(), "TZ=JST-9 は時刻帯の名前ではありません", fixed = TRUE)
})

# --- 時刻帯は .env の TZ → 環境変数 TZ → Asia/Tokyo の順で、記録の環境にも使った時刻帯が残る（REPRODUCIBILITY.md 2 節）---
test_that("時刻帯は .env の TZ を環境変数 TZ より先に使い、空なら環境変数、どちらも無ければ Asia/Tokyo", {
  local_repro_project()
  withr::local_envvar(TZ = "UTC")
  expect_equal(.repro_tz(), "UTC")
  writeLines(c("# 注", "OMP_NUM_THREADS=1", "TZ = \"America/New_York\"  # 途中で変えない"), ".env")
  expect_equal(.repro_tz(), "America/New_York")
  expect_equal(repro_environment_snapshot()$env$TZ, "America/New_York")
  writeLines("TZ=", ".env")
  expect_equal(.repro_tz(), "UTC")
  withr::local_envvar(TZ = NA)
  expect_equal(.repro_tz(), "Asia/Tokyo")
  writeLines("TZ=JST-9", ".env")
  expect_error(.repro_timestamp(), "TZ=JST-9 は時刻帯の名前ではありません", fixed = TRUE)
})

# --- 記録を取るノートブックで knitr の cache を使うと、記録を書かずに止める（notebooks/README.md）---
test_that("knitr の cache を（全体でもチャンクごとでも）使うと、repro_run は記録を書かずに止まる", {
  cfg <- local_repro_project()
  withr::defer(knitr::opts_chunk$set(cache = FALSE))
  heads <- list(c("```{r, include=FALSE}", "knitr::opts_chunk$set(cache = TRUE)", "```"),
                c("```{r first, cache=TRUE}", "x <- 1", "```"))
  for (head in heads) {
    writeLines(c(head, "```{r, error=FALSE, cache=FALSE}", "repro_run(cfg)", "```"), "cached.Rmd")
    expect_error(suppressMessages(knitr::knit("cached.Rmd", quiet = TRUE, envir = environment())),
                 "knitr の cache を使わないでください", fixed = TRUE)
  }
  expect_false(dir.exists("outputs/repro"))
})

# --- quiet でなければ、始めと終わりに実行 ID などを出す（REPRODUCIBILITY.md 2 節）---
test_that("quiet でなければ、repro_run は実行 ID と種を、repro_finish は結果を出す", {
  cfg <- local_repro_project()
  cfg$repro$quiet <- FALSE
  expect_message(state <- repro_run(cfg), "data_mode=dummy seed=42", fixed = TRUE)
  expect_output(repro_finish(state), paste0(state$run_id, " (success)"), fixed = TRUE)
})

# --- スレッド数が 1 でなければ警告する（REPRODUCIBILITY.md 4 節）---
test_that("スレッド数が 1 でなければ repro_run が名前と値を添えて警告し、すべて 1 なら何も言わない", {
  cfg <- local_repro_project()
  expect_no_warning(repro_finish(repro_run(cfg)))
  withr::local_envvar(OMP_NUM_THREADS = "4", OPENBLAS_NUM_THREADS = NA)
  expect_warning(state <- repro_run(cfg),
                 "OMP_NUM_THREADS=4・OPENBLAS_NUM_THREADS=(未設定)", fixed = TRUE)
  repro_finish(state)
})

# --- 記録が無ければ案内し、meta/ は読まず、台帳のファイルは絞らずに決まった列の順で BOM 付きで書き、終わっていない記録の数を出す（REPRODUCIBILITY.md 3 節）---
test_that("記録が無ければ案内し、meta/ の前の形は読まず、実験名や件数で絞っても runs.csv には全件が決まった列の順で BOM 付きで残り、終わっていない記録の数を出す", {
  cfg <- local_repro_project()
  expect_output(suppressMessages(repro_runs(show = TRUE)), "実行記録がありません", fixed = TRUE)
  repro_finish(repro_run(cfg))
  cfg$experiment_name <- "other"
  repro_finish(repro_run(cfg))
  dir.create("outputs/repro/meta")
  file.copy(Sys.glob("outputs/repro/*/*_run.json"), "outputs/repro/meta")
  ledger <- repro_settings()$ledger_path
  read_ledger <- function() utils::read.csv(ledger, fileEncoding = "UTF-8-BOM")
  expect_equal(suppressMessages(repro_runs(experiment = "other"))$experiment, "other")
  expect_identical(readBin(ledger, "raw", 3L), as.raw(c(0xef, 0xbb, 0xbf)))
  expect_equal(nrow(read_ledger()), 2L)
  expect_named(read_ledger(),
               c("run_id", "status", "experiment", "data_mode", "seed", "started_at", "finished_at",
                 "git_commit", "git_dirty", "n_inputs", "n_artifacts", "error"))
  expect_equal(nrow(suppressMessages(repro_runs(limit = 1L))), 1L)
  expect_equal(nrow(read_ledger()), 2L)
  expect_equal(nrow(suppressMessages(repro_runs(experiment = "", limit = ""))), 2L)
  repro_run(cfg)
  expect_output(suppressMessages(repro_runs(show = TRUE)), "status = running）が 1 件", fixed = TRUE)
})

# --- 台帳は新しい順で、コミットは 12 字。壊れた記録で止め、絞って 0 件なら案内する（REPRODUCIBILITY.md 3 節）---
test_that("台帳は新しい順に並び、git_commit は 12 字。壊れた記録で止まり、絞って 0 件なら案内する", {
  cfg <- local_repro_project()
  old <- repro_run(cfg)
  repro_finish(old)
  new <- repro_run(cfg)
  repro_finish(new)
  record <- jsonlite::read_json(old$meta_path)
  record$started_at <- "2000-01-01T00:00:00+0900"
  record$git_commit <- strrep("a", 40L)
  jsonlite::write_json(record, old$meta_path, auto_unbox = TRUE, null = "null")
  table <- suppressMessages(repro_runs())
  expect_equal(table$run_id, c(new$run_id, old$run_id))
  expect_equal(table$git_commit[2], strrep("a", 12L))
  expect_output(suppressMessages(repro_runs(experiment = "none", show = TRUE)),
                "実験名 none の実行記録はありません", fixed = TRUE)
  dir.create("outputs/repro/broken")
  writeLines("{", "outputs/repro/broken/broken_run.json")
  expect_error(suppressMessages(repro_runs()), "broken_run.json を読めません", fixed = TRUE)
})

# --- CSV は BOM 付きの UTF-8 で書き、日本語も読み直せる。repro_smoke() の成果物も同じ（REPRODUCIBILITY.md 4 節）---
test_that("repro_write_csv は BOM 付きの UTF-8 で書き、日本語と NA を読み直せ、repro_smoke() の成果物も BOM 付き", {
  local_repro_project()
  bom <- as.raw(c(0xef, 0xbb, 0xbf))
  table <- data.frame(label = c(enc2utf8("死亡"), "a,\"b\""), n = c(1L, NA))
  repro_write_csv(table, "t.csv", na = "")
  bytes <- readBin("t.csv", "raw", file.info("t.csv")$size)
  expect_identical(bytes[1:3], bom)
  expect_true(validUTF8(rawToChar(bytes[-(1:3)])))
  expect_equal(utils::read.csv("t.csv", fileEncoding = "UTF-8-BOM"), table)
  expect_output(suppressMessages(repro_smoke()), "_smoke.csv", fixed = TRUE)
  output <- Sys.glob("outputs/tables/*_smoke.csv")
  expect_length(output, 1L)
  expect_identical(readBin(output, "raw", 3L), bom)
  expect_named(utils::read.csv(output, fileEncoding = "UTF-8-BOM"), c("x", "y"))
})

# --- CSV の書き出しは、決めてある引数を受け付けず、書く前に止まる（REPRODUCIBILITY.md 4 節）---
test_that("repro_write_csv は sep・qmethod・row.names・append を受け付けず、ファイルを作らない", {
  local_repro_project()
  table <- data.frame(x = 1)
  expect_error(repro_write_csv(table, "t.csv", row.names = TRUE), "row.names は渡せません")
  expect_error(repro_write_csv(table, "t.csv", sep = ";", append = TRUE), "sep・append は渡せません")
  expect_false(file.exists("t.csv"))
})

# --- 失敗した実行も台帳に残り（理由は条件でも文字でもよい）、台帳の値は共通列を上書きしない（REPRODUCIBILITY.md 3 節）---
test_that("失敗した実行も status=failed で台帳に残り（理由は条件でも文字でもよい）、台帳の値は共通列を上書きできない", {
  cfg <- local_repro_project()
  state <- repro_run(cfg)
  state$ledger <- list(status = "looks fine", n_analysis = 3L, models = c("a", "b"))
  repro_fail(state, simpleError("わざと落とした"))
  table <- suppressMessages(repro_runs())
  expect_equal(as.list(table[c("status", "error", "n_analysis")]),
               list(status = "failed", error = "わざと落とした", n_analysis = 3L))
  expect_false("models" %in% names(table))
  repro_fail(repro_run(cfg), "文字で落とした")
  expect_true("文字で落とした" %in% suppressMessages(repro_runs())$error)
})

# --- 記録しない設定では何も書かず（repro_fail でも）、実行 ID と成果物のフォルダは作る（REPRODUCIBILITY.md 2 節）---
test_that("記録が無効なら何も書かず（repro_fail でも）、実行 ID と成果物のフォルダは repro_run が作る", {
  cfg <- local_repro_project()
  cfg$repro$enabled <- FALSE
  expect_warning(state <- repro_run(cfg), "この実行は記録されません", fixed = TRUE)
  expect_match(state$run_id, "^[0-9]{8}_[0-9]{6}_unit_")
  repro_finish(state)
  repro_fail(state, "落ちた")
  expect_true(all(dir.exists(repro_settings()$output_dirs)))
  expect_false(file.exists("outputs/figures/.gitkeep"))
  expect_false(dir.exists("outputs/repro"))
})

# --- git の外の文を見分ける（親のフォルダまで・マウントの境目まで）。.git が壊れている文は見分けない（REPRODUCIBILITY.md 2 節）---
test_that("git の外は、親のフォルダまでの文もマウントの境目の文も見分け、.git が壊れている文は見分けない", {
  parents <- "fatal: not a git repository (or any of the parent directories): .git"
  mount <- c("fatal: not a git repository (or any parent up to mount point /)",
             "Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).")
  expect_true(.repro_outside_git(parents))
  expect_true(.repro_outside_git(mount))
  expect_false(.repro_outside_git("fatal: not a git repository: /nonexistent/.git/worktrees/a"))
  expect_false(.repro_outside_git("fatal: invalid gitfile format: .git"))
})

# --- コミットと作業ツリーの汚れを読んで記録に残し、読めなければ NA にする。持ち主の違う /app でも読む（REPRODUCIBILITY.md 2 節）---
test_that("git の外では黙って NA、読めなければ警告して NA、コミットを読み、変更や新しいファイルがあれば dirty で警告して記録に残し、持ち主の違う /app でも読む", {
  cfg <- local_repro_project()
  unknown <- list(commit = NA_character_, dirty = NA)
  expect_identical(expect_no_warning(.repro_git_version()), unknown)
  file.create(".git")
  expect_warning(version <- .repro_git_version(), "git_commit は NA", fixed = TRUE)
  expect_identical(version, unknown)
  writeLines("gitdir: /nonexistent/.git/worktrees/a", ".git")
  expect_warning(version <- .repro_git_version(), "git_commit は NA", fixed = TRUE)
  expect_identical(version, unknown)
  unlink(".git")
  git <- function(...) {
    system2("git", c("-c", "user.name=t", "-c", "user.email=t@t", ...),
            stdout = FALSE, stderr = FALSE)
  }
  git("init", "-q")
  writeLines("x <- 1", "a.R")
  git("add", "a.R")
  git("commit", "-q", "-m", "a")
  expect_match(.repro_git_version()$commit, "^[0-9a-f]{40}$")
  expect_identical(.repro_git_version()$dirty, FALSE)
  writeLines("x <- 2", "a.R")
  expect_identical(.repro_git_version()$dirty, TRUE)
  git("checkout", "-q", "--", "a.R")
  writeLines("y <- 1", "b.R")
  expect_identical(.repro_git_version()$dirty, TRUE)
  expect_warning(state <- repro_run(cfg), "git_dirty = TRUE", fixed = TRUE)
  repro_finish(state)
  payload <- jsonlite::fromJSON(state$meta_path, simplifyVector = FALSE)
  expect_match(payload$git_commit, "^[0-9a-f]{40}$")
  expect_true(payload$git_dirty)
  skip_if_not(dir.exists("/app/.git"), "/app に .git が無い（コンテナの外か、Zip で受け取ったフォルダ）")
  withr::local_dir("/app")
  expect_match(.repro_git_version()$commit, "^[0-9a-f]{40}$")
})

# --- 読まれる版が renv.lock と合えばその SHA-256 を記録し、違えば何も書かずに止め、記録の置き場所を作れなくても止める（REPRODUCIBILITY.md 2 節）---
test_that("renv.lock と版が合えばその SHA-256 が記録に入り、違うか入っていなければ何も書かずに止まり、置き場所を作れなくても止まる", {
  cfg <- local_repro_project()
  lock <- function(package, version) {
    record <- stats::setNames(list(list(Package = package, Version = version)), package)
    jsonlite::write_json(list(Packages = record), "renv.lock", auto_unbox = TRUE)
  }
  lock("jsonlite", utils::packageDescription("jsonlite")$Version)
  expect_no_error(.repro_check_lock_versions())
  expect_equal(repro_environment_snapshot()$renv_lock_sha256,
               digest::digest("renv.lock", algo = "sha256", file = TRUE))
  lock("jsonlite", "0.0.1")
  expect_error(.repro_check_lock_versions(), "jsonlite: renv.lock は 0.0.1、読まれるのは", fixed = TRUE)
  lock("reproNoSuchPackage", "1.0")
  expect_error(.repro_check_lock_versions(), "reproNoSuchPackage: renv.lock は 1.0、入っていない",
               fixed = TRUE)
  expect_error(repro_run(cfg), "renv.lock に合わせて作り直して", fixed = TRUE)
  expect_false(dir.exists("outputs"))
  unlink("renv.lock")
  file.create("outputs")
  expect_error(suppressWarnings(repro_run(cfg)), "cannot open", fixed = TRUE)
})

# --- 実行 ID は引数 run_id で渡せ（REPRO_RUN_ID より先）、repro_new_run_id() で作れる（REPRODUCIBILITY.md 2 節）---
test_that("run_id の引数は REPRO_RUN_ID より先に使い、repro_new_run_id で前もって作れる", {
  cfg <- local_repro_project()
  run_id <- repro_new_run_id("unit")
  expect_match(run_id, "^[0-9]{8}_[0-9]{6}_unit_[0-9]{4}$")
  withr::local_envvar(REPRO_RUN_ID = "from_env_0000")
  expect_equal(repro_finish(repro_run(cfg, run_id = run_id))$run_id, run_id)
  expect_error(repro_run(cfg, run_id = run_id),
               paste0("run_id=", run_id, " の記録が既にあります"), fixed = TRUE)
  expect_error(repro_run(cfg, run_id = "a/b"),
               "run_id は、記録のファイル名の頭に使うので", fixed = TRUE)
  expect_equal(repro_finish(repro_run(cfg))$run_id, "from_env_0000")
  for (name in list("", "a/b", c("a", "b"), 1)) {
    expect_error(repro_new_run_id(name), "/ を含まない 1 つの名前", fixed = TRUE)
  }
})
