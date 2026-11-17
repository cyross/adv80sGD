# adv80sGD リファレンスマニュアル

最終更新：2026-11-02

## このマニュアルの見方

ゲームは JSON ファイル5種類と、必要なら Ink で書きます。このマニュアルは、それぞれのファイルに書ける項目と、シナリオの中で使える書き方をまとめたものです。作り方の流れは「[新しいゲームの作り方](getting-started.md)」、やりたいことから引くときは「[逆引きガイド](howto.md)」を見てください。

| ファイル | 場所 | 役割 | エディタでの編集 |
| --- | --- | --- | --- |
| `adv80s.project.json` | プロジェクトの直下（1つ） | ゲーム全体の設定 | 「adv80s」画面のフォーム |
| `template.json` | `templates/<ID>/` | 画面の見た目（機種） | 同上 |
| `manifest.json` | 素材フォルダの直下 | 素材の属性（手書き） | 同上 |
| `manifest.auto.json` | 素材フォルダの直下 | 素材の一覧（自動生成。手で直さない） | 自動 |
| `*.scenario.json` | 自由（シナリオエディタを使うならシナリオのフォルダ） | JSON のシナリオ | 「adv80s」画面のシナリオエディタ、VS Code（スキーマ付き） |
| `*.ink` → `*.ink.json` | 自由 | Ink のシナリオ（inklecate で変換） | Inky など |
| `*.effect.json` | 自由 | 自作のフィルター・演出 | VS Code |

**表記の決まり**

- 項目名の後ろの `?` は省略できるものです。
- ID（シーン、物、素材、変数など）は英小文字、数字、`_` で書きます。
- どの JSON にも `$schema` と自由に使える `ext` を書けます。
- テンプレートと意図スキーマの重ね合わせでは、`null` を書くと継承した値を取り除きます。
- スキーマの元は `addons/adv80s/schemas/ja/` にあります（英語版は `en/`）。

## プロジェクト設定（adv80s.project.json）

プロジェクトの直下 `res://adv80s.project.json` に1つ置きます。必須は `project_version`（いまは 1）だけです。

| 項目 | 型 | 中身 |
| --- | --- | --- |
| `project_version` | 整数 | 設定の形の版。`1` |
| `game_id` | 文字列 | ゲームID。ほかのゲームと重ならない名前（英小文字で始まる英小文字・数字・`_`）。セーブデータに入り、違うゲームのセーブデータは読まない |
| `title` | 文字列 | ゲームのタイトル。ウィンドウのタイトルにも使う |
| `template` | 文字列 | 最初に使うテンプレートの ID |
| `inputs` | 辞書 | コマンド方式。書いた項目だけ、テンプレートの `inputs` を上書きする（下の「テンプレート」の `inputs.*` と同じ項目） |
| `input_devices` | 配列 | 使う入力機器：`keyboard`、`mouse`、`gamepad`、`touch`。書かなければすべて |
| `templates` | 配列 | 登録するテンプレートの ID。旧表示と新表示の切り替え（`era_switch`）はこれが2つ以上のとき使える |
| `scenarios` | 配列 | シナリオのパス。`*.scenario.json` は JSON、`*.ink.json` は Ink のアダプタが読む |
| `entry` | 文字列 | 開始シーン。空ならシナリオの `start` |
| `title_screen` | 文字列 | タイトル画面。空ならタイトルなしで始める、`"template"` ならテンプレートのタイトル画面、それ以外はタイトルのシーン ID |
| `opening` | 文字列 | 起動したときに最初に流すオープニングのシーン ID（kind `opening`） |
| `opening_replay` | 文字列か辞書 | オープニングを見返せる条件：`seen`（見たことがあれば、既定）、`always`、`never`、`any_ending`、`all_endings`、`{endings, seen, when}` |
| `fin` | 真偽か辞書 | 「おわり」の画面の既定（`false` で出さない。項目は下の「特殊なシーン」） |
| `extras` | 辞書 | おまけ（ギャラリー `gallery`・音楽 `music`）。`show`、`when`（既定 `sys.all_endings`）、`title`、`menu`（並べる項目：`gallery`・`music`・`endings`・`opening`）、`music_mode`（`one`・`next`・`all`）、`thumbnails`（見本の画像）、`music_desc`（曲の説明）、`bonus`（特典を使うか）、`notify`・`notify_text`（特典のお知らせ）、`title_count`（タイトルに開いた数）など。項目は `{id, label, when?, hint?, bonus?, hidden?}`、ギャラリーは `images`（めくれる画像の並び）・`thumb`（見本）、音楽は `desc`（説明）も書ける |
| `title_labels` | 辞書 | テンプレートのタイトル画面のメニューの文言（項目 → 文） |
| `title_variants` | 配列 | テンプレートのタイトル画面の差し替え `[{when, image, bgm, transition, menu, labels}]`（`when` に合うものを順に重ねる。`sys.endings_seen` など） |
| `opening_hint` | 文字列 | 2回目から飛ばせるオープニングに出す案内（既定「Esc：とばす　Ctrl：はやおくり」） |
| `title_bgm`、`title_transition`、`title_bgm_fade` | ID か辞書、演出、数 | テンプレートのタイトル画面の BGM、出るとき・消えるときの切り替え演出、はじめからで BGM を止めるフェードの秒数（既定 0.5） |
| `title_image`、`title_menu` | 文字列、配列 | テンプレートのタイトル画面の背景の画像 ID と、メニュー（`new`、`continue`、`chapters`、`endings`、`settings`、`quit` から並べる） |
| `endings` | 配列 | エンディングの一覧 `[{id, label, hint}]`。`label` は見たあと、`hint` は見る前に出す |
| `system_scenes` | 辞書 | セーブ・ロード・設定・ログの画面の差し替え（`save`、`load`、`settings`、`log` → `.tscn` のパスかシステムシーンの ID） |
| `subscene_max_depth` | 整数 | サブシーンの呼び出しの深さの上限（既定 10。0 で無制限） |
| `aliases` | 辞書 | 全シナリオで共通のエイリアス（下の「文章の装飾記法」）。同じ名前をシナリオで書くとシナリオが優先 |
| `asset_roots` | 配列 | 素材フォルダ。後ろのものほど優先。アドオンの素材フォルダがいちばん下に重なる |
| `asset_folders` | 辞書 | 種類フォルダの対応表の追加・変更（フォルダ名 → `image`、`bgm`、`se`、`voice`、`font`、`shader`、`video`。`null` で削除） |
| `missing_asset` | `placeholder` / `error` | 素材がないとき、代わりの表示で続けるか、止めるか |
| `lang` | `ja` / `en` | 辞書とパーサーの言語 |
| `dictionaries` | 配列 | 同梱の辞書に重ねる自作の辞書のパス |
| `verbs` | 配列 | 使う拡張の動詞（`GIVE`、`SHOW`、`PUSH`、`PULL`、`HIT`、`CALL`、`THINK`、`WAIT` など） |
| `slot_mode` | `named` / `standard` | 意図のスロット。`named`（既定）は自由な名前、`standard` は `target` と `with` だけ |
| `intent_schema` | 辞書 | 意図スキーマの入口（`entry`）と重ねる層（`layers`：`file` と条件 `when`） |
| `event_defaults` | 辞書 | 出力イベントの種類 → `{wait, log}` の既定値の書き換え |
| `features` | 辞書 | 現代的な機能のキー → `{allow, default, options}`（下の表） |
| `seed` | 整数 | 乱数の種（テスト用。省くと毎回変わる） |
| `hint_topics` | 辞書 | ヒントの話題 → 表示名 |
| `transitions.named` | 辞書 | 名前付きの切り替え演出（名前 → `{type, duration, …}`） |
| `effects` | 配列 | 自作のフィルター・切り替え演出・画面効果（`*.effect.json`） |
| `variables` | 辞書 | 全シナリオで共通の変数：名前 → `{type, default}`。JSON と Ink（同じ名前の VAR）のどちらでも使える。同じ名前をシナリオで宣言するとシナリオが優先 |
| `constants` | 辞書 | 全シナリオで共通の定数：名前 → 値。条件式・計算式・本文の `{名前}` で読め、書き換えられない（validate は `CONST_WRITE`）。セーブには入らない |
| `ink.sync_variables` | 真偽 | Ink の中で変わった変数を状態に返す（既定 `true`） |
| `save` | 辞書 | セーブの設定（下の表） |

