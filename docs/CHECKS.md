# コミット前の検査と lint

---

## 1. コミット前の検査

`.githooks/pre-commit` が、コミットの前にステージしたファイルを検査し、指摘があればコミットを止める（git の [githooks の説明書](https://git-scm.com/docs/githooks)）。フックは、リポジトリを写したり clone したりするたびに、リポジトリの根で 1 回有効にする（有効にしないと、何も止まらない）。

```bash
chmod +x .githooks/pre-commit
git config --local core.hooksPath .githooks
```

git 2.54 以降なら、次の 2 行で、マージのコミットにも同じ検査を掛ける（[git hook](https://git-scm.com/docs/git-hook)）。

```bash
git config --local hook.precommit-checks.command .githooks/pre-commit
git config --local --replace-all hook.precommit-checks.event pre-merge-commit
```

追跡中の全ファイルに同じ検査を掛けるには、`bash .githooks/pre-commit --all` を走らせる。

表の上の 7 つは bash と git だけで走る。下の 3 つ（`tools/precommit_checks.R`）は、コミットする場所の `Rscript` で走らせる（`--vanilla` で起動するので、`.Rprofile` と renv のライブラリは読まない）。`Rscript` が見つからなければ、下の 3 つを飛ばして知らせ、上の 7 つの指摘だけで止める。YAML と JSON の構文は、[yaml](https://yaml.r-lib.org/) と [jsonlite](https://cran.r-project.org/package=jsonlite) が読めるときだけ見る。

| 検査 | 止めるもの |
|---|---|
| `renv.lock` の追跡 | 根に `renv.lock` があるのに、入れ忘れたコミット |
| `data/`・`outputs/`・`models/` の下 | データと成果物（`data/README.md`・`.gitkeep` は通す） |
| `.env` | 秘密情報を書くファイル（`.env.example` は通す） |
| `data/` の外のデータの形式 | CSV・Excel・SPSS・Stata・SAS・RDS・Parquet・pickle・圧縮ファイル（zip・gz・tar など）など（`docs/definition/`・`configs/`・`tests/testthat/` は通す） |
| `.gitignore` が外すファイル | 追跡しているのに `.gitignore` に当たるもの。`git add -f` で入れたものと、`.gitignore` に行を足す前から追跡していたもの（`docs/definition/`・`configs/`・`tests/testthat/` のデータの形式は通す） |
| 大文字小文字だけが違う名前 | macOS・Windows と Linux での衝突 |
| 衝突の印 | `<<<<<<<` などを残したまま仕上げたマージ・cherry-pick・revert（`git rebase --continue` は git がフックを呼ばないので、掛からない） |
| 2 MB を超えるファイル・秘密鍵・よく知られたトークン・秘密情報らしい名前に書いた値（コードでは引用符の中の値） | 秘密情報とデータの混入 |
| R・YAML（`CITATION.cff` を含む）・JSON の構文と、`R/` の `repro.R` 以外が `repro_run()`・`repro_finish()`・`repro_fail()` を呼ぶこと | 壊れたファイルと、記録の流れを解析の関数が握ること（→ [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) 2 節） |
| 行末の空白と末尾の改行 | 書式のゆれ（Markdown と表の形のデータの行末の空白は見ない。作業ツリーがステージと同じなら直してから止めるので、`git add` し直す） |

---

## 2. lint

`.lintr` が、[lintr](https://lintr.r-lib.org/) の決まりを決める（1 行 100 字まで・名前は snake_case・BOM を付けない CSV の書き出し（`write.csv()`・`readr::write_csv()` など）を止める（→ [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) 4 節））。lint はリポジトリの根の R で走らせる。

```r
lintr::lint_dir(".")
```
