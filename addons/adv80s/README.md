# adv80s アドオン

80年代風アドベンチャーゲームを作るための Godot 4 アドオン。仕様はリポジトリ直下の `SPEC.md` を参照。

## 現在の段階：段階7「Ink アダプタ」まで

| 範囲 | 内容 |
| --- | --- |
| Core | 状態（フラグ・変数・所持品・到達記録）、意図の受け取りと省略形の正規化、出力イベントの状態適用、乱数、問い合わせ、診断 |
| 条件式 | JSONの形と短い文字列の形（and/or/not、&&/\|\|/!、括弧、比較、組み込み条件）、`"= 式"` と `let` |
| 意図スキーマ | 標準動詞の定義、層の重ね合わせ（null で削除）、省略形の正規化 |
| 辞書 | 日本語・英語の同梱辞書、ひらがな/カタカナ・全角/半角の同一視、完全一致→語幹の照合 |
| JSONアダプタ | シーン、物、出口、アイテム、会話（地の文、`@話者`、`say`、`if`、`set`、`let`、`call`、`goto`、出力イベントの直接記述）、話題、行IDの自動付与、`validate` |
| 入力 | 日本式パーサー（空白なし入力・助詞による振り分け）、コマンド選択、コマンド入力欄 |
| Inkアダプタ（段階7） | 変換済みの Ink（`.ink.json`）の再生、JSON との受け渡し、変数の同期、外部関数、タグ、選択肢と意図、セーブ、`validate` |
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

段階4で加えたもの：

| 範囲 | 内容 |
| --- | --- |
| 選択肢 | 会話の `choice`（`when`、`once`、`id`）。`choice.show` で止まり、`CHOOSE` の意図で続きから再開する。JSON アダプタは手順をスタックで実行し、入力待ちの位置をセーブに含める |
| セーブ | バイナリ（HMAC-SHA256 の署名、任意で AES-256-CBC）とテキスト（JSON、デバッグ用）。改ざんと「鍵が違う」を区別。書き込みは一時ファイルから置き換え |
| 鍵 | `AdvKeyProvider`、`AdvEmbeddedKeyProvider`（環境変数 → 書き出し時に埋め込んだ鍵 → `master.key`）、`AdvPerUserKeyProvider`。ツールメニュー「adv80s: セーブの鍵を生成」、書き出し時に鍵を平文ではない形で同梱 |
| スロット | クイック、オート（枠を順番に使う）、番号つき。セーブ・ロードの画面（Esc）。オートセーブは `checkpoint` とシーン移動（`features.autosave.options.on`） |
| メッセージログ | 文章とプレイヤーの入力（入力した文字列、選んだコマンドや選択肢）を記録し、セーブに含める。ログの画面（F4、ホイール上）。件数は `features.message_log.options.max_entries` |
| スキップとオート送り | 既読スキップ（Ctrl を押している間、F3 で切り替え）。未読の文章と入力待ちで止まる。スキップ中は切り替え演出を cut、画面効果を省く。オート送り（F2） |
| プレイヤー設定 | `user://adv80s_settings.json`（文字速度の倍率、オート送りの間隔、未読もスキップ、フィルター、モダン機能の切り替え） |

段階5で加えたもの：

| 範囲 | 内容 |
| --- | --- |
| 記録 | `notebook.add`、`objective.set`、`hint.set`、`flow.mark`、`verbs.update`、`hotspots.update`、`input.mode` を Core が状態に記録し、セーブに含める |
| 問い合わせ | `verbs`（`tried`）、`objective`、`notebook`、`hints`、`flow`、`chapters`、`hotspots`（`tried_verbs`、`new`）、`topics`（`new`） |
| 進行の記録 | `user://adv80s_progress.dat`：到達した点とそこから再開する状態、読んだ行（既読スキップをプレイやセーブをまたいで効かせる） |
| システムメニュー | F1・右クリック・ゲームパッドの Start。セーブ、ロード、ログ、まきもどす、ヒント、もくてき、てちょう、フローチャート、チャプター、せってい（有効な機能だけ出す） |
| ヒント | 話題ごとに段階を1つずつ開く。話題の表示名はプロジェクト設定 `hint_topics`。`hint.set` で内容が変わると最初の段階に戻る |
| フローチャート・チャプター | シナリオの `flow`（`nodes`、`edges`）と `chapters`。到達した点から再開できる |
| 巻き戻し | 入力の直前の状態を残し、メニューの「まきもどす」やログの入力の行から戻る（`features.rewind.options.max_steps`） |
| 画面選択 | 入力UI `click`：動詞を選んでから画像の上の物を押す。動詞を選ばずに押すと `inputs.click_verb`（既定 `EXAMINE`） |
| 調べられる場所の表示 | マウスを重ねた物の名前を出す。F6 で全部の枠と名前を出す |
| 試したコマンドの表示 | コマンド選択で試した動詞と対象を薄く出す。まだ試していない物に印を付ける |
| アイコン選択 | 入力UI `icon`：動詞に画像ID `icon.動詞ID（小文字）` のアイコンを付ける |
| 拡張の動詞 | `GIVE`、`SHOW`、`PUSH`、`PULL`、`HIT`、`CALL`、`THINK`、`WAIT`（日本語・英語の辞書、意図スキーマ）。プロジェクト設定 `verbs` で有効にする |
| 設定画面 | 文字の速さ、オートの待ち時間、未読もスキップ、フィルター、画面の時代（`templates` を順に切り替え）、読みやすい文字、読み上げ、印の表示 |
| 読みやすいフォント | テンプレートの `fonts.readable`。なければ OS の読みやすいフォント（BIZ UD ゴシックなど）を使う |
| 読み上げ | Godot の読み上げ機能。ルビのある語はルビで読む。プロジェクト設定の `audio/general/text_to_speech` を有効にしておく |
| ゲームパッド・タッチ | ゲームパッドはフォーカス移動と決定・キャンセル、Start でメニュー。タッチはマウスとして扱う |

