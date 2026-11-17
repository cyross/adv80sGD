# adv80sGD：オリジナルの部品を使うときのノウハウ集

## はじめに

adv80sGD の標準の部品は、プロジェクト設定（adv80s.project.json）やテンプレートに一行書くだけで、自分で作ったものに差し替えられます。フレームワークの中のファイルを書き換える必要はありません。書き換えると更新のたびに消えるので、差し替えはいつも「設定で指す」形にします。

| 差し替えたい部品 | 入口（どこに書くか） | 自作のものの形 | 節 |
| --- | --- | --- | --- |
| セーブ・ロード・設定・ログの画面 | `system_scenes` | Godot のシーン（.tscn）か、JSON のシステムシーン | システム画面 |
| タイトル画面 | `title_screen` | タイトルのシーン ID（JSON） | タイトル・おわり |
| 「おわり」の画面 | `fin` | 文と見た目の設定 | タイトル・おわり |
| 画面の見た目（機種） | `template`・`templates` | `res://game/templates/<ID>/template.json` | テンプレート |
| フィルター・切り替え演出・画面効果 | `effects` | `*.effect.json`＋シェーダー | シナリオと演出 |
| コマンド入力の読み方 | `inputs.parser_profile` | `static func parse(text, core)` を持つスクリプト | 入力 |
| 動詞・言葉 | `verbs`・`dictionaries`・`intent_schema` | 動詞の名前、辞書・意図のファイル | 入力 |
| 作者だけが使う設定 | `ext`、テンプレート・効果の `x.名前` | 中身は自由 | つまずき |

このノウハウ集は、段階67までの作りと、小さい画面（GB・FC）での見直しで分かったことをもとにしています。

## システム画面を自分で作る

セーブ・ロード・設定・ログの画面は、`system_scenes` に画面ごとの差し替え先を書けば入れ替わります。書かない画面は標準のままです。

```json
"system_scenes": {
  "save": "res://game/ui/my_save.tscn",
  "load": "res://game/ui/my_save.tscn",
  "settings": "sys_settings"
}
```

値の書き方で、作り方が二つに分かれます。

| 書き方 | 作り方 | 向いているとき |
| --- | --- | --- |
| `.tscn`・`.scn` で終わるパス | Godot のシーン。一番上のノードに `AdvSystemScreen` を継いだスクリプト | アニメーションや独自の部品を使いたい、自由に組みたい |
| それ以外（シーン ID） | シナリオと同じ JSON のシステムシーン | ゲームの画面の中で、コマンド選びなどいつもの演出で見せたい |

### Godot のシーンで作る

一番上のノードは Control で、`closed` シグナルを持たせます。`AdvSystemScreen` を継ぐと、どちらも満たします。満たさないと警告を出して標準の画面に戻ります。

```gdscript
extends AdvSystemScreen

func _on_opened() -> void:
    for s in slots():            # [{slot, label, exists, info}]
        _add_slot_button(s)

func _on_slot_pressed(slot: String) -> void:
    if mode == "save":
        save(slot)               # セーブして閉じる
    else:
        load_slot(slot)          # 閉じてからロード
```

- 開くと `player`（AdvPlayer）と `mode`（save・load・settings・log）が入り、`_on_opened()` が呼ばれます。一つのシーンをセーブとロードで使い回すときは `mode` で分けます。
- 使える助け：`slots()`・`save(slot)`・`load_slot(slot)`・`get_setting(key, 既定)`・`set_setting(key, 値)`・`log_entries()`・`close()`。
- 設定のキーは text_speed・bgm_volume・se_volume・voice_volume・filters など。`set_setting` はその場で画面にも当てます。
- Esc・右クリックで閉じるのは土台がします。自分で `_gui_input` を書くときは、右クリックを食べないようにします。

### JSON のシステムシーンで作る

