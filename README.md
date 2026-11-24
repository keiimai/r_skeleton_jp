# R 解析プロジェクトの枠組み

研究プロジェクトを起こすための、ディレクトリの構成・ライセンス・記録の雛形と、再現性の記録層のテンプレートです。実行環境は持たず、R の版にもよりません。環境は、このテンプレートの外で用意します。

> **解析のコードも、実行環境を作る仕組み（Docker・パッケージの固定など）も入っていません。**
>
> **このテンプレートから起こしたプロジェクトでは、このファイルをプロジェクトの概要に書き換えてください。**

## 使い方

| するとき | すること |
|---|---|
| プロジェクトを起こす | このフォルダを写して `git init` し、`README.md`・`CITATION.cff`・`CHANGELOG.md`・`notebooks/_project_author.yml` をプロジェクトのものに書き換える。`Rscript setup.R` で `.env` を作り、記録の時刻帯 `TZ` を決める（→ [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) 2 節）。コミット前の検査を有効にする（→ [`docs/CHECKS.md`](docs/CHECKS.md) 1 節。clone したときも） |
| 環境を用意する | このテンプレートの外で用意し、記録層が使うパッケージ（→ [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) 5 節）を入れる。使った環境を `CHANGELOG.md` に書く（→ 下の「記録」） |
| 解析する | 関数を `R/` に、そのテストを `tests/` に、ノートブック（`.qmd`）を `notebooks/` に、設定を `configs/` に書く（書き方 → [`notebooks/README.md`](notebooks/README.md)） |
| 結果を出す | コミットしてから、リポジトリの根の R で `source("R/repro.R"); repro_render("notebooks/<名前>.qmd")`。HTML は `outputs/reports/<実行 ID>/` にできる |
| 構成が欠けたら | `Rscript setup.R`（無いフォルダと `.env` だけを作る） |
| 記録層を確かめる | `testthat::test_dir("tests/testthat")`（テスト）と、`source("R/repro.R"); repro_smoke()`（経路を 1 回通す） |
| lint する | リポジトリの根の R で `lintr::lint_dir(".")`（決まり → [`docs/CHECKS.md`](docs/CHECKS.md) 2 節） |

## 構成

```
configs/          設定（実験の条件など）
data/             raw / raw/dummy / interim / processed / external   ← 中身は Git 追跡外
docs/definition/  変数の定義・コード表など（CSV も追跡する）
models/           学習済みのモデルなど                                ← 同上
notebooks/        解析の入口（.qmd）と、HTML の書式
outputs/          tables / figures / metrics / reports / repro       ← 同上
R/                記録層 repro.R と、解析の関数
tests/            記録層と解析の関数のテスト
tools/            コミット前の検査の本体
```

`data/` の中のフォルダの使い方は [`data/README.md`](data/README.md)。

| ファイル | 役割 |
|---|---|
| `README.md` | プロジェクトの概要（書き換える） |
| `CHANGELOG.md` | 判断の記録（→ 下の「記録」） |
| `CITATION.cff` | 引用の情報（[Citation File Format](https://citation-file-format.github.io/)） |
| `LICENSE` | [MIT](https://opensource.org/license/mit) |
| `R/repro.R`・`tests/testthat/test-repro.R`・`helper-load.R` | 記録層と、そのテスト・テストの前に `R/` を読み込む helper（→ [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md)） |
| `.Rprofile` | R を起動したときの決まり（→ [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) 1 節） |
| `.githooks/pre-commit`・`tools/precommit_checks.R` | コミット前の検査（データ・成果物・秘密情報の混入を止める。→ [`docs/CHECKS.md`](docs/CHECKS.md) 1 節） |
| `.lintr` | lint の決まり（→ [`docs/CHECKS.md`](docs/CHECKS.md) 2 節） |
| `setup.R` | 上の構成のフォルダを、無いものだけ作る。`.env` が無ければ `.env.example` を写す |
| `.env.example` | `.env` の書き方の見本（`setup.R` が `.env` に写す）。記録の時刻帯は、`.env`（Git で追跡しない）の `TZ` で決める（→ [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) 2 節） |
| `notebooks/README.md`・`_metadata.yml`・`_project_author.yml`・`styles.css` | ノートブックの書き方と、HTML の書式（→ [`notebooks/README.md`](notebooks/README.md)） |
| `.gitignore` | 人が書いたものだけを追跡する（[`.gitignore` の説明書](https://git-scm.com/docs/gitignore)）。秘密情報（`.env`・鍵）・データ・成果物・データの形式（CSV・Excel・SPSS・Stata など）を外す（`docs/definition/` の CSV は追跡する）。鍵の `*.key` は Keynote のスライドも外すので、スライドは PDF などに書き出して渡す |
| `.editorconfig` | 字下げ・改行・文字コードの決まり（[EditorConfig](https://editorconfig.org/)）。新しい種類のファイルの決まりは「プロジェクトが足す書式」の見出しの下に足す（後に書いた節が強いので、`[data/**]` の節を最後に残す） |
| `.vscode/settings.json` | VS Code の[ワークスペースの設定](https://code.visualstudio.com/docs/configure/settings#_workspace-settings)（R の拡張機能に、言語サーバーを起こさせず、入れるよう促させない） |

## 記録

| 残すもの | 置き場所 |
|---|---|
| 何を変えたか | Git |
| なぜ変えたか・何を捨てたか・ダミーデータを何から作ったか | `CHANGELOG.md` |
| 使った環境（どこで作ったか・R の版・パッケージの版を固定した方法（renv など）） | `CHANGELOG.md` の頭 |
| 実行ごとの記録（コミット・入力と成果物の SHA-256・環境・設定・状態） | `outputs/repro/<実行 ID>/`（→ [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md)） |
| 全実行の台帳 | `outputs/repro/runs.csv`（`repro_runs()` が作り直す） |
| 引用の情報 | `CITATION.cff` |

`data/`・`outputs/`・`models/` の中身は Git で追跡しません（コミット前の検査が止めます）。

## ライセンスと引用

- コードは [MIT](https://opensource.org/license/mit)（`LICENSE`）です。手順書・動画などの教材を人に渡すプロジェクトは、教材だけを [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/deed.ja) にします（根に `LICENSE-docs` を足す）。
- 使うもの（R・R のパッケージ・Quarto など）は、このテンプレートに入っていません。それぞれの作者の条件に従います。
- このテンプレートを引用するときは、`CITATION.cff` の情報を使ってください。

## AI の使用

コードと文書は、AI のコーディング支援（Anthropic の [Claude Opus 5.5](https://www.anthropic.com/claude/opus) を [Claude Code](https://code.claude.com/docs/en/overview) で使った）を道具として使って書いた。作者が作業を指示し、中身に責任を持つ（AI は著者にしない）。
