# adv80s アドオン

80年代風アドベンチャーゲームを作るための Godot 4 アドオン。仕様はリポジトリ直下の `SPEC.md` を参照。

## 現在の段階：段階67「ふつうの設定画面の見直し、メニューが選んだ項目に付いて流れる、見直しの一覧」まで

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

サンプルは `res://tests/stage1/` にある（シナリオは `tests/stage1/scenario/stage1/`）。

## テスト

```
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_ui_tests.gd
godot --headless --path . --script res://tests/run_editor_tests.gd
```

`run_editor_tests.gd` は画面ありで動かすと、シナリオエディタの画面を `tests/_shots/editor_*.png` に書き出す。

全部のテンプレート（26 個）でゲームの中の画面を見直すときは、画面のテストの `--` の後ろに写真の置き場所と `--review` を付ける（数分かかる。うまくいかない画面は `review_68_*`、見本は `review_69_*` の写真）。

```
godot --path . --script res://tests/run_ui_tests.gd -- /tmp/shots --review
```

見直しが終わると、写真の置き場所に `index.html` ができる（行がテンプレート、列が画面。問題のある写真は赤い枠と、その中身の文）。ブラウザで開くと全部をひと目で見られる。

## マニフェストのコマンドライン

```
godot --headless --path . --script res://addons/adv80s/tools/manifest_cli.gd -- generate
godot --headless --path . --script res://addons/adv80s/tools/manifest_cli.gd -- check --up-to-date --strict
```

- 一度も読み込んでいないプロジェクト（CI で取り出した直後など）では、先に自動でインポートしてから実行する。
- 仕様の引数に加えて `--project <ファイル>` でプロジェクト設定のファイルを指定できる。

## 段階67の決めごと（設定画面、メニューの流れ、見直しの一覧）

- **設定画面の見直し**：`REVIEW_SCREENS` に settings。テストのゲームは設定を作者の画面（system_scenes.settings）にしているので、`_review_built()` が `modern._panel()`＋`_fill_settings()` でふつうの設定画面を組み立て、見える範囲に置いて確かめる（はみ出しと見分けにくい文字）。
- **メニューの流れ**：AdvMenuPanel の ScrollContainer を `follow_focus`。`add_button()` のボタンは `clip_text`＋「…」、説明に全文（GB・GBC の設定で長い項目が窓からはみ出さない）。
- **見直しの一覧**：`--review` では全部の画面の写真 `review_t_<テンプレート>_<画面>.png` を撮り（段階64〜66の review_68・69 はやめた）、`_review_results` に問題の文を覚え、`_write_review_index()` が写真の置き場所に index.html を書く。
- 見直しの結果：26 個のテンプレート × 14 の画面（364 枚）とも問題なし。

## 段階66の決めごと（▲・▼、クリック、Ctrl+Enter）

- **タイトルの ▲・▼**：`AdvTitleScreen._fit()` の終わりで `_more_up`・`_more_down`（題名の色の Label）をメニューの右上・右下（見える範囲の中）に置き、`_update_more()`（縦の棒の value・max_value・page から、上・下に流せる余りがあるときだけ出す）を棒の value_changed・changed で呼ぶ。
- **クリック**：ウィンドウの層のお知らせも `notice_at()`（global rect）でクリックを受ける。テストで確かめた。
- **Ctrl+Enter**：`_ok_key(window, e)`（OK ボタンを押す）を「組を変える」「書き出す」の窓に `_add_keys()` で。「ひな形の組」の窓は閉じるだけなので付けない。

## 段階65の決めごと（見直しを分ける、ほかの画面）

- **見直しを分ける**：`_review_all_templates()` は `--review`（`OS.get_cmdline_user_args()`）を付けたときだけ。ふだんは「info: 全部のテンプレートの見直しは --review を付けたときだけ」と出す。
- **見直す画面**：`REVIEW_SCREENS`（menu・log・save・hints・notebook・flowchart・chapters・endings・extras は開いて、title・fin・credits・image は `_review_built()` が組み立ててゲームの画面に入れる。クレジットは下から流れるので横だけ）。開かないものも問題として数える。
- **直したもの**：
  - フローチャート・チャプター：データのないゲームで開くと止まっていた（`AdvFlowView.setup()` に null）。いまは「フローチャートは ありません。」「チャプターは ありません。」と出す。
  - タイトル画面：項目を `_menu_scroll`（ScrollContainer。流せるが棒は出さず、選ぶと付いて流れる）に入れ、画面に入ってから `_fit()`：題名は見える範囲の幅に入るまで文字を 2 ずつ小さく（8 まで）、メニューは幅を項目に合わせ（見える範囲の幅 - 8 まで）、下がはみ出すなら題名の下まで上へ寄せ、それでも入らなければ見える範囲の下までの高さにして流す。多くのテンプレートで、タイトルのメニューが画面の下へはみ出していた。
- 見直しの結果：26 個のテンプレートで 13 の画面とも、はみ出し・見分けにくい文字なし。

## 段階64の決めごと（デバッグのお知らせの層、全部のテンプレート、見える範囲）

- **デバッグのお知らせの層**：debug.notice_style の `layer`（`NOTICE_LAYERS`：auto・screen・window。`DEBUG_NOTICE_STYLE_KEYS` とスキーマにも）。`show_debug_notice()` が `st["layer"]`（なければ auto）を `show_notice()` に渡し、`_notice_on_window(layer)`（デバッグの層がなければいつも画面。auto は `visible_rect().size.x < NOTICE_WINDOW_AUTO_WIDTH`＝320）なら `_debug_layer` に入れ、メタ "window"。折り返しの幅は `min(ウィンドウの層の幅, NOTICE_WINDOW_MAX_WIDTH＝480) - margin×2`。`_relayout_notices()` は層ごとに並べ、ウィンドウの層は上を `NOTICE_WINDOW_TOP`（36。デバッグのボタンの下）から。`_window_layer_size()`（大きさが 0 ならビューポート）。ふつうのお知らせはいつもゲームの画面。
- **全部のテンプレートの見直し**：画面のテストの `_review_all_templates()` が 26 個すべてで、ゲームを窓いっぱいにしてメニュー・ログ・セーブを開き、`_overflowing()`（はみ出し）と `_low_contrast()`（Label・Button（自分の地があればそれと）・RichTextLabel の文字と地の明るさの差が 0.3 より小さい）を調べる。うまくいかないものだけ `review_68_*`、見本として gbc・win・mx・4k は `review_69_*` の写真。段階63で直したあとは 26 個とも問題なし。
- **見える範囲**：`_relayout_notices()` はゲームの画面のお知らせを `visible_rect()` の中に並べ、折り返しの幅も見える範囲の幅で。AdvImageViewer の絵・見出し・枚数を見える範囲に。題名・おわり・クレジットは、テンプレートの設定で置くか真ん中寄せなので変えていない。

## 段階63の決めごと（小さい画面のゲームの中の窓、キー）

- **見直しのしかた**：画面のテストの GB・FC の見直しで、プレイヤーを窓いっぱい（FULL_RECT）にして（ふつうのゲームと同じ拡大と真ん中寄せ）、ログ・セーブ・メニュー・設定を開き、`_overflowing(node, area)`（clip_contents の窓で切ったうえで、見える範囲の外へ出た Label・Button・RichTextLabel）と写真（`review_66`・`review_67_*`）で確かめる。作者が自分で作った AdvSystemScreen（テストの設定画面）は作者の受け持ちなので写真だけ。
- **直したもの**：
  - `AdvTemplate.window_fill_color()`：window_skin の fill（なければ 0）。文字の色との明るさの差が `WINDOW_FILL_MIN_CONTRAST`（0.3）より小さければ、いちばん差の大きいパレットの色（パレットがなければ黒か白）。AdvMenuPanel・AdvSaveMenu・AdvLogView の地の色に。GB ではメニューの文字が地と同じ色で見えなかった。
  - AdvLogView：見出し・「ひょうじ」・文の色を text.color に（`_ready()`）。入力・お知らせの色は 6 色以下のパレットなら text.color（7 番はパレットの外で白になっていた）。「ひょうじ」の幅は `min(172, 画面の幅 - 8)` で「…」。
  - `AdvTemplate.visible_rect()`：プリセットの visible。メニュー・セーブ・ログはこの大きさで作り、`show_overlay()` が見える範囲に置く（FC では上の 8 が隠れて見出しが切れていた）。
  - AdvCommandSelect：ボタンの文字を `clip_text`＋「…」、説明に全文（GB のセーブの一覧が窓からはみ出していた）。
- **キー**：`_add_keys(window, handler)`・`_is_ctrl_key(e, keys)`。片付け `_on_tidy_key`（Ctrl+Z で `undo()`、Ctrl+Y・Ctrl+Shift+Z で `redo()`。戻せるものがなければ通す）、読み込む `_on_import_key`（Ctrl+Enter）、見た目 `_on_style_key`（Ctrl+Z で `restore_erased_style_set()`。フォーカスのある LineEdit に取り消しがあればそちら）。
- **小さい画面のお知らせの読みやすさ**：GB の写真では、お知らせの文字はゲームの文と同じ大きさのドット字で、これより小さくすると読めない。文字を小さくするかわりに、デバッグのお知らせをゲームの画面の外（ウィンドウの大きさの層）に出す設定を次の段階で考える。

## 段階62の決めごと（小さい画面、一覧が伸びる、キー）

- **小さい画面**：画面のテストで GB（160×144）・FC（256×240）に切りかえて、お知らせと選ぶ窓の写真（`review_64`・`review_65`）を撮り、画面に収まること・重ならないことを確かめる。選ぶ窓はデバッグの層（ウィンドウの大きさ）に出るのでテンプレートの大きさによらない。直したもの：`show_notice()` の折り返しの幅を `template.screen_size.x - margin × 2`（下限 48）に（段階61は画面の Control の大きさで、下限 160 だったので GB では折り返さなかった）。お知らせの `resized` で `_relayout_notices()`（折り返した高さが後から決まっても重ならない）。テストの中ではプレイヤーの大きさが 0 なので小さい画面は左上に等倍で出るが、ふつうのゲームでは窓いっぱいに拡大される。
- **一覧が伸びる**：片付け・組・書き出す・読み込むの一覧の ScrollContainer を縦に EXPAND_FILL。
- **キー**：`AdvKeyCatcher`（adv_key_catcher.gd。窓の中で `_input` を受け、handler が true なら止める）をひな形の窓に入れ、`_on_preset_key(e)`：Ctrl（mac は Cmd）+Enter で OK ボタン、Ctrl+Z で `undo_preset_edit()`（フォーカスのある TextEdit に `has_undo()` があればそちらに渡す）。Esc は ConfirmationDialog のもとからの動き。保存ボタンと「写す前に戻す」の説明にキーを書く。

## 段階61の決めごと（ゲームの中の見直し、読み込む窓の中身、違いの欄）

- **ゲームの中の見直し**：画面のテスト（run_ui_tests.gd）の終わりで、長い変数名・長い値・長い組名の「ひな形にするものを選ぶ」窓、長いデバッグのお知らせ、長い出力のコンソールの写真（`review_61〜63`）を撮る。直したもの：選ぶ窓の行の印は `clip_text`＋「…」＋説明に全文、変数は印と値の欄を 1:1、持ち物は 3:1。一覧は横に広げない。`show_notice()` は `reset_size()` のあと、画面の幅から左右の margin を除いた幅を超えるなら Label を `AUTOWRAP_WORD_SMART` にして幅を決め、もう一度 `reset_size()`（短い文は折り返さない）。コンソールは前から折り返していた。
- **読み込む窓の中身**：`static preset_value_summary(v)`（`preset_summary(name)` もこれを使う）。`import_row_tip(n)`（「ファイル：…」、同じ名前があれば「いま　　：…」）を行の説明に。
- **違いの欄が伸びる**：`_preset_diff` を縦に EXPAND_FILL、stretch_ratio 4（変数の欄より多めに伸びる）。

## 段階60の決めごと（ひな形の窓を並べ直す、読み込む組を覚える、見直し）

- **ひな形の窓を並べ直す**：`_on_files_changed()` でひな形の窓が見えていれば `refresh_preset_dialog_keep()`（`_fill_preset_cmp()` し直して前の比べる相手を選び直す。日時と「そこから動かす」も付け直す。欄の中身は触らない）。
- **読み込む組を覚える**：RUN_UI_FILE の `import_group`（"#file"・""・組の名前）。読み込めたときに `_remember_import_group(import_group_choice())`。`_fill_import_group_pick()` で選び直す（ない組の名前は「新しい組…」に入れる）。
- **見直し**：テストの終わりの `_review_windows()` が、ひな形の窓（比べる・いつもの始まり）・片付け・組・組を変える・書き出す・読み込む・見た目（比べる）・右クリックのメニューを長い名前で開いて `editor_review_*` の写真を撮る。直したもの：`static fit_check(cb, extra)`（「…」で切り、全文と extra を説明に）と `fit_list_scroll(sc)`（横に広げない）を片付け・組・書き出す・読み込むの一覧に。ひな形の窓を 600×600、違いの欄を 150 の高さに。「組を変える」の新しい組の欄は "#new" のときだけ出す。右クリックの「いまのシーンから実行」は `page >= Page.SCENE` のときだけ。ゲームを選ぶ窓（plugin.gd）は見直しに入れていない。

## 段階59の決めごと（並べ直す、全部写す、読み込む組）