**`save` の項目**

| 項目 | 中身 |
| --- | --- |
| `protection` | `hmac`（改ざんの検知、標準）、`hmac_aes`（検知＋暗号化）、`none` |
| `on_tamper` | `reject`（読まない）、`warn`（警告して読む。暗号化したものには効かない） |
| `text_format` | JSON のまま書き出す |
| `dir` | 保存先のフォルダ（`user://` の下） |
| `slots` | スロットの数 |
| `key_provider` | `embedded`（標準）、`per_user`（端末ごとの鍵。セーブを持ち出せない）、自作のスクリプトのパス |

**`features` のキー**

各機能は `{"allow": 使えるか, "default": 最初から入れるか, "options": {細かい設定}}` で書きます。プロジェクトで `allow: false` にした機能は、テンプレートやプレイヤー設定で入れられません。

| キー | 機能 | 既定 | 依存 |
| --- | --- | --- | --- |
| `message_log` | メッセージログ | オン | — |
| `hint` | 段階式ヒント | オフ | — |
| `objective` | 目的の確認 | オフ | — |
| `hotspot` | 調べられる場所の表示 | オフ | — |
| `tried_marks` | 試したコマンドの表示 | オフ | — |
| `autosave` | オートセーブ（`options.on`：`checkpoint`、`scene`） | オン | — |
| `skip` | 既読スキップ | オン | — |
| `auto_advance` | オート送り | オン | — |
| `rewind` | 巻き戻し（`options.max_steps`） | オフ | `message_log` |
| `flowchart` | フローチャート | オフ | — |
| `chapter_select` | チャプター選択 | オフ | — |
| `notebook` | 手帳・推理メモ | オフ | — |
| `era_switch` | 旧表示と新表示の切り替え | オフ | テンプレートが2つ以上 |
| `readable_font` | 読みやすいフォント | オフ | `fonts.readable` がある |
| `text_options` | 文字の大きさ・色・窓の濃さ | オン | — |
| `tts` | 読み上げ | オフ | 実行環境が対応 |
| `gamepad` | コントローラー操作 | オン | — |
| `touch` | タッチ操作 | オン | タッチできる端末 |
| `filter_toggle` | フィルターの無効化 | オン | — |
| `screenshot` | 画面の写真（F7。デバッグ実行中はいつも使える） | オフ | — |
| `recording` | 画面の録画（F10。デバッグ実行中はいつも使える） | オフ | — |

## テンプレート（template.json）

テンプレートは画面の見た目を決めます。`extends` で元のテンプレートを継承し、違う項目だけを書きます（項目ごとに上書き、`null` で取り除く）。座標はすべてそのテンプレートの元の解像度のピクセルで、`rect` は `[x, y, 幅, 高さ]` です。

| 項目 | 中身 |
| --- | --- |
| `template_version`、`id`、`name` | 形の版（`1`）、ID、表示名 |
| `extends` | 継承元のテンプレート ID。`null` で継承しない |
| `display.preset` | 機種 ID（`98`）か `機種ID.モード名`（`X68K.512x512`） |
| `display.scale` | `integer`（整数倍、既定）、`fit`、`none` |
| `display.aspect_correction` | 縦横比の補正（横は整数倍のまま縦を伸ばす） |
| `palette.source` | `preset`（プリセットの色）か `colors`（`palette.colors` に `"#rrggbb"` を並べる） |
| `fonts.main`、`fonts.readable` | `{asset, size, line_height?}` を1つか候補の配列。`main` はドットのまま、`readable` はなめらかに描く |
| `layout.background` | 画面の背景のパレット番号 |
| `layout.layers` | 絵の窓の中の画像の層（奥から順）。既定 `["bg", "char", "fg", "effect"]` |
| `layout.screen_layers` | 画面全体のスプライトの層。既定 `["back", "front"]`。`back` で始まる層は窓の後ろ |
| `layout.regions` | 区割り。`picture`（絵）、`message`（文章）、`commands`（コマンド選択）、`input`（入力欄）ごとに `rect`、`window`、`visible` |
| `layout.named` | 名前付きのレイアウト（`layout.set` で切り替える。窓を隠すときは `"visible": false`） |
| `inputs.enabled` | 使う入力：`select`（コマンド選択）、`parser`（コマンド入力）、`icon`（アイコン）、`click`（絵をクリック）、`verb_click`（動詞リスト＋クリック）、`verb_cursor`（アイコン切り替え）、`context`（コンテキスト） |
| `inputs.click_verb` | 絵をクリックしたときの動詞（既定 `EXAMINE`） |
| `inputs.context_verbs` | コンテキストで、カーソルの種類から決める動詞（種類 → 動詞ID。既定 `talk`→`TALK`、`take`→`TAKE`、`exit`→`MOVE`） |
| `inputs.context_alt_verb` | 右クリックの動詞（既定 `LOOK`） |
| `inputs.item_verb` | 持ち物を押して持ったときの動詞（既定 `USE`） |
| `inputs.verb_cursors` | 動詞ごとのカーソルの種類（動詞ID → 種類） |
| `inputs.parser_profile` | コマンド入力の読み方：`ja`（日本式）、`en`（英語式）、`free`（自由文。「古いドアを開けてみる」）、自作のパーサーのスクリプトのパス |
| `inputs.command_columns` | コマンド選択の列の数（既定 2） |
| `text.speed` | 1秒あたりの文字数（0 で一度に表示） |
| `text.ruby`、`text.emphasis` | ルビと傍点：`above`、`paren`（括弧書き）、`none` |
| `text.color`、`text.name_color` | 文章と話者名のパレット番号 |
| `text.denied_tags` | 使わせない装飾のタグ |
| `filters` | `{mode, list}`。`mode` は `default`（プリセットのまま）、`append`、`replace`、`none`。配列で書くと `replace` |
| `transitions` | `default`（既定の演出）、`named`（名前付き）、`replace`（演出の置き換え表。例 `{"fade": "dissolve"}`） |
| `features` | 機能の既定値の上書き（例 `{"hint": false}`） |
| `assets` | テンプレートが持つ素材フォルダ（`root`）と手書きマニフェスト（`manifest`） |
| `ui.window_skin` | `{"type": "box", "border", "pal", "fill"}`（色の枠線）か `{"type": "nine_patch", "image", "margins"}`（9分割画像） |
| `ui.window_padding` | 窓の内側の余白 `[横, 縦]`（既定 `[8, 4]`） |
| `ui.highlight` | 選んでいる項目のパレット番号 |
| `ui.wait_mark`、`ui.page_mark` | クリック待ちとページ送り待ちの印。文字（"▼"、点滅）か `{text, blink}` か `{image, anim, blink, color_key, offset}`。画像はアニメーションを再生する。`page_mark` を省くと `wait_mark` と同じ |
| `ui.cursors` | マウスカーソル（下の表） |

**`ui.cursors`**

種類ごとに、OS 標準の形の名前（`arrow`、`pointing_hand`、`cross`、`help`、`move`、`busy`、`ibeam`、`wait`）か `{"image": 画像ID, "hotspot": [x, y]}` を書きます。画像は画面の拡大率に合わせて拡大されます。

| 種類 | 使われるとき |
| --- | --- |
| `default` | 通常 |
| `look` | 調べられる物の上 |
| `talk` | 人物の上 |
| `take`、`use` | 物の `cursor` で指定したとき |
| `exit` | 出口の上 |
| `wait` | 演出の実行中 |
| `next` | クリック待ち |
| `text` | 入力欄の上 |

## 素材マニフェスト（manifest.json）

