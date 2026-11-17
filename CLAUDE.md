# adv80sGD：作業のための覚え書き

このファイルは、チャット（claude.ai）と Claude Code の両方で同じ前提で作業するためのものです。決めごとが増えたら、ここに書き足します。

## これは何か

- Godot 4.7（GDScript）で 80 年代風のアドベンチャーゲームを作るためのフレームワークと、シナリオエディタのプラグイン。
- 外部の依存を持たない（アドオン・ライブラリを足さない）。
- シナリオは JSON（`*.scenario.json`）と Ink（`.ink.json`）。

## 置き場所

| 場所 | 中身 |
| --- | --- |
| `addons/adv80s/core` | 状態、条件式（`adv_condition.gd`）、計算式（`adv_expr.gd`）、進行 |
| `addons/adv80s/adapters` | JSON・Ink の取り込み口 |
| `addons/adv80s/presentation` | テンプレート（`adv_template.gd`）、演出、画面部品 |
| `addons/adv80s/input` | 入力方式、パーサー |
| `addons/adv80s/editor` | エディタプラグイン（`editor/scenario/` がシナリオエディタ） |
| `addons/adv80s/debug` | デバッグコンソールなど |
| `addons/adv80s/schemas/ja`・`en` | JSON スキーマ（両方を同じに保つ） |
| `addons/adv80s/presets`・`templates` | 機種プリセットと同梱テンプレート（`tools/build_*.py` で作るものがある） |
| `addons/adv80s/adv_player.gd` | プレイヤー本体 |
| `tests/` | テスト（下の「確かめ方」） |
| `SPEC.md` | 仕様書（設計と決めごと。6.8 がシナリオエディタ） |
| `docs/` | 利用者向けドキュメント（目次は `docs/README.md`） |

## 確かめ方

変更のあとは、三つとも通ることを確かめる。

```text
godot --path . --script res://tests/run_tests.gd
godot --path . --script res://tests/run_editor_tests.gd
godot --path . --script res://tests/run_ui_tests.gd -- /tmp/shots
```

- 段階69の時点で run_tests 872 件、run_editor_tests 498 件が通り、run_ui_tests は「ui failed: 0」。
- 画面に関わる変更では `run_ui_tests.gd -- /tmp/shots --review` も回し、`index.html` で全テンプレート（26）×画面（14）を見る。赤い枠は問題あり（`_overflowing`・`_low_contrast`）。
- テストの中ではプレイヤーの大きさが 0 なので、レビューでは FULL_RECT にしている。
- 環境変数 `ADV80S_TEST_FFMPEG` に ffmpeg.exe のパスを入れて run_ui_tests を回すと、録画を MP4 に変えるところも確かめる（なければ飛ばす）。

## 決めごと

- **機種名は略称で書く**（PC-98、PC-88、FC、SFC、GB、GBC など）。商標を避けるため。コード・文書・画面のすべてで。
- **文書は日本語で、やさしい言葉で書く。** 新しい機能は `SPEC.md`、`docs/reference.md`、`docs/howto.md`、`docs/spec-list.md` のうち関わるものに書き足す。スキーマは ja と en の両方を直す。
- **段階で進める。** 機能のまとまりを「段階NN」と呼び、`docs/spec-list.md` の冒頭の段階番号も上げる。いまは段階69まで。
- **作者の値は `ext` か `x.名前` に入れる。** フレームワークが読まない場所。勝手に新しいキーを生やさない。
- **作者のファイルは `res://game/` に置く。** `addons/adv80s` の中は利用者が書き換えない前提。
- **改行は CRLF**（Windows の作業フォルダ）。
- **新しいスクリプトの `.uid` は Godot で開いて作らせ、一緒にコミットする。** 画像などの `.import` も Godot が作る。
- **`master.key` はコミットしない**（`.gitignore` 済み）。

## git

- コミットは頼まれたときだけ。main のときはブランチを切ってから。
- push はしない（利用者がする）。
- コミットの作者は次のとおり。

```text
git -c core.autocrlf=true -c user.name="Cyross Makoto" -c user.email="cyross4github@gmail.com" commit
```

## 小さい画面・色についての知見（段階61〜67）

- 見える範囲は `AdvTemplate.visible_rect()`。FC は上下 8 px が隠れる。通知などはこの内側に置く。
- 窓の地の色は `window_fill_color()` で取る。文字の色と明るさの差が 0.3 未満なら、パレットの中で一番見分けやすい色に替わる（GB が 98 の地の色 0 を受け継いで読めなかったため）。文字は `text.color`。
- 入りきらないボタンの文字は「…」で切り、全文をツールチップに出す。AdvMenuPanel は follow_focus で選んだ項目に捲る。タイトルのメニューは縮めて収め、あふれたら ▲▼。
- デバッグの通知の `debug.notice_style.layer`：screen（ゲームの画面の中）・window（画面の外の層、幅 480 まで）・auto（見える幅が 320 未満なら window）。
- 作者が作った AdvSystemScreen の位置や色は、フレームワークは直さない。

## もっと詳しく

- 作り方の全体：`docs/getting-started.md`
- シーンの種類と準備：`docs/scenes.md`
- シナリオ・チャプター・シーン・セリフの関係：`docs/scenario-structure.md`
- 変数：`docs/variables.md`、式と条件式：`docs/expressions.md`
- シナリオエディタ：`docs/scenario-editor.md`
- 自作の部品（システム画面・テンプレート・入力・効果）：`docs/custom-components.md`