- **片付けを並べ直す**：`_on_files_changed()`（モデルの `files_changed`）で片付けの窓が見えていれば `refresh_tidy_keep()`（印を覚えて `_refresh_tidy()` し、残っている名前の印を戻す。新しく出たものは初めの形）。
- **全部写す**：`tidy_diff_text()` の終わりの行に `[url=tidyall:L|R]` と薄い説明。`tidy_copy_all(to_left)`。一つずつも全部も `tidy_copy_values(from, to, [[kind, key], …], label)`（ひとまとまりで保存）を通る。
- **読み込む組**：`_import_group_pick`（メタデータ "#file"・""・組の名前・"#new"＋`_import_group_new`）。`import_group_choice()`（null＝ファイルのまま。新しい組の名前が空なら null）・`set_import_group(m)`・`_import_with_group(v)`（一覧の説明用）。`import_run_presets(path, names, overwrite, group_to := null)`（null 以外なら組を書きかえる。並びに足すのはその組だけ）。窓を開くたびに「ファイルの組のまま」に戻す。

## 段階58の決めごと（写す前に戻す、読み込む窓に組、片付けで写す）

- **写す前に戻す**：`preset_edit_undo`（{vars, items, what}。一つだけ）を `_remember_preset_edit(what)` で覚える（`add_start_var_to_dialog`・`add_all_start_vars_to_dialog`・`take_preset_value(kind, key, remember := true)`・`take_all_preset_values`。全部写すは一度だけ覚え、中の一つずつは remember=false）。`undo_preset_edit()`。`open_preset_dialog()` で忘れる。ボタン `_preset_undo_btn`「写す前に戻す」。
- **読み込む窓に組**：`static import_group_text(ps, v)`（「　［組：G］」、ない組は「（新しい組）」、組なしは ""）を名前と説明のあいだに。
- **片付けで写す**：`tidy_preview_text()` の比べは `tidy_diff_text()`（行ごとに `[url=tidy:L|R:kind:キー]`。L は右の値を左へ、R は左の値を右へ。左右は名前の順）。`tidy_copy_value(from, to, kind, key)`（保存して元に戻せる。from になければ消し、空になった vars・items は消す。同じ値・同じひな形・どちらにもないなら false）。片付けの窓を 560×540、中身の欄を 120 の高さに。

## 段階57の決めごと（組の並びを運ぶ、違いを写す、全部写す）

- **組の並びを運ぶ**：組（group）と作った日時（created）は前から書き出し・読み込みで運んでいた（`read_preset_file()`）。`export_run_presets()` は書き出すひな形の組を `preset_group_order()` の順に `group_order` として書く。`read_preset_file_group_order(path)`。`import_run_presets()` は、読み込む前になかった組で、足したひな形が使うものを、いまの並び（`preset_group_order()`）の終わりへファイルの順に足して `debug.run_group_order` に書く（同じひとまとまりで元に戻せる）。group_order がなければ並びは書かない。
- **違いを写す**：`diff_text(…, links := true)` で行を `[url=take:vars|items:キー]`、終わりに薄い説明と `[url=takeall]［全部写す］[/url]`（窓の違いと、いつもの始まりの違いで使う。片付けの比べはリンクなし）。`_preset_cmp_target()`（いつもの始まりなら `start_base()`）・`take_preset_value(kind, key)`（同じ値なら false。持ち物は整数）・`take_all_preset_values()`・`static set_assign_line(text, key, value)`（同じキーの行を一つにして書きかえ、null で消す。なければ終わりに足す。「#」の行・空の行はそのまま）。保存はしない。
- **見た目を全部写す**：`style_diff_text()` の説明の終わりに `[url=copyall]［全部写す］[/url]`。`copy_all_style_keys()`（左を右と同じ中身に。違ったキーの数。`style_last_erased` の kind "copy"、key "全部" で一度に戻せる）。

## 段階56の決めごと（知らせを消す、全部足す、キーを写す）

- **知らせを消す**：`_update_style_show()` の頭で `_style_msg` を空に。書く・消す・写すなどは、そのあとで知らせを出す（`_after_style_change()` は並べ直してから知らせる）。
- **全部足す**：`start_others_text()` の終わりに `[url=addall]［全部足す］[/url]`。`add_all_start_vars_to_dialog()`（`_start_vals` のうち窓にないものを名前の順に全部。並べた 20 を超えても足す。足した数）。
- **キーを写す**：`style_diff_text(…, links := true)` で違う行を `[url=copy:キー]`、終わりに薄い説明。`_style_show.meta_clicked` → `copy_style_key(key)`（同じ値・どちらにもないなら false。左が空になるなら写さない）。戻すのは `style_last_erased` を「最後の一つ」として使う（`kind`："erase" か "copy"。copy は同じ名前に書き戻す。名前を変えたら戻す先も変える）。ボタンは「一つ戻す」。

## 段階55の決めごと（押して足す、組を変える、見た目を比べる）

- **押して足す**：`start_others_text()` の一つずつが `[url=add:名前（uri_encode）]`。`_preset_diff.meta_clicked` → `add_start_var_to_dialog(name)`（`_start_vals` にあり、窓にまだないものだけ。欄の終わりに「名前 = 値」を足して並べ直す。保存はしない）。
- **組を変える**：`PresetCtx.GROUP`（「組を変える…（いまは 組）」）→ `open_move_group_dialog(name)`（`_move_group_pick`：メタデータ "" は組なし、組の名前、"#new" は新しい組で `_move_group_new` に書く）。`select_move_group(g)`・`move_group_choice()`・`set_preset_group(name, g)`（元に戻せる。同じ組なら false）。組の並びを動かす `move_preset_group(g, delta)` とは別。
- **見た目を比べる**：「見た目…」の `_style_cmp`（選んでいる見た目は除く）。`compare_style_with(name)`・`style_cmp_name`。`style_diff_text(a名, a, b名, b)`（値は `value_text` で比べる）。比べている方を選ぶと `_style_last_pick` と入れかえる。

## 段階54の決めごと（ひな形にない変数、右クリック、いまの見た目）

- **ひな形にない変数**：`start_others_text(preset, start_vars)`（`[color=#9ca3af]` で薄く。名前の順に `START_OTHERS_MAX`＝20 まで、あとは「…ほか n」）。`start_diff_text()` が違いの下に足す。
- **右クリック**：`run_preset_pick` の `gui_input`（閉じたまま＝`selected_preset`）と、その一覧（`get_popup()`）の `window_input`（`get_focused_item()` の行。組の見出しは除く）から `open_preset_context(name, at)`。中身は `preset_context_items(name)`（`[id, 文字, 押せるか]`、id は `PresetCtx`：RUN_LAST・RUN_HERE・OPEN・DUP）、押すと `preset_context_pressed(id, play)`。
- **いまの見た目を取っておく**：`keep_project_style(game, name)`（プロジェクト設定の notice_style か debug.notice_style を `AdvPlayer.put_notice_style_set()` で。空の名前は「いまの設定」、同じ名前があれば「名前 2」…。書いていなければ ""）。名前の欄は見た目がなくても書ける。

## 段階53の決めごと（見た目の名前・消す、いつもの始まり、そこから動かす）

- **見た目の名前・消す**：`AdvPlayer.rename_notice_style_set(game, old, new)`（できれば ""、できなければ理由。並びは保つ）・`erase_notice_style_set(game, name)`・`put_notice_style_set(game, name, values)`（static。コンソールの `drop` も erase を使う）。エディタは `rename_style_set()`・`erase_style_set()`（`style_last_erased` に {game, name, values} を一つだけ覚える）・`restore_erased_style_set()`（同じ名前があれば「（戻す）」を付ける）。user:// のファイルなので「元に戻す」ではなく「消したのを戻す」。
- **いつもの始まり**：「比べる：」の 2 番目（メタデータ `PRESET_CMP_START`）。`start_values()` は `AdvVariableIndex.collect()` の変数の default（Ink は JSON として読む）を窓を開いたときに読む（`_start_vals`）。`start_base(preset, start_vars)` はひな形にあるキーだけ（宣言のないものは入れない＝「なし」、持ち物は 0）。`start_diff_text()` は頭に「始めるシーン：いつもは entry　このひな形は最後に …」。
- **そこから動かす**：`run_from()` が `last_where[name].req`（頼みからひな形の名前と値を除いたもの）も書く。`preset_last_request(name)`（JSON の数を整数に戻す。req のない古い記録は {scene}）・`run_preset_from_last(name, play)`。ひな形の窓の `_preset_run_last`（使った場所がなければ押せない）。ひな形を消しても記録は消さない（元に戻せるので）。

## 段階52の決めごと（見た目をエディタから、二つを比べる、場所）

- **見た目をエディタから**：上の「見た目…」→ `open_style_sets_dialog(game)`（`AdvPlayer.notice_style_sets()` を読む。ゲームとエディタは同じ user:// を使う）。`apply_style_set(game, name)` が書いたキーだけを notice_style（ふつう）か debug.notice_style（デバッグ）に書く（fg などは整数に。元に戻せる）。窓はいまの値と違うキーに「（いま …）」を添える。
- **二つを比べる**：片付けの窓の `_tidy_compare`。印が二つなら `diff_text()`、ほかは「印を二つ付けてください（いま n）」。
- **場所**：`run_from()` がひな形を使うと `RUN_UI_FILE` の `last_where`（名前 → {scene, place}。place は `run_place_text()` から「から」を除いたもの）に書く。`preset_last_where(name)`（「hall ／ 会話 talk の 2 番目」）。ひな形の窓の日時の下に「最後に使った場所：…」。

## 段階51の決めごと（日時、見た目を取っておく、中身をのぞく）

- **日時**：ひな形の窓の `_preset_dates`（`preset_dates_text(name)`：「作った日時：…（今日）　最後に使った日時：…」。作った時刻がなければ「不明」、使っていなければ「未使用」、新しいひな形なら「（新しいひな形）」）。
- **見た目を取っておく**：`AdvPlayer.NOTICE_STYLE_SETS_FILE`（`user://adv80s_notice_styles.json`、`{debug: {名前: {…}}, game: {…}}`。パソコンごと）。`keep_notice_style(game, name)`・`use_notice_style(game, name)`・`next_notice_style(game)`（名前の順に一つずつ。終わりまで行くと頭へ）・`drop_notice_style(game, name)`・`notice_style_sets(game)`。コンソール `noticestyle [game] keep・use・next・list・drop`。
- **中身をのぞく**：`preset_summary(name)`（「a = 1、b = "x" ／ 持ち物 key × 2」、なければ「（中身なし）」）。片付けの窓の `_tidy_preview`（`tidy_preview_text()`、印を付けたものを名前の順に）と、それぞれの行のツールチップ。

## 段階50の決めごと（組で絞る、ふつうのお知らせ、作った順）

- **組で絞る**：`stale_presets(days, include_unused, now, group)`（group が "*" で全部、"" で組なし、ほかはその組）。片付けの窓の「探す組」（`open_tidy_dialog(group)`・`set_tidy_group(g)`・`tidy_group()`）。
- **ふつうのお知らせ**：`AdvPlayer.notice_style_override`（`notice_style()` のいちばん上に重なる。動かしている間だけ）、`set_game_notice_style(key, value)`（`GAME_NOTICE_STYLE_KEYS`。値の確かめは `_try_style()` でデバッグのお知らせと共通）、`save_game_notice_style_to_editor()`（`GAME_SETTINGS_FILE` の game_notice_style）。エディタの `import_game_settings()` はプロジェクト設定のいちばん上の notice_style に書く（返す辞書のキーは game_notice_style。debug に書くものがなければ debug は足さない）。コンソール `noticestyle game …`。
- **作った順**：ひな形の `created`（Unix 秒。`save_run_preset` は書きかえなら前の時刻のまま、ゲームからの取り込みは送った時刻、ファイルの読み込みはファイルの時刻かいま）。`preset_created(name)`。並べ方は `RUN_UI_FILE` の sort（"name"・"used"・"created"。`run_sort()`・`set_run_sort(mode)`、「実行：」の選ぶ欄 `_sort_pick`）。違い（`diff_presets`）には入れない。

## 段階49の決めごと（使った順、片付け、見た目を試す）

- **使った順**：`RUN_UI_FILE` の `sort`（"used"・"name"。パソコンごと）。`run_sort_by_used()`・`set_run_sort_by_used(on)`、「実行：」の「使った順」。`preset_pick_layout(…, used)` が組の中を最後に使った順（同じなら名前の順、使っていないものは下）に並べる。組の並びは変えない。
- **片付け**：`stale_presets(days, include_unused, now)`（最後に使ってから days 日以上。未使用は include_unused のときだけ）。`delete_run_presets(names)`・`set_presets_group(names, g)`（どちらもひとまとまりで元に戻せる）。「片付け…」の窓（`open_tidy_dialog()`・`set_tidy_check()`・`tidy_to_group()`・`tidy_delete()`。消すときは確かめる）。
- **見た目を試す**：`AdvPlayer.debug_notice_style_override`（動かしている間だけ。debug.notice_style の上、pre_set_style などの下に重なる）、`set_debug_notice_style(key, value)`（値を確かめる。だめなら理由の文）、`debug_notice_style_now()`、`save_debug_notice_style_to_editor()`。設定の書きかえは `_write_game_settings(section, values)` で `GAME_SETTINGS_FILE` の notices・notice_style に書き足す。エディタの `import_game_settings()` は `{notices?, notice_style?}` を返す（fg・bg・border は整数に）。コンソール `noticestyle`（表示）・`noticestyle キー 値`・`noticestyle test`・`noticestyle reset [キー]`・`noticestyle save`。