段階6で加えたもの：

| 範囲 | 内容 |
| --- | --- |
| 音 | `bgm.play`（`loop`、`fade`、`volume`）、`bgm.stop`（`fade`）、`se.play`、`voice.play`。素材マニフェストの `loop_start`（秒）と `volume` を使う。機種別の差し替えも効く。BGM はセーブに含め、ロードで鳴らし直す |
| ボイス | 台詞（`say` の `voice`）とログに結び付け、ログの ♪ を押すともう一度鳴らす。次の文章に進むと止める（設定 `voice_stop_on_advance`）。ボイスがあるときは読み上げない |
| 音量 | 設定画面で おんがく・こうかおん・こえ を変えられる |
| 聞き返し | 必須のスロットが足りないとき、Core が `input.request`（`slot`、`type`、`verb`、`prompt`）を返す。コマンド選択はそのスロットの候補を出し、コマンド入力は名詞だけで答えられる |
| 英語式パーサー | `inputs.parser_profile: "en"`。「OPEN DOOR」「USE KEY ON DOOR」「GIVE KEY TO GIRL」「LOOK AT」「PICK UP」など。冠詞を読み飛ばし、前置詞で名詞を区切る。自作のパーサーはスクリプトのパスで指定できる |
| palette_cycle | パレットで減色しているときに、`range` の色を `speed` 段/秒で回す。`duration` が 0 なら止めるまで続け、`speed: 0` で止める |

まだないもの：Ink アダプタ。

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

## 段階7の決めごと（Ink アダプタ）

- Ink の実行部分は GDScript で一から書いた（`adapters/ink/adv_ink_story.gd`、inkle 社の C# 版の動きにそろえた）。inklecate は制作時だけ使い、ゲームには含めない。対応する inkVersion は 19〜21。
- 未対応：`LIST`（使うと validate が `INK_LIST` を出す）。`RANDOM` とシャッフルのシーケンスは乱数の作り方が C# 版と違うので、同じ種でも結果は一致しない。
- シナリオの一覧の `.ink.json` は Ink のアダプタが読む。`.ink.json` だけなら Ink が主のアダプタになる。複数の `.ink.json` を並べると、ノットを持つ最初のファイルを使う。
- 受け渡し：JSON の `{"ink": "ノット"}` は出力イベント `adapter.enter` を出して止まる。Core が Ink を積んで `start`、Ink が選択肢なしで止まる（DONE、END、終わり）と `adapter.exit` を出し、Core が Ink を外して JSON の `resume` を呼ぶ。この2つのイベントは表示側へは渡さない。アダプタの基底クラスに `resume(result)` を足した。
- セーブは、すべてのアダプタの状態と積み上げの順番を持つ（`adapters`、`active`）。段階6までの形（`adapter`）も読める。
- 変数：Ink に入るとき、Ink のグローバル変数と同じ名前の Core の変数の値を Ink に写す。Ink の中で変わったグローバル変数は `state.set` で返す（プロジェクト設定 `ink.sync_variables: false` で止める）。
- 行：1行ごとに `text.show`。`@話者ID 文章` か `# speaker:ID` で台詞。行IDは `# id:…`、省略すると `ink:ノット#本文のハッシュ`。タグ `# voice:`、`# bg:`、`# bgm:`、`# se:`、`# {"image.show": {…}}`（JSONの手順と同じ書き方）で出力イベントを出す。そのほかのタグは `ext.tags`。
- 選択肢：項目の ID は `c0`、`c1`…。タグ `# intent:動詞[:対象[:with]]`（`*` は何でも）をつけると、コマンド入力の意図でも選べる。`# hidden` は一覧に出さない（全部 hidden なら選択肢の一覧を出さず、コマンド入力だけで進む会話になる）。intent タグがあるときは、選択肢を出していてもコマンド入力を受け付ける（`pending_choice` の `accepts_intents`）。合う選択肢がない意図には、辞書の既定の返事を出して待ち続ける。
- 外部関数：`has_item`、`item_count`、`item_add`、`item_remove`、`get_var`、`set_var`、`visited`、`talked`、`cond`（条件式）、`event`（種類, 引数のJSON）、`goto_scene`。これ以外は Ink 側に同じ名前の関数があればそれを使い、なければ validate が `INK_EXTERNAL` を出す。
- Ink に入るとき `state.mark`（talked、`ink:ノット`）を出す。選んだ選択肢は `chosen` に `ink:ノット#c…/c番号` で残す。
- validate のコード：`INK_LOAD`、`INK_VERSION`、`INK_UNSUPPORTED`、`INK_LIST`、`INK_EXTERNAL`、`INK_MISSING_KNOT`（JSON の `{"ink"}` の行き先）、タグの素材は `ASSET_NOT_FOUND`。
- タグだけの行は本文が空の行になる（C# 版と同じ）。アダプタは、その行の出力イベント以外のタグを次の行の `ext.tags` に回す。
- 確かめ方：`tests/ink/src/*.ink` を inklecate で変換したものを `tests/ink/` に置いている。`conformance.ink` は、inklecate の再生モード（`-p`）で選択肢を 1 2 1 2 1 1 2 と選んだ出力（`conformance.expected.txt`）と一字一句同じになることをテストで確かめる。`.ink` を直したら次のように作り直す。

