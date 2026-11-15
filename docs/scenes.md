# adv80sGD：シーンの作り方と目的別の準備

## シーンの種類

シーンは、チャプターのファイルの `scenes` に「シーンID → 中身」で書きます。中身の `kind` で種類が決まり、書かなければ `normal` です。特殊なシーンは、作るだけでは使われず、プロジェクト設定（`adv80s.project.json`）に入口を書いて初めて動きます。

| 目的 | kind | 入口（プロジェクト設定） | 終わったあと |
| --- | --- | --- | --- |
| 遊ぶ場面 | `normal` | `entry`（なければシナリオの `start`）、または他のシーンから `goto` | 自分で `goto` する |
| オープニング | `opening` | `opening` | シーンの `next`、なければタイトルか開始シーン |
| タイトル画面 | `title` | `title_screen`（シーンID。`"template"` なら標準のタイトル） | メニューで選んだもの |
| エンディング | `ending` | `endings`（一覧）。シーンへは他のシーンから `goto` | 「おわり」の画面 → `fin.then` |
| セーブ・ロード・設定・ログ | `system` | `system_scenes` | 開く前の状態に戻る |
| 呼んで戻る部品 | `sub` | なし（`call_scene` で呼ぶ） | 呼び出し元の続き |

- タイトル・オープニング・エンディング・システムのシーンでは、コマンドの一覧と入力欄を出しません。選べるのは選択肢（メニュー）だけです。
- どの種類でも、背景 `image`、曲 `bgm`、入るときの演出 `transition`、入ったときの手順 `enter`（初回だけなら `first`）は同じように書けます。
- 一つのシーンを、一つのファイルにすることもできます（ファイルのいちばん上に `"scene": "ID"` とシーンの項目を書く）。ただしシナリオエディタはチャプターのファイルにまとめる形を前提にしています。

## 通常シーン

遊ぶ場面は、「背景」「調べられるもの」「出口」「入ったときの手順」の四つで組み立てます。

```json
"scenes": {
  "hallway": {
    "name": "ろうか",
    "image": "hallway",
    "bgm": "theme1",
    "first": ["うすぐらい ろうかに いる。"],
    "enter": ["ろうかに もどってきた。"],
    "objects": {
      "door": {
        "names": ["ドア", "とびら"],
        "region": [120, 40, 80, 140],
        "on": {
          "LOOK": "ふるびた きの ドアだ。",
          "OPEN": { "if": "has(key)", "then": { "goto": "room" }, "else": "かぎが かかっている。" }
        }
      }
    },
    "exits": { "stairs": { "names": ["かいだん"] } }
  }
}
```

| 作るもの | 書くところ | コツ |
| --- | --- | --- |
| 背景 | `image`（素材ID。配列なら `when` に合うものを重ねる） | ドアが開いた絵などは、差分を重ねると絵を増やさずに済む |
| 入ったときの文 | `first`（初回）、`enter`（`first` があれば 2 回目から） | 初回は説明、二回目からは短く |
| 調べられるもの・人物 | `objects`（`names`、`region`、`on`、`when`、人物なら `character`） | `names` には遊ぶ人が打ちそうな呼び方を並べる |
| 動詞ごとの反応 | `on`（`"LOOK"`、`"USE+key"` のように使うものも指定できる） | シーン全体の `on` は対象のないコマンド用 |
| 出口 | `exits`（行き先のシーンID → 設定） | 移る前に何か起こすなら出口の `on.MOVE` に書き、最後に `goto` |
| 絵の上の部品 | `sprites`（条件に合うものを出し、合わなくなったら消す） | 物に `"sprite"` を書くと、絵の形どおりにクリックできる |
| 曲と演出 | `bgm`、`transition` | 同じ曲が鳴っていればそのまま続く |

会話が長くなるときは、シーンの中に書かず、チャプターの `dialogues` に会話IDを付けて書き、シーンからは `{"dialogue": "会話ID"}`（動詞の反応）や `{"call": "会話ID"}`（手順の中）で呼びます。何度も使う場面（店、実験など）は `kind: "sub"` のサブシーンにして、`{"call_scene": "shop", "args": {…}, "into": "変数"}` で呼ぶと、戻ってきて続きを進められます。

## オープニング

起動したら最初に流れる場面です。`kind: "opening"` のシーンを作り、プロジェクト設定の `opening` にその ID を書きます。

```json
"op": {
  "kind": "opening",
  "replay": "skippable",
  "next": "prologue",
  "bgm": "op_theme",
  "enter": [
    { "image.show": { "layer": "bg", "id": "town_night", "transition": "fade" } },
    "その よる、まちは しずまりかえっていた。",
    { "wait": { "seconds": 1 } }
  ]
}
```

**進み方**：手順を最後まで進め、選択肢もなければ終わりです。終わるとシーンの `next`、なければタイトル（`title_screen`）、それもなければ開始シーンへ進みます。

**2 回目からの流し方**（シーンの `replay`）：

