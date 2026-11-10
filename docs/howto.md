# adv80sGD 逆引きガイド

最終更新：2026-11-02

「こうしたい」から、シナリオや設定の書き方を引くためのガイドです。項目の意味と全部の引数は「[リファレンスマニュアル](reference.md)」、一覧は「[仕様一覧](spec-list.md)」を見てください。例の JSON は、シナリオ（`*.scenario.json`）の中に書くものです。

## シーンと移動

| やりたいこと | 書き方 |
| --- | --- |
| シーンを作る | `"scenes": {"hallway": {"name": "ろうか", "image": "hallway"}}` |
| 最初のシーンを決める | シナリオの `"start": "hallway"`（プロジェクト設定の `entry` が優先） |
| 初めて入ったときだけ文を出す | `"first": ["うすぐらい ろうかに いる。"]`、2回目からは `"enter": "ろうかに もどってきた。"` |
| よそのシーンへ行けるようにする | `"exits": {"room": {"names": ["へや"]}}`（「へやへ いく」で移る） |
| 条件を満たすまで出口を隠す | 出口に `"when": "door_unlocked"` |
| 移る前に何か起こす | 出口の `"on": {"MOVE": ["ドアを あけた。", {"goto": "room"}]}` |
| イベントの途中でシーンを移る | 手順に `{"goto": "room"}`（そこで手順は終わる） |
| 移るときの切り替え演出を変える | `{"scene.goto": {"scene": "room", "transition": "wipe"}}` |
| 絵の一部をクリックで調べられるようにする | 物に `"region": [x, y, 幅, 高さ]`（絵の窓の中の座標）。クリックはテンプレートの `inputs.enabled` に `click` |
| 絵の形どおりにクリック範囲を作る | スプライトを置き、物に `"sprite": "lamp"`（透明でない画素だけが範囲） |
| 出口もクリックで移れるようにする | 出口に `"region"` か `"sprite"`（クリックすると MOVE） |
| 人物として話しかけられるようにする | 物に `"character": "ayumi"`、`"on": {"TALK": {"dialogue": "ayumi_first"}}` |
| 条件で物を出し入れする | 物に `"when": "not got_key"` |
| 対象のないコマンド（「かんがえる」）に答える | シーンの `"on": {"THINK": "うえきばちが きになる。"}`（拡張の動詞はプロジェクト設定の `verbs`） |
| シーンごとにファイルを分ける | ファイルのいちばん上に `"scene": "hallway"` とシーンの項目を書き、`scenarios` に並べる |

## 文章と会話

| やりたいこと | 書き方 |
| --- | --- |
| 地の文を出す | 手順に `"ドアが あいた。"` |
| 話者の名前つきで台詞を出す | `"@ayumi ……だれ？"`（話者は `characters` に `{"name": "あゆみ"}`） |
| 行頭に `@` をそのまま出す | `"@@マーク"` |
| 台詞にボイスを付ける | `{"say": "ayumi", "text": "その かぎ……！", "id": "ayumi_key_01", "voice": "ayumi_key_01"}` |
| 主人公の名前などを差し込む | `"{player}くん"`（文字の `{` は `{{`） |
| ルビをふる | `"[ruby=やかた]館[/ruby]"` |
| 色を変える | `"[pal=2]あかい[/pal]"`（テンプレートのパレット番号） |
| 文の途中でクリックを待つ | `"ドアが あいた。[p]なかは くらい。"` |
| 窓を消して次のページから続ける | `"……。[page]つぎの ひ。"` |
| 長い文章をページに分ける | そのまま書く。窓に入りきらなければ自動でページに分かれる |
| クリックせずに一定時間でめくる | `"[page=3]"`、`"[p=2]"`、または `{"type": "text.show", "args": {"body": "…"}, "wait": 3}` |
| すべて自動で進める（オート） | 遊ぶ人が F2 か設定画面でオート送りを入れる（機能 `auto_advance`） |
| 少し間を置く | `"待って[w=0.5]……だれ？"`、または手順に `{"wait": {"seconds": 1}}` |
| 文の途中で効果音を鳴らす | `"[se=knock]コン、コン。"` |
| 一部だけゆっくり出す | `"[speed=5]ゆっくり[/speed]"`、一度に出すなら `[instant]…[/instant]` |
| 選択肢を出す | `{"choice": {"prompt": "どう こたえる？", "options": [{"label": "はい", "do": […]}, {"label": "いいえ", "do": […]}]}}` |
| 一度選んだ項目を消す | 項目に `"once": true` |
| 条件を満たすときだけ項目を出す | 項目に `"when": "has(key)"` |
| 会話を別に書いて呼ぶ | `"dialogues": {"ayumi_first": […]}`、呼ぶ側は `{"call": "ayumi_first"}`（終わると戻る） |
| 「きく → 話題」を作る | `"topics": {"ayumi": [{"id": "case", "label": "事件について", "dialogue": "ayumi_case"}]}` |
| 話題を条件で出す | 話題に `"when": "has_key"` |
| 文章を消す | `{"text.clear": {}}` |
| 決まった返事（「そんな ものは ない」など）を変える | シナリオの `"replies": {"no_target": "……"}` |