素材はフォルダの決まりで自動登録され、`manifest.auto.json` に書き出されます。手書きの `manifest.json` には、自動では決まらない属性だけを書きます。同じ ID は手書きの方が優先です。

**ファイル全体**

| 項目 | 中身 |
| --- | --- |
| `manifest_version` | `1`（必須） |
| `base` | ファイルの基準フォルダ（省略時はマニフェストのあるフォルダ） |
| `generated` | 自動生成なら `true` |
| `assets` | `ID`（または `種類:ID`）→ 素材の属性 |

**素材の属性**

| 項目 | 対象 | 中身 |
| --- | --- | --- |
| `type` | すべて | `image`、`bgm`、`se`、`voice`、`font`、`shader`、`video` |
| `file` | すべて | 既定のファイル（`base` からの相対パス） |
| `variants` | 画像 | 差分名 → ファイル（表情など） |
| `by_preset` | すべて | 機種別の差し替え。キーは `98.640x400` → `98` → `pc80` → `file` の順に探す |
| `pivot` | 画像 | 基準点 [x, y] |
| `region` | 画像 | 切り出し範囲 [x, y, 幅, 高さ] |
| `color_key` | 画像 | 透明にする色（`"#ff00ff"` かテンプレートのパレット番号） |
| `grid` | 画像 | スプライトシートの切り方 [横の数, 縦の数] |
| `anims` | 画像 | アニメーション名 → `{frames, fps, loop}`。`frames` はコマ番号か画像 ID、`loop` は真偽か回数 |
| `hotspot` | 画像 | カーソル画像の指す位置 [x, y] |
| `alt` | 画像 | 外字（`[gaiji=ID]`）を文字で表すときの文字（メッセージログ、読み上げ） |
| `keep_colors` | 画像 | 色をそのまま出す。`true` なら、外字として出すときに減色フィルターをかけない（既定 `false`。走査線などはかかる） |
| `loop_start` | 音 | 繰り返しの戻り先（秒） |
| `volume` | 音 | 音量（0〜1） |
| `x.名前`、`ext` | すべて | 自作の項目 |

**自動登録の決まり**

| 決まり | 例 | 登録されるもの |
| --- | --- | --- |
| 種類はいちばん上のフォルダで決まる | `bg/hallway.png` | 種類 `image`、ID `hallway` |
| さらに下のフォルダは `.` でつなぐ | `bg/town/street.png` | ID `town.street` |
| `@` の後ろは差分名 | `chara/ayumi@smile.png` | `ayumi` の差分 `smile` |
| `presets/<機種かグループ>/` の下は機種別 | `presets/88/bg/hallway.png` | `hallway` の `by_preset.88` |
| `_` か `.` で始まるものは無視 | `bg/_draft.png` | なし |

種類フォルダの既定：`bg`、`chara`、`cg`、`ui`、`sprite` → 画像、`bgm`、`se`、`voice` → 音、`font` → フォント、`shader` → シェーダー、`movie` → 動画。プロジェクト設定の `asset_folders` で変えられます。

**重ねる順番**：アドオンの素材 → プロジェクトの `asset_roots` → テンプレートの `assets`。後のものが同じ ID を上書きします。素材 ID の名前は種類ごとに別です（`bg/door.png` と `se/door.wav` はぶつからない）。

## JSON シナリオの構成（*.scenario.json）

1つのゲームを複数のシナリオファイルに分けても構いません。プロジェクト設定の `scenarios` に並べたファイルをすべて読み、ひとつにまとめます。

**ファイルのいちばん上**

| 項目 | 中身 |
| --- | --- |
| `scenario_version` | 形の版（`1`） |
| `start` | 開始シーンの ID |
| `variables` | 変数の宣言：名前 → `{type, default}`。`type` は `bool`、`int`、`float`、`string` |
| `constants` | 定数：名前 → 値（書き換えられない。全シナリオ共通のものはプロジェクト設定に書く） |
| `aliases` | エイリアス：名前 → 文か `{params, text}`（「文章の装飾記法」） |
| `characters` | 話者：ID → `{name, names, pal, voice}`（`pal` は名前の色、`voice` は既定の声） |
| `items` | アイテム：ID → `{name, names, on}` |
| `scenes` | シーン：ID → 下の表 |
| `dialogues` | 会話：ID → 手順の配列 |
| `topics` | 話題：話者 ID → `[{id, label, names, dialogue, when}]`（「きく」で選ぶ） |
| `nouns` | 名詞の言い換え：語 → 別名の配列 |
| `replies` | 決まった返事（`no_target` など）の上書き |
| `verbs`、`particles` | 辞書の動詞と助詞の上書き |
| `event_defaults` | このファイルだけのイベントの既定値 |
| `assets` | シナリオが持つ素材フォルダ（`root`、`manifest`） |
| `flow` | フローチャート：`nodes`（`{id, label, chapter}`）と `edges`（`{from, to}`） |
| `chapters` | チャプター：`[{id, label, node, unlocked}]`（`node` に到達すると選べる） |
| `scene` | シーン1つだけのファイルのときのシーン ID（下のシーンの項目をいちばん上に書く） |

**シーン（`scenes.<ID>`）**

| 項目 | 中身 |
| --- | --- |
| `name` | 表示名 |
| `kind` | シーンの種類：`normal`（既定）、`title`（タイトル）、`opening`、`ending`、`sub`（サブシーン）、`system`（システムシーン）。下の「特殊なシーン」 |
| `params` | サブシーンの引数：名前 → 既定値か `{default, required, description}` |
| `menu` | タイトル・システムのシーンのメニュー `[{label, do, when, once, id}]`。選択肢として出し、選んだ項目の手順が終わるとまた出す |
| `ending` | エンディングの ID（kind `ending`）。入ると見た記録を付ける |
| `replay` | オープニングの2回目から：`always`（毎回、既定）、`once`（流さずに次へ）、`skippable`（Esc で飛ばせ、Ctrl で早送り） |
| `next` | オープニングを飛ばしたとき・終わったときに移るシーン（なければタイトルか開始シーン） |
| `bgm`、`bgm_fade` | 入ったときに鳴らす BGM（ID か `{id, fade, loop, volume}`。同じ曲ならそのまま、`null` で止める）と、止めるときのフェード |
| `transition` | このシーンに入るときの切り替え演出 |
| `variants` | 入ったときの背景・BGM・メニューの差し替え `[{when, image, bgm, bgm_fade, menu}]`（`when` に合うものを順に重ねる。見たエンディングでタイトルを変えるなど） |
| `fin` | エンディングを最後まで進めたときの「おわり」の画面（`false` で出さない。辞書ならプロジェクト設定の `fin` に重ねる） |
| `image` | 背景の画像 ID（入るとき `bg` 層に出す）。配列なら、要素（素材 ID か `{id, variant, x, y, when}`）のうち `when` に合うものを順に重ねて1枚にする。条件が変わると描き直す |
| `image_transition` | 配列の image が条件で変わったときの切り替え演出（既定 cut） |
| `first` | 初めて入ったときの手順 |
| `enter` | 入ったときの手順（`first` があれば2回目から） |
| `objects` | 物と人物：ID → 下の表 |
| `exits` | 出口：行き先のシーン ID → `true` か `{names, label, when, on, region, sprite, cursor}` |
| `sprites` | シーンに置くスプライトの配列（`sprite.show` と同じ項目に、`when`、`show`、`hide` を足す） |
| `on` | 対象のないコマンド（「かんがえる」など）への反応 |

**物（`objects.<ID>`）**

| 項目 | 中身 |
| --- | --- |
| `names` | コマンド入力で通じる呼び名 |
| `label` | コマンド選択に出す名前（省略時は `names` の最初） |
| `region` | クリックできる範囲 [x, y, 幅, 高さ]（絵の窓の中の座標） |
| `sprite` | 結び付けるスプライト ID（不透明な部分がクリック範囲） |
| `cursor` | マウスを重ねたときのカーソルの種類 |
| `click` | クリックしたときに使う動詞ID（コンテキストと画面選択の方式。書かなければカーソルの種類から決める） |
| `character` | 人物として扱うときの話者 ID |
| `when` | この物がある条件 |
| `on` | 動詞 → 手順。`"USE+door"` のように「動詞+相手の ID」で、`with` の相手ごとの反応を書ける |