## 段階48の決めごと（組の窓から実行、設定に書く、最後に使った時）

- **組の窓から実行**：`run_with_preset(name, play)`（そのひな形を選んで、`run_scene_for_dialogue()` のシーンから `run_from`）。組の窓の「この組のひな形で：」（`_group_run_pick`）と「▶ 実行」（`run_group_pick()`。動かしたら窓を閉じる）。
- **設定に書く**：コンソール `notice save` → `AdvPlayer.save_debug_notices_to_editor()` が `GAME_SETTINGS_FILE`（`user://adv80s_game_settings.json`、`{notices: {種類: bool}}`）に書き足し、デバッガに `adv80s:settings_saved`。エディタは `import_game_settings()`（デバッガの知らせ → plugin → 画面、または窓に戻ったとき）で debug.notices に書き（知らない種類は飛ばす。元に戻せる）、ファイルを消す。
- **最後に使った時**：`run_from()` でひな形を使うと `RUN_UI_FILE` の `last_used`（名前 → Unix 秒）に書く（パソコンごと。たたんだ組 `folded` と同じファイル。`_run_ui()`・`_save_run_ui()`）。`preset_last_used(name)`・`used_label(t, now)`（今日・昨日・n日前・n週前・nか月前・未使用。その土地の日付で数える）・`used_datetime(t)`。「実行：」の一覧の名前のあとに「〔…〕」、ツールチップに日時。組の窓の一覧にも出す。

## 段階47の決めごと（並び順、出し入れ、コンソール）

- **並び順**：プロジェクト設定 `debug.run_group_order`（並べたい組の名前の配列）。`preset_group_order()` がいまある組だけを書いた順に、書いていない組を名前の順に足す（`run_preset_groups()` も同じ順）。`move_preset_group(g, delta)`（元に戻せる）。`preset_pick_layout(…, order)`。組の名前を変えると並びの中の名前も変わる。並びはプロジェクトに入る（たたむはパソコンごと）。
- **出し入れ**：`apply_group_members(g, names)`（names を g に、ほかで g のものは組から外す。ひとまとまりで元に戻せる）。組の窓の下の一覧（`_group_member_checks`、ほかの組のものは「（組：名前）」を添える）→「この中身にする」（`confirm_group_members()`）。
- **コンソール**：`notice`・`notice 種類|all on/off`・`notice on/off`・`notice reset [種類]`。`AdvPlayer.debug_notice_override`（動かしている間だけ。設定より先）、`set_debug_notice(kind, on)`（on が null なら設定に戻す）、`debug_notice_report()`、`DEBUG_NOTICE_KINDS`。

## 段階46の決めごと（組ごとの操作、たたむ、種類ごと）

- **組ごとの操作**：`run_preset_groups()`・`preset_names_in_group(g)`・`rename_preset_group(old, new)`（new が "" なら組を外す。たたんでいればたたんだまま新しい名前に）・`delete_preset_group(g)`・`export_group(g, path)`。どれもひとまとまりで元に戻せる。「組…」の窓（`open_group_dialog(g)`・`picked_group()`。消すときは確かめる）。
- **たたむ**：「実行：」の一覧の組の見出し（メタデータ `#group:名前`）を選ぶと `set_group_folded(g)`（選んでいたひな形はそのまま）。たたんだ組は `RUN_UI_FILE`（`user://adv80s_run_ui.json`、`folded_groups()`）に覚える。元に戻すでは戻らない（見た目のため）。
- **種類ごと**：プロジェクト設定 `debug.notices`（run_from・pre_set・reload・editor・preset・auto_reload）。`show_debug_notice(…, kind)` が `debug_notice_on(kind)` を見る。「先に設定」は `pre_set_notice` も見る。

## 段階45の決めごと（デバッグのお知らせ、組、絞り込み）

- **デバッグのお知らせ**：`show_debug_notice(text, kind_style, seconds, at, log)` がプロジェクト設定 `debug.notice_style`（fg・bg・border・se・icon・position・seconds）に kind_style を重ねて `show_notice()` に渡す。シーンから実行・先に設定（kind_style は pre_set_style）・読み直し・エディタにつながっていません・エディタで開く・ひな形にしました／書けません／選んでください・保存したら読み直す が使う。
- **組**：ひな形の `group`（"" は組なし）。`save_run_preset(name, vars, items, group)`、`preset_group(v)`。「実行：」は `preset_pick_layout(ps, filter, keep)` の順（組なし → 組の名前の順。見出しは `add_separator("組：…")`）。窓の「組」。複製・`read_preset_file`・ゲームからの取り込みで付いたまま。違い（`diff_presets`）には入れない。ゲームの選ぶ一覧の「組」の欄（`_picker_group`）。「送っても閉じない」に印を付けたとき空ならいまの名前を入れる。
- **絞り込み**：「実行：」の横の LineEdit（`set_preset_filter(text)`・`run_preset_filter`）。名前か組の一部（大文字・小文字は区別しない）。選んでいるものは合わなくても出す。
- **テスト**：UI テストの終わりに「ここまで来たか」を確かめる（途中のスクリプトのエラーで止まると失敗にする）。

## 段階44の決めごと（違いを見る、見た目、続けて送る）

- **違いを見る**：読み込む窓の下の `_import_preview`。`import_overwrite_preview()` が、上書きにして印を付けたものについて「名前 を上書き（いま → 読み込み）」と変数・持ち物の違いを並べる（なければ ""、窓では隠す）。印を変えるたびに付け直す。値の出し方は `AdvPlayer.value_text()`（`diff_text()` も同じ）。
- **見た目**：プロジェクト設定 `debug.pre_set_style`（fg・bg・border・se・icon）。`show_notice(text, seconds, icon, log, at, style)` の style で、fg・bg・border・se だけそのお知らせで変える。
- **続けて送る**：選ぶ一覧の「送っても閉じない（続けて送る）」（`picker_keep_open`）。送ったら `next_preset_name(name)`（末尾が「 数」ならその次、ほかは「 2」）を名前の欄に入れる。

## 段階43の決めごと（上書き、位置、戻す）

- **上書き**：`import_status(ps, name, v, overwrite)`（overwrite のときはその名前の中身とだけ比べ、違えば "overwrite"）。`import_run_presets(path, names, overwrite)`。読み込む窓の「中身が違うものは上書きする」（`set_import_overwrite(on)`・`import_overwrite`。切り替えると `_refresh_import_pick()` が説明と押せるかを付け直す）。元に戻せる。
- **位置**：プロジェクト設定 `debug.pre_set_position`（お知らせの位置と同じ値。書かなければお知らせの決まり）。
- **戻す**：`picker_remove()` が外したときの値と印を `_picker_removed` に残し、「外したものを戻す」（`picker_restore_removed()`、戻した数を返す）でまとめて戻す。同じ名前が一覧にあればそれはそのまま。外したものがなければボタンは押せない。

## 段階42の決めごと（選んで読み込む、秒数、外す）

- **選んで読み込む**：「読み込む…」でファイルを選ぶと `open_import_pick(path)`（`read_preset_file(path)` で読み、`import_status(ps, name, v)` が "new"・"same"・"rename"。"same" は印なしで押せない。"rename" は `import_rename_target(ps, name)` の名前を出す）→ `confirm_import_pick()`（`set_import_all()`・`set_import_check()`。一つも選ばなければ []）→ `import_run_presets(path, names)`。
- **秒数**：プロジェクト設定 `debug.pre_set_seconds`（0 でクリックするまで。書かなければお知らせの決まりの秒数）。
- **外す**：選ぶ一覧の行の「×」→ `picker_remove(key)`（足した行も、もとからの行も。外したものはまた `picker_add` で足せる）。

## 段階41の決めごと（選んで書き出す、切り替え、足す）

- **選んで書き出す**：「書き出す…」は `open_export_pick()`（ひな形の一覧。初めは全部に印。`set_export_all()`・`set_export_check()`）→ `confirm_export_pick()`（一つも選ばなければ false。全部に印なら `export_names = []`、ほかは選んだ名前）→ ファイルを選ぶ窓 → `export_run_presets(path, export_names)`。
- **切り替え**：プロジェクト設定 `debug.pre_set_notice`（お知らせ）・`debug.pre_set_log`（メッセージログ）。どちらも既定 true。
- **足す**：選ぶ一覧の下の行（種類・名前・値・「足す」）。`picker_add(kind, name, value)`（kind は "v"・"i"。印を付けて足す。あれば値を書きかえる。名前が空なら false。持ち物の個数は空なら 1、数でなければ 1）。

## 段階40の決めごと（先に設定した値、書き出し・読み込み、値の書きかえ）

- **先に設定した値**：アダプタが先に動かす手順の前後に `{"_pre_sets": "begin"}`・`{"_pre_sets": "end"}` を積み、その間の set・let で入った値を `pre_set_log`（入った順）に残す。問い合わせ `"pre_set_log"`（なければ null）。ゲームは `_boot()` で `pre_set_text(log, 4)` をお知らせに（ログには出さない）、`pre_set_text(log, 0)` をメッセージログ（`add_notice`）に。
- **書き出し・読み込み**：`export_run_presets(path, names := [])`・`import_run_presets(path)`（`PRESET_FILE_FORMAT`。同じ名前で同じ中身は飛ばす。前に読み込んだ「（読み込み）」の名前に同じ中身があっても飛ばす。違えば「（読み込み）」「（読み込み 2）」…。ひとまとまりで元に戻せる）。窓の「書き出す…」「読み込む…」は FileDialog（ファイルシステム）。
- **値の書きかえ**：選ぶ一覧の行は印・名前・値（変数は LineEdit、持ち物は SpinBox）。`picker_preset()` が印の付いたものを欄の値で `{vars, items}` に（`parse_value_text`：JSON として読めればその値、読めなければ文字。`value_text` は整数の小数を整数で）。`set_picker_value(key, value)`。送るのは `send_preset_data(name, data)`。絞り込みは行ごと隠す（`_picker_row_visible`）。

## 段階39の決めごと（条件も、複製、絞り込み）

- **条件も**：頼みの `pre_sets` は `true`（設定するだけ）か `"cond"`（もしも見る）。エディタは `run_pre_cond`（「条件も」。「設定を先に」がないと押せない）、`pre_sets_mode(v)` が `""`・`"plain"`・`"cond"`。アダプタは `sets_before(arr, idx, with_ifs)` → `sets_only(steps, with_ifs)` で「もし」を中の set・let・もしだけに絞って積む（中が空の「もし」は入れない）。条件は積んだものを動かすときに見るので、それまでの設定が効く。履歴では別の実行として「（設定を先に・条件も）」。
- **複製**：`duplicate_run_preset(src, new_name := "")`（保存してあるものを写す）、窓の「複製」は `duplicate_preset_in_dialog()`（書いている中身を保存し、写しを開いてもとと比べる）。名前は `unique_preset_name(base)`。
- **絞り込み**：`filter_picker(text)`（名前の一部、大文字・小文字は区別しない。見えている数を返す）。`set_picker_all()` は見えているものだけ。`picker_selection()` は隠れたものも含む。

## 段階38の決めごと（比べる、設定を先に、選んでひな形に）

- **比べる**：`AdvScenarioEditor.diff_presets(a, b)` が `[{kind: "vars"|"items", key, a, b}]`（ない方は null。数は 3 と 3.0 を同じと見る。種類・名前の順）、`diff_text()` が窓に出す文。窓の「比べる：」（`_preset_cmp`、書いているひな形のほか）で選び、窓に書いている中身（`_preset_in_dialog()`）と比べる。`compare_preset_with(name)`。
- **設定を先に**：頼みの `pre_sets: true`（会話の画面の「設定を先に」、`run_pre_sets`）。アダプタの `_enter_path(path, pre_sets)` が通り道のそれぞれの段で始める場所より前の set・let（`sets_before(arr, idx)`、「もし」の中までは見ない）を集め、いちばん上に積んで先に動かす。Ink のノットからは使わない。履歴では別の実行として数え、「（設定を先に）」と出す。
- **選んでひな形に**：ゲームの「ひな形に」は `open_preset_picker()`（変数・持ち物の一覧。初めは全部に印）。`set_picker_check("v:名前" / "i:ID", on)`・`set_picker_all()`・`picker_selection()`・`confirm_preset_picker()`（何も選ばなければ送らない）・`close_preset_picker()`（Esc）。`send_preset_to_editor(name, only)`・`preset_from_state(st, only)` の only は `{vars: [名前], items: [ID]}`（null で全部）。コンソールの `preset` は全部。

## 段階37の決めごと（ゲームからひな形、入れ子から、お気に入り）