```
inklecate -o tests/ink/sample.ink.json tests/ink/src/sample.ink
inklecate -o tests/ink/conformance.ink.json tests/ink/src/conformance.ink
printf '1\n2\n1\n2\n1\n1\n2\n' | inklecate -p tests/ink/src/conformance.ink > tests/ink/conformance.expected.txt
```

## 段階6の決めごと

- 必須のスロットが足りない意図には、文章の返事ではなく `input.request` を返す（引数に `verb`、`type`、足りないスロットまでを埋めた `intent` を足した）。
- 英語式パーサーは、前置詞をスロットの振り分けには使わず、意図スキーマのスロットの順に型で入れる。英語の辞書の `particles` は前置詞の一覧として使う。
- パーサープロファイルは、テンプレートの `inputs.parser_profile`（`ja`、`en`、またはスクリプトのパス）。
- `palette_cycle` は減色フィルターのパレットの番号で回す。パレットのないプリセット（ビット数で減色するもの）では使えない。
- BGM の `volume` は、イベントの `volume` とマニフェストの `volume` をかけ合わせる。

## 段階5の決めごと

- 出力イベントの短い書き方は、「.」を含まない `checkpoint`、`wait`、`group` にも使える（例 `{"checkpoint": {}}`）。
- 拡張の動詞は辞書で `"extended": true` にして、標準の一覧から外す。プロジェクト設定 `verbs` に書くと使えるようになる。
- 話題の表示名はプロジェクト設定 `hint_topics`（話題 → 表示名）。
- フローチャートは、シナリオの `flow`（点と線）と、出力イベント `flow.mark` で記録する到達で作る。到達したときの状態を進行の記録に残し、そこから再開できる。チャプターはシナリオの `chapters`（`node` に到達すると選べる）。
- 進行の記録（到達した点、読んだ行）はセーブとは別の、全プレイ共通のファイルに置く。
- 画面選択の範囲（`region`）は、画像の層の中の座標で書く。
- キー操作に F1（メニュー）、F6（調べられる場所の表示）、右クリック（メニュー）、ゲームパッドの Start（メニュー）を足した。

## 段階4の決めごと

- セーブの設定はプロジェクト設定の `save`（`protection`：hmac / hmac_aes / none、`on_tamper`：reject / warn、`text_format`、`dir`、`slots`、`key_provider`：embedded / per_user / スクリプトのパス）。
- 鍵がないとき、開発中（デバッグビルド）は仮の鍵を使って警告する。製品版ではセーブできない。
- `on_tamper: warn` は暗号化していないセーブだけに効く（暗号化したものは、署名が一致しなければ読まない）。
- オートセーブは、出力イベントをひとまとまり実行し終えた時点で行う（Core が状態をまとめて適用するため）。
- 選択肢を出している間は、ほかのコマンドを受け付けない。選択肢の項目の ID を省略すると `o1`、`o2`… になる。選択肢の ID を省略すると、場所と項目の名前から作る。
- 出力イベントの引数を仕様にそろえた：`state.set` は `name`、`scene.goto` は `scene`（`var` と `id` も読める）。
- キー操作は F2（オート）、F3（スキップの切り替え）、F4（ログ）、F5（クイックセーブ）、F9（クイックロード）、Esc（セーブ・ロード）、Ctrl（押している間スキップ）。コマンド入力の文字と重ならないように、ファンクションキーにした。

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
