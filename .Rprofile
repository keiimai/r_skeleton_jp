# --- セッション開始時の既定値（REPRODUCIBILITY.md 1 節）---

# --- 起動時の設定（REPRODUCIBILITY.md 1 節）---
local({
  # --- 警告をその場で出し、引用符を ASCII にする（REPRODUCIBILITY.md 1 節）---
  options(
    warn = 1,
    useFancyQuotes = FALSE
  )

  # --- 対話セッションで、BLAS と OpenMP のスレッド数を環境変数の値に設定し直す（REPRODUCIBILITY.md 4 節）---
  if (interactive() && requireNamespace("RhpcBLASctl", quietly = TRUE)) {
    blas <- suppressWarnings(as.integer(Sys.getenv("OPENBLAS_NUM_THREADS")))
    omp <- suppressWarnings(as.integer(Sys.getenv("OMP_NUM_THREADS")))
    if (!is.na(blas)) RhpcBLASctl::blas_set_num_threads(blas)
    if (!is.na(omp)) RhpcBLASctl::omp_set_num_threads(omp)
  }

  # --- 対話セッションでスレッド数が 1 でなければ注意を出す（REPRODUCIBILITY.md 4 節）---
  if (interactive()) {
    threads <- Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS"), unset = "")
    threads <- threads[threads != "1"]
    if (length(threads) > 0L) {
      shown <- ifelse(nzchar(threads), threads, "(未設定)")
      message(
        "注意: ", paste0(names(threads), "=", shown, collapse = "・"),
        " です。最終結果を出す実行では 1 にしてください（変えたなら戻す）。"
      )
    }
  }
})

# --- プロジェクトが足す行（REPRODUCIBILITY.md 1 節）---