シナリオのシーンと同じ書き方で作り、その ID を書きます。開く前の状態を取っておき、閉じるとそこへ戻すので、システムシーンの中で変えた変数は捨てられます。

- 読める値：`sys.mode`、`sys.slot_count`、`sys.slot_<枠>`（説明）、`sys.slot_<枠>_exists`、`sys.slot_<枠>_label`、`sys.<設定のキー>`。
- ゲームのシーンを実行している途中は開けません。そのときは標準の画面が出ます。
- コマンドの一覧で選ばせるとき、長い項目は窓の幅で「…」と切れます。小さい画面では「01：第3章」のように頭を短くします。

## タイトル・おわり・クレジット

タイトル画面は、まず設定で変えて、足りないときだけ自分のシーンにします。標準のタイトル画面は段階65から、小さい画面でも題名とメニューを自動で収めます。自分で作ると、その整えは自分の受け持ちになります。

| やりたいこと | 書くところ |
| --- | --- |
| メニューの項目と順番 | `title_menu`（new・continue・chapters・endings・opening・extras・settings・quit） |
| メニューの文言 | `title_labels`（項目 → 文）、テンプレートの `title.labels` |
| 背景・BGM・切り替え | `title_image`・`title_bgm`・`title_transition` |
| クリア後などで画面を変える | `title_variants`（`when` に合うものを順に重ねる。`sys.endings_seen`・`sys.ending_<ID>`・`sys.all_endings` が使える） |
| 題名・メニューの位置と色 | テンプレートの `title`（title_y・title_size・title_pal・menu_y・show_title・fill） |
| 画面そのものを自分で作る | `title_screen` にタイトルのシーン ID（空ならタイトルなし、`"template"` なら標準） |

自分のタイトルのシーンは JSON のシーンなので、絵・文・コマンド選びといったいつもの演出で組めます。その中では `sys.endings_seen`、`sys.opening_replay`（オープニングをもう一度見られるか）、`sys.extras`（おまけを開けるか）で、出す項目を切り替えられます。

「おわり」の画面は `fin` で変えます。`false` で出さず、設定では文（text）・色（pal・fill）・絵（image）・閉じる条件（advance：click・key・秒数・trigger:名前）・閉じたあと（then：title・new・quit・stay・シーン ID）を決められます。絵ごと差し替えたいときは、then に自分のシーン ID を書き、そこでふつうの演出として見せるのが近道です。

クレジットも、ふつうは定められた形（items の並び）に書くだけです。下から上へ流れるので、一行が画面の幅を超えないようにします。小さい画面では、名前と仕事を二行に分けます。

## 見た目をテンプレートで作る

自分の見た目は、いちから書かず、近い標準のテンプレートを `extends` で受け継いで、変えるところだけ書きます。テンプレートは `res://game/templates/<ID>/template.json` に置き、プロジェクト設定の `template` にその ID を書きます。game の方が先に探されるので、標準と同じ ID にすると標準を上書きできます。ただし取り違えやすいので、別の ID を勧めます。

```json
{
  "template_version": 1,
  "id": "my98",
  "name": "自作 98",
  "extends": "pc98_classic",
  "text": { "color": 7, "name_color": 6 },
  "ui": { "window_skin": { "type": "box", "border": 1, "pal": 7, "fill": 1 } }
}
```

| 変えたいこと | 書くところ | コツ |
| --- | --- | --- |
| 画面の大きさ・機種の色数 | `display.preset`（機種 ID か 機種 ID.モード名）、`display.scale` | 大きさは自分で数えず、プリセットを選ぶ。上下を隠す機種（FC など）もプリセットが持っている |
| 色 | `palette`（source：preset か colors） | 番号で指す。パレットの外の番号は白になる |
| 文字の色・速さ・ルビ | `text`（color・name_color・speed・ruby） | 窓の地の色と明るさを離す |
| 窓の枠と地 | `ui.window_skin`（box：色の枠、nine_patch：9分割の画像） | 画像の窓でも `fill` を書く（メニュー・ログ・セーブの地に使う） |
| 絵・文・コマンドの窓の場所 | `layout.regions`（rect：[x, y, 幅, 高さ]、元の解像度のピクセル） | 見える範囲の中に置く |
| フォント | `fonts`（main・readable。候補の配列で書くと、見つかった最初のもの） | 画面の解像度に合うドット字を先に書く |
| 自分だけの値 | `ext`、または `x.名前` | フレームワークは読まないので、自分のスクリプトから読む |

