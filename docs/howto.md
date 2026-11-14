# adv80sGD 逆引きガイド

最終更新：2026-11-12

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
| 何度も使う場面をまとめて呼ぶ（サブルーチン） | `"shop": {"kind": "sub", "params": {"price": {"default": 3}}, "enter": ["{arg.price}えん です。", {"return": "=arg.price * 2"}]}`、呼ぶ側は `{"call_scene": "shop", "args": {"price": 10}, "into": "paid"}` |
| サブシーンに計算した値を渡す | `"args": {"price": "=money + 5"}`（呼ぶ側で計算する） |
| サブシーンの呼び出しの深さを変える | プロジェクト設定の `"subscene_max_depth": 20`（0 で無制限） |

## タイトル・エンディング・システム画面

| やりたいこと | 書き方 |
| --- | --- |
| すぐ使えるタイトル画面を出す | プロジェクト設定の `"title_screen": "template"`（背景は `title_image`、メニューは `title_menu`） |
| タイトル画面を自分で作る | `"title": {"kind": "title", "image": "title_bg", "menu": [{"label": "はじめから", "do": {"game.new": {}}}, {"label": "つづきから", "do": {"game.continue": {}}}]}`、プロジェクト設定の `"title_screen": "title"` |
| タイトルへ戻る | `{"game.title": {}}`（システムメニューの「タイトルへ」でも戻れる） |
| エンディングを作る | `"end_good": {"kind": "ending", "ending": "good", "enter": [...]}`、プロジェクト設定の `"endings": [{"id": "good", "label": "ハッピーエンド", "hint": "…"}]` |
| エンディング一覧を見せる | システムメニューの「エンディング」、タイトルのメニューの `{"endings.open": {}}` |
| スタッフロールを流す | `{"credits.roll": {"lines": ["げんさく", "なまえ", "", "おんがく", "なまえ"], "speed": 30}}` |
| オープニングを作る | `"op": {"kind": "opening", "enter": [...]}`、プロジェクト設定の `"opening": "op"`（起動時に流れ、終わるとタイトルへ） |
| オープニングを1回目だけ流す | シーンに `"replay": "once"` |
| 2回目からオープニングを飛ばせるようにする | シーンに `"replay": "skippable"`（Esc で飛ばす、Ctrl で早送り） |
| オープニングのあとに行くシーンを決める | シーンに `"next": "prologue"` |
| シーンに入ったら BGM を鳴らす | シーンに `"bgm": "theme"`（止めるなら `null`） |
| シーンに入るときの演出を決める | シーンに `"transition": "fade"`（タイトル・エンディングでも同じ） |
| テンプレートのタイトルに BGM と演出を付ける | プロジェクト設定の `"title_bgm": "title"`、`"title_transition": "fade"` |
| エンディングのあとに「おわり」を出す | エンディングのシーンを最後まで進めると出る。見た目と閉じ方はシーンかプロジェクト設定の `"fin": {"text": "THE END", "advance": ["key", 10], "then": "title"}` |
| 「おわり」を出さない | シーンかプロジェクト設定に `"fin": false` |
| 「おわり」のあと別のシーンへ行く | `"fin": {"then": "epilogue"}`（はじめの状態に戻してから行くなら `"reset": true`） |
| 決まったキーで「おわり」を閉じる | `"advance": ["key:Enter"]` |
| ゲームの外の合図で「おわり」を閉じる | `"advance": ["trigger:next"]` と書き、GDScript で `player.fire_trigger("next")` |
| 「おわり」に複数の行や画像を並べる | `"fin": {"items": [{"text": "おわり", "size": 40}, {"image": "logo"}, "あそんでくれて ありがとう"]}` |
| 「おわり」のあとクリアデータをセーブさせる | `"fin": {"save_prompt": true, "save_resume": "epilogue"}`（聞かないなら `false`、既定） |
| クリアデータで引き継ぐものを選ぶ | `"fin": {"save_prompt": true, "save_carry": {"vars": ["money", "hero_name"], "items": "all"}}`（全部なら `"all"`、何もなら `"none"`） |
| 見たエンディングの数でタイトルの絵を変える | タイトルのシーンに `"variants": [{"when": "sys.endings_seen >= 2", "image": "title2"}]` |
| エンディングを見たらタイトルのメニューを変える | タイトルのシーンの `"variants": [{"when": "sys.all_endings", "menu": [{"label": "はじめから", "do": {"game.new": {}}}, {"label": "おまけ", "do": {"extras.open": {}}}]}]`（テンプレートなら `title_variants` の `menu`・`labels`） |
| おまけ（ギャラリーと音楽）を付ける | プロジェクト設定の `"extras": {"gallery": [{"id": "cg_01", "label": "であい"}], "music": [{"id": "theme", "label": "テーマ"}]}`（すべてのエンディングを見ると開ける） |
| おまけにエンディング一覧とオープニングも並べる | `"extras": {"menu": ["gallery", "music", "endings", "opening"], …}` |
| ギャラリーで何枚かの画像をめくる | `"gallery": [{"images": ["cg_03a", "cg_03b"], "label": "さんにんで"}]` |
| 音楽を続けて鳴らす | 音楽の画面の「さいせい」で切り替え（初めを決めるなら `"extras": {"music_mode": "next", …}`） |
| ギャラリーの見本の画像を変える・出さない | 項目の `"thumb": "cg_03_small"`、出さないなら `"extras": {"thumbnails": false, …}` |
| 音楽に曲の説明を出す | `"music": [{"id": "theme", "label": "テーマ", "desc": "さっきょく：○○"}]`（出さないなら `"music_desc": false`） |
| 全部開いたら特典を出す | `"gallery": [ …, {"id": "cg_special", "label": "とくべつ", "bonus": true}]`（条件を変えるなら `"when": "sys.gallery_opened >= 5"`） |
| おまけを開ける条件を変える・出さない | `"extras": {"when": "sys.ending_true_end", …}`、出さないなら `"show": false` |
| すべてのエンディングを見たらタイトルの曲を変える | `"variants": [{"when": "sys.all_endings", "bgm": "true_theme"}]`（テンプレートのタイトルならプロジェクト設定の `title_variants`） |
| オープニングを見返せるようにする | テンプレートのタイトルのメニューに出る（`title_menu` に `opening`）。タイトルのシーンなら `{"label": "オープニング", "when": "sys.opening_replay", "do": {"opening.play": {}}}` |
| 見返せる条件を決める | プロジェクト設定の `"opening_replay": "any_ending"`、`{"endings": ["true_end"]}` など |
| スタッフロールに画像や色・大きさの違う行を入れる | `{"credits.roll": {"items": [{"text": "スタッフ", "pal": 6, "size": 24}, {"image": "logo", "scale": 2, "gap": 16}, "なまえ"], "bgm": "staff"}}` |
| セーブ画面を JSON で作る | `"sys_save": {"kind": "system", "enter": "どこに セーブする？", "menu": [{"label": "01：[if=sys.slot_01_exists]{sys.slot_01}[else]（からっぽ）[/if]", "do": {"system.save": {"slot": "01"}}}, {"label": "もどる", "do": {"system.close": {}}}]}`、プロジェクト設定の `"system_scenes": {"save": "sys_save"}` |
| ロードと同じ画面を使い分ける | `"system_scenes": {"save": "sys_save", "load": "sys_save"}`、中で `{"if": "sys.mode == \"load\"", "then": {"system.load": {"slot": "01"}}, "else": {"system.save": {"slot": "01"}}}` |
| 設定画面を Godot のシーンで作る | `AdvSystemScreen` を継いだスクリプトを付けた `.tscn` を作り、`"system_scenes": {"settings": "res://game/ui/settings.tscn"}` |
| システム画面から設定を変える | `{"settings.set": {"key": "bgm_volume", "value": 0.5}}` |