- **ゲームからひな形**：`AdvPlayer.send_preset_to_editor(name)`（デバッグの「ひな形に」、コンソール `preset [名前]`。名前を省くと「シーン 時:分:秒」）が `GAME_PRESETS_FILE`（`user://adv80s_game_presets.json`、`[{name, vars, items, time}]`）に書き足し、デバッガにつながっていれば `adv80s:preset_saved`。中身は `preset_from_state()`（書かれた変数のうち定数でないもの、持ち物）。エディタは `import_game_presets()`（デバッガの知らせ → plugin → 画面、または `NOTIFICATION_APPLICATION_FOCUS_IN`）でひとまとまりに書き（元に戻せる）、ファイルを消す。
- **入れ子から**：頼みの `path`（`get_steps()` の形での道筋。数は手順の番目、文字はキー。選択肢の項目の番目は `"0"` のように文字）。エディタは `AdvStepEditor.selected_path()`・`path_of()`（「そうなら」の行・項目の行そのものは、その中の最初）。アダプタの `_enter_path()` は通った手順の次を外の枠の続きにし、中の配列を積む（条件は見ない。枝がなければ外の続き）。道筋が1つなら `line` にする。`AdvPlayer.take_run_from()` は番目を整数にそろえる。表示は `path_text()`（「2 › そうなら › 1」）・`run_place_text()`。
- **お気に入り**：履歴の記録の `fav: true`。`_write_history()` がお気に入りを上に並べ、ほかだけ 10 件まで。`toggle_favorite(i)`、「履歴を消す」は `clear_history_keep_favorites()`。もう一度動かすときも印は残る。

## 段階36の決めごと（ひな形、途中から、履歴）

- **ひな形**：プロジェクト設定 `debug.run_presets`（名前 → `{vars, items}`）。エディタは `run_presets()`・`save_run_preset()`・`delete_run_preset()`（元に戻せる）、窓は「名前 = 値」の行（`parse_assign_lines`。値は JSON として読めればその値、読めなければ文字列）。実行の頼みにはそのときの値を入れ、ゲームは `apply_run_values()` で始める前に `set_var`・持ち物の個数を入れる（0 以下は持たない）。
- **途中から**：頼みの `dialogue`・`line`（いちばん上の段の何番目か。0 から）か `knot`（「ノット.ステッチ」も）。`AdvCore.start_at(entry, at)` → 主のアダプタの `start_at`（JSON：シーンに入ってから入ったときの手順を捨て、会話を呼んでその番目から。ノットは `adapter.enter`）。`start_at` のないアダプタはふつうに始める。
- **履歴**：`user://adv80s_run_history.json`（新しい順に 10 件。同じシーン・会話・行・ノット・ひな形は先頭へ）。ひな形の値は入れず、もう一度動かすときに読み直す（消えたひな形は「なし」で動かす）。
- **頼みのファイル**：`AdvPlayer.take_run_from()` が頼みをまるごと返す（`take_run_from_request()` はシーンだけ）。`run_from` に残し、お知らせは `run_from_text()`。

## 段階35の決めごと（このシーンから実行、会話・ノットを開く、大きさ）

- **このシーンから実行**：`AdvScenarioEditor.run_from_scene(id)` が `AdvPlayer.RUN_FROM_FILE`（`user://adv80s_run_from.json`、`{scene, time}`）を書き、エディタの中なら `EditorInterface.play_main_scene()`。ゲームはデバッグビルドの `_boot()` で `take_run_from_request()`（読んで消す。30秒より古いものは使わない）があれば、タイトルを通らずそのシーンから始める（`run_from_scene`、お知らせ「シーンから実行：…」）。
- **会話・ノットを開く**：アダプターの問い合わせ `"location"`（JSON は `{scene, dialogue}`、Ink は `{knot}`）を `current_location()` でまとめ、`adv80s:open_scene` で `[id, loc]` を送る。エディタは `open_location(scene, loc)`：会話はチャプターを探して開き、ノットは Ink のソースから `== 名前` の行を探してその行に移る。
- **大きさ**：`AdvPlayer.file_stamp(path)` が `"更新時刻:大きさ"`。プロジェクト設定・シナリオのファイルの見張り（`watch_snapshot`）とエディタの `files_snapshot` で使う（素材フォルダは更新時刻だけ）。

## 段階34の決めごと（外の書き換え、ファイルの数、エディタで開く）

- **外の書き換え**：`AdvScenarioEditor.files_snapshot()`（プロジェクト設定・シナリオのファイル・Ink のソース → 更新時刻）を、読み直したときとエディタで書いたとき（`files_changed`）に取っておき、`NOTIFICATION_APPLICATION_FOCUS_IN` で `check_external_changes()`。更新時刻は秒の単位なので、1秒の中の二度目の書き換えは気づかないことがある。
- **ファイルの数**：`changes_text(changes, limit)` の limit に `debug.notice_files`。
- **エディタで開く**：ゲームの `request_open_in_editor(scene_id)` が `EngineDebugger.send_message("adv80s:open_scene", [id])`。エディタは `editor/adv_debugger_plugin.gd`（EditorDebuggerPlugin、`open_scene_requested`）を `plugin.gd` で足し、`open_scene_in_editor` → `adv_editor_screen.open_scenario_scene` → `AdvScenarioEditor.open_scene_by_id`。

## 段階33の決めごと（エディタからの入・切、変わったファイル、自動の確かめ直し）

- **エディタからの入・切**：シナリオエディタの `auto_reload_toggle`（`set_auto_reload_setting(on)` がプロジェクト設定 `debug.auto_reload` を書く。元に戻せる）。ゲームはデバッグビルドで `DebugPoll`（2秒ごと、`poll_debug_settings()`）がプロジェクト設定のファイルの更新時刻を見て、`debug.auto_reload` が前と変わっていれば `set_auto_reload` で合わせる（コンソールで入・切したものは、設定が変わらなければそのまま）。
- **変わったファイル**：見張りは `watch_snapshot()`（ファイル → 更新時刻）と `watch_changes(now)`。`debug_reload` のあと `last_reload_changes`、`changes_text()` でお知らせ、`print`、コンソール。
- **自動の確かめ直し**：`AdvScenarioModel.files_changed`（ひとまとまりの書き換え・元に戻す・やり直すのあと）を、エディタが `_on_files_changed` で受け、ID の確認の一覧を出していれば次のフレームで `refresh_check`。

## 段階32の決めごと（自動の読み直し、入り直し、書き出し）

- **自動の読み直し**：`set_auto_reload(on)`（Timer `ReloadWatch`）、`check_watch()`（`_watch_signature()` が変われば読み直す。忙しいときは `_watch_pending` で次へ）。見張るのはプロジェクト設定・シナリオのファイルと、素材フォルダの中のファイル（.import・.uid を除く。アドオンの標準は除く）の更新時刻。起動時に `debug.auto_reload` なら入れる。
- **入り直し**：`debug_reload(reenter)`（null ならプロジェクト設定 `debug.reload_reenter`）。入り直しは `core.start(いまのシーン)`（変数などはそのまま。`first` は初めてのときだけなので動かない）。Shift+F8、`reload enter`。
- **書き出し**：`AdvScenarioEditor.export_check(path)`（`check_view` の行。.csv は BOM つきの CSV、ほかはテキスト）と `export_dialog`。

## 段階31の決めごと（絞り込み、確かめ、読み直し）

- **絞り込み**：`check_kind_pick`・`check_file_pick`、`set_check_filter(kind, file)`。一覧の行は `check_view` で `check_results` の番号に対応させる。
- **確かめ**：`fix_selected(same_id, confirm = true)`。まとめて直すときは `fix_confirm`（ConfirmationDialog）に書き換える場所を出し、OK で `_do_fix`。
- **読み直し**：`AdvPlayer.debug_reload()`（デバッグビルド。F8、デバッグのボタン、コンソールの `reload`）。`_make_save_data` で取っておき、プロジェクト設定を読み直し、素材はいまの素材フォルダを `AdvManifestGenerator.scan` で読み直した新しい `AdvAssets` に替え、主のアダプタを作り直してシナリオを読み、確かめ（`missing_ids`）をし直してから `_apply_save_data` で戻す。シグナル `reloaded`。

## 段階30の決めごと（Ink の確認、まとめて直す、デバッグ実行の一覧）