受け継ぐと、書かなかった値は親のものが使われます。これが落とし穴になることがあります。GB のテンプレートは 98 を受け継いでいて、窓の地の色 0 まで受け継いだため、文字と同じ色になってメニューが読めませんでした（段階63で、近すぎるときは見分けやすい色に切り替わるようにしました）。親と色数や文字の色を変えたときは、`window_skin.fill` も書き直します。

## 入力の差し替え：パーサー・動詞・辞書

入力は、使う方式を選ぶところと、文を意図に変えるところに分かれています。まずは設定だけで済むかを確かめ、足りないときにパーサーのスクリプトを書きます。

| 変えたいこと | 書くところ | コツ |
| --- | --- | --- |
| 使う入力方式 | `inputs.enabled`（select・parser・icon・click・verb_click・verb_cursor・context） | 要らない方式は外す。外した方式の画面部品は出ない |
| コマンドの言葉 | `verbs` | 短い言葉にする。長いと小さい画面で「…」になる |
| 言い換え・同じ意味の語 | `dictionaries` | パーサーを書く前に、まず辞書で足りるか試す |
| 意図の形 | `intent_schema`（entry と layers [{file, when}]） | when で場面ごとに層を足す |
| 文の読み方そのもの | `inputs.parser_profile`（ja / en / free、またはスクリプトのパス） | 標準で足りないときだけスクリプトにする |

パーサーを自分で書くときは、`parse` という関数を一つ持つスクリプトを作り、そのパスを `parser_profile` に書きます。static でも、インスタンスの関数でも動きます。

```gdscript
# res://game/parser/my_parser.gd
extends RefCounted

static func parse(text: String, core: AdvCore) -> Dictionary:
	var t := text.strip_edges()
	if t == "":
		return {"reply": "なにをしますか？", "code": "empty"}
	var words := t.split(" ", false)
	if words.size() >= 2:
		return {"intent": {"verb": words[1], "object": words[0]}}
	return {"reply": "わかりません。", "code": "unknown"}
```

- 分かったときは `{"intent": …}` を返します。中身の形は intent_schema に合わせます。
- 分からなかったときは `{"reply": …, "code": …}` を返します。reply がそのまま画面に出ます。code はテストやログで見分けるのに使います。
- `core` からフラグや変数を読めます。パーサーの中で書き換えるのは避け、変更はシナリオ側に任せます。

## シナリオと演出：効果・Ink・自分だけの値

自分のフィルターや場面転換は、`*.effect.json` を一つ書いて、プロジェクト設定の `effects` にパスを並べます。シェーダーだけで済むものは shader、動きを伴うものは handler（GDScript）を書きます。

```json
{
  "id": "my_scanline",
  "kind": "filter",
  "name": "自作走査線",
  "shader": "my_scanline.gdshader",
  "params": {
    "strength": { "type": "float", "default": 0.4, "min": 0.0, "max": 1.0, "label": "濃さ" },
    "tint": { "type": "color", "default": "#000000" }
  },
  "era": "80s",
  "x.note": "自分だけのメモ"
}
```

