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
| `*.scenario.json` | 自由 | JSON のシナリオ | VS Code（スキーマ付き） |
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
| `inputs.parser_profile` | `ja` など |
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
| `[gaiji=ID]` | 外字・小さなアイコン（まだ。表示から取り除く） |

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
| `text.clear` | — | `none` |
| `image.show` | `layer`（既定 `bg`）、`id`、`variant?`、`transition?`、`duration?` | 演出あり `end`、`cut` は `none` |
| `image.hide` | `layer`、`transition?`、`duration?` | 同上 |
| `effect.play` | `name`（`flash`、`shake`、`invert`、`tint`、`palette_cycle`、`scroll`、`zoom`、`raster` など）、`duration?`、効果ごとの引数（`color`、`amount`、`amplitude` など。`args` にそのまま書く） | `end` |
| `sprite.show` | `id`、`image`、`variant?`、`layer?`（既定 `char`）、`x`、`y`、`anchor?`、`z?`、`scale?`、`rotation?`、`opacity?`、`flip?`、`blend?`、`tint?`、`smooth?`、`color_key?`、`anim?`、`transition?`、`duration?`、`keep?` | 演出あり `end`、なし `none` |
| `sprite.set` | `id`、変える項目、`duration?`、`ease?`、`loop?`（`-1` で終わりなし）、`yoyo?`、`path?` | `duration` があれば `end`（繰り返しは `none`） |
| `sprite.hide` | `id`（配列も可）、`transition?`、`duration?` | 演出あり `end` |
| `sprite.anim` | `id`、`anim`（`null` で止める）、`loop?` | `none` |
| `sprite.effect` | `id`、`name`（`flash`、`shake`、`blink`、`mono`、`sepia`、`silhouette`、`mosaic`、`none`、シェーダーのパス）、`duration?`、`params?` | `end` |
| `sprite.clear` | `layer?`（省くとすべて） | `none` |
| `cursor.set` | `kind` か `image` と `hotspot`（`null` で自動に戻す） | `none` |
| `video.play` | `id`、`area?`（`picture`、`screen`）、`fit?`（`contain`、`cover`、`stretch`）、`loop?`、`skippable?`、`volume?`、`bgm?`（`pause`、`keep`、`stop`）、`filters?` | `loop` なら `none`、ほかは `end` |
| `video.stop` | — | `none` |
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

**切り替え演出（`transition`）**：`cut`、`fade`、`fade_color`、`wipe`、`blinds`、`line_draw`、`interlace`、`plane_draw`、`mosaic`、`dissolve`、`blocks`、`iris`、`mask`（ルール画像）。名前だけか `{"type": "wipe", "direction": "right", "duration": 0.8}` のように書きます。スプライトの出し入れは、いまはどの演出も `fade` として扱います。

- `image.show` の `id` には配列も書けます（要素は素材 ID か `{id, variant, x, y}`。順に重ねて1枚にする）。
- `text.show` の `wait` に秒数を書くと、クリックかその秒数で次へ進みます。

いまは `text.append` と動画の `transition` はまだ実装していません。自作のイベントは `x.名前` で書きます。

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

**そのほか**

- 選択肢の項目 ID は `c0`、`c1`…。選んだものは `chosen` に `ink:ノット#…` で残ります。
- Ink が選択肢なしで止まる（`DONE`、`END`、終わり）と、呼んだ JSON の手順の続きに戻ります。
- `LIST` はまだ使えません。`RANDOM` とシャッフルは、inkle 社の版と同じ種でも結果が一致しません。

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

**シグナル**：`game_ended`（`game.end`）、`idle`（入力待ちになった）、`saved(slot)`、`loaded(slot)`

**主な関数**

| 関数 | 中身 |
| --- | --- |
| `submit_text(text)` | コマンド入力と同じように文字列を渡す |
| `submit_intent(intent)` | 意図 `{verb, slots}` を直接渡す |
| `save_game(slot)`、`load_game(slot)`、`autosave()`、`list_saves()` | セーブとロード（`load_game` は await し、失敗すると理由の文字列） |
| `open_save_menu(mode)`、`open_log()` | セーブ・ロード画面、ログを開く |
| `switch_template(id, transition)` | テンプレートを切り替える（await） |
| `cycle_template()` | 登録したテンプレートを順に切り替える |
| `set_feature(key, on)` | 機能のオン・オフ |
| `set_text_option(key, value)` | `text_size`、`text_color`、`window_opacity` |
| `set_filters_enabled(on)` | フィルターのオン・オフ |
| `toggle_auto()`、`toggle_skip()` | オート送り、スキップ |
| `can_rewind()`、`rewind(steps)` | 巻き戻し |
| `jump_to_node(node)` | フローチャートの点から再開 |
| `current_cursor_kind()` | いまのカーソルの種類 |

**主なプロパティ**：`core`（状態とシナリオ。`core.state.get_var("money")` など）、`screen`（画面の部品）、`template`、`audio`、`settings`、`features`、`message_log`、`busy`（実行中か）。