**特殊なシーン**

- **タイトル**：プロジェクト設定 `title_screen` にシーン ID を書くと、そこから始まります。`menu` の手順では `{"game.new": {}}`（はじめから）、`{"game.continue": {}}`（ロード画面）、`{"endings.open": {}}`、`{"chapters.open": {}}`、`{"settings.open": {}}`、`{"game.quit": {}}` を使います。
- **オープニング**：`kind: "opening"`。プロジェクト設定 `opening` に書くと起動時に流れ、終わるとタイトル（なければ開始シーン）へ進みます。2回目からの流し方は `replay`。
- **エンディング**：`kind: "ending"` と `ending: "ID"`。スタッフロールは `{"credits.roll": {"items": [...]}}`、タイトルへ戻るのは `{"game.title": {}}`。BGM と切り替え演出はシーンの `bgm` と `transition`。
- **サブシーン**：`kind: "sub"`。`{"call_scene": "ID", "args": {…}, "into": "変数"}` で呼び、`{"return": 値}` で戻ります。中では引数を `arg.名前` で読みます。
- **システムシーン**：`kind: "system"`。プロジェクト設定 `system_scenes` で、セーブ・ロード・設定・ログの画面の代わりに開きます。中では `sys.mode` などが読め、`system.save`、`system.load`、`system.close`、`settings.set` を使います。閉じると、開く前の状態に戻ります。
- **「おわり」の画面**：エンディングのシーンを最後まで進めると出ます。`fin` の項目は `text`、`pal`、`size`、`image`、`fill`、`transition`、`advance`（閉じる条件：`"click"`、`"key"`、`"key:Enter"`、秒数、`"trigger:名前"`）、`min_time`、`then`（`"title"`、`"new"`、`"quit"`、`"stay"`、シーン ID）、`reset`。`"trigger:名前"` は GDScript から `fire_trigger("名前")` で送ります。
- **「おわり」の画面の続き**：`items`（スタッフロールと同じ）で複数の行と画像を並べられます。`save_prompt: true` で、閉じたあとクリアデータをセーブするか聞きます。クリアデータをロードすると、変数を引き継いで `save_resume`（なければ開始シーン）から始まります。
- **クリアデータで引き継ぐもの**：`save_carry` に `"all"`（既定）、`"none"`、`{"vars": ["money"], "items": "all", "visited": true}` など。書かなかったものは引き継ぎません。
- **おまけ**：プロジェクト設定 `extras` の `gallery`（画像）と `music`（曲）。条件 `when`（既定 `sys.all_endings`）に合えば、テンプレートのタイトルの「おまけ」か `{"extras.open": {}}` で開けます。項目は一度見た・聞いたものが開きます（`when` で条件も書けます）。
- **おまけの続き**：`menu` でエンディング一覧（`endings`）とオープニング（`opening`）も並べられます。ギャラリーの項目に `images` を書くと、見た画像をめくれます。音楽は「さいせい」で、1曲くりかえし・つづけて・ぜんぶくりかえしを切り替えます。
- **見本の画像と曲の説明**：ギャラリーは開いている項目の左に見本の画像を出します（`thumb` で選べます。`"thumbnails": false` で出しません）。音楽は項目の `desc` を鳴らしている間に出します（`"music_desc": false` で出しません）。
- **特典**：項目に `"bonus": true` を書くと、ギャラリー（音楽）を全部開いたときに開く特典になります。条件は `when` で変えられ、`sys.gallery_opened`・`sys.gallery_total`・`sys.gallery_all`（音楽は `sys.music_…`）が使えます。開くまで出さず、`"hidden": false` なら「？？？」で出します。`"bonus": false`（extras の項目）で特典を使いません。
- **特典のお知らせ・開いた数**：特典が開くと右上に「おまけが ふえました」が出ます（`"notify": false` で出さない、文言は `notify_text`）。`"title_count": true` でテンプレートのタイトルの「おまけ」に開いた数が出ます。数は `sys.extras_opened`・`sys.extras_total` でも読めます。
- **お知らせ**：`{"notice.show": {"text": "てちょうを みなおそう"}}` で出します。プロジェクト設定 `notices` に場面ごとの文言を書くと、その場面で自動で出ます：`item_add`・`item_remove`（`{name}`、`{count}`）、`notebook_add`（`{title}`）、`objective_set`（`{text}`）、`hint_set`（`{topic}`）、`autosave`。書かなかった場面は出さず、`"enabled": false` で全部止めます。
- **お知らせの絵とログ**：`{"notice.show": {"text": "…", "icon": "key_icon", "log": true}}`。`notices` の項目は `{"text": "…", "icon": "…", "log": true}` とも書けます。持ち物には `items` の `icon` で絵を付けられ、持ち物のお知らせに出ます。ログに残すかの既定は `notice_style` の `log`（既定 false）。
- **お知らせの見た目**：テンプレートの `notice` かプロジェクト設定 `notice_style` の `position`（`top_right`・`top_left`・`bottom_right`・`bottom_left`・`top`・`bottom`・`center`）、`fg`・`bg`・`border`（パレットの番号。`-1` で枠なし）、`se`、`seconds`（`0` でクリックするまで出す）、`margin`、`icon_size`、`log`、`click_close`（クリックで消せるか。既定 true）、`log_mark`・`log_color`（ログでの印と色）、`max`（同時に出す数。既定 5、超えたら古いものから消す。0 で上限なし）、`overflow`（上限で消すとき：`instant`・`fade`）、`log_filter`（ログの画面を開いたときに出すもの：`all`・`text`・`notice`）、`log_labels`（ログの切り替えの文言 `{all, text, notice}`）。`notice.show` と `notices` の項目の `position` で、そのお知らせだけ別の位置に出せます。ログに残したお知らせは、ログの画面で印と色が付き、右上の切り替え（Tab キーでも）でお知らせだけ・文章だけにできます。
- **読み直す（デバッグ）**：デバッグ実行中に F8（デバッグの「読み直す」ボタン、デバッグコンソールの `reload` でも）で、プロジェクト設定・シナリオ・素材の一覧を読み直します。遊んでいる状態と画面はそのままです。Shift+F8（`reload enter`）で読み直したあといまのシーンに入り直し、プロジェクト設定 `debug` の `auto_reload: true`（コンソールの `autoreload on`）で、ファイルを保存したら自動で読み直します。`reload_reenter`、`watch_interval`（秒）も書けます。シナリオエディタの右上の「保存で読み直す」でも入・切でき、読み直したときは変わったファイルの名前をお知らせに出します（数は `notice_files`）。デバッグの「エディタで開く」（コンソールの `edit`）で、いまのシーンをエディタのシナリオエディタで開きます（会話の中ならその会話、Ink ならそのノットの行まで）。シナリオエディタの「▶ このシーンから実行」で、開いているシーンからゲームを動かせます（デバッグビルドだけ）。「実行：」の列でフラグ・変数・持ち物のひな形（プロジェクト設定 `debug.run_presets`：`{"終盤": {"vars": {"key_found": true}, "items": {"key": 1}}}`）を選べ、「履歴 ▾」で最近の実行をもう一度動かせます。会話の画面の「▶ ここから実行」は、選んでいる手順（「もし」や選択肢の中の手順も。Ink はカーソルのあるノット）から始めます。履歴は「★ お気に入りの印…」で上に残せます。デバッグ実行中のゲームの「ひな形に」で、入れる変数・持ち物を選んでひな形にできます（コンソールの `preset [名前]` は全部）。ひな形の窓の「比べる：」で、ほかのひな形と違うところだけを見られます。会話の画面の「設定を先に」で、途中から実行するときにそこまでの「設定する」を先に動かせます（「条件も」で前の「もし」の中も条件を見て）。ひな形の窓の「複製」で写しを作れ、「書き出す…」「読み込む…」でほかのプロジェクトとやり取りできます。ゲームの「ひな形に」の一覧は絞り込め、値を書きかえて送れます。先に動かした「設定する」の値は、お知らせとメッセージログに出ます（`debug.pre_set_notice`・`debug.pre_set_log` で切り替え）。書き出しも読み込みも、全部でも選んだものだけでもできます。「先に設定」のお知らせの秒数は `debug.pre_set_seconds`（0 でクリックするまで）。ゲームの一覧の行は「×」で外せ、「外したものを戻す」でまとめて戻せます。読み込みでは「中身が違うものは上書きする」も選べます。「先に設定」のお知らせの位置は `debug.pre_set_position`、見た目は `debug.pre_set_style`。上書きで読み込むときは、いまの中身との違いが窓に出ます。ゲームの一覧は「送っても閉じない」で続けて送れ、そのとき同じ組にまとまります。デバッグのお知らせはまとめて `debug.notice_style` で見た目を変えられます。「実行：」の一覧は組ごとに並び、「絞り込み」で名前か組の一部で絞れ、組の見出しを選ぶとたたむ・開くができます。「組…」で組の名前を変える・書き出す・消すができます。デバッグのお知らせは `debug.notices` で種類ごとに出さないようにでき、動かしている間はコンソールの `notice` で切り替えられます。「組…」では組の並び順と、組に入れるひな形も決められ、組のひな形を選んでそのまま実行できます。ひな形には最後に使った時が出ます。コンソールの切り替えは `notice save` で設定に書けます。「実行：」は「使った順」にも並べられ、「片付け…」でしばらく使っていないひな形をまとめて寄せる・消すことができます。お知らせの見た目はコンソールの `noticestyle` で試して `noticestyle save` で残せます（ふつうのお知らせは `noticestyle game …`）。「実行：」は「作った順」にも並べられ、「片付け…」は組で絞れ、印を付けたひな形の中身ものぞけます。ひな形の窓には作った日時と最後に使った日時が出ます。試したお知らせの見た目は `noticestyle [game] keep 名前` で取っておき、`next` で切り替えて見比べられ、エディタの「見た目…」から選んでプロジェクト設定に書けます。片付けの窓では二つのひな形を比べられ、ひな形の窓には最後に使った場所も出ます。「見た目…」では取っておいた見た目の名前を変えたり消したり（一つだけ戻せます）でき、ひな形の窓の「比べる：」の「いつもの始まり」でひな形なしで始めたときとの違いを見られ、「そこから動かす」で最後に使った場所からもう一度動かせます。いつもの始まりと比べると、ひな形にない変数も薄く並びます。「実行：」の一覧を右クリックすると、そこから動かす・いまのシーンから実行・開く・複製のメニューが出ます。「見た目…」の「いまの設定を取っておく」で、プロジェクト設定の見た目をエディタから取っておけます。薄く並んだ「ひな形にない変数」は押すとひな形に足せ、右クリックの「組を変える…」でひな形を別の組へ移せ、「見た目…」の「比べる：」で二つの見た目の違いを見られます。薄い行の「［全部足す］」でひな形にない変数をまとめて足せ、見た目を比べているときは違う行を押すと右の値を左へ写せます（「一つ戻す」で戻せます）。「［全部写す］」でまとめて写せます。ひな形の窓でも違いの行を押すと相手の値を窓へ写せ、書き出したファイルには組・作った日時・組の並びも入ります。ひな形の窓の「写す前に戻す」で最後の写す・足すを戻せ、読み込む窓には組が出て、片付けの「二つを比べる」では「← 左へ」「右へ →」で値を写せます（元に戻せます）。「［← 全部左へ］」「［全部右へ →］」でまとめて写せ、片付けの窓は開いたまま元に戻しても並べ直します。読み込む窓の「読み込む組」で、まとめて入れる組を選べます（前の選びを覚えています）。ひな形の窓も開いたまま元に戻すと並べ直し、長い名前の一覧は「…」で切って、全文はマウスを当てると出ます。読み込む窓の行にマウスを当てるとファイルの中身（同じ名前があればいまの中身も）が出ます。ゲームの中のお知らせは、長い文なら画面の幅で折り返します（GB のような小さい画面でも）。ひな形の窓は Ctrl+Enter で保存、Ctrl+Z で写す前に戻せ、片付け・読み込むなどの窓は広げると一覧が伸びます。片付けは Ctrl+Z・Ctrl+Y、読み込むは Ctrl+Enter、見た目は Ctrl+Z も使えます。GB・FC のような小さい画面でも、メニュー・ログ・セーブの窓は文字が見え、見える範囲に収まります。小さい画面では、デバッグのお知らせはゲームの画面の外（デバッグのボタンの下）に出ます（debug.notice_style の layer で screen・window にも）。タイトル画面は小さい画面でも題名とメニューが収まるよう寄せ、入らなければ流せます（▲・▼ でまだ項目があると知らせます）。メニューや設定の一覧は、キーで選んだ項目に付いて流れ、長い項目は「…」で切ります。ゲームの一覧の「足す」で、まだ書かれていない変数・持ち物も入れられます。
- **画面の写真と録画**：F7 で写真（PNG）、F10 で録画（AVI。もう一度押すと止める）。デバッグ実行中はいつも使え、配布アプリではモダン機能 `screenshot`・`recording` を入れたときだけ使えます（`"features": {"screenshot": {"default": true}}`）。`features` に書くと、設定の画面に遊ぶ人の切り替えが出ます（`options.menu: false` で出さない）。`options` は、両方に `key`（キーの名前、既定 `"F7"`・`"F10"`）、`source`（`window`：窓の全体を見えているとおり、`screen`：元の解像度の画面をフィルターの前で）、`scale`（倍率、既定 1）、`folder`（既定 `user://screenshots`・`user://recordings`）、`prefix`（ファイルの名前の頭）、`notice`（保存のお知らせ、既定 true）、`menu`。録画だけ `fps`（1〜60、既定 30）、`quality`（JPEG の質 0〜1、既定 0.85）、`audio`（音も、既定 true）、`max_seconds`（既定 600、0 で決めない。1.9 GB でも止まる）、`indicator`（`title`：窓の名前に「● REC」、`none`）。録画は映像が MJPEG、音が 16 ビット PCM の AVI です。SNS に載せるときは `ffmpeg -i 録画.avi -c:v libx264 -pix_fmt yuv420p -c:a aac 録画.mp4` などで変換します。デバッグ実行中に止めたいときは、プロジェクト設定 `debug.capture: false`（配布アプリと同じく、モダン機能に従います）。デバッグコンソールでは `shot`、`rec [start|stop]`、`capture`（保存先と様子）、`capture open shot|rec`（フォルダを開く）。
- **見つからない ID（デバッグ）**：デバッグ実行の起動時に、シナリオの素材・行き先とプロジェクト設定の素材を確かめ、見つからないものをデバッグコンソールの `ids` で一覧にします。
- **記録を消す（デバッグ）**：デバッグコンソール（F12）で `extras clear`（おまけの記録）、`extras unlock`（全部開く）、`endings clear`（見たエンディング）、`read clear`（既読）、`flow clear`（チャプター選択の到達点）、`openings clear`（見たオープニング）、`progress clear`（すべて）。`progress` で記録の数を出します。
- **見たエンディングでタイトルを変える**：`sys.endings_seen`、`sys.endings_total`、`sys.all_endings`、`sys.ending_<ID>` を条件に使い、タイトルのシーンの `variants` かプロジェクト設定 `title_variants` で背景と BGM を差し替えます。
- **オープニングを見返す**：テンプレートのタイトルの「オープニング」、エンディング一覧、`{"opening.play": {}}`。条件はプロジェクト設定 `opening_replay`。タイトルのシーンでは `sys.opening_replay` で見返せるかを読めます。
- タイトル・オープニング・エンディング・システムのシーンでは、コマンドの一覧と入力欄を出さず、選択肢だけを選べます。