| 値 | 動き | 向いているもの |
| --- | --- | --- |
| `always`（既定） | 毎回流す | 短いロゴや題名の出し方 |
| `once` | 流さずに `next` へ | 長い物語の導入 |
| `skippable` | 流すが Esc・右クリック・B で飛ばせる。Ctrl・F3 で早送り。右上に `opening_hint` の案内 | たいていはこれ |

**もう一度見る**：タイトルのメニューやエンディング一覧から見返せます（自作のタイトルなら `{"opening.play": {}}`）。見返せる条件はプロジェクト設定の `opening_replay`（`seen`（既定）・`always`・`never`・`any_ending`・`all_endings`・`{endings, seen, when}`）です。見返すときは始める前の状態で流し、いつでも飛ばせ、終わるとタイトルへ戻ります。

- タイトルの「はじめから」は始める前の状態に戻してから始めるので、オープニングの中で変えた変数は残りません。遊ぶのに要る値は、変数の初めの値（`variables` の `default`）で決めます。
- 動画を流すなら、手順に `{"video.play": {…}}` を書きます（動画は `.ogv`）。

## タイトル画面

作り方は二つあり、プロジェクト設定の `title_screen` で選びます。空（既定）ならタイトルなしで、開始シーンから始まります。

| | 標準のタイトル（`"template"`） | 自作のタイトルシーン（シーンID） |
| --- | --- | --- |
| 作るもの | 設定だけ | `kind: "title"` のシーン |
| 背景・曲・演出 | `title_image`、`title_bgm`、`title_transition` | シーンの `image`、`bgm`、`transition` |
| メニュー | `title_menu`（並べる項目）、`title_labels`（文言） | `menu` に `{label, do, when?, once?}` |
| 見たエンディングで変える | `title_variants` | シーンの `variants` |
| 向いているとき | まず動かしたいとき、機種を切り替えるとき | 配置や演出を自分で決めたいとき |

標準のタイトルのメニューは、既定で `new`・`continue`・`chapters`・`endings`・`opening`・`extras`・`settings`・`quit` です。使えないもの（セーブがないときの「つづきから」、見返せないときの「オープニング」など）は自動で隠れます。

自作のタイトルシーンの例：

```json
"title": {
  "kind": "title",
  "image": "title_bg",
  "bgm": "title",
  "menu": [
    { "label": "はじめから", "do": { "game.new": {} } },
    { "label": "つづきから", "do": { "game.continue": {} } },
    { "label": "オープニング", "when": "sys.opening_replay", "do": { "opening.play": {} } },
    { "label": "おまけ", "when": "sys.extras", "do": { "extras.open": {} } },
    { "label": "おわる", "do": { "game.quit": {} } }
  ],
  "variants": [
    { "when": "sys.all_endings", "image": "title_dawn", "bgm": "true_theme" }
  ]
}
```

- メニューで使う出力イベント：`game.new`（はじめから。始める前の状態に戻す）、`game.continue`（ロード画面）、`game.quit`、`endings.open`、`chapters.open`、`settings.open`、`opening.play`、`extras.open`。
- 選んだ項目の手順が終わると、またメニューが出ます。
- タイトルでは `sys.opening_replay`、`sys.extras`、`sys.endings_seen`、`sys.all_endings`、`sys.ending_<ID>` が読めます（全プレイ共通の記録から入る）。
- `title_screen` を書くと、システムメニューに「タイトルへ」が出ます。シナリオから戻すときは `{"game.title": {}}`。

## エンディング

エンディングは、「一覧に登録する」「シーンを作る」「そこへ goto する」の三つで準備します。

1. プロジェクト設定の `endings` に `[{id, label, hint?}]` を並べる。エンディング一覧では、見たものは `label`、見ていないものは「？？？」と `hint` が出る。
2. `kind: "ending"` のシーンを作り、`ending` に ID を書く。入ると、全プレイ共通の記録（セーブとは別）に「見た」が付く。
3. 分岐したところから `{"goto": "end_good"}` で移る。

```json
"end_good": {
  "kind": "ending",
  "ending": "good",
  "bgm": "ending",
  "enter": [
    "こうして じけんは かいけつした。",
    { "credits.roll": { "items": [ { "text": "スタッフ", "size": 24 }, "げんさく　なまえ" ], "speed": 30 } }
  ],
  "fin": { "text": "おわり", "advance": ["click", "key"], "then": "title" }
}
```

**「おわり」の画面**：エンディングのシーンを最後まで進め、選択肢も移動もなければ出ます。設定はプロジェクト設定の `fin` → シーンの `fin` → `fin.show` の引数の順に重なります（共通の見た目はプロジェクト設定に、エンディングごとの違いだけシーンに）。