## 文章と会話

| やりたいこと | 書き方 |
| --- | --- |
| 地の文を出す | 手順に `"ドアが あいた。"` |
| 話者の名前つきで台詞を出す | `"@ayumi ……だれ？"`（話者は `characters` に `{"name": "あゆみ"}`） |
| 行頭に `@` をそのまま出す | `"@@マーク"` |
| 台詞にボイスを付ける | `{"say": "ayumi", "text": "その かぎ……！", "id": "ayumi_key_01", "voice": "ayumi_key_01"}` |
| 主人公の名前などを差し込む | `"{player}くん"`（文字の `{` は `{{`） |
| よく使う言い回しに名前を付ける | `"aliases": {"hero": "[pal=6]{player}[/pal]"}`、本文に `"[alias=hero]は おどろいた。"` |
| 引数のある言い回しを作る | `"aliases": {"greet": {"params": ["who"], "text": "{arg.who}、こんにちは。"}}`、本文に `"[alias=greet あゆみ]"`（空白を含む引数は `"…"` で囲む） |
| 条件で文の一部を変える | `"いまは [if=money >= 10]ゆうふく[elif=money > 0]ふつう[else]びんぼう[/if]。"` |
| 選択肢の文に変数を入れる | 項目の `"label": "{money}えん はらう"`（エイリアスと条件も使える） |
| ルビをふる | `"[ruby=やかた]館[/ruby]"` |
| 色を変える | `"[pal=2]あかい[/pal]"`（テンプレートのパレット番号） |
| 文の途中でクリックを待つ | `"ドアが あいた。[p]なかは くらい。"` |
| 窓を消して次のページから続ける | `"……。[page]つぎの ひ。"` |
| 出した文章の続きを足す | `{"text.append": {"body": "……でも かぎは ない。"}}`（話者のある文章なら「」の中に足す） |
| 文中に小さな絵（外字）を入れる | `"すきな ものは [gaiji=heart] です。"`、ログ用の文字はマニフェストに `"heart": {"type": "image", "alt": "（ハート）"}` |
| 外字の色を減色せずにそのまま出す | マニフェストに `"heart": {"type": "image", "keep_colors": true}`（エディタでは keep_colors を「有効」にする） |
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
| 当時の MAG 画像を使う | `.mag` を素材フォルダに置くだけ（16色・256色。エディタが取り込む） |
| アニメーションさせる | GIF・APNG・MNG を置くだけ。並べた画像ならマニフェストに `"grid": [4, 1], "anims": {"walk": {"frames": [0, 1, 2, 1], "fps": 8}}` |
| アニメーションを切り替える・止める | `{"sprite.anim": {"id": "bird", "anim": "fly"}}`、止めるなら `"anim": null` |
| 絵だけモノクロ・シルエットにする | `{"sprite.effect": {"id": "ayumi", "name": "silhouette", "params": {"color": "#000000"}}}`、戻すなら `"name": "none"` |
| オープニング動画を流す | `movie/opening.ogv` を置き、`{"video.play": {"id": "opening", "area": "screen"}}` |
| 動く背景にする | `{"video.play": {"id": "rain", "loop": true, "bgm": "keep"}}`、止めるなら `{"video.stop": {}}` |
| 人物を円が広がるように出す | `{"sprite.show": {"id": "ayumi", "image": "ayumi", "x": 200, "y": 40, "transition": "iris"}}` |
| 背景の一部を動かす（GIF を重ねる） | シーンの `"image": ["room", {"id": "candle", "x": 120, "y": 60}]`（candle は GIF やスプライトシート） |
| 動画を演出つきで出し入れする | `{"video.play": {"id": "opening", "transition": "fade"}}`、繰り返しなら `{"video.stop": {"transition": "fade"}}` |
| スプライトの動画の音を出す | `{"sprite.show": {"id": "tv", "image": "tv_noise", "x": 40, "y": 30, "mute": false, "volume": 0.5}}` |
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
| 「古いドアを開けてみる」のような文で入力させる | `"inputs": {"enabled": ["parser"], "parser_profile": "free"}` |
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
| 持ち物や状態を集合で持つ | Ink の `LIST`（`LIST doors = (front), back`、`~ inv += key`、`{inv ? key: …}`、`LIST_RANDOM(…)` など。JSON 側からは「front, back」の文字列で見える） |
| 共通の定数を読む | `EXTERNAL get_var(name)` を宣言して `{get_var("MAX_HP")}`、または同じ名前の `VAR` |
| 話者つきの台詞 | `@ayumi まどの そと？` |
| 行にボイスや背景を付ける | `台詞 # voice:ayumi_02`、`# bg:room`、`# se:knock` |
| Ink から出力イベントを出す | `# {"sprite.show": {"id": "bird", "image": "bird", "x": 0, "y": 40}}`、または `~ event("se.play", "{\"id\": \"knock\"}")` |
| アイテムを増やす・調べる | `EXTERNAL item_add(id)`、`EXTERNAL has_item(id)` を宣言して使う |
| 選択肢をコマンド入力でも選べるようにする | `* [かぎを みせる] # intent:SHOW:key` |
| 選択肢を一覧に出さない | `# hidden`（コマンド入力だけで選ぶ） |
| JSON の条件式を Ink で使う | `EXTERNAL cond(text)` を宣言して `{cond("has(key) and visited(cellar)")}` |
| Ink からシーンを移る | `~ goto_scene("room")` |
| Ink から JSON のサブシーンを呼ぶ | `EXTERNAL call_scene(id, args, into)` と書き、`~ call_scene("shop", "price=7; item=ミルク", "result")`（戻ってくると続きから） |
| Ink の call_scene の行き先を確かめる | 確認（validate）で、ないシーンは `MISSING_TARGET`、kind が sub でないシーンは `SUBSCENE_KIND`。シナリオエディタの Ink のエディタでは `call_scene("` のあとに候補が出る |
| Ink からタイトルへ戻る | `~ event("game.title", "")` かタグ `# {"game.title": {}}` |