**反応の探し方**：対象の物 → 出口 → 持っているアイテムの順に探します。出口に `MOVE` の反応がなければ、そのシーンへ移ります。ある動詞の反応がないとき、ほかの動詞の反応を代わりに使うことはしません（「しらべる」と「みる」も別々）。

## 手順の書き方

`first`、`enter`、`on` の各動詞、`dialogues` の会話は、すべて「手順」で書きます。手順は1つの書き方か、その配列です。配列は上から順に実行します。

| 書き方 | 意味 |
| --- | --- |
| `"文章"` | 地の文（`text.show`） |
| `"@ayumi 文章"` | 台詞（話者 ID つき）。行頭に `@` を出したいときは `@@` |
| `{"say": "ayumi", "text": "…", "id": "…", "voice": "…"}` | 台詞。行 ID とボイスを付けるとき |
| `{"if": 条件, "then": 手順, "else": 手順}` | 条件分岐（`else` は省略できる） |
| `{"set": {"変数": 値}}` | 変数の変更。値が `"= 式"` なら計算式 |
| `{"let": "money = money - 10; visits = visits + 1"}` | 計算式での変更（`;` で複数） |
| `{"call": "会話ID"}`、`{"dialogue": "会話ID"}` | 別の会話を呼ぶ（終わったら戻る） |
| `{"goto": "ID"}` | 移る（戻らない。会話の中では会話を、それ以外ではシーンを優先して探す）。そこで手順を打ち切る |
| `{"choice": {"id", "prompt", "options": [{"id", "label", "do", "when", "once"}]}}` | 選択肢。`when` で出す条件、`once` で一度選んだら消す。ID は省略できる |
| `{"ink": "ノット名"}` | Ink に処理を渡し、終わったら戻る |
| `{"call_scene": "ID", "args": {"名前": 値}, "into": "変数"}` | サブシーンを呼ぶ。`"= 式"` の引数は呼ぶ側で計算する。戻り値は `into` の変数に入る |
| `{"return": 値}` | サブシーンから戻る（`"= 式"` も可。値がなければ `null`） |
| `{"種類": {引数}}` | 出力イベント（例 `{"se.play": {"id": "knock"}}`。「出力イベント」の章） |
| `{"checkpoint": {}}`、`{"wait": {"seconds": 1}}`、`{"group": {…}}` | `.` のない出力イベント |
| `{"type": "…", "args": {…}, "wait": …}` | 出力イベントの正式な形（`wait` や `log` を変えるとき） |

