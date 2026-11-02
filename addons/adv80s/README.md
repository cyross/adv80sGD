# adv80s アドオン

80年代風アドベンチャーゲームを作るための Godot 4 アドオン。仕様はリポジトリ直下の `SPEC.md` を参照。

## 現在の段階：段階3「表示まわり」まで

| 範囲 | 内容 |
| --- | --- |
| Core | 状態（フラグ・変数・所持品・到達記録）、意図の受け取りと省略形の正規化、出力イベントの状態適用、乱数、問い合わせ、診断 |
| 条件式 | JSONの形と短い文字列の形（and/or/not、&&/\|\|/!、括弧、比較、組み込み条件）、`"= 式"` と `let` |
| 意図スキーマ | 標準動詞の定義、層の重ね合わせ（null で削除）、省略形の正規化 |
| 辞書 | 日本語・英語の同梱辞書、ひらがな/カタカナ・全角/半角の同一視、完全一致→語幹の照合 |
| JSONアダプタ | シーン、物、出口、アイテム、会話（地の文、`@話者`、`say`、`if`、`set`、`let`、`call`、`goto`、出力イベントの直接記述）、話題、行IDの自動付与、`validate` |
| 入力 | 日本式パーサー（空白なし入力・助詞による振り分け）、コマンド選択、コマンド入力欄 |
| 表示 | 98 プリセット（640x400、16色）、テンプレート（継承、区割り、枠の窓）、`text.show`（文字送り・クリック待ち）、`image.show`/`image.hide`（素材がなければ代わりの表示）、装飾記法の一部 |

段階2で加えたもの：

| 範囲 | 内容 |
| --- | --- |
| プロジェクト設定 | `res://adv80s.project.json`（テンプレート、シナリオ、素材フォルダ、`asset_folders`、`missing_asset`、`event_defaults`、`features` など） |
| 素材マニフェスト | `manifest.auto.json`（自動生成）と `manifest.json`（手書き）の読み込み、プロジェクト → テンプレート → シナリオ の重ね合わせ、機種別の差し替え（完全一致 → 機種 → グループ → 既定）、差分（`name@variant`）、種類ごとの名前空間 |
| 自動生成 | フォルダの決まりによる自動登録と確認（IDの重複、推奨外の文字、対応表にないフォルダ、手書きマニフェストの誤り、シナリオが参照する素材） |
| エディタ | ドック「adv80s」（生成ボタンと結果の一覧）、ファイル変更時の自動生成、書き出し直前の生成とJSONの同梱、VS Code 設定の書き出し（ツールメニュー） |
| コマンドライン | `tools/manifest_cli.gd`（generate / check / --up-to-date / --strict ほか、終了コードは仕様どおり） |
| JSON Schema | `schemas/ja`、`schemas/en`（シナリオ、テンプレート、意図スキーマ、マニフェスト、プロジェクト設定、自作演出） |
| validate | スキーマによる確認（SCHEMA_VIOLATION、UNKNOWN_KEY）、未定義の変数、話者・会話・移動先の存在、素材の参照、どこからも来ないシーン |
| モダン機能 | 機能キーの解決（プロジェクトの許可 → テンプレート → 実行時）と依存の確認（FEATURE_DEPENDENCY） |
| 出力イベント | `event_defaults`（イベント → シナリオ → プロジェクト → 標準 の順） |

段階3で加えたもの：

| 範囲 | 内容 |
| --- | --- |
| プリセット | 7.1 の全26機種（略称）とモード。色（固定パレットかビット数）、ピクセルの縦横比、縦2倍表示、見える範囲、既定のフィルター。`presets.json` は `tools/build_presets.py` で書き出す |
| 表示 | 元の解像度の SubViewport に描き、整数倍に拡大。640x200 などは縦2倍、縦横比補正（`display.aspect_correction` かフィルター `aspect`）は縦を伸ばす |
| フィルター | 標準：`scanline`、`reduce`（パレットかビット数）、`dither`、`bleed`、`crt`（曲面と周辺の暗さ）、`rgb_mask`、`mono`、`lcd`、`aspect`。`default` / `append` / `replace` / `none`、配列は replace。自作は `*.effect.json`（kind: filter）で画面を読み直す段として重ねる。`set_filters_enabled()` でまとめて無効化 |
| 切り替え演出 | `cut`、`fade`、`fade_color`、`wipe`、`blinds`、`line_draw`、`interlace`、`plane_draw`、`mosaic`、`dissolve`、`blocks`、`iris`、`mask`。テンプレートの既定、名前付きの組み合わせ（プロジェクトとテンプレート）、置き換え表、自作（kind: transition）。元の解像度でかけてからフィルターを通す |
| 画面効果 | `flash`、`shake`、`invert`、`tint`（続けてかけ、amount 0 で戻る）、`scroll`、`zoom`、`raster` |
| テンプレート | `pc88_classic`（`pc98_classic` を継承）を追加。名前付きのレイアウト（`layout.set`）、テンプレートの切り替え（`template.switch`、機種別の素材に差し替わる）、フォントの行の高さ（`fonts.main.line_height`）、`nine_patch` の窓 |