## フラグ・変数・アイテム

| やりたいこと | 書き方 |
| --- | --- |
| フラグを立てる | `{"set": {"door_unlocked": true}}` |
| 変数を計算する | `{"set": {"money": "= money - price * 2"}}`、まとめてなら `{"let": "money = money - 10; visits = visits + 1"}` |
| 変数の初期値を決める | `"variables": {"money": {"type": "int", "default": 100}}` |
| 全部のシナリオで同じ変数を使う | プロジェクト設定に `"variables": {"money": {"type": "int", "default": 0}}`（Ink の同じ名前の `VAR` とも値を受け渡す） |
| 書き換えられない値（定数）を使う | プロジェクト設定かシナリオに `"constants": {"MAX_HP": 99}`。`"hp >= MAX_HP"`、`"{MAX_HP}"` で読める |
| 条件で反応を変える | `{"if": "door_unlocked", "then": "あいている。", "else": "かぎが かかっている。"}` |
| 複雑な条件を書く | `"has_key and money >= 100 and (visited(cellar) or has(lamp))"` |
| いまのシーンで分ける | `"scene == hallway"` |
| 会話を見たかで分ける | `"talked(ayumi_first)"` |
| 前に選んだ選択肢で分ける | `"chosen(who, detective)"`（選択肢と項目に `id` を書いておく） |
| 機種（画面）ごとに分ける | `"preset == 98"`、`"group == console"` |
| アイテムを手に入れる・渡す | `{"item.add": {"id": "key"}}`、`{"item.remove": {"id": "key"}}` |
| アイテムを作る | `"items": {"key": {"name": "かぎ", "names": ["鍵", "key"], "on": {"LOOK": "ふるびた かぎだ。"}}}` |
| 持っているかで分ける | `"has(key)"`、数は `"count(coin) >= 3"` |
| 鍵でドアを開ける | ドアの `"on": {"USE+key": […]}` か、アイテムの `"on": {"USE+door": […]}`（「かぎを ドアに つかう」） |
| 「あける」と「かぎで あける」を分ける | `"OPEN"` と `"OPEN+key"` を両方書く（`+` の方が優先） |
| ゲームを終える | `{"game.end": {"ending": "true_end"}}` |

## 絵と演出