**行 ID と既読**：文章の行 ID は、会話 ID と本文から自動で作ります。本文を直すと既読が外れるので、ボイス付きの行などは `say` の `id` を手で書きます。

**選択肢の例**

```json
{ "choice": {
    "prompt": "どう こたえる？",
    "options": [
      { "label": "たんていだ", "do": ["@ayumi よかった……。", { "set": { "met_ayumi": true } }] },
      { "label": "なのらない", "once": true, "do": ["@ayumi ……そう。"] }
    ] } }
```

選択肢を出している間は、ほかのコマンドを受け付けません。セーブすると入力待ちの位置も残り、ロードすると同じ選択肢を出し直します。

## 条件式と計算式

`if`、`when`、選択肢や話題の出す条件など、条件を書く場所はすべて同じ書き方です。短い文字列の形と JSON の形があり、どちらでも書けます。

```json
"has_key and money >= 100 and (visited(cellar) or has(lamp)) and not scene == hallway"

{ "all": ["has_key", { "var": "money", "ge": 100 },
          { "any": [{ "visited": "cellar" }, { "has": "lamp" }] },
          { "not": { "scene": "hallway" } }] }
```

| 種類 | 短い形 | JSON の形 |
| --- | --- | --- |
| フラグ | `has_key` | `"has_key"` |
| 比較 | `==`、`!=`、`<`、`<=`、`>`、`>=` | `{"var": "money", "eq"｜"ne"｜"lt"｜"le"｜"gt"｜"ge": 値}`、`"in": […]` |
| かつ | `and`、`&&` | `{"all": […]}` |
| または | `or`、`\|\|` | `{"any": […]}` |
| 否定 | `not`、`!` | `{"not": …}` |
| まとめる | `( )` | 入れ子 |

**組み込みの名前**

| 名前 | 意味 |
| --- | --- |
| `has(アイテム)` | そのアイテムを持っているか |
| `count(アイテム)` | 持っている数（`count(coin) >= 3`） |
| `scene` | 今のシーン（`scene == hallway`） |
| `visited(シーン)` | そのシーンを訪れたか |
| `talked(会話ID)` | その会話を見たか |
| `read(行ID)` | その行を読んだか |
| `chosen(選択肢ID, 項目ID)` | その選択肢でその項目を選んだか |
| `arg.名前` | サブシーンの引数 |
| `sys.名前` | システムシーンの値（`sys.mode`、`sys.slot_count`、`sys.slot_01`、`sys.slot_01_exists`、`sys.slot_01_label`、`sys.bgm_volume` など） |
| `preset`、`group` | 今の画面プリセットとグループ（`preset == 98`、`group == console`） |
| `feature(機能)` | その機能が有効か |

**値の書き方**

- 数（`100`、1.5）、真偽（`true`、`false`）、文字列（`"ゆうじ"` か `'ゆうじ'`）。
- 比較の右の識別子は変数として読みます（`money > price`）。ただし `scene`、`preset`、`group` の右は ID として読みます。
- 宣言していない変数は `false`、0、空文字として扱います（開発中は警告）。

**計算式**（`set` の `"= 式"` と `let`）

- 演算子は `+`、`-`、`*`、`/`、`%` と括弧。比較や組み込みの名前も使えます。
- `{"set": {"money": "= money - price * 2"}}`、`{"let": "money = money - price * 2; visits = visits + 1"}`
- 出力イベント `state.set` の `op` でも変えられます：`set`、`add`、`sub`、`mul`、`div`、`mod`、`min`、`max`、`toggle`。

## 文章の装飾記法

文章には Godot の BBCode（`[b]`、`[color]`、`[wave]` など）と、次の独自のタグを書けます。タグは入れ子にできますが、交差した書き方（`[b][i]…[/b][/i]`）は使えません。

| タグ | 動き |
| --- | --- |
| `{名前}`、`[var=名前]` | 変数・定数の値を差し込む（`{{` で文字の `{`） |
| `[pal=番号]…[/pal]` | テンプレートのパレットの色 |
| `[ruby=よみ]漢字[/ruby]` | ルビ（表示方法は `text.ruby`） |
| `[em]…[/em]` | 傍点（表示方法は `text.emphasis`） |
| `[blink]…[/blink]` | 点滅 |
| `[p]`、`[p=秒]` | クリックを待ち、同じ窓で続ける。秒数を書くとその秒数で自動で続ける |
| `[page]`、`[page=秒]` | クリックを待ち、次のページ（窓の先頭）から続ける。秒数は同上 |
| `[w=秒]` | その秒数止まる（省くと 0.5 秒） |
| `[se=ID]` | その位置で効果音 |
| `[speed=文字数]…[/speed]` | その範囲の表示速度（1秒あたりの文字数。プレイヤー設定の倍率をかける） |
| `[instant]…[/instant]` | その範囲を一度に表示 |
| `[gaiji=ID]` | 外字・小さなアイコン。素材の画像をそのままの大きさで文中に入れ、文字送りでは1文字として数える。ログと読み上げではマニフェストの `alt` の文字にする |
| `[alias=名前 引数…]` | エイリアスを置き換える。引数は空白で区切り、空白を含むものは `"…"` で囲む |
| `[if=条件]…[elif=条件]…[else]…[/if]` | 条件に合う部分だけを出す（入れ子にできる） |

**エイリアス**：タグや変数を組み合わせた文に名前を付けます。シナリオかプロジェクト設定の `aliases` に書きます。

```json
"aliases": {
  "hero": "[pal=6]{name}[/pal]",
  "greet": { "params": ["who", "words"], "text": "[alias=hero]は {arg.who}に「{arg.words}」と いった。" }
}
```