| 項目 | 中身 | コツ |
| --- | --- | --- |
| `kind` | filter（画面全体に掛け続ける）・transition（場面転換）・effect（一度きりの演出） | 迷ったら、終わりがあるかで分ける |
| `shader` | シェーダーのパス | json からの相対パス。同じフォルダに置くと迷わない |
| `handler` | GDScript のパス | シェーダーで書けない動きだけこちらに書く |
| `params` | type（float・int・bool・color・vec2・enum・texture・string）、default、min・max、values、label、description | default を必ず書く。label と description はエディタに出る |
| `duration` | 長さ | transition と effect で使う |
| `era`、`ext`、`x.名前` | 分類と自分だけの値 | フレームワークは読まない |

シナリオを Ink で書きたいときは、Ink で書き出した `.ink.json` をシナリオとして並べるだけで、取り込み口が読みます。自分で読み込み口を作る前に、こちらで足りるか確かめます。

プロジェクト、テンプレート、効果には、自分だけの値を置く場所（`ext` と `x.名前`）があります。フレームワークはここを読まず、検査でも弾きません。新しいキーを勝手に生やすと、将来の版で同じ名前が使われたときにぶつかります。自分の値は必ずこの二つに入れます。

## 画面の大きさ・見える範囲・色

標準の画面は、小さい画面や色数の少ない機種でも崩れないように調べてあります。自分の画面を作るときは、その工夫を自分でも入れます。自作の AdvSystemScreen は、フレームワークが位置や色を直しません。

### 見える範囲の中に置く

- 画面の大きさと、実際に見える範囲は同じとは限りません。FC は上下 8 ピクセルが隠れます。
- 位置を決めるときは `AdvTemplate.visible_rect()` を使い、その内側に置きます。通知もこの範囲に置かれ、幅は「見える幅 − 余白×2」で折り返します。
- 数字で位置を書くときは、一番小さい機種に合わせるか、機種ごとにテンプレートを分けます。

### 文字が収まらないとき

- 標準のコマンドボタンと AdvMenuPanel のボタンは、入りきらない文字を「…」で切り、全文をツールチップに出します。自作のボタンでも同じようにすると、使う人が迷いません。
- 項目が多いメニューは、AdvMenuPanel の follow_focus で選んだ項目に捲ります。タイトルのメニューは文字を小さくして収め、それでもあふれるときは▲▼で続きがあることを示します。
- 一番効くのは、言葉を短くすることです。

### 文字と地の色

- 窓の地の色が文字の色と明るさで近すぎる（差が 0.3 未満）とき、`window_fill_color()` はパレットの中から一番見分けやすい色を選びます。パレットがなければ黒か白です。
- 自作の画面でも地の色はこの関数から取り、文字は `text.color` を使うと、テンプレートを切り替えても読めます。ログも `text.color` で描いています。
- 色を数字（例：白固定）で書くと、白い地の機種で消えます。

### デバッグの通知

デバッグの通知は `debug.notice_style.layer` で描く場所を選べます。screen（ゲームの画面の中に描く）・window（ゲームの画面の外、ウィンドウの大きさの層に、デバッグのボタンの下から並べる。幅は 480 まで）・auto（書かなければこれ。見える範囲の幅が 320 より狭いと window、それ以外は screen）の三つです。GB のような小さい画面では window になり、ゲームの画面を覆わずに読めます。

## 録画の書き出しを足す

録画は、本体では AVI（MJPEG）だけを書きます。MP4 などを OS のエンコーダーで直接書きたいときは、`AdvVideoEncoder` を継いだ書き出しを作って登録します。C++ の GDExtension で OS の機能を呼ぶものを、`addons/adv80s` の外（たとえば `addons/my_mp4/`）に置きます。Windows の Media Foundation を使う `addons/adv80s_mp4`（中身の C++ は `native/adv80s_mp4`）が、そのまま見本になります。