| やりたいこと | 書き方 |
| --- | --- |
| 背景を変える | `{"image.show": {"layer": "bg", "id": "room"}}` |
| 立ち絵を出す・消す | `{"image.show": {"layer": "char", "id": "ayumi", "variant": "smile"}}`、`{"image.hide": {"layer": "char"}}` |
| 表情を変える | 素材を `chara/ayumi@smile.png` と置き、`"variant": "smile"` |
| 背景に絵を重ねる | シーンの `"image": ["hallway", {"id": "door_open", "x": 260, "y": 90}]` |
| 条件で背景の一部を変える | `"image": ["hallway", {"id": "door_open", "when": "door_unlocked"}]`（条件が変わると描き直す。演出は `"image_transition": "fade"`） |
| 昼と夜で背景を切り替える | `"image": [{"id": "town", "when": "not night"}, {"id": "town", "variant": "night", "when": "night"}]` |
| 切り替え演出を付ける | `"transition": "wipe"`、細かくは `{"type": "wipe", "direction": "right", "duration": 0.8}` |
| 演出に名前を付けて使い回す | プロジェクト設定の `"transitions": {"named": {"door_open": {"type": "wipe", …}}}`、使うとき `"transition": "door_open"` |
| 80年代風に1行ずつ描く | `"transition": "line_draw"`（色の面ごとなら `plane_draw`） |
| 画面を揺らす・光らせる | `{"effect.play": {"name": "shake"}}`、`{"effect.play": {"name": "flash"}}` |
| 夜やセピアの色味にする | `{"effect.play": {"name": "tint", "color": "#4060ff", "amount": 0.5}}` |
| 水面などをパレットで動かす | `{"effect.play": {"name": "palette_cycle", "range": [4, 7], "speed": 4}}` |
| アイテムの絵を置き、取ったら消す | シーンの `"sprites": [{"id": "key", "image": "key", "x": 120, "y": 180, "when": "not has(key)"}]` |
| 絵を自由に置く・重ねる | `{"sprite.show": {"id": "bird", "image": "bird", "x": 0, "y": 40}}`（`layer`、`z` で重なり） |
| 絵を動かす | `{"sprite.set": {"id": "bird", "x": 600, "duration": 3, "ease": "in_out"}}` |
| ふわふわ浮かせる | `{"sprite.set": {"id": "ghost", "y": 30, "duration": 1, "loop": -1, "yoyo": true}}` |
| 拡大・回転・半透明 | `"scale": 2`、`"rotation": 15`、`"opacity": 0.5` |
| 黒を透明にする（カラーキー） | マニフェストに `"lamp": {"type": "image", "color_key": "#000000"}` |
| アニメーションさせる | GIF・APNG・MNG を置くだけ。並べた画像ならマニフェストに `"grid": [4, 1], "anims": {"walk": {"frames": [0, 1, 2, 1], "fps": 8}}` |
| アニメーションを切り替える・止める | `{"sprite.anim": {"id": "bird", "anim": "fly"}}`、止めるなら `"anim": null` |
| 絵だけモノクロ・シルエットにする | `{"sprite.effect": {"id": "ayumi", "name": "silhouette", "params": {"color": "#000000"}}}`、戻すなら `"name": "none"` |
| オープニング動画を流す | `movie/opening.ogv` を置き、`{"video.play": {"id": "opening", "area": "screen"}}` |
| 動く背景にする | `{"video.play": {"id": "rain", "loop": true, "bgm": "keep"}}`、止めるなら `{"video.stop": {}}` |
| 一枚絵を画面いっぱいに出す | `{"layout.set": {"layout": "fullscreen_cg"}}`、戻すなら `{"layout.set": {"layout": ""}}` |

## 音

| やりたいこと | 書き方 |
| --- | --- |
| BGM を鳴らす | `bgm/theme.ogg` を置き、`{"bgm.play": {"id": "theme"}}` |
| BGM をフェードで切り替える | `{"bgm.play": {"id": "battle", "fade": 1.0}}` |
| BGM を止める | `{"bgm.stop": {"fade": 2.0}}` |
| イントロのあとだけ繰り返す | マニフェストに `"theme": {"type": "bgm", "loop_start": 9.6}`（秒） |
| 曲ごとに音量をそろえる | マニフェストに `"volume": 0.8` |
| 効果音を鳴らす | `{"se.play": {"id": "knock"}}` |
| 効果音が鳴り終わるまで待つ | `{"type": "se.play", "args": {"id": "knock"}, "wait": "end"}` |
| 台詞にボイスを付ける | `{"say": "ayumi", "text": "…", "voice": "ayumi_01"}`（`voice/ayumi_01.ogg`） |
| 機種ごとに音を差し替える | `presets/88/bgm/theme.ogg` のように置く |
| 動画を流す間も BGM を流し続ける | `{"video.play": {"id": "op", "bgm": "keep"}}` |

## 画面の見た目

画面の見た目はテンプレート（`template.json`）で決めます。同梱のテンプレートは直接直さず、`extends` した自分のテンプレートに書きます。