- 本文に `[alias=greet あゆみ "こんにちは です"]` と書くと、表示するときに置き換えます。エイリアス → 条件 → 変数と装飾タグの順です。
- エイリアスの中で別のエイリアスを使えます。自分に戻る循環はエラー（`ALIAS_CYCLE`）です。
- JSON の本文、Ink の本文、選択肢の文、エンディング一覧、スタッフロールで使えます。

**ページめくり**

- 窓に入りきらない文章は、窓がいっぱいになったところで止まり、ページ送り待ちの印を出して待ちます。クリックすると残りの行を窓の先頭から出します。
- 文字送り中のクリックは、次の止まる位置（タグかページの終わり）まで一度に出します。
- 何も書かなければ、入力があるまで待ち続けます。`[p=秒]`、`[page=秒]`、`text.show` の `wait` の秒数で、時間で進められます。
- オート送り（F2、設定画面の速さ）を入れると、ページの終わり、`[p]`、`[page]`、クリック待ちのすべてで自動で進みます。
- 待ちの印はテンプレートの `ui.wait_mark`、`ui.page_mark` で変えられます。

その他：

- テンプレートの `text.denied_tags` に書いたタグは取り除いて表示します。
- メッセージログには装飾を外した文字列を残し、ルビは括弧書きにします。読み上げはルビの読みを読みます。

## 出力イベント

出力イベントは「何をするか」の命令です。手順の中では `{"種類": {引数}}` と書き、待ち方を変えるときは `{"type": "種類", "args": {…}, "wait": …}` と書きます。

**`wait`（次に進む条件）**：`none`（すぐ進む）、`click`（クリック待ち）、`end`（演出の終わりまで）、`input`（選択や入力まで）、または秒数。優先順位は、イベント自身 → シナリオの `event_defaults` → プロジェクトの `event_defaults` → 下の表の既定。

**素材の指定**：`id` や `image` には素材 ID かファイルのパスを書きます（`res://` で始まるか `/` を含むものはパス）。

| イベント | 主な引数（`?` は省略可） | 既定の wait |
| --- | --- | --- |
| `text.show` | `body`、`speaker?`、`name?`、`voice?` | `click` |
| `text.append` | `body` | `click` |
| `text.clear` | — | `none` |
| `image.show` | `layer`（既定 `bg`）、`id`、`variant?`、`transition?`、`duration?` | 演出あり `end`、`cut` は `none` |
| `image.hide` | `layer`、`transition?`、`duration?` | 同上 |
| `effect.play` | `name`（`flash`、`shake`、`invert`、`tint`、`palette_cycle`、`scroll`、`zoom`、`raster` など）、`duration?`、効果ごとの引数（`color`、`amount`、`amplitude` など。`args` にそのまま書く） | `end` |
| `sprite.show` | `id`、`image`、`variant?`、`layer?`（既定 `char`）、`x`、`y`、`anchor?`、`z?`、`scale?`、`rotation?`、`opacity?`、`flip?`、`blend?`、`tint?`、`smooth?`、`color_key?`、`anim?`、`transition?`、`duration?`、`keep?`、`mute?`・`volume?`（動画のとき。既定は音なし） | 演出あり `end`、なし `none` |
| `sprite.set` | `id`、変える項目、`duration?`、`ease?`、`loop?`（`-1` で終わりなし）、`yoyo?`、`path?` | `duration` があれば `end`（繰り返しは `none`） |
| `sprite.hide` | `id`（配列も可）、`transition?`、`duration?` | 演出あり `end` |
| `sprite.anim` | `id`、`anim`（`null` で止める）、`loop?` | `none` |
| `sprite.effect` | `id`、`name`（`flash`、`shake`、`blink`、`mono`、`sepia`、`silhouette`、`mosaic`、`none`、シェーダーのパス）、`duration?`、`params?` | `end` |
| `sprite.clear` | `layer?`（省くとすべて） | `none` |
| `cursor.set` | `kind` か `image` と `hotspot`（`null` で自動に戻す） | `none` |
| `video.play` | `id`、`area?`（`picture`、`screen`）、`fit?`（`contain`、`cover`、`stretch`）、`loop?`、`skippable?`、`volume?`、`bgm?`（`pause`、`keep`、`stop`）、`filters?`、`transition?` | `loop` なら `none`、ほかは `end` |
| `video.stop` | `transition?` | 演出あり `end`、なし `none` |
| `bgm.play` | `id`、`loop?`（既定 true）、`fade?`（秒）、`volume?` | `none` |
| `bgm.stop` | `fade?` | `none` |
| `se.play` | `id`、`volume?` | `none` |
| `voice.play` | `id`、`speaker?` | `none` |
| `state.set` | `name`、`value`、`op?` | `none` |
| `item.add`、`item.remove` | `id`、`count?` | `none` |
| `scene.goto` | `scene`、`transition?` | `end` |
| `wait` | `seconds` | その秒数 |
| `group` | `events`（中のイベントを同時に実行） | `end` |
| `choice.show` | `choices`（`id`、`label`、`when?`）、`prompt?` | `input` |
| `input.request` | `slot`、`prompt?` | `input` |
| `game.end` | `ending?` | 終了 |
| `verbs.update` | `verbs`、`mode?`（`replace`、`add`、`remove`） | `none` |
| `hotspots.update` | `objects`、`mode?` | `none` |
| `input.mode` | `enable`（`parser`、`select`、`click`） | `none` |
| `notebook.add` | `id`、`category?`、`title`、`body` | `none` |
| `objective.set` | `id?`、`text`（空で消す） | `none` |
| `hint.set` | `topic`、`hints`（段階の順の配列） | `none` |
| `flow.mark` | `node` | `none` |
| `checkpoint` | `id?`、`autosave?` | `none` |
| `layout.set` | `layout`、`transition?` | `end` |
| `template.switch` | `template`、`transition?` | `end` |
| `save.request` | — | `input` |
| `credits.roll` | `items`（`{text, pal, size, align, image, scale, gap}` か文字列の配列）か `lines` か `text`、`speed?`（1秒あたりの画素。既定 30）、`duration?`（秒）、`align?`、`pal?`、`size?`、`margin?`、`fill?`、`background?`、`skippable?`（既定 true）、`bgm?` | `end` |
| `ending.reach` | `id`（kind `ending` のシーンに入ると自動で出る） | `none` |
| `game.new` | `scene?`（はじめから） | 流れを切る |
| `game.title`、`game.continue`、`game.quit` | — （タイトルへ、ロード画面、終わる） | 流れを切る |
| `endings.open`、`chapters.open`、`settings.open` | — （エンディング一覧、チャプター、設定を開く） | 流れを切る |
| `fin.show` | 「おわり」の画面の設定（`text`、`advance`、`then` など） | 流れを切る |
| `opening.play` | `scene?`（オープニングを見返す） | 流れを切る |
| `extras.open` | — （おまけを開く） | 流れを切る |
| `notice.show` | `text`、`seconds?`（既定 2.5。画面の右上に少しの間お知らせを出す） | `none` |
| `system.save` | `slot`（システムシーンで、開く前の状態をセーブ） | `none` |
| `system.load` | `slot`（システムシーンを閉じてロード） | 流れを切る |
| `system.close` | — （システムシーンを閉じる） | 流れを切る |
| `settings.set` | `key`、`value`（`text_speed`、`bgm_volume`、`features.<キー>` など） | `none` |

**切り替え演出（`transition`）**：`cut`、`fade`、`fade_color`、`wipe`、`blinds`、`line_draw`、`interlace`、`plane_draw`、`mosaic`、`dissolve`、`blocks`、`iris`、`mask`（ルール画像）。名前だけか `{"type": "wipe", "direction": "right", "duration": 0.8}` のように書きます。スプライトの出し入れにも同じ演出が使え、スプライトの範囲だけにかかります（`fade_color` はスプライトでは `fade` と同じ。動画のスプライトはいつも `fade`）。

