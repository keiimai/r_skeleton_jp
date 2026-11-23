# notebooks/ — 解析ノートブック

[Quarto](https://quarto.org/) の `.qmd` を置くフォルダ（描き方と出力 → 下）。

## 構成

| ファイル | 中身 |
|---|---|
| `_metadata.yml` | Quarto の共通設定（このフォルダの直下の `.qmd` に効く。著者は `_project_author.yml` から読む（Quarto の[メタデータの取り込み](https://quarto.org/docs/projects/quarto-projects.html#metadata-includes)）。Quarto の[フォルダごとの設定](https://quarto.org/docs/projects/quarto-projects.html#directory-metadata)） |
| `_project_author.yml` | レポートの著者と所属（プロジェクトが書き換える） |
| `styles.css` | HTML の見た目（`_metadata.yml` が読む） |

## 描き方

リポジトリの根で R を起動し、記録層を読み込んでから描く（Quarto は環境の側で入れておく）。

```r
source("R/repro.R")
repro_render("notebooks/<名前>.qmd")
repro_render("notebooks/<名前>.qmd", params = c("名前:値"))
```

`params` には `名前:値` を並べる。`.qmd` の YAML の `params:` に書いた既定値を、描くときだけ上書きする（Quarto の[パラメータの説明](https://quarto.org/docs/computations/parameters.html)）。`params` で変えた値は記録に残らないので、論文に載る結果に効く値は設定ファイルに書く。

ノートブックは 1 本ずつ描く（同時に描くと、先に描き終えた方が Quarto の作業フォルダ `notebooks/.quarto/` を消し、もう片方が止まることがある）。

## 出力の扱い

| 場所 | 出力 | git |
|---|---|---|
| `notebooks/` | `.qmd`（RStudio の［Render］で描くと、HTML も隣にできる） | 追跡するのは `.qmd` と上の構成のファイルだけ（外すもの → `.gitignore`） |
| `outputs/reports/<run_id>/` | `repro_render()` が描いた HTML（1 ファイルで完結する）。`run_id` は、`.qmd` の中の `repro_run()` の記録と同じ（形 → [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) 2 節）。HTML の題名の帯にも出る（ほかの描き方の帯は「repro_render() で描くと出る」） | 追跡しない |

## 書き方の約束

- 記録を始めて終えるチャンクで包んでいないノートブックは、探索と結果を読むための場所（論文に載る数字の条件 → [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) 4 節）
- 読むデータのファイルと `.qmd` 自身を、`repro_run()` の `inputs` に渡す（その SHA-256 が記録に残る）
- 1 つの設定ファイルを、複数のノートブックが読んでよい（実行 ID の名前の部分と、記録の `experiment_name` → [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) 2 節）
- パスはリポジトリの根から書く（`setup` のチャンクが、knitr の [`root.dir`](https://yihui.org/knitr/options/) で作業フォルダを根に揃える）
- チャンクの先頭に [`#| label: 名前`](https://quarto.org/docs/reference/cells/cells-knitr.html) を書く（Quarto の図表の参照と、描画のログでの目印になる。図を参照するなら `fig-` で始める）
- 記録した図は [`knitr::include_graphics(file.path("..", path), rel_path = FALSE, error = FALSE)`](https://search.r-project.org/CRAN/refmans/knitr/html/include_graphics.html) で差し込む
- 受け取ったデータは、CSV などに変換せず元の形式のまま読む
- 人が開く CSV の書き方 → [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) 4 節
- パッケージを `library()` で読むなら、[conflicted](https://conflicted.r-lib.org/) も読み、`library()` の直後に [`conflicts_prefer()`](https://conflicted.r-lib.org/reference/conflicts_prefer.html) で、名前がぶつかる関数のどちらを使うかを決める（決めないと、読んだ順で呼ばれる関数が変わる。`conflicted` は環境に入れておく）
- 書式は `_metadata.yml` と `styles.css` が決めるので、`.qmd` には書かない
- 見出しは `#` から始める（`_metadata.yml` が [`number-sections`](https://quarto.org/docs/output-formats/html-basics.html#section-numbering) で番号を振るので、最初の `#` より前の `##` には 0.1 と振られる）
- 探索のあいだは記録を取らない（設定の書き方と、記録が `failed`・`running` のまま残るとき → [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) 2 節）
- 記録を取るノートブックでは、knitr の cache（`execute: cache: true`・`#| cache: true`）を使わない（キャッシュから読んだチャンクは走らず、記録・成果物と HTML がずれる。`repro_run()` が止める）

`.qmd` は次の形で書く（記録の流れ → [`../docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) 2 節）。チャンクの名前は `setup` のままにする（RStudio でチャンクを手で走らせるとき、`root.dir` はこの名前のチャンクでしか効かない。[R Markdown の説明書](https://bookdown.org/yihui/rmarkdown/notebook.html)）。`setup` は、リポジトリの根を見つけてから読む（VS Code でチャンクを送ると、R はリポジトリの根で動く）。

````markdown
```{r}
#| label: setup
root <- normalizePath(if (file.exists("R/repro.R")) "." else "..")
knitr::opts_knit$set(root.dir = root)
for (path in list.files(file.path(root, "R"), pattern = "[.][Rr]$", full.names = TRUE)) source(path)
cfg <- repro_config_load(file.path(root, "configs/experiment/<設定の名前>.yaml"))
repro_set_seed(cfg$seed)
```

```{r}
#| label: begin
state <- repro_run(cfg, inputs = c("data/raw/<受領ファイル>", "notebooks/<名前>.qmd"))
```

```{r}
#| label: analysis
result <- my_analysis(cfg, state$run_id)
```

```{r}
#| label: finish
state$artifacts <- result$paths
state$ledger <- list(n_analysis = result$n)
repro_finish(state)
```
````