```gdscript
# res://game/capture/my_mp4_encoder.gd
class_name MyMp4Encoder
extends AdvVideoEncoder

func extension() -> String:
	return "mp4"

func is_available() -> bool:
	return OS.get_name() in ["Windows", "macOS"]   # 使えない環境では false（AVI になる）

func open(path: String, width: int, height: int, fps: int, audio_rate: int) -> Error:
	return OK   # ここでファイルを開く

func add_video(img: Image) -> void:
	pass        # RGB8 の 1 コマ

func repeat_video() -> void:
	pass        # 前のコマをもう一度

func add_audio(samples: PackedVector2Array) -> void:
	pass        # 左右の組（-1〜1）

func close() -> Dictionary:
	return {"path": "", "frames": 0}
```

ゲームの始めに登録し、プロジェクト設定で `"recording": {"options": {"format": "mp4"}}` にします。

```gdscript
AdvCapture.register_encoder("mp4", func(): return MyMp4Encoder.new())
```

- open から close まで、どれも録画のスレッドから順に呼ばれます。画面の部品にはさわらないでください。
- `options`（モダン機能 recording の options）が open の前に入っています。`quality` などを読めます。
- 登録した書き出しがあれば、ffmpeg で変えるより先に使われます。`is_available()` が false なら使われません。

## 確かめ方

自分の部品を入れたら、全部のテンプレートで画面を並べて見ます。一つの機種で大丈夫でも、別の機種で崩れることがよくあります。

```text
godot --path . --script res://tests/run_ui_tests.gd -- /tmp/shots --review
```

- `/tmp/shots/index.html` に、テンプレートごと・画面ごとの写真（`review_t_<テンプレート>_<画面>.png`）が並びます。
- 問題がある画面は赤い枠で囲まれます。文字がはみ出している（_overflowing）か、文字と地の色が近すぎる（_low_contrast）かを調べています。
- 赤い枠がなくても、小さい画面（GB）、上下が隠れる画面（FC）、色数の少ない画面は目でも確かめます。自動の検査は「読めるか」までは分かりません。

動かしながら確かめるときは、デバッグの通知を使います。コンソールの `noticestyle` で、通知の描き方をその場で切り替えられます。自作の画面が開かず標準の画面が出たときは、警告が出ていないかをまず見ます。

フレームワーク自体のテスト（`run_tests.gd` と `run_editor_tests.gd`）も、自分の部品を入れたあとに一度回しておくと安心です。

## つまずきやすいところ

| 起きること | わけ | どうするか |
| --- | --- | --- |
| 更新したら自分の変更が消えた | `addons/adv80s` の中を直接書き換えた | 自分のものは `res://game/` に置き、設定から指す |
| 自作の画面でなく標準の画面が出る | .tscn の一番上が Control でないか、`closed` シグナルがない（警告を出して標準に戻る） | AdvSystemScreen を継ぐ。警告を見る |
| JSON のシステム場面が開かない | 演出の途中（busy）は開けない | 演出が終わってから開く |
| システム場面で変えた変数が戻っている | 閉じると開く前の状態に戻る | 残したいものは設定（set_setting）やセーブで残す |
| ボタンが「…」になる | 言葉が幅に入らない | 言葉を短くする。全文はツールチップで確かめられる |
| GB で文字が読めない | 地の色を親から受け継いだ。自作の画面で色を数字で書いた | `window_skin.fill` を書く。`window_fill_color()` と `text.color` を使う |
| FC で見出しが切れる | 上下 8 ピクセルが隠れる | `visible_rect()` の内側に置く |
| 自作の画面だけ崩れる | 自作の画面はフレームワークが直さない | 「画面の大きさ・見える範囲・色」の工夫を自分で入れ、`--review` で見る |
| コミットに .uid が入っていない | .uid は Godot で開いたときに作られる | 新しいスクリプトを足したら、一度 Godot で開いてからコミットする |
| 自分のキーが将来の版とぶつかる | 勝手にキーを生やした | `ext` か `x.名前` に入れる |

最後に、文章や画面で機種の名前を出すときは、PC-98・FC・GB のような略称で書きます。フレームワークの標準のテンプレートも略称で揃えています。
