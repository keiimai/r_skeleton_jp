# 再現性の記録

記録層は、その数値がどのコード・どの入力・どの環境・どの設定から出たかを記録する。環境は作らない（作り方は、このテンプレートの外で決める）。

---

## 1. 構成と保証の範囲

| ファイル | 役割 |
|---|---|
| `R/repro.R` | 記録層。実行の記録・乱数の種の固定（`repro_set_seed()`）・設定の読み込み・BOM 付きの CSV の書き出し（`repro_write_csv()`）・描画（`repro_render()`）・台帳（`repro_runs()`）・疎通確認（`repro_smoke()`） |
| `tests/testthat/test-repro.R`・`helper-load.R` | 記録層のテストと、テストの前に `R/` を読み込む helper（リポジトリの根で `testthat::test_dir("tests/testthat")`。コンテナの中でしか確かめられない 2 件は、外では飛ばす） |
| [`.Rprofile`](https://search.r-project.org/R/refmans/base/html/Startup.html) | R を起動したときの決まり（警告をその場で出す・引用符を ASCII にする・対話セッションのスレッド数）。末尾の見出しの下に、プロジェクトが行を足してよい（→ 下の注意） |
| `notebooks/README.md`・`notebooks/_metadata.yml`・`notebooks/_project_author.yml`・`notebooks/styles.css` | ノートブックの書き方の約束と、HTML の書式（それぞれの役目 → [`notebooks/README.md`](../notebooks/README.md)「構成」） |

`.Rprofile` の末尾に足すときの注意:

- リポジトリの根で起動するすべての R が読む（RStudio・`Rscript`・テスト・`repro_render()` の描画の中の R など）。対話のときだけ、または RStudio のときだけ動かしたい処理は、[`interactive()`](https://search.r-project.org/R/refmans/base/html/interactive.html) などで分ける。時間のかかる処理・パッケージの読み込み・秘密の値は書かない
- `--vanilla` で起動した R と、根の外で起動した R は、`.Rprofile` を読まない

| | 保証するか |
|---|---|
| 同じ環境で同じ結果が出る | 記録層は乱数の種類を固定し、環境（依存・ロケール・スレッド数）を記録する。環境を揃えるのは、環境を作る側である。解析が種を渡しているかと、2 回走らせて一致するかは、プロジェクトが確かめる |
| 成果物がどのコード・どの入力・どの設定から出たか辿れる | する（コミット・`inputs` に渡したファイルと成果物の SHA-256・解決済みの設定を記録する） |
| データの差し替えに気づける | する（`inputs` に渡したファイルの SHA-256）。差し替える前のデータは復元しない（データは版管理しない） |
| ダミーの数字が結果として出回らない | 記録の `data_mode` と、成果物に付けた実行 ID（名前の頭かフォルダ）で見分ける |
| 別の CPU で下位桁まで一致する | しない（arm64 と amd64 では、数値計算の実装が違う） |

---

## 2. 記録の流れ

入口のノートブックが、`repro_run()` と `repro_finish()` で実行を挟む（書き方は `notebooks/README.md`）。R はリポジトリの根で起動する。

- 設定で記録層が読むのは `seed`・`experiment_name`・`data.mode`・`repro`（`enabled`・`quiet`）だけで、ほかのキーはそのまま持ち越して記録する。省いたキーは既定になる（→ `R/repro.R` の `repro_config_defaults()`）。`repro.quiet: true` にすると、始めと終わりの表示を出さない
- 失敗を記録に残すには、`repro_fail(state, error)` を呼ぶ（記録を `status: failed` で終え、`error` に理由（条件か文字）を残す。例: `tryCatch(本体, error = function(e) { repro_fail(state, e); stop(e) })`）
- 台帳（`runs.csv`）の列になるのは、`state$ledger` のうち長さ 1 の値だけである。どの実行にもある列と同じ名前は、列にしない（知らせは出ない）
- 記録を取らないときは設定を `repro.enabled: false` にする（`repro_finish()`・`repro_fail()` は何もしない）
- 実行 ID は `<YYYYMMDD_HHMMSS>_<名前>_<4 桁の数>`（時刻帯 → 下）で、`outputs/` に書く成果物は、名前の頭に実行 ID を付けるか、実行 ID のフォルダ（`outputs/figures/<run_id>/` など）に入れる。環境変数 `REPRO_RUN_ID` に値があれば、それを実行 ID にする
- 実行 ID は、`repro_run(cfg, inputs, run_id = )` の引数でも渡せる（引数 → 環境変数 `REPRO_RUN_ID` → 新しく作る、の順）。描画の前などに実行 ID を知りたいときは `repro_new_run_id(名前)` で作り、その値を `run_id` に渡す
- `<名前>` は、ノートブックを描いている間は `.qmd` の名前、それ以外（チャンクを手で走らせたときや `repro_smoke()`）は設定の `experiment_name` である。記録の `experiment_name`（`repro_runs(experiment = )` で絞る名前）は、どのノートブックが読んでも設定の値のまま残る。次の段が読む `data/interim/`・`data/processed/`・`models/` のファイルは決まった名前で書き、前の段の記録の `artifacts` と次の段の `inputs` の SHA-256 で辿る
- 実行 ID と記録の時刻は、根の `.env` の `TZ` の時刻帯で付ける（`.env` に無ければ環境変数 `TZ`、それも無ければ `Asia/Tokyo`。`.env` のほかの行は読まない）。`.env` は Git では追跡しない（`Rscript setup.R` が、書き方の見本の `.env.example` を写して作る）。時刻帯は、プロジェクトの初めに `.env` で決めて途中で変えず、共同研究者とも同じにする（実行 ID の名前には時差が入らないので、途中で変えると、実行 ID が実行した順に並ばなくなる）。記録の環境（`environment` の `env` の `TZ`）には、使った時刻帯が残る
- 描画した HTML は、記録の成果物に載らない

```
outputs/repro/<run_id>/<run_id>_run.json      記録
outputs/repro/<run_id>/<run_id>.config.yaml   解決済みの設定（既定値まで含む）
outputs/repro/runs.csv                        実行台帳（repro_runs() が作り直す。BOM 付きの UTF-8）
```

記録と解決済みの設定は始めた時点で書かれ（記録は `status: running`）、記録は終わりに上書きされる。`repro_render()` は、成功したときだけ HTML を `outputs/reports/<run_id>/` に写す。`repro_render()` が失敗すると（描画の段で落ちても）、記録を `failed` に書き換え、名前かフォルダにその実行 ID を含む途中の成果物（`outputs/` の下）を `outputs/repro/<run_id>/partial/` に移す。［Render］が途中で止まるか、チャンクを手で走らせて `finish` のチャンクの前にやめると、記録は `status: running` のまま残る。

台帳は `repro_runs()` で作り直す（`repro_runs(experiment = "smoke", limit = 10, show = TRUE)` で絞って表示する）。記録層の経路を 1 回通すには `repro_smoke()` を走らせる。

---

## 3. 記録の読み方と再現

1. `git_dirty` が `false` なら、[`git checkout <git_commit>`](https://git-scm.com/docs/git-checkout) でそのコードに戻る（`true` なら、そのコードはもう無い。`git_commit`・`git_dirty` が null なら、Git の外で走らせたか、Git が失敗した）
2. `environment` の `r_version`・`platform`・`renv_lock_sha256`・`build_info` で、同じ環境を作る（`renv_lock_sha256` と `build_info` は、根に `renv.lock` があるときと、`/opt/build-info.json` があるときだけ入る）
3. `inputs` の SHA-256 と、手元のデータを突き合わせる
4. 同じノートブックを、そのコミットのまま `repro_render()` で描き直し（設定もそのコミットのものを読む）、`artifacts` の SHA-256 と突き合わせる。書き出した時刻を中に持つ形式（SAV・XLSX など）は、読み込んだ中身で比べる

---

## 4. 注意

- ロケールは、[factor](https://search.r-project.org/R/refmans/base/html/factor.html) の水準順（回帰の参照水準と係数の符号）を決める。環境の側で `LANG`・`LC_ALL` を固定する（例: `C.UTF-8`）。参照水準を決める変数は `factor(x, levels = c(...))` で明示する
- BLAS（[OpenBLAS](https://www.openmathlib.org/OpenBLAS/docs/runtime_variables/)）と OpenMP は、R の起動前の環境変数（`OMP_NUM_THREADS`・`OPENBLAS_NUM_THREADS`）でスレッド数を決める。最終結果を出す実行では 1 にする（1 でなければ `repro_run()` が警告する）。`.Renviron` や `Sys.setenv()` では効かない。対話セッションでは、`.Rprofile` が [`RhpcBLASctl`](https://cran.r-project.org/package=RhpcBLASctl) で設定し直し（入っていれば）、1 でなければ注意を出す
- 並列化（[`parallel`](https://search.r-project.org/R/refmans/parallel/html/parallel-package.html)）は種を壊す。するなら [`parallel::clusterSetRNGStream()`](https://search.r-project.org/R/refmans/parallel/html/RngStream.html) で乱数列を配り、しないなら逐次で回す
- 設定は `repro_config_load()`・`repro_read_yaml()` で読む（UTF-8 として読み、YAML 1.1 で論理値や文字に化ける書き方（[論理値](https://yaml.org/type/bool.html)・[小数](https://yaml.org/type/float.html)の決まり）は、止めるか警告する）
- 人が開く CSV は、BOM 付きの UTF-8 で書く（`repro_write_csv()`）。日本語版 Excel は BOM の無い CSV を Shift_JIS として読み、日本語が化ける（[Microsoft の説明](https://support.microsoft.com/ja-jp/excel/opening-csv-utf-8-files-correctly-in-excel)）。lint が、BOM を付けない書き出しを止める（→ [`CHECKS.md`](CHECKS.md) 2 節）。R で読み直すときは `fileEncoding = "UTF-8-BOM"` を付ける
- 論文に載る結果は、記録を始めて終えるチャンク（`repro_run()`・`repro_finish()`）で包んだノートブックから出す。コミットしてから、記録を取って（`repro.enabled: true`）、`repro_render()` で描く（図は、描き方でバイトが変わる）

---

## 5. 依存

記録層が使うパッケージは、環境の側で入れておく。版の固定は、環境を作る側が決める。根に [`renv.lock`](https://rstudio.github.io/renv/articles/lockfile.html) があれば、`repro_run()` は読まれるパッケージの版が同じかを確かめ（違えば止める）、その SHA-256 を記録する。

| 使う所 | パッケージ |
|---|---|
| 記録層 | [yaml](https://yaml.r-lib.org/)・[digest](https://eddelbuettel.github.io/digest/)・[jsonlite](https://cran.r-project.org/package=jsonlite) |
| 描画 | [Quarto](https://quarto.org/)・[knitr](https://cran.r-project.org/package=knitr)・[rmarkdown](https://pkgs.rstudio.com/rmarkdown/) |
| テスト・lint | [testthat](https://testthat.r-lib.org/)・[withr](https://withr.r-lib.org/)・[lintr](https://lintr.r-lib.org/) |
| 任意 | [RhpcBLASctl](https://cran.r-project.org/package=RhpcBLASctl)（`.Rprofile` が、対話セッションのスレッド数を設定し直す） |