| 項目 | 内容 |
| --- | --- |
| `advance` | 閉じる条件：`"click"`、`"key"`、`"key:Enter"`、秒数、`"trigger:名前"` |
| `min_time` | この秒数まではキーで閉じない（既定 1.0。押しっぱなしで飛ばさないため） |
| `then` | 閉じたあと：`title`（既定）・`new`・`quit`・`stay`・シーンID（`reset: true` で始める前の状態から） |
| `save_prompt` | 閉じたあとクリアデータをセーブさせる。引き継ぐものは `save_carry`、ロードしたときの行き先は `save_resume` |
| `false` | 「おわり」を出さない |

- エンディングのシーンの中で選択肢や `goto` を書くと、「おわり」は出ません。「おわり」のあとに続けたい場面は `then` に書きます。
- 見たエンディングの数は、タイトルの `variants` やおまけの `when`（`sys.endings_seen`、`sys.all_endings`）に使えます。

## システムシーン

セーブ・ロード・設定・ログの画面は標準のものがあり、プロジェクト設定の `system_scenes` で差し替えられます。値は JSON のシステムシーン（`kind: "system"`）の ID か、Godot の `.tscn` のパスです。

```json
"system_scenes": { "save": "sys_save", "load": "sys_save", "settings": "res://game/ui/settings.tscn" }
```

JSON のセーブ画面の例（セーブとロードで同じシーンを使う）：

```json
"sys_save": {
  "kind": "system",
  "enter": [
    { "if": "sys.mode == \"load\"", "then": "どこから よみこむ？", "else": "どこに セーブする？" }
  ],
  "menu": [
    { "label": "01：[if=sys.slot_01_exists]{sys.slot_01}[else]（からっぽ）[/if]",
      "do": { "if": "sys.mode == \"load\"",
              "then": { "system.load": { "slot": "01" } },
              "else": { "system.save": { "slot": "01" } } } },
    { "label": "もどる", "do": { "system.close": {} } }
  ]
}
```

| 使うもの | 内容 |
| --- | --- |
| `sys.mode` | `save`・`load`・`settings`・`log` |
| `sys.slot_count`、`sys.slot_<枠>`、`sys.slot_<枠>_exists`、`sys.slot_<枠>_label` | 枠の数、説明（日時とシーン名）、セーブがあるか、枠の名前。枠は `01`、`quick`、`auto1` など |
| `sys.<設定のキー>`、`sys.feature_<キー>` | `text_speed`、`bgm_volume` などと、モダン機能の入・切 |
| `system.save {slot}`、`system.load {slot}` | 開く前の状態をセーブ、閉じてからロード |
| `system.close` | 閉じる（Esc・右クリックでも閉じる） |
| `settings.set {key, value}` | 設定を変える（`features.<キー>` でモダン機能） |

**JSON と .tscn の選び方**：文字とメニューだけで済むなら JSON、スライダーや自由な配置が要るなら `.tscn` です。`.tscn` は、一番上のノードに `AdvSystemScreen` を継いだスクリプトを付け、`_on_opened()` で中身を作り、`slots()`・`save(slot)`・`load_slot(slot)`・`get_setting`・`set_setting`・`log_entries()`・`close()` を使います（詳しくは[オリジナルの部品を使うときのノウハウ集](custom-components.md)）。

- JSON のシステムシーンは、開くといまの状態を取っておき、閉じると戻します。中で変えた変数やログは残りません。
- 中ではオートセーブ・到達点・既読・巻き戻しの記録をしません。
- 文章の表示の途中など、実行中に開こうとすると標準の画面が出ます。

## つまずきやすいところ

| 起きること | わけ | どうするか |
| --- | --- | --- |
| 作ったオープニング・タイトルが出ない | プロジェクト設定に入口を書いていない | `opening`、`title_screen` にシーンID を書く |
| エンディング一覧に出ない、確認で `ENDING_UNKNOWN` | シーンの `ending` がないか、`endings` にない ID | 両方に同じ ID を書く |
| 「おわり」が出ない | エンディングの中に選択肢や `goto` がある、`fin: false` | 続きは `fin.then` に書く |
| オープニングが二度目から出ない | `replay: "once"` | 飛ばせるようにするなら `skippable` |
| タイトルでコマンドが出ない | 特殊なシーンでは選択肢だけを受け付ける | 動作は `menu` に書く |
| システムシーンで変えた値が消える | 閉じると開く前の状態に戻る | 残すものは `settings.set` かセーブで |
| 自作のセーブ画面でなく標準の画面が出る | 文章の表示の途中などで開こうとした、または `.tscn` の一番上が `closed` を持たない | 入力を待っているときに開く。`AdvSystemScreen` を継ぐ |
| サブシーンから戻らない | サブシーンの中で `goto` した | 戻るときは `{"return": 値}` |
| タイトルの絵や曲が変わらない | `variants` は後ろほど優先、記録は全プレイ共通 | 条件の厳しいものを後ろに置く。デバッグではコンソールの `endings clear` で記録を消して試す |

一つの場面だけを試したいときは、シナリオエディタの「▶ このシーンから実行」で、タイトルとオープニングを飛ばしてすぐ動かせます。