まだないもの：選択肢（choice）、Ink アダプタ、音、セーブファイル、メッセージログ、スキップとオート送り、モダン機能の画面、`palette_cycle`。

## 使い方（最小）

1. `addons/adv80s` をプロジェクトにコピーし、プロジェクト設定でプラグインを有効にする。
2. `res://adv80s.project.json` を作る（このリポジトリのものが例）。
   ```json
   {
     "project_version": 1,
     "template": "pc98_classic",
     "scenarios": ["res://game/main.scenario.json"],
     "asset_roots": ["res://game/assets"]
   }
   ```
3. シーンに `Control` を置き、スクリプトに `res://addons/adv80s/adv_player.gd` を設定する。
4. 素材は種類フォルダに置く（`bg/hallway.png` は画像ID `hallway`、`chara/ayumi@smile.png` は `ayumi` の差分 `smile`）。
   エディタが `manifest.auto.json` を自動で書き出すので、コミットしておく。
5. 表示設定は、基本の大きさ 640x400、ストレッチモード `canvas_items`、アスペクト `keep`、拡大方式 `integer` を推奨。
   フィルターは実際の画面の解像度で描くので、`canvas_items` にすると走査線などがきれいに出る。

サンプルは `res://tests/stage1/` にある。

## テスト

```
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_ui_tests.gd
```

## マニフェストのコマンドライン

```
godot --headless --path . --script res://addons/adv80s/tools/manifest_cli.gd -- generate
godot --headless --path . --script res://addons/adv80s/tools/manifest_cli.gd -- check --up-to-date --strict
```

- 一度も読み込んでいないプロジェクト（CI で取り出した直後など）では、先に自動でインポートしてから実行する。
- 仕様の引数に加えて `--project <ファイル>` でプロジェクト設定のファイルを指定できる。

## 段階3の決めごと

- 自作のフィルター、切り替え演出、画面効果は、プロジェクト設定の `effects` に `*.effect.json` を並べて登録する。フィルターのシェーダーは `hint_screen_texture` で画面を読み直す canvas_item シェーダーとして書く（例：`tests/stage1/effects/`）。
- 名前付きの切り替え演出は、プロジェクト設定の `transitions.named` とテンプレートの `transitions.named` に書く（テンプレートが優先）。
- `image.show` で切り替え演出が `cut` 以外になったとき（テンプレートの既定を含む）、`wait` を省略すると `end` になる。
- 名前付きのレイアウトで窓を隠すときは、その区割りに `"visible": false` を書く（`null` は継承で「取り除く」意味になるため）。
- 縦横比補正は縦を伸ばして行う（横は整数倍のまま）。

## 段階2の決めごと

- プロジェクト設定のファイルは `res://adv80s.project.json`。
- 自動生成マニフェストのキーは「種類:ID」（例 `image:hallway`、`se:door`）。手書きのマニフェストは ID だけでも書ける（種類は `type`）。
- VS Code の結び付けは、シナリオ `*.scenario.json`、テンプレート `template.json`、マニフェスト `manifest.json` / `manifest.auto.json`、プロジェクト設定 `adv80s.project.json`、意図スキーマ `*.intent_schema.json`、自作演出 `*.effect.json`。
- 未定義の変数の警告は「読んでいるのに、宣言も `set`・`let` での変更もない変数」だけに出す。
- スキーマを直すときは `tools/build_schemas.py`（開発用、Python）を直して `python3 tools/build_schemas.py addons/adv80s/schemas` で再生成する。

## JSON アダプタの補足（段階1の決めごと）

- シーンの `first` は初めて入ったとき、`enter` はそれ以外のときに実行する（`first` がなければ毎回 `enter`）。
- `goto` はそこで手順を打ち切る。行き先は、会話の中では会話を、それ以外ではシーンを優先して探す。
- 反応のキーに `"USE+door"` のように「動詞+with の対象ID」を書くと、`with` がその対象のときに優先して使う。
- 比較の右辺の識別子は変数として扱う（`money > price`）。文字列は引用符で囲む（`name == "ゆうじ"`）。ただし `scene`、`preset`、`group` の右辺はIDとして扱う（`scene == hallway`）。
- 書き出したゲームでJSONを含めるには、今のところエクスポート設定の「リソース以外のファイル」に `*.json` を加える（段階2でプラグインが自動で行う）。
