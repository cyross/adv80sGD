# adv80sGD 新しいゲームの作り方

最終更新：2026-11-02

## はじめに

Godot の空のプロジェクトにアドオン `adv80s` を入れ、設定ファイル1つ、素材フォルダ1つ、シナリオ1つ、シーン1つを用意すれば、新しいゲームが動きます。この手順書は、その最小の形から始めて、遊べるところまでを順に説明します。

この手順書では、次の配置を例にします（`game/` の名前は自由です）。サンプルの完成形は、リポジトリの `tests/stage1/` と `adv80s.project.json` にあります。

```
res://
├─ addons/adv80s/          アドオン（そのままコピー）
├─ adv80s.project.json     プロジェクト設定
├─ master.key              セーブの鍵（Git に入れない）
└─ game/
   ├─ main.tscn            メインシーン
   ├─ scenario/
   │  ├─ main/                シナリオ（シナリオエディタの形）
   │  │  ├─ _scenario.scenario.json  シナリオ共通の設定
   │  │  ├─ chapter1.scenario.json   チャプター（シーンと会話）
   │  │  └─ ink/                     Ink のセリフ（使うときだけ）
   │  ├─ src/talk.ink         Ink の元のファイル（使うときだけ）
   │  └─ talk.ink.json        Ink を変換したもの
   └─ assets/              素材フォルダ
      ├─ manifest.json        手書きのマニフェスト
      ├─ manifest.auto.json   自動生成のマニフェスト
      ├─ bg/  chara/  sprite/  ui/
      ├─ bgm/  se/  voice/
      ├─ font/  movie/
```

## 必要なもの

ゲームに入るのは Godot とアドオンだけです。そのほかの道具は制作のときだけ使います。