| やりたいこと | 書き方 |
| --- | --- |
| 機種を変える | プロジェクト設定の `"template": "x68k_classic"` |
| 自分のテンプレートを作る | 「adv80s」画面 → テンプレート → 新規…（`extends` を選ぶ） |
| 旧表示と新表示を切り替えられるようにする | `"templates": ["pc98_classic", "hd_modern"]` と機能 `era_switch`。シナリオからは `{"template.switch": {"template": "hd_modern"}}` |
| 画面モードを選ぶ | `"display": {"preset": "X68K.512x512"}` |
| 走査線や CRT を足す | `"filters": {"mode": "append", "list": [{"type": "crt", "curvature": 0.02}]}` |
| フィルターを使わない | `"filters": {"mode": "none"}`（遊ぶ人が切れるのは機能 `filter_toggle`） |
| 自作のフィルターを使う | シェーダーと `*.effect.json` を作り、プロジェクト設定の `effects` に並べる |
| 窓の位置や大きさを変える | `"layout": {"regions": {"message": {"rect": [16, 264, 416, 96]}}}` |
| 窓の枠を画像にする | `"ui": {"window_skin": {"type": "nine_patch", "image": "frame", "margins": [8, 8, 8, 8]}, "window_padding": [12, 8]}` |
| 文字の速さ・色を変える | `"text": {"speed": 30, "color": 7, "name_color": 6}` |
| フォントを変える | `font/myfont.ttf` を置き、`"fonts": {"main": {"asset": "myfont", "size": 16}}` |
| 98 を 16 ドットの字にする | DotGothic16 を `font/dot16.ttf` として置く |
| クリック待ちの印を変える | `"ui": {"wait_mark": "▽"}`、画像なら `{"image": "cursor_next", "anim": "default"}` |
| ページ送りの印を別にする | `"ui": {"page_mark": {"image": "page_icon", "offset": [0, -2]}}` |
| マウスカーソルの形を変える | `"ui": {"cursors": {"default": {"image": "my_arrow", "hotspot": [0, 0]}, "look": "cross"}}` |
| 物ごとにカーソルを変える | 物に `"cursor": "take"` |
| 演出の間だけカーソルを固定する | `{"cursor.set": {"kind": "wait"}}`、戻すなら `{"cursor.set": {"kind": null}}` |
| 全画面の一枚絵用のレイアウトを作る | `"layout": {"named": {"cg": {"regions": {"picture": {"rect": [0, 0, 640, 400]}, "message": {"visible": false}}}}}` |
| コマンド選択を 1 列にする | `"inputs": {"command_columns": 1}` |
| コマンド入力を使わず選ぶだけにする | `"inputs": {"enabled": ["select"]}` |
| 動詞を選んでから絵の中の対象をクリックする方式にする | プロジェクト設定に `"inputs": {"enabled": ["verb_click"]}`（セットアップ画面でも選べる） |
| 右クリックでカーソルの動詞を切り替える方式にする | `"inputs": {"enabled": ["verb_cursor"]}` |
| 対象に合わせて動作が決まる方式（動詞を選ばない）にする | `"inputs": {"enabled": ["context"]}` |
| クリックしたときの動作を物ごとに決める | 物・出口に `"click": "OPEN"`（動詞ID） |
| カーソルの種類ごとの動作を変える | `"inputs": {"context_verbs": {"look": "LOOK"}}` |
| 使う入力機器をしぼる | プロジェクト設定に `"input_devices": ["keyboard", "mouse"]` |
| ゲームの名前とIDを決める | セットアップ画面、またはプロジェクト設定の `title` と `game_id` |

## 現代的な機能

機能はプロジェクト設定の `features` で使えるようにし、シナリオのイベントで中身を入れます。