## 確かめる・配布する

| やりたいこと | 書き方 |
| --- | --- |
| 書き間違いや足りない素材を探す | ドック「adv80s」の「マニフェストを生成」（エラーと警告の一覧が出る） |
| 変数の使われ方を一覧で見る | 「adv80s」画面の左上で「変数の一覧」 |
| シナリオからお知らせを出す | `{"notice.show": {"text": "てちょうを みなおそう"}}` |
| 持ち物・手帳のときに自動でお知らせを出す | `"notices": {"item_add": "{name}を てにいれた", "notebook_add": "てちょうに かきました：{title}"}` |
| 目的・ヒント・オートセーブでもお知らせを出す | `"notices": {"objective_set": "もくてき：{text}", "hint_set": "ヒントが ふえました", "autosave": "セーブしました"}`（全部止めるなら `"enabled": false`） |
| お知らせの位置・色・音を変える | `"notice_style": {"position": "bottom_left", "fg": 6, "bg": 1, "border": -1, "se": "pi"}`（テンプレートなら `notice`） |
| お知らせに絵を付ける | `{"notice.show": {"text": "かぎを てにいれた", "icon": "key_icon"}}`、持ち物なら `"items": {"key": {"name": "かぎ", "icon": "key_icon"}}` |
| お知らせをメッセージログにも残す | 全部なら `"notice_style": {"log": true}`、ひとつだけなら `notice.show` や `notices` の項目に `"log": true` |
| お知らせをクリックするまで出しておく | `"notice_style": {"seconds": 0}`（クリックで消せないようにするなら `"click_close": false`） |
| ログの中のお知らせの印・色を変える | `"notice_style": {"log": true, "log_mark": "★", "log_color": 4}` |
| エディタで曲・効果音を試しに鳴らす | 曲・効果音・ボイスの ID の項目の ▶ を押す（もう一度押すと止める） |
| お知らせを同時に出す数を変える | `"notice_style": {"max": 3}`（上限なしは `0`） |
| ログでお知らせだけ・文章だけを見る | ログの画面の右上の切り替え（Tab キーでも）。開いたときの表示は `"notice_style": {"log_filter": "text"}` |
| プロジェクト全体の見つからない ID を一覧にする | シナリオエディタの右上の「ID の確認」（Ink のタグや call_scene も調べる。もう一度押すと隠す。ダブルクリックでそのシーンを開く） |
| 見つからない ID をまとめて直す | 「ID の確認」の一覧で行を選び、下の「直す ID」で候補を選んで「同じ ID をまとめて直す」（書き換える場所を確かめてから。元に戻せる） |
| 「ID の確認」の一覧を絞り込む | 一覧の上の「種類」「ファイル」 |
| ゲームを止めずにシナリオ・素材を読み直す | デバッグ実行中に F8（デバッグの「読み直す」ボタン、コンソールの `reload` でも） |
| 読み直したあと、いまのシーンに入り直す | Shift+F8（コンソールなら `reload enter`。いつもなら `"debug": {"reload_reenter": true}`） |
| 保存したら自動で読み直す | シナリオエディタの右上の「保存で読み直す」（`"debug": {"auto_reload": true}` と同じ。実行中のゲームにも伝わる。コンソールの `autoreload on` / `off` でも） |
| 遊んでいるシーンをエディタで開く | デバッグ実行中にデバッグの「エディタで開く」（コンソールなら `edit`）。エディタから実行したときだけ |
| いま書いているシーンから試す | シナリオエディタの「▶ このシーンから実行」（タイトル・オープニングを飛ばす。デバッグビルドだけ） |
| フラグや持ち物をそろえてからシーンを試す | 「ひな形…」で `名前 = 値`・`ID = 個数` を書いて保存し、「実行：」で選んでから実行 |
| 会話の途中の行から試す | 会話の画面で手順を選び「▶ ここから実行」（Ink はカーソルのあるノットから） |
| ゲームのいまの値をひな形にする | デバッグ実行中に「ひな形に」で入れるものに印を付けて「送る」（全部をすぐ送るならコンソールの `preset 名前`）。エディタに戻ると「実行：」に出る |
| 二つのひな形の違いを見る | 「ひな形…」の窓の「比べる：」で相手を選ぶ（違うところだけ並ぶ） |
| 途中から試すとき、それまでの変数も入れておく | 会話の画面の「設定を先に」に印を付けてから「▶ ここから実行」 |
| 前の「もし」の中の変数も入れておく | 「設定を先に」と「条件も」に印を付けてから「▶ ここから実行」 |
| ひな形を少しだけ変えたものを作る | 「ひな形…」の窓で書きかえて「複製」（もとはそのまま） |
| 「設定を先に」で何が入ったか見る | 実行したときのお知らせ「先に設定：…」と、メッセージログ（全部） |
| ひな形をほかのプロジェクトへ持っていく | 「ひな形…」の窓の「書き出す…」で書き出すものを選び（全部でも一部でも）、.json に書いて向こうの「読み込む…」で読む |
| ファイルから一部のひな形だけ読み込む | 「読み込む…」でファイルを選んだあと、読み込む窓で入れたいものだけに印を付ける |
| 「先に設定」のお知らせをクリックするまで残す | プロジェクト設定の debug に `"pre_set_seconds": 0`（長くするなら秒数） |
| ゲームの一覧から要らない行を外す | 行の左の「×」（「外したものを戻す」でまとめて戻せる） |
| 読み込むとき、中身が違うものを上書きする | 読み込む窓の「中身が違うものは上書きする」に印を付ける |
| デバッグのお知らせをまとめて目立たせる | プロジェクト設定の debug に `"notice_style": {"bg": 4, "border": 9}` など |
| ひな形を組にまとめる | 「ひな形…」の窓の「組」に名前を書く（ゲームで続けて送ったものは自動で組になる） |
| 使わない組をたたむ | 「実行：」の一覧で「▾ 組：名前」を選ぶ（もう一度選ぶと開く） |
| よく使うひな形を上に出す | 「実行：」の並べ方を「使った順」にする |
| 新しく作ったひな形を上に出す | 「実行：」の並べ方を「作った順」にする |
| 一つの組の中だけ片付ける | 「片付け…」の「探す組」で組を選ぶ |
| 消す前にひな形の中身を確かめる | 「片付け…」の窓の下の「印を付けたひな形の中身」を見る |
| ゲームで取っておいた見た目をプロジェクトに入れる | シナリオエディタの上の「見た目…」で選んで「プロジェクト設定に書く」 |
| 二つのひな形の違いを片付けの前に見る | 「片付け…」の「二つを比べる」に印を付け、ひな形に二つ印を付ける |
| ひな形をどこで使ったか見る | 「ひな形…」の窓の「最後に使った場所」 |
| 取っておいた見た目の名前を変える・消す | 「見た目…」で選んで「名前を変える」「消す」（「一つ戻す」で一つ戻せる） |
| ひな形がいつもの始まりとどう違うか見る | 「ひな形…」の「比べる：」で「いつもの始まり（ひな形なし）」 |
| ひな形を前に使った場所からもう一度動かす | 「ひな形…」の窓の「そこから動かす」、または「実行：」の一覧を右クリック |
| ひな形で足し忘れた変数がないか見る | 「比べる：」で「いつもの始まり」を選び、下の薄い「ひな形にない変数」を見る |
| いまのプロジェクト設定の見た目を取っておく | 「見た目…」で名前を書いて「いまの設定を取っておく」 |
| 足し忘れた変数をひな形に入れる | 「いつもの始まり」と比べ、薄い「ひな形にない変数」の名前を押して保存 |
| ひな形を別の組へ移す | 「実行：」の一覧を右クリックして「組を変える…」 |
| 取っておいた二つの見た目の違いを見る | 「見た目…」で一つ選び、「比べる：」でもう一つを選ぶ |
| ひな形にない変数をまとめて足す | 薄い行の終わりの「［全部足す］」を押して保存 |
| 比べている見た目の一つのキーだけをそろえる | 違う行を押す（右の値が左へ写る。「一つ戻す」で戻せる） |
| 比べている見た目を丸ごとそろえる | 「［全部写す］」（「一つ戻す」で一度に戻せる） |
| ほかのひな形の値をこのひな形に取り込む | 「比べる：」で相手を選び、違いの行か「［全部写す］」を押して保存 |
| 写した・足したのをやめる（保存前） | ひな形の窓の「写す前に戻す」 |
| 読み込むひな形がどの組に入るか見る | 「読み込む…」でファイルを選ぶと、一覧に「［組：…］」が出る |
| 片付けながら二つのひな形の値をそろえる | 「二つを比べる」で違いの行の「← 左へ」か「右へ →」（元に戻せる） |
| 二つのひな形をまるごとそろえる | 片付けの「二つを比べる」で「［← 全部左へ］」か「［全部右へ →］」（一度で元に戻せる） |
| 読み込むひな形を一つの組にまとめる | 「読み込む…」の「読み込む組」で組（または新しい組）を選ぶ |
| 読み込む前にファイルのひな形の中身を見る | 読み込む窓の行にマウスを当てる（同じ名前があればいまの中身も出る） |
| ひな形の違いをたくさん一度に見る | ひな形の窓を下へ広げる（違いの欄が伸びる） |
| ひな形の窓をキーボードで使う | Ctrl+Enter で保存、Ctrl+Z で写す前に戻す、Esc でやめる |
| 全部のテンプレートで画面がはみ出さないか確かめる | 画面のテストに -- /tmp/shots --review を付けて動かし、/tmp/shots/index.html をブラウザで開く |
| デバッグのお知らせをゲームの画面の外に出す | プロジェクト設定 debug.notice_style の layer を window に（auto なら狭い画面だけ。コンソールで noticestyle layer window） |
| 片付けで写した・消したのを戻す | 片付けの窓で Ctrl+Z（やり直すは Ctrl+Y） |
| キーボードで読み込む | 読み込む窓で Ctrl+Enter |
| 片付け・読み込むの一覧をたくさん一度に見る | 窓を下へ広げる（一覧が伸びる） |
| 長くて切れたひな形の名前を全部見る | 一覧の行にマウスを当てる（説明に全文と中身が出る） |
| 組の並びごとひな形をほかのプロジェクトへ運ぶ | 「書き出す…」で書き出し、相手のプロジェクトで「読み込む…」（新しい組は元の並びの順に終わりへ） |
| お知らせの見た目をいくつか見比べる | `noticestyle game fg 9` → `noticestyle game keep あお` のように取っておき、`noticestyle game next` で切り替える |
| 遊ぶ人が見るお知らせの見た目を試して決める | デバッグコンソールで `noticestyle game fg 12` などを試し、よければ `noticestyle game save` |
| しばらく使っていないひな形を片付ける | 「実行：」の「片付け…」で日数を決め、印を付けて「この組に寄せる」か「消す…」 |
| デバッグのお知らせの見た目を試して決める | デバッグコンソールで `noticestyle fg 11` などを試し、よければ `noticestyle save` |
| 組の中のひな形ですぐ試す | 「組…」の窓の「この組のひな形で：」で選んで「▶ 実行」 |
| しばらく使っていないひな形を探す | 「実行：」の一覧の〔3日前〕〔未使用〕などを見る |
| コンソールで切り替えたお知らせを設定に残す | デバッグコンソールで `notice save`（エディタに戻るとプロジェクト設定に書かれる） |
| よく使う組を上に並べる | 「組…」の窓で組を選び「↑ 上へ」 |
| ひな形を別の組へ移す・組から外す | 「組…」の窓の下の一覧で印を付け外しして「この中身にする」 |
| 試しているあいだだけお知らせを止める | デバッグコンソールで `notice reload off`（全部なら `notice off`、戻すなら `notice reset`） |
| 組の名前を変える・組ごと書き出す・消す | 「実行：」の「組…」の窓で組を選んで操作する |
| 「読み直しました」などのお知らせを出さない | プロジェクト設定の debug に `"notices": {"reload": false}`（種類：run_from・pre_set・reload・editor・preset・auto_reload） |
| ひな形が多いとき探す | 「実行：」の横の「絞り込み」に名前か組の一部を書く |
| 上書きで読み込む前に、何が変わるか見る | 読み込む窓で「中身が違うものは上書きする」に印を付けると、窓の下に違いが出る |
| 「先に設定」のお知らせを目立たせる | プロジェクト設定の debug に `"pre_set_style": {"fg": 10, "border": 12}` など |
| 値を少しずつ変えたひな形をいくつも作る | ゲームの一覧で「送っても閉じない」に印を付け、値を変えては「送る」（名前は次の番号になる） |
| 「先に設定」のお知らせを別の場所に出す | プロジェクト設定の debug に `"pre_set_position": "bottom_left"` など |
| 「先に設定」のお知らせを出さない | プロジェクト設定の debug に `"pre_set_notice": false`（ログも出さないなら `"pre_set_log": false`） |
| まだ書かれていない変数をひな形に入れる | ゲームの「ひな形に」の一覧の下で、種類・名前・値を書いて「足す」 |
| ゲームの値を少し変えてひな形にする | 「ひな形に」の一覧で値の欄・個数を書きかえてから「送る」 |
| たくさんの変数から選んでひな形にする | ゲームの「ひな形に」の一覧の「絞り込み」に名前の一部を書く |
| 「もし」や選択肢の中の行から試す | 会話の画面でその行を選び「▶ ここから実行」（条件は見ずにその中から） |
| よく試す実行を残しておく | 「履歴 ▾」→「★ お気に入りの印…」で印を付ける（上に並び、消しても残る） |
| 前に試した実行をもう一度 | シーンの画面の「履歴 ▾」から選ぶ |
| 会話や Ink のノットの中からエディタで開く | 会話・ノットの中で「エディタで開く」（`edit`）。その会話・ノットの行を開く |
| 読み直したときのお知らせに出すファイルの数を変える | `"debug": {"notice_files": 5}`（0 で名前を出さない） |
| 「ID の確認」の結果をファイルにする | 一覧の上の「書き出す…」（.csv か .txt） |
| ゲームを動かして見つからない ID を見る | デバッグ実行でデバッグコンソール（F12）を開き `ids` |
| 上限で消えるお知らせを、すっと消す | `"notice_style": {"max": 3, "overflow": "fade"}` |
| お知らせをひとつだけ別の位置に出す | `{"notice.show": {"text": "…", "position": "bottom"}}`（`notices` の項目にも書ける） |
| ログの切り替えの文言を変える | `"notice_style": {"log_labels": {"all": "ぜんぶ", "text": "ぶんしょう", "notice": "おしらせ"}}` |
| エディタで打ち間違いの ID を見つける | 見つからない ID の項目は赤字になり、項目名にマウスを置くと理由が出る |
| エディタで一覧にない ID を書く | 一覧の最後の「（手で入力…）」を選ぶ |
| 既読・チャプター選択などの記録を消して試す | デバッグコンソール（F12）で `read clear`、`flow clear`、`openings clear`、`progress clear` |
| 特典が開いたことを知らせる・知らせない | 既定で出ます。文言は `"extras": {"notify_text": "…"}`、出さないなら `"notify": false` |
| タイトルの「おまけ」に開いた数を出す | `"extras": {"title_count": true, …}`（タイトルのシーンなら文章に `{sys.extras_opened} / {sys.extras_total}`） |
| おまけ・エンディングの記録を消して試す | デバッグコンソール（F12）で `extras clear`、`extras unlock`、`endings clear` |
| エディタでタイトル・おまけを設定する | シナリオエディタのゲームの一覧の左の「タイトル」「おわり・おまけ」「システム」のタブ（素材やシーンの ID は一覧から選べる） |
| エディタで「おまけを開く」などの手順を書く | 「＋ 手順を追加」→「演出・システム（出力イベント）」、下の欄でイベントの名前を選び、引数をフォームで書く |
| シナリオを画面で書く | 「adv80s」画面の左上で「シナリオエディタ」。シナリオ → チャプター → シーンのカードを開き、シーンの「コマンドを作成」「セリフを作成」 |
| シナリオ・シーンを複写する | シナリオエディタのカードを右クリック →「複写…」（ID と中の参照は付け替わる）、「別のシナリオ・チャプターへ複写…」 |
| 条件式を候補つきで書く | シナリオエディタの手順の「式…」、設定のフォームの条件の項目の「式…」、または一覧の左下の「式エディタ…」 |
| シーン・会話の ID を変える | シナリオエディタのカードを右クリック →「ID を変更…」（参照している手順も書き換わる） |
| エディタでの操作を取り消す | シナリオエディタの右上の「元に戻す」（Ctrl+Z）・「やり直す」（Ctrl+Shift+Z） |
| ゲームを始めるシナリオを決める | シナリオエディタのゲームの一覧の「開始シナリオ」 |
| もの・出口のクリックする範囲を決める | シーンの「範囲を絵で決める…」で、背景の上をドラッグ |
| 古い1ファイルのシナリオをエディタの形にする | 「フォルダの外のファイル」のカードを右クリック →「シナリオのフォルダの形に移す…」 |
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