| もの | 必要か | 使いどころ | 入手先 |
| --- | --- | --- | --- |
| Godot 4.7（標準版、GDScript） | 必須 | エディタと実行 | [godotengine.org](https://godotengine.org/) |
| アドオン `addons/adv80s` | 必須 | ゲームの仕組み一式。標準のフォント（PixelMplus10・12、Tekuplus）とカーソル画像も入っている | adv80sGD リポジトリ |
| DotGothic16（OFL-1.1） | 任意 | 98 クラシックの 16 ドットの字。なければ PixelMplus12 を使う | [DotGothic16](https://github.com/fontworks-fonts/DotGothic16) |
| inklecate | Ink を使うとき | `.ink` を `.ink.json` に変換する | [ink のリリース](https://github.com/inkle/ink/releases) |
| ffmpeg など | 動画を使うとき | 動画を `.ogv`（Ogg Theora）に変換する | [ffmpeg.org](https://ffmpeg.org/) |
| VS Code | 任意 | JSON をスキーマ付きで書く（入力の候補と確認） | [code.visualstudio.com](https://code.visualstudio.com/) |

DotGothic16 はアドオンに同梱していません。使うときは `DotGothic16-Regular.ttf` を入手し、素材フォルダの `font/dot16.ttf` として置きます。配布するゲームに入れるときは、OFL のライセンス文も一緒に入れてください。

## 手順1 プロジェクトを作ってアドオンを入れる

空のプロジェクトにアドオンをコピーし、プラグインを有効にします。

1. Godot のプロジェクトマネージャーで新しいプロジェクトを作る。レンダラーは「互換性」（Compatibility）を選ぶ。
2. adv80sGD の `addons/adv80s` フォルダを、フォルダごと新しいプロジェクトの `addons/` にコピーする。
3. エディタを開き、「プロジェクト → プロジェクト設定 → プラグイン」で adv80s を有効にする。画面の上の切り替え（2D、3D、Script の並び）に「adv80s」が出れば成功。
4. 「プロジェクト設定 → 一般 → ディスプレイ → ウィンドウ」を次のようにする（98 の 640x400 の例）。
    - ビューポートの幅・高さ：640、400（使うテンプレートの解像度に合わせる）
    - ストレッチ → モード：`canvas_items`、アスペクト：`keep`、拡大方式：`integer`
    - 走査線などのフィルターは実際の画面の解像度で描くので、`canvas_items` にするときれいに出ます。
5. Git を使うなら、`.gitignore` に `master.key` を足す（手順9 で作るセーブの鍵です）。

## 手順2 プロジェクト設定 adv80s.project.json を作る

**いちばん早い方法：セットアップ画面を使う。** アドオンを有効にして、エディタの上の「adv80s」画面を開くと、プロジェクト設定がまだないときは「セットアップ」が出ます（種類の一覧から「セットアップ」を選んでも出せます）。次の5つを決めて「作成する」を押すと、プロジェクト設定、素材フォルダ（手順4）、最初のシナリオ（手順5）、メインシーン（手順7）までがまとめて作られ、F5 ですぐに実行できます。

| 項目 | 決めること |
| --- | --- |
| タイトル | ゲームの名前（ウィンドウのタイトルにも使います） |
| ゲームID | ほかのゲームと重ならない名前（英小文字で始まる英小文字・数字・`_`）。セーブデータの見分けに使います |
| 画面テンプレート | 機種のテンプレート（手順3。あとから変えられます） |
| コマンド方式 | テンプレートのまま、コマンド選択、コマンド入力、選択＋入力、動詞リスト＋クリック、アイコン切り替え、コンテキスト |
| 入力デバイス | キーボード、マウス、ゲームパッド、タッチから、使うものを選びます |

すでにあるファイルは上書きしません。プロジェクト設定は上の項目だけを書き換えるので、あとからコマンド方式や入力デバイスを変えるときにも使えます。以下の手順2〜7は、セットアップ画面が作るものの中身と、手で作る場合の説明です。

プロジェクトの直下に `adv80s.project.json` を置きます。エディタの「adv80s」画面で「プロジェクト設定」を開くと、フォームで作れます（テンプレートやシナリオは一覧から選べます）。手で書く場合の最小の形は次のとおりです。

```json
{
  "project_version": 1,
  "template": "pc98_classic",
  "scenarios": ["res://game/scenario/main.scenario.json"],
  "asset_roots": ["res://game/assets"],
  "lang": "ja"
}
```

| 項目 | 中身 |
| --- | --- |
| `template` | 最初に使うテンプレート（機種）の ID（手順3） |
| `templates` | 遊ぶ人が切り替えられるテンプレート（旧表示と新表示など） |
| `scenarios` | シナリオのファイル。`*.scenario.json` と `*.ink.json` を並べられる。最初のものから始まる |
| `asset_roots` | 素材フォルダ。後ろに書いたものほど優先 |
| `missing_asset` | 素材がないとき `placeholder`（代わりの表示）か `error` |
| `features` | ヒント、目的、手帳、フローチャート、巻き戻しなどの現代的な機能を、使えるか（`allow`）と最初から入れるか（`default`） |
| `verbs` | 辞書の拡張の動詞を使う（`GIVE`、`THINK` など） |
| `variables`、`constants` | 全シナリオで共通の変数と定数 |
| `effects`、`transitions` | 自作のフィルター・演出と、名前付きの切り替え演出 |
| `save` | セーブの保護（`hmac`、`hmac_aes`、`none`）、スロットの数、保存先など |

全部の項目は、リポジトリの `adv80s.project.json`（サンプル用の設定）、[リファレンスマニュアル](reference.md)、仕様書にあります。

## 手順3 テンプレート（機種）を選ぶ・自分用に作る

まず同梱の 26 機種のテンプレートから選び、見た目を変えたいときだけ自分用のテンプレートを作ります。テンプレートは、解像度と色、画面の区割り、フォント、窓の枠、入力の方法、マウスカーソルを決めます。

| 時代 | テンプレート ID | 画面の形 |
| --- | --- | --- |
| 80年代パソコン | `pc98_classic`、`pc88_classic`、`sx1_classic`、`sx1t_classic`、`sx1tz_classic`、`f7_classic`、`f77a_classic`、`mx_classic`、`mx2_classic`、`m2p_classic` | 絵の下に文章とコマンド、入力欄あり（MX 系はコマンド選択だけ） |
| 90年代パソコン | `x68k_classic`、`ftns_classic`、`mtr_classic`、`vga_classic`、`win_classic` | 同上。マウスカーソルの絵あり |
| 家庭用ゲーム機 | `fc_classic`、`pce_classic`、`sfc_classic`、`ps1_classic`、`ps2_classic` | 絵の右にコマンド、下に文章。コマンド選択だけ |
| 携帯機 | `gb_classic`、`gbc_classic`、`gba_classic` | 同上 |
| 現代 | `hd_modern`、`fhd_modern`、`4k_modern` | 絵の下に文章とコマンド、入力欄あり |

**自分用のテンプレートを作るとき**

1. 「adv80s」画面で「テンプレート」を選び、「新規…」を押す。
2. ID と元にするテンプレート（`extends`）を選ぶと、`res://game/templates/<ID>/template.json` ができ、プロジェクト設定の `templates` に加わる。
3. 変えたい項目だけを書く。書いていない項目には「継承：値」と元の値が出るので、＋で足して上書きする。
4. アドオンの中のテンプレートは読むだけです。直接は直さず、必ず extends して使う。

サンプルの絵は 640x400 用です。ほかの機種でも遊ぶなら、機種ごとの絵を素材フォルダの `presets/<機種ID>/bg/…` に置きます（同じ名前の素材が、その機種のときだけ差し替わります）。

## 手順4 素材フォルダとマニフェスト

素材は種類ごとのフォルダに置くだけで、ファイル名がそのまま素材 ID になります。エディタが `manifest.auto.json` を自動で書き出すので、それも一緒にコミットします。

| フォルダ | 種類 | 形式 |
| --- | --- | --- |
| `bg/`、`chara/`、`cg/`、`ui/`、`sprite/` | 画像 | PNG、JPG、WebP、GIF、APNG、MNG、MAG など |
| `bgm/`、`se/`、`voice/` | 音 | WAV、OGG、MP3 |
| `font/` | フォント | TTF、OTF |
| `movie/` | 動画 | OGV（Ogg Theora）だけ |
| `shader/` | シェーダー | gdshader |

- **ID の決まり**：`bg/hallway.png` は画像 ID `hallway`。ファイル名は英小文字、数字、`_` にする。
- **差分**：`chara/ayumi@smile.png` は `ayumi` の差分 `smile`（シナリオでは `variant` で選ぶ）。
- **機種ごとの差し替え**：`presets/88/bg/hallway.png` のように置くと、88 のときだけそちらを使う。
- **手書きのマニフェスト**：ファイル名だけでは決まらないことを `manifest.json` に書く。「adv80s」画面の「マニフェスト」の「素材ファイルから追加…」で項目を足せる。

```json
{
  "manifest_version": 1,
  "assets": {
    "theme":   { "type": "bgm", "loop_start": 9.6, "volume": 0.8 },
    "lamp":    { "type": "image", "color_key": "#000000" },
    "sparkle": { "type": "image", "grid": [3, 1],
                 "anims": { "default": { "frames": [0, 1, 2, 1], "fps": 6, "loop": true } } }
  }
}
```

`loop_start` は BGM を繰り返すときの戻り先（秒）、`color_key` は透明にする色、`grid` と `anims` はスプライトシートの切り方とアニメーションです。

## 手順5 シナリオを書く（JSON、Ink）

**シナリオエディタで書く。** 「adv80s」画面の種類から「シナリオエディタ」を選ぶと、シナリオ → チャプター → シーンのカードを開いていって書けます（ダブルクリックで開く、右クリックで名前の変更・複写・削除、上のパンくずで戻る）。シーンを開くと、右に「セリフ」（会話。JSON か Ink）と「コマンド」（入ったときの手順と、動詞ごとの反応）の一覧が出ます。「コマンドを作成」で、対象（シーン・もの・出口）と動詞を選び、「＋ 手順を追加」から地の文・台詞・条件分岐・選択肢などを足します。条件は「式…」で式エディタを開くと、変数やシーンの名前の候補が出ます。エディタが書くのは下と同じ JSON のファイルなので、VS Code で直接書いても構いません。

ゲームの骨組み（シーン、物、出口、アイテム）は JSON で書き、長い会話や分岐の多い場面だけ Ink で書くのがおすすめです。JSON だけでも作れます。

**JSON のシナリオ（`*.scenario.json`）の最小の形**

```json
{
  "start": "hallway",
  "variables": { "got_key": { "type": "bool", "default": false } },
  "items": {
    "key": { "name": "かぎ", "names": ["鍵", "key"], "on": { "LOOK": "ふるびた かぎだ。" } }
  },
  "scenes": {
    "hallway": {
      "name": "ろうか",
      "image": "hallway",
      "first": [{ "bgm.play": { "id": "theme" } }, "うすぐらい ろうかに いる。"],
      "enter": "ろうかに もどってきた。",
      "objects": {
        "plant": {
          "names": ["うえきばち", "植木鉢", "pot"],
          "region": [60, 130, 50, 110],
          "on": {
            "LOOK": "かれかけた うえきばちだ。",
            "EXAMINE": { "if": "got_key", "then": "もう なにも ない。",
                         "else": ["かぎを みつけた！", { "set": { "got_key": true } }, { "item.add": { "id": "key" } }] }
          }
        }
      },
      "exits": { "room": { "names": ["へや", "room"] } }
    },
    "room": { "name": "へや", "image": "room", "exits": { "hallway": { "names": ["ろうか"] } } }
  }
}
```

- **シーン**：`first` は初めて入ったとき、`enter` は2回目から。`image` が背景の画像 ID（配列にすると条件で重ね合わせられる）。
- **物と反応**：`names` は入力で通じる呼び方。`on` に動詞（`LOOK`、`EXAMINE`、`TAKE`、`TALK`、`OPEN`、`USE` など）ごとの反応を書く。`"USE+door"` のように「動詞+相手」も書ける。`region` はクリックできる範囲 [x, y, 幅, 高さ]。
- **手順の書き方**：文字列は地の文、`"@ayumi ……だれ？"` は話者つき。`if`、`set`、`goto`、`call`、`choice`、出力イベントの直接記述（`{"se.play": {"id": "knock"}}`）が使える。
- **人物と会話**：`characters` に話者を、`dialogues` に会話を書き、物の `"TALK": {"dialogue": "ayumi_first"}` で呼ぶ。
- VS Code では、ツールメニューの VS Code 設定の書き出しを使うと、書きながら入力の候補と確認が出ます。

**Ink を使うとき**

1. `game/scenario/src/talk.ink` に場面（ノット）を書く。話者は JSON と同じ `@ayumi ……` の書き方。JSON と同じ名前の `VAR` は値が同期する。
2. inklecate で変換する（Windows の PowerShell）：`inklecate.exe -o game\scenario\talk.ink.json game\scenario\src\talk.ink`
3. プロジェクト設定の `scenarios` に `res://game/scenario/talk.ink.json` を足す。
4. JSON の手順から `{"ink": "ノット名"}` で呼ぶ。Ink が終わると JSON に戻る。

`.ink` を直したら、そのたびに変換し直します。`LIST` はまだ使えません。

## 手順6 スプライト、カーソル、動画

必要になったら足す機能です。使わなければ飛ばしてかまいません。

**シーンに置くスプライト**：シーンの `sprites` に書くと、条件（`when`）に合うあいだだけ出ます。物に `sprite` を書くと、その絵の見えている部分がクリックできる場所になります。

```json
"sprites": [
  { "id": "lamp", "image": "lamp", "x": 214, "y": 70, "scale": 2 },
  { "id": "sparkle", "image": "sparkle", "x": 96, "y": 222, "scale": 2,
    "when": "not got_key", "hide": "fade" }
],
"objects": {
  "lamp": { "names": ["ランプ"], "sprite": "lamp", "cursor": "look",
            "on": { "EXAMINE": [{ "sprite.effect": { "id": "lamp", "name": "flash" } }, "あつい！"] } }
}
```

**イベントで動かす**：手順の中に出力イベントを書きます。

| やりたいこと | 書き方の例 |
| --- | --- |
| 出す | `{"sprite.show": {"id": "bird", "image": "bird", "x": 0, "y": 40, "layer": "front"}}` |
| 動かす | `{"sprite.set": {"id": "bird", "x": 600, "duration": 3, "ease": "in_out"}}` |
| アニメーション | `{"sprite.anim": {"id": "bird", "anim": "fly"}}` |
| 効果 | `{"sprite.effect": {"id": "bird", "name": "sepia"}}`（`none` で外す） |
| 消す | `{"sprite.hide": {"id": "bird", "transition": "fade"}}`、全部なら `{"sprite.clear": {}}` |
| カーソルを固定 | `{"cursor.set": {"kind": "wait"}}`（`null` で自動に戻す） |
| 動画 | `{"video.play": {"id": "opening"}}`、繰り返しなら `"loop": true` と `{"video.stop": {}}` |

- **層**：絵の窓の中なら `char`（既定）など、画面全体なら `front`（窓の前）と `back`（窓の後ろ）。
- **透明**：PNG の透明はそのまま使える。透明のない絵はマニフェストの `color_key` で色を抜く。
- **マウスカーソル**：90年代のパソコン以降のテンプレートには標準の絵が入っている。変えるときはテンプレートの `ui.cursors` に、種類ごとの画像 ID とホットスポットを書く。
- **動画**：mp4 などは ffmpeg で `.ogv` にしてから `movie/` に置く（例：`ffmpeg -i op.mp4 -c:v libtheora -q:v 7 -c:a libvorbis -q:a 5 op.ogv`）。

## 手順7 メインシーンを作って遊ぶ

シーンは `Control` を1つ置いてスクリプトを付けるだけです。画面の部品は、テンプレートに従って自動で作られます。

1. 「シーン → 新規シーン」で、ルートノードに `Control` を選ぶ。
2. その `Control` のスクリプトに `res://addons/adv80s/adv_player.gd` を設定する（インスペクターの Script にドラッグ）。
3. `res://game/main.tscn` として保存し、「プロジェクト設定 → 一般 → アプリケーション → 実行 → メインシーン」に選ぶ。
4. F5 で実行する。シナリオの `start` のシーンから始まれば成功。

遊ぶときの主な操作：

| 操作 | キー |
| --- | --- |
| メニュー | F1、右クリック、ゲームパッドの Start |
| オート、スキップ | F2、F3（Ctrl を押している間もスキップ） |
| ログ | F4 |
| クイックセーブ、クイックロード | F5、F9 |
| セーブ・ロードの画面 | Esc |
| 調べられる場所の表示 | F6 |

エディタで実行するときの F5 は Godot の「実行」です。ゲームの画面が出たあとの F5 は、クイックセーブになります。

## 手順8 確かめる

エディタのドック「adv80s」の「マニフェストを生成」を押すと、素材とシナリオをまとめて確かめ、エラーと警告を一覧に出します。エラーと警告が 0 になれば、書き出しの準備ができています。

確かめるもの：

- シナリオの書き方（スキーマに合うか、知らない項目がないか）
- 宣言も変更もしていないのに読んでいる変数、書き換えようとしている定数
- 話者、会話、移動先、素材があるか（素材がないとエラー）
- どこからも来られないシーン
- Ink の変換したファイルの版、未対応の機能、外部関数、呼び出すノット
- 再生できない動画の形式（`ASSET_UNSUPPORTED`）

「adv80s」画面の左上で「変数の一覧」を選ぶと、JSON と Ink の変数、共通の変数と定数を一覧で見られます。書き間違いの変数を探すのに便利です。

CI などコマンドラインで確かめるときは、次のようにします。

```
godot --headless --path . --script res://addons/adv80s/tools/manifest_cli.gd -- generate
godot --headless --path . --script res://addons/adv80s/tools/manifest_cli.gd -- check --up-to-date --strict
```

遊んで確かめるときは、F6 で調べられる場所を全部表示し、`region` の位置が絵と合っているかを見ます。

## 手順9 セーブの鍵と書き出し

配布する前に、セーブの改ざんを防ぐ鍵を作ります。鍵は Git に入れず、プロジェクトの外で保管します。

1. 「プロジェクト → ツール → adv80s: セーブの鍵を生成」で `res://master.key` を作る。
2. `master.key` が `.gitignore` に入っていることを確かめる。中身は別の場所に控えておく（失くすと、それまでのセーブが読めなくなる）。
3. CI で書き出すときは、ファイルの代わりに環境変数 `ADV80S_MASTER_KEY` で鍵を渡す。
4. 「プロジェクト → エクスポート」で書き出す。初めてなら、Godot のエクスポートテンプレートを入れる。

書き出すとき、プラグインが自動で次のことを行います。

- マニフェストを生成し直す
- シナリオなどの JSON をゲームに入れる
- 鍵を平文ではない形でゲームに埋め込む

鍵がないとき、開発中は仮の鍵で動き、警告が出ます。製品版ではセーブできません。フォントなどを配布物に入れるときは、それぞれのライセンス文も同梱してください（アドオンのフォントは `assets/font/LICENSE_M+FONTS.txt`）。

## 困ったとき

| こんなとき | 確かめること |
| --- | --- |
| 「adv80s」画面が出ない | プラグインが有効か。`addons/adv80s/plugin.cfg` がその場所にあるか |
| 絵の代わりに灰色の枠が出る | 素材 ID とファイル名が合っているか。「マニフェストを生成」を押したか |
| 入力しても「わからない」と言われる | 物の `names` にその呼び方があるか。動詞が辞書にあるか（拡張の動詞は `verbs` に書く） |
| GIF が動かない | エディタで一度開いて取り込みを済ませたか。`.import` の importer が `adv80s.anim_image` か |
| 動画が流れない | `.ogv`（Ogg Theora）か。`movie/` に置いたか |
| Ink の変更が入らない | inklecate で `.ink.json` を作り直したか |
| 字がぼやける・大きさが合わない | プロジェクト設定の大きさとストレッチ（手順1）。`dot16` を置いていないときは 12 ドットの字になる |
| セーブが「鍵が違う」で読めない | 保存したときと同じ `master.key`（または `ADV80S_MASTER_KEY`）か |

細かい決めごとは、アドオンの `README.md` とリポジトリ直下の `SPEC.md`（仕様書）にあります。ほかのドキュメント：[リファレンスマニュアル](reference.md)、[逆引きガイド](howto.md)、[仕様一覧](spec-list.md)。