| やりたいこと | 書き方 |
| --- | --- |
| 機能を使えるようにする | `"features": {"hint": {"allow": true, "default": true}}` |
| 機能を使わせない | `"features": {"rewind": {"allow": false}}` |
| 80年代の機種だけ機能を切る | そのテンプレートに `"features": {"hint": false}` |
| 段階式のヒントを出す | `{"hint.set": {"topic": "door", "hints": ["…", "…", "…"]}}`、表示名はプロジェクト設定の `"hint_topics": {"door": "ドアについて"}` |
| いまの目的を出す・消す | `{"objective.set": {"text": "ここから でる ほうほうを さがす"}}`、消すなら `"text": ""` |
| 手帳に書き残す | `{"notebook.add": {"id": "key", "category": "もちもの", "title": "ふるい かぎ", "body": "…"}}` |
| フローチャートを作る | シナリオの `"flow": {"nodes": [{"id": "start", "label": "はじまり"}], "edges": [{"from": "start", "to": "met"}]}`、到達したら `{"flow.mark": {"node": "met"}}` |
| チャプターを選べるようにする | `"chapters": [{"id": "ch2", "label": "第2章", "node": "met"}]` |
| ここでオートセーブする | `{"checkpoint": {"id": "start"}}`（シーンを移ったときも標準で保存） |
| オートセーブの時を変える | `"autosave": {"allow": true, "default": true, "options": {"on": ["checkpoint"]}}` |
| セーブ画面を開かせる | `{"save.request": {}}` |
| 調べられる場所を光らせる | 機能 `hotspot`（F6） |
| 試したコマンドに印を付ける | 機能 `tried_marks` |
| 読みやすいフォントを選べるようにする | 機能 `readable_font` とテンプレートの `fonts.readable` |
| 動詞の一覧を入れ替える | `{"verbs.update": {"verbs": ["THINK"], "mode": "add"}}` |
| 物を一覧から隠す | `{"hotspots.update": {"objects": ["plant"], "mode": "remove"}}` |

## Ink を使う

| やりたいこと | 書き方 |
| --- | --- |
| Ink をゲームで使える形にする | `inklecate.exe -o game\scenario\talk.ink.json game\scenario\src\talk.ink`、`scenarios` に `.ink.json` を足す |
| JSON のシーンから Ink の会話を呼ぶ | 手順に `{"ink": "window_talk"}`（Ink が終わると続きに戻る） |
| JSON と同じ変数を使う | Ink で同じ名前の `VAR met_ayumi = false` を書く（値が受け渡される） |
| 共通の定数を読む | `EXTERNAL get_var(name)` を宣言して `{get_var("MAX_HP")}`、または同じ名前の `VAR` |
| 話者つきの台詞 | `@ayumi まどの そと？` |
| 行にボイスや背景を付ける | `台詞 # voice:ayumi_02`、`# bg:room`、`# se:knock` |
| Ink から出力イベントを出す | `# {"sprite.show": {"id": "bird", "image": "bird", "x": 0, "y": 40}}`、または `~ event("se.play", "{\"id\": \"knock\"}")` |
| アイテムを増やす・調べる | `EXTERNAL item_add(id)`、`EXTERNAL has_item(id)` を宣言して使う |
| 選択肢をコマンド入力でも選べるようにする | `* [かぎを みせる] # intent:SHOW:key` |
| 選択肢を一覧に出さない | `# hidden`（コマンド入力だけで選ぶ） |
| JSON の条件式を Ink で使う | `EXTERNAL cond(text)` を宣言して `{cond("has(key) and visited(cellar)")}` |
| Ink からシーンを移る | `~ goto_scene("room")` |

## 確かめる・配布する

| やりたいこと | 書き方 |
| --- | --- |
| 書き間違いや足りない素材を探す | ドック「adv80s」の「マニフェストを生成」（エラーと警告の一覧が出る） |
| 変数の使われ方を一覧で見る | 「adv80s」画面の左上で「変数の一覧」 |
| JSON を入力の候補つきで書く | ツールメニュー「adv80s: VS Code の設定を書き出す」 |
| クリック範囲が絵と合っているか見る | 遊んでいるときに F6 |
| 既読を飛ばして速く確かめる | Ctrl を押している間か F3 |
| CI で確かめる | `godot --headless --path . --script res://addons/adv80s/tools/manifest_cli.gd -- check --up-to-date --strict` |
| セーブの鍵を作る | ツールメニュー「adv80s: セーブの鍵を生成」（`master.key` は Git に入れない） |
| CI で鍵を渡す | 環境変数 `ADV80S_MASTER_KEY` |
| セーブを他の端末に持ち出せなくする | `"save": {"key_provider": "per_user"}` |
| セーブを暗号化する | `"save": {"protection": "hmac_aes"}` |
| ゲームとして書き出す | 「プロジェクト → エクスポート」（マニフェストの生成、JSON の同梱、鍵の埋め込みは自動） |
| mp4 の動画を使う | `ffmpeg -i op.mp4 -c:v libtheora -q:v 7 -c:a libvorbis -q:a 5 op.ogv` で変換して `movie/` に置く |