- `image.show` の `id` には配列も書けます（要素は素材 ID か `{id, variant, x, y}`。順に重ねて1枚にする）。
- `text.show` の `wait` に秒数を書くと、クリックかその秒数で次へ進みます。
- `text.append` は、いまの文章の続きに本文を足します（話者のある文章では「」の中）。ログでは同じ記録になります。
- `video.play` の `transition` は、動画が現れるときと、終わったときや飛ばしたときに消えるときの両方にかかります。繰り返しの動画は `video.stop` の `transition` で消します。

自作のイベントは `x.名前` で書きます。

## Ink との連携

Ink のシナリオは inklecate で `.ink.json` に変換して、プロジェクト設定の `scenarios` に並べます。対応する inkVersion は 19〜21 です。`.ink.json` だけでゲームを作ることも、JSON のシナリオから `{"ink": "ノット"}` で呼ぶこともできます。

**行とタグ**

| 書き方 | 意味 |
| --- | --- |
| `文章` | 1行ごとに `text.show` |
| `@ayumi 文章`、`# speaker:ayumi` | 台詞 |
| `# id:行ID` | 行 ID（省くと `ink:ノット#本文のハッシュ`） |
| `# voice:ID`、`# bg:ID`、`# bgm:ID`、`# se:ID` | その行でボイス、背景、BGM、効果音 |
| `# {"image.show": {…}}` | 出力イベント（JSON の手順と同じ書き方） |
| `# intent:動詞[:対象[:with]]` | 選択肢をコマンド入力でも選べるようにする（`*` は何でも） |
| `# hidden` | 選択肢を一覧に出さない（コマンド入力だけで選ぶ） |

タグだけの行のタグは、次の行に付きます。そのほかのタグは `ext.tags` に入ります。

**変数の同期**：Ink に入るとき、Ink のグローバル変数（`VAR`）と同じ名前の変数・定数の値を Ink に写します。Ink の中で変わったものは戻します（プロジェクト設定 `ink.sync_variables: false` で止める）。

**外部関数**（Ink の `EXTERNAL` で宣言して使う）

| 関数 | 意味 |
| --- | --- |
| `has_item(id)`、`item_count(id)` | 持っているか、いくつ持っているか |
| `item_add(id)`、`item_remove(id)` | アイテムを増やす、減らす |
| `get_var(name)`、`set_var(name, value)` | 変数を読む、書く |
| `visited(scene)`、`talked(id)` | 訪れたか、話したか |
| `cond("条件式")` | 条件式を評価する |
| `event("種類", "引数のJSON")` | 出力イベントを出す |
| `goto_scene(id)` | シーンへ移る |
| `call_scene(id, 引数, 変数)` | JSON のサブシーンを呼ぶ。その行のあとで止まり、戻ったら続きから。引数は `"price=7; item=ミルク"` か JSON、戻り値は変数（同じ名前の VAR にも写る） |

**そのほか**

- 選択肢の項目 ID は `c0`、`c1`…。選んだものは `chosen` に `ink:ノット#…` で残ります。
- Ink が選択肢なしで止まる（`DONE`、`END`、終わり）と、呼んだ JSON の手順の続きに戻ります。
- `LIST` も inkle 社の版と同じに動きます。LIST の変数は、JSON の側からは「項目名, 項目名」の文字列として見えます。`RANDOM`、`SEED_RANDOM`、シャッフルは inkle 社の版と同じ乱数を使うので、同じ種なら同じ結果になります。

## GDScript から使う（AdvPlayer）

メインシーンの `Control` に付ける `adv_player.gd`（`AdvPlayer`）は、インスペクターの項目と、スクリプトから呼べる関数を持ちます。自分のタイトル画面やメニューから操作するときに使います。

**インスペクターの項目**（空ならプロジェクト設定の値）

| 項目 | 中身 |
| --- | --- |
| `project_path` | プロジェクト設定のファイル（既定 `res://adv80s.project.json`） |
| `template_id` | 使うテンプレート |
| `scenario_paths` | シナリオファイル |
| `assets_root` | 追加の素材フォルダ |
| `entry` | 開始シーン |
| `settings_path`、`progress_path` | プレイヤー設定と進行の記録のファイル（空なら保存しない） |
| `auto_click` | テスト用：クリック待ちを自動で進める |

**シグナル**：`fin_shown`（「おわり」の画面を出した）、`system_scene_closed`（JSON のシステムシーンを閉じた）、`game_ended`（`game.end`）、`idle`（入力待ちになった）、`saved(slot)`、`loaded(slot)`

**主な関数**

| 関数 | 中身 |
| --- | --- |
| `submit_text(text)` | コマンド入力と同じように文字列を渡す |
| `submit_intent(intent)` | 意図 `{verb, slots}` を直接渡す |
| `save_game(slot)`、`load_game(slot)`、`autosave()`、`list_saves()` | セーブとロード（`load_game` は await し、失敗すると理由の文字列） |
| `open_save_menu(mode)`、`open_log()` | セーブ・ロード画面、ログを開く（`system_scenes` で差し替えていればそれを開く） |
| `new_game(scene)`、`go_title()`、`open_title_screen()` | はじめから、タイトルへ、テンプレートのタイトル画面 |
| `open_system_scene(id, mode)`、`close_system_scene()`、`is_system_scene_open()` | JSON のシステムシーン |
| `offer_clear_save(settings)` | クリアデータをセーブするか聞き、はいならセーブ画面を開く |
| `can_open_extras()`、`modern.open_extras()` | おまけを開けるか、開く |
| `extras_menu()` | おまけに並べる項目（出せるものだけ） |
| `fill_extras_sys()` | おまけの開き具合を `sys.gallery_*`・`sys.music_*`・`sys.extras_*` に入れる |
| `check_bonus_unlocks()`、`show_notice(text)` | 新しく開いた特典を知らせる、お知らせを出す |
| `title_variant()` | テンプレートのタイトル画面に使う差し替え（`title_variants` のうち合うもの） |
| `fire_trigger(name)` | 合図を送る（「おわり」の画面の `"trigger:名前"`） |
| `show_fin(settings)`、`fin_settings(layers)` | 「おわり」の画面を出す、設定を重ねる |
| `can_replay_opening()`、`replay_opening(scene)` | オープニングを見返せるか、見返す |
| `apply_setting(key, value)` | 設定を変える（`text_speed`、`bgm_volume`、`features.<キー>` など） |
| `modern.open_endings()` | エンディング一覧 |
| `switch_template(id, transition)` | テンプレートを切り替える（await） |
| `cycle_template()` | 登録したテンプレートを順に切り替える |
| `set_feature(key, on)` | 機能のオン・オフ |
| `set_text_option(key, value)` | `text_size`、`text_color`、`window_opacity` |
| `set_filters_enabled(on)` | フィルターのオン・オフ |
| `toggle_auto()`、`toggle_skip()` | オート送り、スキップ |
| `can_rewind()`、`rewind(steps)` | 巻き戻し |
| `jump_to_node(node)` | フローチャートの点から再開 |
| `current_cursor_kind()` | いまのカーソルの種類 |

**自作のシステム画面（.tscn）**：一番上のノードに `AdvSystemScreen` を継いだスクリプトを付け、`_on_opened()` で画面を作ります。`player`、`mode`、`slots()`、`save(slot)`、`load_slot(slot)`、`get_setting(key)`、`set_setting(key, value)`、`log_entries()`、`close()` が使えます。

```gdscript
extends AdvSystemScreen

func _on_opened() -> void:
    var box := VBoxContainer.new()
    add_child(box)
    for s in slots():
        var b := Button.new()
        b.text = "%s %s" % [s["label"], s["info"]]
        var slot: String = s["slot"]
        b.pressed.connect(func():
            if mode == "save":
                save(slot)
            else:
                load_slot(slot))
        box.add_child(b)
```

**主なプロパティ**：`core`（状態とシナリオ。`core.state.get_var("money")` など）、`screen`（画面の部品）、`template`、`audio`、`settings`、`features`、`message_log`、`busy`（実行中か）。