- **Ink**：`AdvScenarioEditor.all_ink_sources()`（シナリオのフォルダの ink/*.ink）と `_scan_ink`（タグ `INK_TAG_KINDS`、JSON のタグは `arg_id_kind`、`call_scene`・`goto_scene` の文字列）。結果は行番号 `line` を持つ。
- **直す**：結果に `kind`・`id`・`fix_path`（JSON の中の道筋）か `line`（Ink）。`fix_selected(same_id)` → `apply_fixes(targets, new_id)`（ファイルごとに `model.begin/end` でまとめて書く。Ink は `_replace_ink_ref` で `tag:ID` と `"ID"` だけを置き換える）。
- **共通の確かめ**：`core/adv_id_check.gd`（`AdvIdCheck.asset_kind_of`、`check_project`）。エディタの `asset_kind_of` はこれを使う。
- **デバッグ実行**：`AdvPlayer.missing_ids`（起動時の診断のうち `ASSET_NOT_FOUND`・`MISSING_TARGET`・`SUBSCENE_KIND` と、`AdvIdCheck.check_project` の結果）。デバッグコンソールの `ids`。

## 段階29の決めごと（ID の確認の一覧、お知らせの消え方と位置、ログの文言）

- **ID の確認**：`AdvScenarioEditor.scan_missing_ids()`（プロジェクト設定とシナリオのファイルをたどる。シーンの中はシーンからの道筋で `form_check`、手順の出力イベントは `ARG_ID_KINDS` の引数を `missing_message`）。候補は確かめる間 `_cand_cache` に取っておく（持ち物は全シナリオの持ち物）。一覧は `check_panel`・`check_list`、`show_check_panel(on)`、`open_check_result(i)`。
- **消え方と位置**：`notice_style.overflow`、`show_notice` の最後の引数 `at`（位置）、`notice.show`・`notices` の項目の `position`。
- **文言**：`notice_style.log_labels` を `AdvLogView.set_filter` が重ねる。

## 段階28の決めごと（見つからない ID、お知らせの上限、ログの出し分け）

- **注意**：`AdvSchemaForm.check`（func(path, value) -> String）と `_apply_check`（赤字 `WARN_COLOR`、項目名の説明の先頭に「⚠ 理由」、`warning_of`）。シナリオエディタの `form_check` と `missing_message(kind, id, known)`（画像は「ID@違い」の ID で確かめる）。おわりの画面の then の title・new・quit・stay、システム画面の .tscn は注意しない。
- **上限**：`notice_style.max`（既定 5）。超えたら `_dismiss_now` で古いものから消す。`_relayout_notices` が位置ごとに出した順に並べ直す（出したとき、消えたとき）。
- **ログ**：`AdvLogView.set_filter`（`all`・`text`・`notice`）、`filter_button`（お知らせがあるときだけ）、Tab キー。開いたときは `notice_style.log_filter`。

## 段階27の決めごと（お知らせの消し方とログ、音の試し鳴らし）

- **消し方**：お知らせのクリックは `AdvPlayer._input` の最初で受け取る（`notice_at(pos)` → `dismiss_notice`。文字送りの前に止める）。`seconds` が 0 なら時間のトゥイーンを作らない。
- **ログ**：`AdvMessageLog.add_notice`（種類 `notice`）。`AdvLogView.open` の最後の引数にお知らせの見た目（`log_mark`・`log_color`）。
- **試し鳴らし**：`AdvSchemaForm.audio_kind` と `play_requested`（▶ のボタン `BTN_PLAY`）。シナリオエディタの `play_audio(kind, id)`（同じ音ならもう一度で止める、`playing_audio`）、`form_audio_kind`、`AdvScenarioModel.asset_path`。手順のエディタは `audio_player`。

## 段階26の決めごと（お知らせの絵とログ、画像の見本）

- **絵**：`show_notice(text, seconds, icon, log)`。中身は HBox（`Icon` の TextureRect と `Text` の Label）。持ち物の絵はシナリオの `items.<ID>.icon`、JSON アダプタの問い合わせ `item_info`（手放したあとでも名前と絵を返す）。`notice_entry(key)` は `notices` の項目を `{text, icon, log}` にそろえる。
- **ログ**：`notice_style.log`（既定 false）か、`notice.show`・`notices` の項目の `log`。残すときは `message_log.add_text`。
- **見本**：`AdvSchemaForm.preview`（func(path, value) -> Texture2D）。絵は項目名の列に出す（値の列が一覧のときは絵が描かれないため）。シナリオエディタは `form_preview`（`asset_kind_of` が image の項目）、手順のエディタは `image_source`（`arg_id_kind` が image の引数）。

## 段階25の決めごと（お知らせの見た目・場面、ID の一覧と手入力）

- **見た目**：`AdvPlayer.notice_style()`（既定 → テンプレートの `notice` → プロジェクト設定 `notice_style`）。`show_notice` の seconds が負なら見た目の秒数。`_notice_position` は同じ位置のお知らせと重ならないようにずらす（下の位置は上へ）。スキーマは `definitions.notice_style`（テンプレートとプロジェクトで共通）。
- **場面**：`AUTO_NOTICES`（item.add・item.remove・notebook.add・objective.set・hint.set）と `notice_text(key)`（`notices.enabled` が false なら ""）。オートセーブは `autosave()` のあと。
- **ID**：`AdvStepEditor.ARG_ID_KINDS` と `arg_id_kind(event, path)`、`id_source`（シナリオエディタの `id_candidates(kind)`：素材・シーン・持ち物）。`AdvSchemaForm` の候補の一覧の最後に `MANUAL`（「（手で入力…）」）を足し、選ぶと値を聞く（`set_manual_value`）。image.show・sprite.hide の id は「文字列か配列」。

## 段階24の決めごと（引数のフォーム、お知らせ、デバッグ）

- **引数のフォーム**：`tools/build_schemas.py` の `EVENT_ARGS` を、シナリオのスキーマの `definitions.event_args` に書き出す（fin.show は `#/definitions/fin`）。`AdvStepEditor.event_args_schema(name)` で読み、`args_form`（AdvSchemaForm）で書く。定義のないイベント（`x.*`）は JSON の欄。項目のないイベントは「引数はありません」。
- **お知らせ**：出力イベント `notice.show`。プロジェクト設定 `notices`（item_add・notebook_add）は `_auto_notice` が `_play` で見る（システムシーンの中を除く）。`show_notice` は出ているお知らせの下に並べる。
- **デバッグ**：`AdvProgress.clear_read()`・`clear_flow()`・`clear_openings()`。コンソールに `progress`・`read clear`・`flow clear`（`chapters clear`）・`openings clear`・`progress clear`。

## 段階23の決めごと（特典のお知らせ、タイトルの開いた数、デバッグ、シナリオエディタ）

- **お知らせ**：`AdvPlayer.check_bonus_unlocks()`（新しく開いた特典の名前を返す。`progress.seen["bonus"]` に「一覧:名前」で残す）と `show_notice(text)`・`notices()`。`_play` の image.show・bgm.play で初めて見た・聞いたとき（`AdvProgress.mark_seen` が true を返す）と ending.reach のあとに呼ぶ。
- **開いた数**：`fill_extras_sys` が `sys.extras_opened`・`sys.extras_total` も入れる。`AdvTitleScreen` は `extras.title_count` なら「おまけ」に数を足す。
- **デバッグ**：`AdvProgress.clear_extras()`・`clear_endings()`。デバッグコンソールに `player`（AdvPlayer）を渡し、`extras`・`extras clear`・`extras unlock`・`endings clear` を足した。
- **シナリオエディタ**：`GAME_TABS` にタイトル・おわり・おまけ・システム。`_suggest` が `asset_kind_of(keys)` で素材の ID（`AdvScenarioModel.asset_ids(kind)`）を、オープニング・システム画面・next・fin.then でシーンの ID を出す。`AdvStepEditor` に種類 event（`DOTLESS_EVENTS` と点のある名前の1キーの手順。名前の一覧は `event_names()` でシナリオのスキーマから読む）。`AdvScenarioModel.scenes()` が kind も返し、カードに種類を出す。

## 段階22の決めごと（おまけの見本の画像、曲の説明、特典）

- **見本の画像**：`AdvModernUI.gallery_thumb(entry)` と `_set_thumb`（Button.icon、`icon_max_width` 64）。`extras.thumbnails`。
- **曲の説明**：`_music_desc`（name_color の色の行）。`extras.music_desc`。
- **特典**：`AdvPlayer.fill_extras_sys()`（特典を除いて sys.gallery_* と sys.music_* を数える。can_open_extras、open_gallery、open_music から呼ぶ）、`extra_listed(entry, kind)`（一覧に出すか）、`extras_bonus_on()`。`extra_unlocked` は特典なら when（既定 sys.<一覧>_all）。`extra_pages` は特典なら全部の画像。
- スキーマの `title_menu` に `opening`、`extras` を足した（段階17・20で使えるようにしていたが、スキーマに入れ忘れていた）。

## 段階21の決めごと（おまけの拡張）

- **並べる項目**：`AdvPlayer.extras_menu()` が `extras.menu`（既定 gallery、music）のうち出せるものを返す。`can_open_extras` はこれが空なら出さない。`AdvModernUI.open_extras` は endings なら `open_endings`、opening はタイトルから開いたときだけ `replay_opening`。
- **めくれる画像**：`extra_ids(entry)`（images か id）、`extra_pages(entry)`（when があれば全部、なければ見たものだけ）。`AdvImageViewer.setup` は Texture2D かその並びを受け取り、`next_page`・`prev_page`・`page_count` を持つ。
- **音楽の鳴らし方**：`AdvAudio.bgm_finished`（ループしない BGM が鳴り終わった）と `set_bgm_loop(loop)`（鳴らしている曲のくりかえしを変える）。`AdvModernUI.music_mode()`・`music_play(i)`、鳴り終わると `_on_music_finished` が次の開いている曲へ。プレイヤー設定 `music_mode`。

## 段階20の決めごと（クリアデータの引き継ぎ、タイトルのメニューの差し替え、おまけ）

- **引き継ぎ**：`save_carry` はクリアデータの meta の `carry` に入る。`load_game` は meta.clear なら `_carry_over(carry)`：`"all"` は何もしない、それ以外は `duplicate_state` で取っておき、`_initial_data` に戻してから選んだもの（vars・items は全部か名前の配列、visited・talked・notebook・chosen は丸ごと）を写す。
- **メニューの差し替え**：JSON アダプタの `_with_variants` が `menu` も重ね、`_push_menu` も variants を通す。テンプレートのタイトル画面は `title_variant()` の `menu`・`labels` と、プロジェクト設定 `title_labels`。
- **おまけ**：`AdvPlayer.can_open_extras`（show、when）と `extra_unlocked`、`AdvModernUI.open_extras`・`open_gallery`・`open_music`、`presentation/adv_image_viewer.gd`（`AdvImageViewer`）。`AdvProgress.seen`（image・bgm）は `_play` の image.show（重ねる絵は要素ごと）と bgm.play で記録する（システムシーンの中を除く）。`_fill_title_sys` に `sys.extras` を足し、ほかの値は `_fill_title_sys_basic` に分けた（can_open_extras から呼ぶため）。

## 段階19の決めごと（クリアデータのセーブ、見たエンディングでタイトルを変える、おわりの画面の複数行）

- **クリアデータ**：`AdvPlayer.offer_clear_save(settings)`（`show_fin` が `save_prompt` のとき、閉じたあとに呼ぶ）。はいなら `_clear_meta`（clear、ending、resume）を立てて `open_save_menu("save")`。`_make_save_data` は meta に `_clear_meta` を重ねる（JSON のシステムシーンの取っておいた状態にも入る）。`list_saves` は「クリア」を付ける。`load_game` は meta.clear なら、ログを消して `core.start(resume か開始シーン)`。
- **JSON のシステムシーンも閉じるまで待つ**：`_open_custom_system` は JSON のシステムシーンを開いたら `system_scene_closed` を待つ（`open_save_menu` などの「閉じるまで待つ」をそろえた）。`close_system_scene(notify)` が出す。`system.load` は、閉じてロードしたあとに出す。`_reset_state` で閉じたときも出す。
- **見たエンディングでタイトルを変える**：`_fill_title_sys` が `sys.endings_seen`・`sys.endings_total`・`sys.all_endings`・`sys.ending_<ID>` を入れる（起動時、タイトルを始めるとき、システムシーンを閉じたとき）。JSON アダプタの `_with_variants` がシーンの `variants`（image、bgm、bgm_fade）を `_enter_scene` で重ねる。テンプレートのタイトル画面は `AdvPlayer.title_variant()`（プロジェクト設定 `title_variants`）。validate は variants の条件と素材を確かめる。
- **おわりの画面の複数行**：`AdvCredits.build_items`（スタッフロールの行の組み立てを static にしたもの）を `AdvFinScreen` でも使い、出したあと（call_deferred）に縦の真ん中へ寄せる。

## 段階18の決めごと（おわりの画面、オープニングを見返す、Ink のサブシーンの確認と候補）

- **「おわり」の画面**：`presentation/adv_fin_screen.gd`（`AdvFinScreen`）。設定は `AdvFinScreen.merge_settings`（`DEFAULTS` → プロジェクト設定 `fin` → シーンの `fin` → `fin.show` の引数。bool は show）。AdvPlayer の `_run` の終わりで、kind `ending` のシーンに選択肢がなく、そのシーンでまだ出していなければ（`_fin_scene`。シーンが変わると消す）`show_fin` する。`fin.show` は `_pending_action`。閉じる条件は `_input`（click・key・key:名前）、`_process`（秒数）、`trigger(名前)`（`AdvPlayer.fire_trigger`）。`min_time` まではキーで閉じない。閉じたら `then`（title・new・quit・stay・シーンID と reset）。出し入れは `AdvScreen.transition_group`。
- **オープニングを見返す**：`AdvPlayer.can_replay_opening`（プロジェクト設定 `opening_replay`）と `replay_opening`（`_reset_state` してから `_opening_replay` を立てて流す）。`_track_opening` は見返し中なら飛ばせる印にし、終わる・飛ばす・ほかのシーンへ進むと `go_title`。テンプレートのタイトル画面の項目 `opening`、エンディング一覧のボタン（タイトルから開いたときだけ）、出力イベント `opening.play`。タイトルのシーン向けに `_fill_title_sys` が `sys.opening_replay`・`sys.endings_seen` を入れる（タイトルを始めるとき、システムシーンを閉じたとき）。
- **Ink のサブシーンの確認**：`AdvInkAdapter.subscene_calls(story)` が、外部関数 `call_scene` の呼び出しの直前の `"str" 文字列 "/str"` の組から行き先を読む（引数がすべて文字列そのままのときだけ）。validate は `ctx.query("scene_info")` で JSON のシーンを確かめる。
- **Ink のエディタの候補**：`AdvScenarioEditor.ink_completion_items(行の頭からカーソルまで)`。CodeEdit の候補の仕組み（`code_completion_requested`）を使い、`call_scene("` か `goto_scene("` のあとで文字を打つと出す。
- **確かめ用**：`tests/stage16/ink/bad_sub.ink`（行き先の誤り）、シナリオのエンディング `end_bad`（fin の設定）と `end_quiet`（fin: false）、タイトルのメニューの「オープニング」。

## 段階17の決めごと（オープニングの流し方、スタッフロールの画像、Ink のサブシーン、タイトルの BGM と演出）

- **オープニング**：プロジェクト設定 `opening`（起動時に流すシーン）と、シーンの `replay`（`always`・`once`・`skippable`）・`next`。AdvPlayer は scene.goto・scene.call でオープニングに入ると `_track_opening` で `_opening` を作り、抜けたとき（ほかのシーンへ移る、飛ばす、はじめから・タイトルへ）に `_end_opening` で `AdvProgress.openings` に記録する。手順を最後まで進めて選択肢もなければ `_after_opening(next)`（next、なければ `_start_title_or_entry`）。`once` で見たことがあれば、起動時は流さずに進み、途中で入ったときは `_pending_action` で飛ばす。`skippable` で見たことがあれば、案内の Label を出し、Esc・右クリック・B で `skip_opening`（実行中なら `_pending_action` に入れ、`_skip_held` が true を返すので待ちが飛ぶ）。JSON アダプタの問い合わせ `scene_info`（kind、replay、next、bgm など）を足した。
- **流れを切る操作の待ち**：`_pending_action` があるあいだは `_skip_held()` が true を返す（クリック待ちや文字送りで止まらない）。
- **シーンの BGM と切り替え演出**：JSON アダプタが、シーンの `bgm` を入ったとき（`_scene_bgm`、サブシーンから戻ったときは呼び出し元のもの）に bgm.play・bgm.stop にし、`transition` を scene.goto・scene.call の引数に入れる。validate は `bgm` の素材と `next` の行き先を確かめる。kind `opening` のシーンは UNREACHABLE にしない。
- **テンプレートのタイトル画面**：中身を CanvasGroup（`AdvTitleScreen.group`）にまとめ、`AdvScreen.transition_group(g, tr, hiding)`（画像の切り替えと同じ `_transition` を、重ねた画面全体の範囲でかける）で出し入れする。`reveal()` は出したあと（call_deferred）に呼ぶ。BGM は `open_title_screen` が `title_bgm` で鳴らす。
- **スタッフロール**：`AdvCredits` を VBoxContainer に行（RichTextLabel、TextureRect、空き）を並べる形にした。画像は AdvPlayer の `_layer_texture`（カラーキー、機種別の差し替えも効く）で読む。`bgm` は流す前に bgm.play として実行する。
- **Ink からサブシーン**：AdvInkStory に `stop_requested`（立つと `_run_until_stop` がいまの命令のあとで止まる）。外部関数 `call_scene` が立て、AdvInkAdapter が `_run` の最後で内部イベント `adapter.call {adapter: "main", step}` を出す。Core は `_switch_adapter` で主のアダプタを上にもう一度積み、`call_step(step)` を呼ぶ（積み方はセーブの `active` に名前で残るので、同じアダプタが2回あってもよい）。JSON アダプタは `_scene_calls` の記録に `from_adapter` と、Ink を待っていた `_suspended` を残し、`return` でそれを見つけたら `_suspended` を戻して `adapter.exit` を出す。Core が上の JSON を外し、Ink の `resume` が Core の値を写して（`_sync_in`）続きを進める。
- **画面に入ったときの入力UI**：scene.goto などで `_apply_input_modes` を呼ぶ（タイトルやオープニングでは、入ったときからコマンドを隠す）。
- **確かめ用**：`tests/stage16/ink/sub.ink`（`.ink.json` は inklecate で作ったもの）、シナリオのオープニング `op`。

## 段階16の決めごと（特殊シーン、システムシーン、サブシーン、エイリアス）

- **シーンの種類**：シーンの `kind`（`normal`・`title`・`opening`・`ending`・`sub`・`system`）。JSON アダプタの問い合わせ `scene_kind`。タイトル・オープニング・エンディング・システムのシーンでは、AdvPlayer の `_input_modes()` が選択肢を出しているときだけ `["select"]`、ほかは `[]` を返す（入力UIの設定より優先）。
- **タイトル**：プロジェクト設定 `title_screen`（`""`・`"template"`・シーンID）。AdvPlayer は起動の流れを `_boot()` にまとめ、始める前の状態（`_initial_data`、`_make_save_data()` の形）を取っておく。`new_game(scene)`・`go_title()` はその状態に戻してから始める（巻き戻しの記録も消す）。
  - テンプレートのタイトル画面は `presentation/adv_title_screen.gd`（`AdvTitleScreen`）。重ねる画面として出し、選んだ項目（`action`）で AdvPlayer の `open_title_screen()` が続きを行う。ロードやチャプターで始まらなければ、またタイトルを出す。テンプレートの `title` の項（`image`、`fill`、`title_y`、`title_pal`、`title_size`、`show_title`、`menu_y`、`menu`、`labels`）で見た目を変えられる。
  - タイトルのシーンの `menu` は、選択肢（`style: "menu"`）として出す。項目の `do` の後ろに内部の手順 `{"_menu": シーンID}` を足し、手順が終わるとまたメニューを出す。
  - 流れを切るイベント（`game.new`・`game.title`・`game.continue`・`game.quit`・`endings.open`・`chapters.open`・`settings.open`・`system.load`・`system.close`）は、AdvPlayer の `_pending_action` に入れて `_run` の繰り返しを抜け、実行中（busy）でなくなってから行う。
- **エンディング**：kind `ending` のシーンに入ると、JSON アダプタが `ending.reach {id}` を出し、AdvPlayer が `AdvProgress.mark_ending`（`endings`：ID → {time, count}）で記録する。一覧は `AdvModernUI.open_endings()`。プロジェクト設定 `endings` が Core の設定にも入り、validate が `ENDING_UNKNOWN` を確かめる。
- **スタッフロール**：`presentation/adv_credits.gd`（`AdvCredits`）。RichTextLabel を Tween で下から上へ動かす。クリック（`_click_pending`）とスキップで飛ばす。
- **システムシーン**：プロジェクト設定 `system_scenes`。`open_save_menu`・`open_log`・`AdvModernUI.open_settings` の最初に `_open_custom_system(mode)` を呼ぶ。
  - `.tscn`：`presentation/adv_system_screen.gd`（`AdvSystemScreen`）を継いだもの。`closed` シグナルを持つ Control なら使える（`open(player, mode)` があれば呼ぶ）。
  - JSON：`open_system_scene(id, mode)`。開く前の状態を `_sys.snapshot` に取っておき、`core.start(id)` で始める。閉じる（`close_system_scene`）と、その状態を `_apply_save_data` で戻す。中で `save_game` すると、`_make_save_data()` が取っておいた状態を返すので、開く前の状態がセーブされる。`sys.` の値は `AdvState.sys`（セーブしない。`duplicate_state` でも同じ辞書を共有する）に `_fill_sys_vars()` が入れる。実行中は開けない（標準の画面を出す）。
  - 設定の変更は `AdvPlayer.apply_setting(key, value)` にまとめた（`settings.set`、AdvSystemScreen の `set_setting`）。
- **サブシーン**：JSON アダプタの手順 `call_scene`（`args`、`into`）と `return`。呼び出し元の手順の続き（`_stack`）と背景を `_scene_calls` に積み、セーブにも入れる。Core の状態には状態イベント `scene.call`・`scene.return` で `frames`（`{from, scene, args, into}`）を積む。`arg.名前` は `AdvState.get_var` が一番上の `frames` から読む。引数の数は整数の値なら整数にそろえる（JSON の数は小数で読むため）。深さの上限は Core の設定 `subscene_max_depth`（既定 10）。`goto`（`_goto_scene`）は `_scene_calls` と `frames` を空にする。
- **エイリアスと文中の条件**：`presentation/adv_text_markup.gd`。`AdvTextMarkup.expand(body, state)` が、エイリアス（`_expand_aliases`）→ 条件（`_expand_ifs`）の順に置き換え、`to_bbcode_stops`・`to_plain`・`to_speech` の最初に呼ばれる。定義は `AdvTextMarkup.set_aliases(core.aliases())`（プロジェクト設定 → シナリオの順に重ねる）。条件の評価は `cond_evaluator`（AdvPlayer が `core.ctx.eval` を入れる。なければ `AdvCondition.evaluate`）。循環は呼び出しの鎖で見つけ、`push_error` で `ALIAS_CYCLE` を出して置き換えをやめる。validate は `AdvTextMarkup.check_aliases`（定義どうしの循環を深さ優先でたどる）と、本文の参照（JSON アダプタの問い合わせ `alias_refs`）を確かめる。Ink の本文も表示のときに置き換わる。
- **選択肢の文**：AdvPlayer は選択肢を出すとき、文を `AdvTextMarkup.to_plain` に通す（変数・エイリアス・条件が使える）。
- **シナリオエディタ**：手順の種類に「サブシーンの呼び出し」（専用の欄 `args`（JSON）・`into`）と「サブシーンから戻る」を足した。式エディタの候補に、サブシーンの引数（`arg.名前`）とシステムの値（`sys.名前`）を足し、`.` を含む名前も補えるようにした。シーンの設定のフォームには `kind`、`params`、`menu`、`ending` が出る（スキーマから）。
- **確かめ用**：`tests/stage16/`（シナリオ、プロジェクト設定、自作の設定画面 `settings_screen.tscn`、検証の誤りを集めた `bad.scenario.json`）。

## 段階15の決めごと（Ink の LIST、自由文のパーサー、シナリオエディタの拡張）

- **Ink の LIST**：`adapters/ink/adv_ink_list.gd`（`AdvInkList`）。C# 版の InkList と同じに、項目は「リスト名.項目名」→ 値で持ち、並び順は C# の Dictionary と同じにする（消した場所は空きになり、次に足したものがそこに入る。`LIST_RANDOM` と、値が同じ項目の扱いがこの順に従う）。元のリスト（origins）は評価用の値を積むとき（`_push_eval`、C# 版の PushEvaluationStack）に決める。変数の名前として書いたリストの項目（`~ inv += red`）は、変数がなければ1つだけ入ったリストとして読む。空のリストを入れたときは、元のリストの名前を引き継ぐ（RetainListOriginsForAssignment）。セーブは C# 版と同じ `{"list": {…}, "origins": […]}`。確かめ用の物語は `tests/ink/src/lists.ink`（期待する出力は `tests/ink/lists.expected.txt`、inklecate -p の出力）。validate の `INK_LIST` はなくした。
- **LIST と Core**：LIST の変数が変わると、Core には「項目名, 項目名」の文字列で渡す（`state.set`）。Core の状態から Ink に戻すときは、その文字列から作り直す（同じ文字列なら作り直さない）。
- **自由文のパーサー**：`input/adv_parser_free.gd`（`AdvParserFree`、`AdvParserJa` を継いだもの）。`inputs.parser_profile: "free"`。文の終わりの言い回し（`ENDINGS`）を取り、文の終わりから動詞を探し（言い換え、言い換えの最後の1文字の活用、語幹＋活用の終わり `CONJ`）、残りから名詞を長い順に拾う。スロットの振り分けは日本式と同じ（`_tokens_to_intent` に分けた）。
- **シナリオエディタ**
  - **元に戻す**：`AdvScenarioModel` がファイルを書き換える前の中身を、操作ごと（`begin`〜`end`）にまとめて覚える（`undo`・`redo`、最大100）。ごみ箱へ移すものも中身を覚えるので、戻せる。エディタの書き込みはすべてモデルを通す（`write_json`、`write_text`、`remove_path`）。
  - **整数**：Godot の JSON は数をすべて小数で読むので、モデルは読むときと書くときに `AdvSchemaForm.normalize` で整数に戻す（段階14では `1.0` のように書いてしまうことがあった）。
  - **新規作成**：名前と ID を聞くダイアログ（`ask_new`）。ID の候補は `suggest_id`、確かめるのは `is_valid_id` と `taken_ids`。
  - **ID の変更**：`change_id`。シーンと会話は、すべての JSON シナリオのファイル（`all_files`）を複写と同じ `_remap` で書き換え、プロジェクト設定の `entry` も変える。
  - **開始シナリオ**：`set_start_scenario`（`entry` をそのシナリオの `start` に）、`start_scenario`。
  - **並べ替え**：`AdvCardGrid` のドラッグ（`set_drag_forwarding`、`reordered`、`move_ids`）と `AdvScenarioModel.set_order`。
  - **サムネイル**：`image_path`（プロジェクトとシナリオの素材フォルダのマニフェストを読む）と `load_texture`（取り込み前でも PNG などと MAG を読む）。
  - **範囲のエディタ**：`editor/scenario/adv_region_editor.gd`（`AdvRegionEditor`）。背景を整数倍（入らなければ縮小）で出し、ドラッグで `[x, y, 幅, 高さ]` を決める。
  - **フォームの式**：`AdvSchemaForm.expr_mode`（式の項目か）と `expr_requested`、`set_value_at`。`$ref` が `#/definitions/condition` の項目と `let` に「式…」を出す。
  - **自前の候補**：`AdvExprEditor` は CodeEdit の候補の仕組みを使わず、CodeEdit の上に ItemList を出す（`completion_items`、`request_completion`、`accept_completion`）。キーは CodeEdit の `gui_input` で先に受ける。
  - **手順の専用の欄**：`AdvStepEditor.DETAILS`。台詞の `id`・`voice`、選択肢の `id`、選択肢の項目の `id`・`once`。
  - **古い形のファイルを移す**：`migrate_loose`。`MAIN_KEYS` をシナリオ共通の設定に、ほかをチャプターに入れる。
- **段階1のサンプル**：`tests/stage1/scenario/stage1.scenario.json` を、シナリオのフォルダの形（`tests/stage1/scenario/stage1/`）に移した。

## 段階14の決めごと（シナリオエディタ）

- **シナリオエディタ**（仕様 6.8）：エディタの「adv80s」画面で種類「シナリオエディタ」を選ぶ。パンくず（フォルダ › ゲーム › シナリオ › チャプター › シーン › セリフ／コマンド）で戻れる。中身は `editor/scenario/`：データの読み書き `adv_scenario_model.gd`（`AdvScenarioModel`）、画面 `adv_scenario_editor.gd`（`AdvScenarioEditor`）、カードの一覧 `adv_card_grid.gd`（`AdvCardGrid`）、手順のエディタ `adv_step_editor.gd`（`AdvStepEditor`）、式エディタ `adv_expr_editor.gd`（`AdvExprEditor`）。
- **ファイル**：シナリオのフォルダ（`ext.adv80s_editor.scenario_root`、既定 `res://game/scenario`）の下に、シナリオごとのフォルダ、その中にシナリオ共通の設定 `_scenario.scenario.json` とチャプターごとの `<ID>.scenario.json`、Ink は `ink/`。ゲームから見ると、これまでどおりの JSON シナリオのファイルが並んでいるだけ（プロジェクト設定の `scenarios` をエディタが書き直す）。表示名と並び順は `ext.adv80s_editor` に書く。シナリオの直下の古い形のファイルは「（フォルダの外のファイル）」というシナリオのチャプターとして見せ、`scenarios` の中の位置も変えない。
- **ID**：名前から作る（`AdvSetup.to_id`。日本語だけの名前なら `scenario`・`chapter`・`scene`）。名前の変更は表示名だけで、ID は変えない。
- **複写**：シーンと会話の ID に `_copy`（重なれば `_copy_2`…）を付け、複写したものの中の参照（`goto`、`call`、`dialogue`、`start`、`scene`、`exits` のキー、`scene.goto`、条件の `visited`・`talked`・`scene ==`）を付け替える（`AdvScenarioModel._remap`）。
- **削除**：`OS.move_to_trash`（ごみ箱がなければ消す）。
- **設定のタブ**：その段のファイルのスキーマから、タブの項目だけのスキーマ（`definitions` つき）を作って AdvSchemaForm で出す（`AdvScenarioEditor.sub_schema`）。シーンの設定は、手順の項目（`on`・`first`・`enter`、もの・出口の `on`）を除いたスキーマで出し、保存するときに元の手順を戻す（`strip_steps`・`merge_steps`）。
- **手順のエディタ**：Tree の3列（種類・内容・条件）。木で書けない形（`set`、`dialogue`、`id` や `voice` のある `say`、出力イベントなど）は「そのほか（JSON）」の行にして、書き換えずに保存する。台詞は `@話者 文章` の短い形で書き出す。
- **式エディタ**：CodeEdit の候補（`code_completion_requested`）。候補は `AdvExprEditor.collect_candidates`（変数の一覧 `AdvVariableIndex.collect`、組み込み、シーン、会話、アイテム、機能）。確かめるのは `AdvCondition.check` と `AdvExpr.parse_let`。Godot の CodeEdit は `(` の直後では候補を出さないので、引数の候補は1文字打ってから出る。
- **Ink のコンパイル**：エディタ設定 `adv80s/inklecate_path` の inklecate を `OS.execute` で動かす（`-o <名前>.ink.json <名前>.ink`）。
- **保存**：画面ごとの「保存」か Ctrl+S。ほかの画面へ移るときは保存してから移る。
- **セットアップ**：最初のシナリオを、シナリオのフォルダの形（`scenario/main/_scenario.scenario.json` と `chapter1.scenario.json`）で作り、`ext.adv80s_editor.scenario_root` を書くようにした。

## 段階13の決めごと（スプライトの出し入れの演出、動く背景の重ね合わせ、Ink の乱数、MAG）

- **スプライトの出し入れの演出**：`fade`・`fade_color` は不透明度を変える。そのほかは、演出のあいだだけスプライトの絵（`_body`）を CanvasGroup に入れ（`AdvSprite.begin_transition_group`）、画像の切り替えと同じシェーダーをかける（`AdvScreen._sprite_transition`）。範囲はスプライトの見えている四角（`AdvSprite.screen_bounds`、回転は考えない）。スプライトそのものは層に置いたままなので、演出中も ID で探せる。テンプレートの `transitions.replace` も効く（98 では `fade` が `dissolve` になる）。動画のスプライトは `fade`。段階9の「どれも fade」は取りやめた。
- **動く背景の重ね合わせ**：重ねる画像にアニメーション画像（コマが2つ以上、またはマニフェストの `grid`・`anims`）があれば、1枚にまとめず、要素ごとの AdvSprite を重ねた Control にする（`_layer_visual`、`_layer_anim_node`。最初の画像の大きさの枠を、絵の窓に合わせて拡大する）。要素の `anim` で再生するアニメーションを選べる（既定 `default`）。動くものがなければ、これまでどおり1枚の画像にする。1枚だけの背景でも、アニメーション画像なら動かす。
- **MAG**：`media/adv_mag.gd`（`AdvMag.decode`・`load_frames`）。アニメーション画像の取り込み（`adv80s.anim_image`）が `.mag` も受け持ち、コマが1つの `AdvImageFrames` にする。MAKI02 の 16色・256色。フラグAの1ビットごとにフラグBから1バイトを読んで前の行と XOR し、フラグの4ビットで「新しい2バイト」か「決まった位置（`VECTORS`）から写す」かを決める。ヘッダーの左右の範囲（8ドット・4ドット単位に広げて読む）から切り出す。200ライン用の画像も縦に伸ばさない。確かめ用の画像は `tools/build_test_mag.py` で作る（`tests/media/mag16.mag`・`mag256.mag` と、同じ絵の PNG）。マニフェストの生成と「素材ファイルから追加…」も `.mag` を画像として扱う。
- **Ink の乱数**：`AdvDotNetRandom`（.NET の System.Random と同じ Knuth の減算法）を使い、`RANDOM`・`SEED_RANDOM`・シャッフルの結果を inklecate と同じにした。C# の int の足し算のあふれも同じにする（`wrap32`）。最初の種は本家と同じく時刻から 0〜99。確かめ用の物語は `tests/ink/src/random.ink`（期待する出力は `tests/ink/random.expected.txt`、inklecate -p の出力）。

## 段階12の決めごと（text.append、外字、動画の切り替え演出と音）

- **text.append**：いまの文章の続きに本文を足す（`AdvScreen.append_text`）。話者のある文章では「」の中に足し、足したところから文字送りを続ける。ページはそのまま続ける。メッセージログは最後の記録に足す（`AdvMessageLog.append_text`。間に入力があれば新しい記録）。セーブの `view.text` には続けた本文が入る。文章が出ていなければ `text.show` と同じ。JSON シナリオの手順に直接書いた `text.show`・`text.append` には行のIDをつけ（`_with_line_id`）、Core が既読を記録する。足す文章が `[page]` で始まるときは、前の文章との間で改行する。
- **外字**：`[gaiji=ID]` は素材の画像を `[img]` で文中に入れ、1文字として数える。画像は AdvPlayer が読み込み（カラーキー、機種別の差し替えも効く）、仮のパス `res://.adv80s_gaiji/<ハッシュ>.tex` に置いて使う（`AdvTextMarkup.gaiji_resolver`）。そのままの大きさで入れる。ログと読み上げはマニフェストの `alt`。素材がなければ何も出さない。`validate` は文章の中の外字の素材も確かめる。
- **減色しない外字**：マニフェストで `keep_colors: true` にした画像は、外字として出すときに減色フィルターをかけない。画像の写しを `res://.adv80s_gaiji/keep/` に置き（`AdvTextMarkup.GAIJI_KEEP_PREFIX`）、文章の窓と同じ並びの写し（文字は透明、ほかの画像も透明）を別の SubViewport（`AdvDisplay.keep_layer`）に描く。フィルターのシェーダーは、その写しが不透明なところだけ減色を飛ばす（`keep_mask`）。走査線などのほかのフィルターはかかる。写しは減色しない外字が出ているあいだだけ作る。
- **動画の切り替え演出**：動画と黒い余白を CanvasGroup にまとめ、画像と同じ切り替え演出をかける（`AdvScreen.reveal_video`、`stop_video_with`）。`video.play` の `transition` は現れるときと消えるとき（終わったとき、飛ばしたとき）の両方。繰り返しの動画は演出を待たずに次へ進む。`video.stop` は演出があれば終わるまで待つ。演出をかける範囲は動画の置き場所から求めるので、`filters: false`（フィルターの外）でも使える。
- **動画の音**：スプライトの動画は `mute: false` で音を出す（音量は `volume` × マニフェストの `volume` × BGM の音量）。プレイヤー設定の BGM の音量を変えると、スプライトの動画と流している動画の音量も変わる（`apply_volumes`）。`video.play` の音量にもマニフェストの `volume` をかけるようにした。
- **マニフェスト**：`alt`（外字を文字で表すとき）と `keep_colors`（`true` で外字を減色しない）を足した。

## 段階11の決めごと（セットアップ画面、絵の中の対象を選ぶコマンド方式）

- **セットアップ画面**（仕様 6.7）：エディタの「adv80s」画面で種類「セットアップ」を選ぶ（`adv80s.project.json` がなければ最初に出る）。ゲームID、タイトル、画面テンプレート、コマンド方式、入力デバイスを決めて「作成する」を押すと、プロジェクト設定、素材フォルダ（`res://game/assets/` と種類フォルダ）、最初のシナリオ（段階14からは `scenario/main/` の下に `_scenario.scenario.json` と `chapter1.scenario.json`）、メインシーン（`main.tscn`）を作る。すでにあるファイルは残し、プロジェクト設定はセットアップの項目だけを書き換える。中身は `editor/adv_setup.gd`（`AdvSetup.check`・`plan`・`apply`）、画面は `editor/adv_setup_view.gd`。
- **プロジェクト設定の新しい項目**：`game_id`、`title`（ウィンドウのタイトルにも使う）、`inputs`（テンプレートの `inputs` を項目ごとに上書き）、`input_devices`（`keyboard`、`mouse`、`gamepad`、`touch`。書かなければすべて）。
- **ゲームID**：セーブデータに入れ、違うゲームのセーブデータは読まない（`load_game` が `GAME_MISMATCH` を返す）。ゲームIDのないセーブデータは確かめない。
- **コマンド方式**（仕様 4.5。`inputs.enabled` に書く）：`verb_click`（動詞リスト＋クリック）、`verb_cursor`（アイコン切り替え。右クリックでカーソルの動詞を切り替える）、`context`（コンテキスト。対象に合わせて動詞が決まり、右クリックは「みる」）。どれも同じ意図を出すので、シナリオは変えなくてよい。
- 動詞の決め方は、物・出口の `click` → 出口は `MOVE` → カーソルの種類と `inputs.context_verbs` → `inputs.click_verb`。右クリックは `inputs.context_alt_verb`、持ち物を持ったときの動詞は `inputs.item_verb`、動詞ごとのカーソルは `inputs.verb_cursors`。
- 絵の中に範囲（`region`、`sprite`）のない対象は、コマンドの窓に「→ 名前」のボタンで並ぶ。Tab とゲームパッドの L・R で調べられる場所を順に選べる。
- タッチでは、0.5秒の長押しが右クリックの代わりになる（やめる／次の動詞／みる）。この方式の間、絵の中のタッチは離したときにクリックになる。
- テンプレートに `ui.cursors` がないときは、この方式の間だけアドオンの標準のカーソル画像を使う。
- 入力UIの部品 `AdvCommandSelect` は、窓の中が「選びかけの文／動詞の一覧／持ち物」の3段になった（`mode`：`menu`、`verbs`、`cursor`、`context`）。

## 段階10の決めごと（背景の重ね合わせ、共通の変数と定数、ページめくり）

- **背景の重ね合わせ**：シーンの `image` を配列にすると、`when` に合う要素（素材IDか `{id, variant?, x?, y?, when?}`）を、最初の画像の大きさの1枚に重ねて背景にする（`Image.blend_rect`）。コマンドを実行するたびに条件を見直し、変わったらシーンの `image_transition`（既定 `cut`）で描き直す。`image.show` の `id` にも配列を書ける。重ねる画像のカラーキーも効く。アニメーション画像は最初のコマ。いま重ねているものは JSON アダプタのセーブ（`image`）と、表示のセーブ（`view.images`）に入る。
- 背景（`image.show`）も GIF・APNG・MNG とカラーキーを使えるようにした（段階13から動かす）。
- **共通の変数と定数**：プロジェクト設定の `variables`（シナリオの宣言の前に重ねる。同じ名前はシナリオが優先し、validate が警告 `DUPLICATE_ID`）と `constants`。シナリオにも `constants` を書ける。定数は状態（`AdvState.constants`）に置き、`get_var` で読める。書き換えは無視して警告 `CONST_WRITE`、validate はエラー `CONST_WRITE`。定数はセーブに入れない。エディタの「変数の一覧」に共通の変数と定数も出す。
- **ページめくり**：文章の窓（`TextClip` で切り取る）に入りきらない文章は、行単位でページに分ける（`RichTextLabel.get_line_offset`・`get_line_range` で窓に入る行を数え、文章をずらす）。文字送りのタグ `[p]`、`[p=秒]`、`[page]`、`[page=秒]`、`[w=秒]`（既定 0.5 秒）、`[se=ID]`、`[speed=n]…[/speed]`、`[instant]…[/instant]` を実装した（`AdvTextMarkup.to_bbcode_stops` が表示する文字の数で止まる位置を返す）。`[page]` の前には改行を入れる。`[blink]` は `[pulse]` で描く。
- 文字送り中のクリックは、次の止まる位置かページの終わりまで出す。ページの終わりと `[p]` などが重なったときは、二度待たない。
- **待ちの印**：テンプレートの `ui.wait_mark`、`ui.page_mark`（文字か画像。画像はアニメーションを再生する）。既定は「▼」の点滅。
- **時間で進む**：`[p=秒]`、`[page=秒]`、`text.show` の `wait` の秒数。オート送りはページの終わりと `[p]`、`[page]` にも効く（待ち時間はプレイヤー設定 `auto_delay` ＋ 最後に待ってから出した文字の数 × `auto_per_char`）。
- `[gaiji]` と `text.append` は段階12で実装した。
- サンプルのろうかの最初の文章に `[p]` を入れた。

## 段階9の決めごと（スプライト、マウスカーソル、アニメーション画像、動画）

- **スプライトの置き場所**：画像の層（`bg`、`char` など）ごとに、その層のすぐ上に `Sprites_<層>` を置く。画面の層は `layout.screen_layers`（既定 `["back", "front"]`）。名前が `back` で始まる層は絵の窓より後ろ（画面の背景のすぐ上）、それ以外は窓より前に置く。`layer` を省くと `char`、知らない名前なら `char`（なければ最初の画像の層）。
- **座標**：画像の層・絵の窓の中のネイティブ解像度の座標。描くときは整数に丸める（`smooth: true` で丸めない）。`anchor` は `top_left`（既定）、`top`、`center`、`bottom` など9か所。
- **出し入れの演出**：`sprite.show`・`sprite.hide` の `transition` は、段階9ではどれを書いても薄く出す・薄く消す（`fade`）だった（段階13で各演出に対応）。書かなければ演出なし（テンプレートの既定の演出は使わない）。`duration` で長さを変えられる。
- **シーンのスプライト**：JSON シナリオのシーンの `sprites`。`when` が合うものを出し、合わなくなったら `hide` の演出で消す（コマンドを1つ実行するたびに確かめる）。シーンを移ると消える。物（`objects`）と出口（`exits`）に `sprite` を書くと、そのスプライトの形（不透明な画素）が調べられる場所になり、動けば当たり判定もついていく。出口をクリックすると MOVE になる。
- **イベントで出したスプライト**は `sprite.hide`・`sprite.clear` まで残る。`"keep": false` ならシーンを移ると消える。
- **セーブ**：スプライトの状態（位置などは動いている途中なら終わりの値、繰り返しの動き、かけている効果、アニメーション）、繰り返しの動画、`cursor.set` の固定をセーブに入れる。テンプレートを切り替えても出し直す。
- **アニメーション画像**：GIF・APNG・MNG は、アドオンの取り込み（`adv80s.anim_image`）で `AdvImageFrames`（コマの画像と待ち時間、繰り返しの回数）にする。拡張子 `.apng` も Godot の画像の取り込みより先にこちらが受け持つ。待ち時間 0.01 秒以下のコマは 0.1 秒にする（ブラウザと同じ）。GIF の繰り返しの指定がなければ1回だけ。MNG は、フレームの区切り（FRAM）と繰り返し（TERM）、位置（DEFI）、埋め込みの PNG・JNG だけを読む（それ以外の命令があると読み込めない警告）。1コマの GIF は止まった画像として使える。アニメーション画像は、出すと「default」のアニメーションを自動で再生する。
- **カラーキー**：読み込むときに、その色の画素を透明にした写しを作る（同じ画像と色の組み合わせは使い回す）。パレットの番号はいまのテンプレートの色。
- **効果**：`flash`、`shake`、`blink` は一度きり。`mono`、`sepia`、`silhouette`（`params.color`）、`mosaic`（`params.cells`）と自作のシェーダー（`.gdshader` のパス、`params` はシェーダーの引数）は `none` で外すまで残る。
- **マウスカーソル**：種類は、`cursor.set` の固定 → 実行中（クリック待ちなら `next`、それ以外は `wait`）→ 調べられる場所の上（その場所の `cursor`、なければ人物は `talk`、出口は `exit`、ほかは `look`）→ `default` の順に決める。`ui.cursors` の画像は画面の整数倍に合わせて拡大し、ホットスポットも同じ倍率にする。入力欄の上は `text`。キーボードやゲームパッドを使うとカーソルを隠し、マウスを動かすとまた出す（`ui.cursors` があるテンプレートだけ）。
- **標準のカーソルの画像**：アドオンの `assets/ui/cursor_*.png`（16x16。`tools/build_cursors.py` で作る）。90年代のパソコン、家庭用ゲーム機、携帯機、現代の機種のテンプレートの `ui.cursors` に入れた。80年代のパソコンは OS の矢印のまま。
- **動画**：`.ogv`（Ogg Theora）だけ。ほかの形式は素材フォルダに置くと、マニフェストの生成で ASSET_UNSUPPORTED の警告を出し、素材に入れない（ffmpeg などで変換してから置く）。`video.play` は、終わるかクリック（`skippable: false` なら飛ばせない）まで待つ。スキップ中は、一度見た動画を飛ばす。`bgm` は `pause`（既定。終わると続きから鳴らす）、`stop`、`keep`。`filters: false` なら減色などのフィルターの外に出す。動画の素材のフォルダは `movie/`。
- **サンプル**：ろうかに、ゆれるランプ（GIF、黒をカラーキーで抜く、2倍）と、かぎを取るまでうえきばちで光るきらめき（スプライトシートの `grid` と `anims`）を置いた。ランプは調べられる（`しらべる` で `flash`）。動作確認用の短い動画 `movie/op_test.ogv` もある。

## 段階8の決めごと（標準のフォント、エディタでの編集）

- **標準のフォント**：アドオンの `assets/font/` に PixelMplus10・12 と Tekuplus（どれも M+ FONT LICENSE。`LICENSE_M+FONTS.txt`）を同梱した。ファイル名は素材IDの決まりに合わせて英小文字にした（`pixelmplus12` など）。
- **アドオンの素材フォルダ**：`res://addons/adv80s/assets` を、プロジェクトの素材フォルダより下（いちばん先）に重ねる。プロジェクトに同じIDの素材を置けば、そちらが使われる。マニフェストの自動生成の対象にも入る。
- **フォントの候補**：テンプレートの `fonts.main`・`fonts.readable` は、`{asset, size, line_height}` を1つでも、候補の配列でもよい。配列なら、素材が見つかった最初のものを使う。`asset` の頭の `font.` は省いてよい（前の書き方の名残）。
- **98 クラシックのフォント**：`dot16`（16ドット）→ `pixelmplus12`（12ドットを16ドットの行に並べる）の順に探す。DotGothic16（OFL-1.1）は同梱しないので、使うときは https://github.com/fontworks-fonts/DotGothic16 から入手し、`DotGothic16-Regular.ttf` を素材フォルダの `font/dot16.ttf` として置く。
- **ドットのフォントの描き方**：`fonts.main` のフォントは、なめらかにせず（アンチエイリアスなし、ヒンティングなし、サブピクセル位置なし）描く。`fonts.readable` はなめらかに描く。
- **エディタの「adv80s」画面**：エディタの上の切り替え（2D、3D、Script の並び）に「adv80s」を足した。プロジェクト設定、テンプレート、マニフェスト（手書きの `manifest.json`）を、同梱の JSON Schema から作ったフォームで編集する。
  - スキーマにある項目は書いていなくても灰色で並び、＋で足せる。説明はマウスを重ねると出る。型を選べる項目は ⇄ で切り替える。
  - 右に確認の結果（スキーマと、テンプレートの継承・プリセット、シナリオ・素材フォルダ・ファイルがあるか）と JSON を出す。JSON を直接書き換えて「JSON を反映」でフォームに戻せる。
  - 保存すると JSON を整形して書き出す（手で揃えた桁や改行は消える）。Ctrl+S でも保存できる。
  - テンプレートの「新規…」は、ID と元にするテンプレート（extends）を選んで `res://game/templates/<ID>/template.json` を作り、プロジェクト設定の `templates` に加える。
  - マニフェストの「素材ファイルから追加…」は、選んだファイルの項目（`種類:ID` → `{type, file}`）を足す。`loop_start` や機種別の差し替えなどを書くのに使う。
  - アドオンの中のテンプレートとマニフェストは読むだけ（直すときは extends して自分のテンプレートを作る）。
  - **一覧から選ぶ項目**：プロジェクト設定の `template`・`templates`（テンプレートのID）と `scenarios`（`*.scenario.json`・`*.ink.json`）、テンプレートの `extends`（自分以外のテンプレートのID、「（なし）」で null）、`display.preset`（機種と「機種.画面モード」）、`fonts` の `asset`（フォントの素材ID）。いまの値が一覧になければ、その値も残して並べる。一覧にない値は右の JSON で書く。Tree の一覧の書き方の都合で、表示では `,` と `:` を全角にしている（保存される値はそのまま）。
  - **変数の一覧**：左上の切り替えで「変数の一覧」を選ぶと、JSON シナリオの変数（宣言したもの、宣言せずに読み書きしているもの。読む・書く場所の数と場所）、Ink の変数・定数・リスト（シナリオの `.ink.json` と同じ名前の `.ink` と、そこから INCLUDE しているものを読む。元の `.ink` がなければ `.ink.json` のグローバル変数）、条件式の組み込みの名前を並べる。JSON と Ink で同じ名前の変数には「同期」と出る。読んでいるのに宣言も変更もない変数は、メモに出す。
- **継承した値の表示**：テンプレートの編集では、書いていない項目に元のテンプレート（extends を解決したもの）の値を「継承：値」と出す。中身は灰色の行で開いて見られる。＋で足すと、その値の写しから上書きを始める。ツールバーの「継承した値」で表示を切り替える。
- **入力機器の切り替え（gamepad、touch）**：オフにすると、その機器の操作（ゲームパッドのボタンとスティック、タッチと、タッチから作られるマウスの操作）を、画面の部品に届く前に止める。キーボードとマウスは止めない。設定に「コントローラー」と「タッチそうさ」（タッチできる端末だけ）を足した。
- **同梱のテンプレート**：プリセットの全26機種に1つずつ。`pc98_classic`、`pc88_classic` のほか、`sx1_classic`、`sx1t_classic`、`sx1tz_classic`、`f7_classic`、`f77a_classic`、`mx_classic`、`mx2_classic`、`m2p_classic`、`x68k_classic`、`ftns_classic`、`mtr_classic`、`vga_classic`、`win_classic`、`fc_classic`、`pce_classic`、`sfc_classic`、`ps1_classic`、`ps2_classic`、`gb_classic`、`gbc_classic`、`gba_classic`、`hd_modern`、`fhd_modern`、`4k_modern`。どれも `pc98_classic`（SX1、F7 は `pc88_classic`）を extends し、代表モードの解像度に合わせた区割り・フォント・色・窓を持つ。
  - パソコンと現代の機種は「絵の下に文章とコマンド、入力欄あり」、家庭用ゲーム機・携帯機と MX 系は「絵の右にコマンド、下に文章、入力欄なし（コマンド選択だけ）」。
  - パレットを持たないプリセットでは、文章などの色の番号のために、テンプレートに8色（`palette.source: colors`）を持たせた（画面の減色はプリセットのまま）。MX と GB はプリセットのパレットの番号を使う。
  - 家庭用ゲーム機・携帯機・WIN・現代の機種は、窓の枠を9分割の画像で描く（`assets/ui/frame_<ID>.png`）。
  - 各テンプレートの素材フォルダ `assets/` に、手書き用の `manifest.json`（空）と `manifest.auto.json` を置いた（pc98_classic、pc88_classic にも）。
  - 作り直しは `python3 tools/build_templates.py addons/adv80s`（開発用、Python と Pillow。pc98_classic と pc88_classic の template.json は書き換えない）。そのあとマニフェストを生成する。
  - サンプルの絵は 640x400 用なので、ほかの機種では大きさが合わない。機種ごとの絵は素材フォルダの `presets/<機種ID>/bg/…` に置く。
- **テンプレートの項目の追加**：`ui.window_padding`（窓の内側の余白 [横, 縦]、既定 [8, 4]。枠の画像が太いときに広げる）、`inputs.command_columns`（コマンド選択の列の数、既定 2）。
- テンプレートを切り替えたとき（旧表示と新表示の切り替え）、切り替え先のテンプレートの素材フォルダも重ねるようにした（窓の枠の画像が見つからなかった）。
- **文章の表示調整（text_options）**：設定に「もじの おおきさ」（x1、x1.5、x2）、「もじの いろ」（テンプレートの色、しろ、きいろ、みずいろ、みどり）、「まどの こさ」（100%、75%、50%、25%）を足した。プレイヤー設定の `text_size`、`text_color`（パレットの番号、-1 でテンプレートの色）、`window_opacity`。ドットのフォントは x1.5 だと形が崩れるので、x2 を選ぶとよい。
- **サンプルの BGM**：`tools/build_sample_bgm.py`（開発用、Python と numpy）で作った 86 秒の曲。イントロ 4 小節（9.6 秒）のあとを繰り返す（マニフェストの `loop_start` が 9.6）。
- WAV のループの終わりは、データの大きさではなく長さ（秒）から求める（Godot が WAV を圧縮して取り込んでもずれないように）。
- 話題の別名（`topics` の `names`）を、パーサーが使うようにした（問い合わせ `topics` に入れていなかった）。

## 段階7の決めごと（Ink アダプタ）

- Ink の実行部分は GDScript で一から書いた（`adapters/ink/adv_ink_story.gd`、inkle 社の C# 版の動きにそろえた）。inklecate は制作時だけ使い、ゲームには含めない。対応する inkVersion は 19〜21。
- `LIST` は段階15で対応した。`RANDOM` とシャッフルは段階13で C# 版と同じ結果にした。
- シナリオの一覧の `.ink.json` は Ink のアダプタが読む。`.ink.json` だけなら Ink が主のアダプタになる。複数の `.ink.json` を並べると、ノットを持つ最初のファイルを使う。
- 受け渡し：JSON の `{"ink": "ノット"}` は出力イベント `adapter.enter` を出して止まる。Core が Ink を積んで `start`、Ink が選択肢なしで止まる（DONE、END、終わり）と `adapter.exit` を出し、Core が Ink を外して JSON の `resume` を呼ぶ。この2つのイベントは表示側へは渡さない。アダプタの基底クラスに `resume(result)` を足した。
- セーブは、すべてのアダプタの状態と積み上げの順番を持つ（`adapters`、`active`）。段階6までの形（`adapter`）も読める。
- 変数：Ink に入るとき、Ink のグローバル変数と同じ名前の Core の変数の値を Ink に写す。Ink の中で変わったグローバル変数は `state.set` で返す（プロジェクト設定 `ink.sync_variables: false` で止める）。
- 行：1行ごとに `text.show`。`@話者ID 文章` か `# speaker:ID` で台詞。行IDは `# id:…`、省略すると `ink:ノット#本文のハッシュ`。タグ `# voice:`、`# bg:`、`# bgm:`、`# se:`、`# {"image.show": {…}}`（JSONの手順と同じ書き方）で出力イベントを出す。そのほかのタグは `ext.tags`。
- 選択肢：項目の ID は `c0`、`c1`…。タグ `# intent:動詞[:対象[:with]]`（`*` は何でも）をつけると、コマンド入力の意図でも選べる。`# hidden` は一覧に出さない（全部 hidden なら選択肢の一覧を出さず、コマンド入力だけで進む会話になる）。intent タグがあるときは、選択肢を出していてもコマンド入力を受け付ける（`pending_choice` の `accepts_intents`）。合う選択肢がない意図には、辞書の既定の返事を出して待ち続ける。
- 外部関数：`has_item`、`item_count`、`item_add`、`item_remove`、`get_var`、`set_var`、`visited`、`talked`、`cond`（条件式）、`event`（種類, 引数のJSON）、`goto_scene`、`call_scene`（段階17）。これ以外は Ink 側に同じ名前の関数があればそれを使い、なければ validate が `INK_EXTERNAL` を出す。
- Ink に入るとき `state.mark`（talked、`ink:ノット`）を出す。選んだ選択肢は `chosen` に `ink:ノット#c…/c番号` で残す。
- validate のコード：`INK_LOAD`、`INK_VERSION`、`INK_UNSUPPORTED`、`INK_EXTERNAL`、`INK_MISSING_KNOT`（JSON の `{"ink"}` の行き先）、タグの素材は `ASSET_NOT_FOUND`。
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
- パーサープロファイルは、テンプレートの `inputs.parser_profile`（`ja`、`en`、`free`、またはスクリプトのパス）。
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
