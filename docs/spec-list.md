# adv80sGD 仕様一覧

最終更新：2026-11-02

adv80sGD（段階10）で使えるものの一覧です。引数や書き方の詳しい説明は「[リファレンスマニュアル](reference.md)」、設計の理由は「[仕様書](../SPEC.md)」にあります。

## 出力イベント

出力イベントは 38 種類です。「状態」の列が○のものは、画面ではなくゲームの状態を変えます（Core が記録する）。

| 分類 | イベント | 既定の wait | 状態 |
| --- | --- | --- | --- |
| 文章 | `text.show`、`text.append` | `click` |  |
| 文章 | `text.clear` | `none` |  |
| 画像 | `image.show`、`image.hide` | 演出あり `end`、なし `none` |  |
| 画像 | `effect.play` | `end` |  |
| 画像 | `layout.set` | `end` |  |
| スプライト | `sprite.show`、`sprite.hide` | 演出あり `end`、なし `none` |  |
| スプライト | `sprite.set` | `duration` あり `end`（繰り返しは `none`） |  |
| スプライト | `sprite.anim`、`sprite.clear` | `none` |  |
| スプライト | `sprite.effect` | `end` |  |
| カーソル | `cursor.set` | `none` |  |
| 動画 | `video.play` | `end`（`loop` なら `none`） |  |
| 動画 | `video.stop` | 演出あり `end`、なし `none` |  |
| 音 | `bgm.play`、`bgm.stop`、`se.play`、`voice.play` | `none` |  |
| 状態 | `state.set`、`item.add`、`item.remove` | `none` | ○ |
| 進行 | `scene.goto` | `end` | ○ |
| 進行 | `wait` | その秒数 |  |
| 進行 | `group` | `end` |  |
| 進行 | `choice.show`、`input.request` | `input` |  |
| 進行 | `game.end` | 終了 |  |
| 入力 | `verbs.update`、`hotspots.update`、`input.mode` | `none` | ○ |
| モダン機能 | `notebook.add`、`objective.set`、`hint.set`、`flow.mark` | `none` | ○ |
| モダン機能 | `checkpoint` | `none` |  |
| システム | `template.switch` | `end` |  |
| システム | `save.request` | `input` |  |

- `wait` の値：`none`、`click`、`end`、`input`、秒数。書き換えはイベント自身 → シナリオの `event_defaults` → プロジェクトの `event_defaults` の順。
- 自作のイベントは `x.名前`。知らないイベントは警告して無視します。
- 内部で使うもの（画面には届かない）：`state.mark`、`adapter.enter`、`adapter.exit`。

## 動詞

標準の動詞は 11、拡張の動詞は 8 です。拡張の動詞はプロジェクト設定の `verbs` に書いたものだけ使えます。表示名は日本語の辞書のものです。

| 動詞 | 表示名 | 種類 | スロット（助詞） | 反応がないとき |
| --- | --- | --- | --- | --- |
| `LOOK` | みる | 標準 | target?（を） | とくに かわった ところは ない。 |
| `EXAMINE` | しらべる | 標準 | target?（を） | とくに かわった ところは ない。 |
| `TAKE` | とる | 標準 | target（を） | とれない。 |
| `USE` | つかう | 標準 | target：アイテム（を）、with?（に、で、へ） | ここでは つかえない。 |
| `TALK` | はなす | 標準 | target：人物（と、に） | へんじが ない。 |
| `ASK` | きく | 標準 | target：人物（に）、topic（を、について） | なにも こたえない。 |
| `MOVE` | いく | 標準 | target：シーン（へ、に） | そこへは いけない。 |
| `OPEN` | あける | 標準 | target（を）、with?：アイテム（で） | あかない。 |
| `CLOSE` | しめる | 標準 | target（を） | しめられない。 |
| `ITEMS` | アイテム | 標準 | なし | 持ち物の一覧 |
| `CHOOSE` | — | 標準（内部） | target：選択肢 | 選択肢を選んだとき |
| `GIVE` | わたす | 拡張 | with：アイテム（を）、target：人物（に、へ） | うけとって もらえない。 |
| `SHOW` | みせる | 拡張 | with：アイテム（を）、target：人物（に、へ） | はんのうが ない。 |
| `PUSH` | おす | 拡張 | target（を） | びくとも しない。 |
| `PULL` | ひく | 拡張 | target（を） | びくとも しない。 |
| `HIT` | たたく | 拡張 | target（を） | いたいだけだ。 |
| `CALL` | よぶ | 拡張 | target：人物（を） | へんじが ない。 |
| `THINK` | かんがえる | 拡張 | なし | なにも おもいつかない。 |
| `WAIT` | まつ | 拡張 | なし | しばらく まった。 |

`?` は省けるスロットです。必須のスロットが足りないときは、「なにを …」と聞き返します。

## 文章の装飾タグと条件式

**装飾タグ**（このほか Godot の `[b]`、`[i]`、`[u]`、`[s]`、`[color]` も使える）

| タグ | 動き | 対応 |
| --- | --- | --- |
| `{名前}`、`[var=名前]` | 変数・定数の値 | ○ |
| `[pal=n]…[/pal]` | パレットの色 | ○ |
| `[ruby=よみ]…[/ruby]` | ルビ | ○ |
| `[em]…[/em]` | 傍点 | ○ |
| `[blink]…[/blink]` | 点滅 | ○ |
| `[p]`、`[p=秒]` | クリック待ち（秒数で自動） | ○ |
| `[page]`、`[page=秒]` | 次のページへ（秒数で自動） | ○ |
| `[w=秒]` | 待つ | ○ |
| `[se=ID]` | 効果音 | ○ |
| `[speed=n]…[/speed]` | 文字の速さ | ○ |
| `[instant]…[/instant]` | 一度に表示 | ○ |
| `[gaiji=ID]` | 外字（素材の画像を1文字として入れる） | ○ |

**条件式の演算子**：`and`（`&&`）、`or`（`||`）、`not`（`!`）、`==`、`!=`、`<`、`<=`、`>`、`>=`、`( )`。計算式は `+`、`-`、`*`、`/`、`%`。JSON の形は `all`、`any`、`not`、`var` と `eq`、`ne`、`lt`、`le`、`gt`、`ge`、`in`。

**組み込みの名前**

| 名前 | 意味 |
| --- | --- |
| `has(id)` | アイテムを持っている |
| `count(id)` | アイテムの数 |
| `scene` | 今のシーン |
| `visited(シーン)` | 訪れた |
| `talked(会話)` | 会話を見た |
| `read(行)` | 行を読んだ |
| `chosen(選択肢, 項目)` | その項目を選んだ |
| `preset`、`group` | 画面プリセット、グループ |
| `feature(機能)` | モダン機能が有効 |

**変数の操作（`state.set` の `op`）**：`set`、`add`、`sub`、`mul`、`div`、`mod`、`min`、`max`、`toggle`。変数の型：`bool`、`int`、`float`、`string`。

## 演出とフィルター

**切り替え演出（`transition`）**　既定の長さは 0.5 秒

| 名前 | 動き | 主な引数 |
| --- | --- | --- |
| `cut` | すぐに切り替える | — |
| `fade` | 重ねながら切り替える | `duration` |
| `fade_color` | 単色を挟む | `color`、`duration` |
| `wipe` | 一方向から塗り替える | `direction`、`softness` |
| `blinds` | すだれ状 | `direction`、`count` |
| `line_draw` | 1行ずつ描く | `speed`（行/秒）、`direction` |
| `interlace` | 1行おきに描く | `duration` |
| `plane_draw` | 色の面ごとに描く | `order`、`duration` |
| `mosaic` | モザイク | `max_size`、`duration` |
| `dissolve` | 点が入れ替わる | `pattern`、`duration` |
| `blocks` | ブロック単位 | `size`、`order`、`duration` |
| `iris` | 円形に開く | `center`、`duration` |
| `mask` | ルール画像 | `image`、`softness`、`duration` |

**画面効果（`effect.play`）**：`flash`（`color`、`count`）、`shake`（`axis`、`amplitude`）、`invert`、`tint`（`color`、`amount`）、`palette_cycle`（`range`、`speed`）、`scroll`（`direction`、`distance`）、`zoom`（`scale`、`center`）、`raster`（`amplitude`、`wavelength`、`speed`）

**スプライトの効果（`sprite.effect`）**

| 名前 | 動き | 続くか |
| --- | --- | --- |
| `flash` | 一瞬光る | 一度きり |
| `shake` | 揺れる（`amount`） | 一度きり |
| `blink` | 点滅する | 一度きり |
| `mono` | モノクロ | `none` まで |
| `sepia` | セピア | `none` まで |
| `silhouette` | 影（`color`） | `none` まで |
| `mosaic` | モザイク（`cells`） | `none` まで |
| `.gdshader` のパス | 自作のシェーダー（`params` が引数） | `none` まで |

**スプライトの項目**：`x`、`y`、`anchor`（`top_left`、`top`、`top_right`、`left`、`center`、`right`、`bottom_left`、`bottom`、`bottom_right`）、`z`、`scale`、`rotation`、`opacity`、`flip`（`h`、`v`、`hv`）、`blend`（`normal`、`add`、`multiply`）、`tint`、`visible`、`smooth`。動きの `ease`：`linear`、`in`、`out`、`in_out`。

**フィルター（テンプレートの `filters`）**：`scanline`（走査線）、`reduce`（減色）、`dither`（ディザ）、`bleed`（にじみ）、`crt`（曲面と周辺の暗さ）、`rgb_mask`、`mono`（単色モニター）、`lcd`（液晶の網目）、`aspect`（縦横比補正）。`mode` は `default`、`append`、`replace`、`none`。

## 機種プリセットと同梱テンプレート

全 26 機種にテンプレートが1つずつあります。画面の形の「下」は絵の下に文章とコマンド（入力欄あり）、「右」は絵の右にコマンド、下に文章（コマンド選択だけ）です。

| グループ | 機種 ID | 代表モード | テンプレート | 画面の形 | カーソルの絵 |
| --- | --- | --- | --- | --- | --- |
| `pc80` | 88 | 640x200（8色） | `pc88_classic` | 下 | — |
| `pc80` | 98 | 640x400（16色） | `pc98_classic` | 下 | — |
| `pc80` | SX1 | 640x200（8色） | `sx1_classic` | 下 | — |
| `pc80` | SX1T | 640x400（8色） | `sx1t_classic` | 下 | — |
| `pc80` | SX1TZ | 320x200（4096色） | `sx1tz_classic` | 下 | — |
| `pc80` | F7 | 640x200（8色） | `f7_classic` | 下 | — |
| `pc80` | F77A | 320x200（4096色） | `f77a_classic` | 下 | — |
| `pc80` | MX | 256x192（16色） | `mx_classic` | 右 | — |
| `pc80` | MX2 | 256x212（16色） | `mx2_classic` | 右 | — |
| `pc80` | M2P | 256x212 | `m2p_classic` | 右 | — |
| `pc90` | X68K | 768x512（16色） | `x68k_classic` | 下 | ○ |
| `pc90` | FTNS | 640x480（256色） | `ftns_classic` | 下 | ○ |
| `pc90` | MTR | 256x212 | `mtr_classic` | 右 | ○ |
| `pc90` | VGA | 640x480（16色） | `vga_classic` | 下 | ○ |
| `pc90` | WIN | 640x480（256色） | `win_classic` | 下 | ○ |
| `console` | FC | 256x240 | `fc_classic` | 右 | ○ |
| `console` | PCE | 256x224 | `pce_classic` | 右 | ○ |
| `console` | SFC | 256x224 | `sfc_classic` | 右 | ○ |
| `console` | PS1 | 320x240 | `ps1_classic` | 右 | ○ |
| `console` | PS2 | 640x480 | `ps2_classic` | 右 | ○ |
| `handheld` | GB | 160x144（4階調） | `gb_classic` | 右 | ○ |
| `handheld` | GBC | 160x144 | `gbc_classic` | 右 | ○ |
| `handheld` | GBA | 240x160 | `gba_classic` | 右 | ○ |
| `modern` | HD | 1280x720 | `hd_modern` | 下 | ○ |
| `modern` | FHD | 1920x1080 | `fhd_modern` | 下 | ○ |
| `modern` | 4K | 3840x2160 | `4k_modern` | 下 | ○ |

- 画面モードを選ぶときは `機種ID.モード名`（例 `X68K.512x512`、`98.640x400_8`）。モードの一覧は仕様書 7.1。
- 家庭用ゲーム機・携帯機・WIN・現代の機種は、窓の枠を画像（9分割）で描きます。

## 素材

| 種類 | 既定のフォルダ | 使える形式 | マニフェストの属性 |
| --- | --- | --- | --- |
| `image` | `bg/`、`chara/`、`cg/`、`ui/`、`sprite/` | PNG、JPG、WebP、BMP、SVG、TGA、GIF、APNG、MNG、MAG | `variants`、`by_preset`、`pivot`、`region`、`color_key`、`grid`、`anims`、`hotspot` |
| `bgm` | `bgm/` | WAV、OGG、MP3 | `loop_start`、`volume` |
| `se` | `se/` | WAV、OGG、MP3 | `volume` |
| `voice` | `voice/` | WAV、OGG、MP3 | `volume` |
| `font` | `font/` | TTF、OTF | — |
| `video` | `movie/` | OGV（Ogg Theora） | — |
| `shader` | `shader/` | gdshader | — |

- **ファイル名**：英小文字、数字、`_`、`-`。`@` の後ろは差分名。`_` か `.` で始まるものは無視。
- **機種別の差し替え**：`presets/<機種 ID かグループ>/<種類フォルダ>/…`。
- **再生できない動画**（MP4、M4V、WebM、AVI、MOV、MKV、MPG、MPEG、WMV、FLV）は素材に入れず、警告 `ASSET_UNSUPPORTED`。
- **同梱の素材**（アドオンの `assets/`）：フォント `pixelmplus10`、`pixelmplus12`、`tekuplus` とそれぞれの `_bold`、カーソル画像 `cursor_arrow`、`cursor_look`、`cursor_talk`、`cursor_hand`、`cursor_exit`、`cursor_wait`、`cursor_next`。
- **重ねる順番**：アドオン → プロジェクトの `asset_roots` → テンプレート → シナリオ（後が優先）。

## 機能、設定、操作

**モダン機能（`features` のキー）**

| キー | 機能 | 既定 |
| --- | --- | --- |
| `message_log` | メッセージログ | オン |
| `hint` | 段階式ヒント | オフ |
| `objective` | 目的の確認 | オフ |
| `hotspot` | 調べられる場所の表示 | オフ |
| `tried_marks` | 試したコマンドの表示 | オフ |
| `autosave` | オートセーブ | オン |
| `skip` | 既読スキップ | オン |
| `auto_advance` | オート送り | オン |
| `rewind` | 巻き戻し | オフ |
| `flowchart` | フローチャート | オフ |
| `chapter_select` | チャプター選択 | オフ |
| `notebook` | 手帳 | オフ |
| `era_switch` | 旧表示と新表示の切り替え | オフ |
| `readable_font` | 読みやすいフォント | オフ |
| `text_options` | 文字の大きさ・色・窓の濃さ | オン |
| `tts` | 読み上げ | オフ |
| `gamepad` | コントローラー操作 | オン |
| `touch` | タッチ操作 | オン |
| `filter_toggle` | フィルターの無効化 | オン |

**プレイヤー設定**（`user://adv80s_settings.json`）

| キー | 中身 | 既定 |
| --- | --- | --- |
| `text_speed` | 文字速度の倍率 | 1.0 |
| `auto_delay`、`auto_per_char` | オート送りの待ち（秒）と1文字ごとの足し | 1.2、0.04 |
| `skip_unread` | 未読もスキップ | false |
| `filters` | フィルターを使う | true |
| `bgm_volume`、`se_volume`、`voice_volume` | 音量（0〜1） | 1.0 |
| `voice_stop_on_advance` | 次へ進むとボイスを止める | true |
| `text_size`、`text_color`、`window_opacity` | 文字の大きさ、色（-1 でテンプレート）、窓の濃さ | 1.0、-1、1.0 |
| `features` | 機能のオン・オフ | — |

**キー操作**

| キー | 動き |
| --- | --- |
| F1、右クリック、ゲームパッドの Start | メニュー |
| F2 | オート送り |
| F3、Ctrl（押している間） | スキップ |
| F4 | ログ |
| F5、F9 | クイックセーブ、クイックロード |
| F6 | 調べられる場所の表示 |
| Esc | セーブ・ロードの画面 |
| F11（デバッグ実行時のみ） | シーングラフの表示・閉じる |
| F12（デバッグ実行時のみ） | デバッグコンソールの表示・再開 |

**コマンド方式（`inputs.enabled`）**

| 値 | 方式 | 操作 |
| --- | --- | --- |
| `select` | コマンド選択 | 動詞 → 対象を一覧から選ぶ |
| `parser` | コマンド入力 | 文字で入力する |
| `icon` | アイコン選択 | 動詞をアイコンで選ぶ |
| `click` | 画面選択 | 絵の中の対象をクリックする（動詞は選んだもの、なければ `click_verb`） |
| `verb_click` | 動詞リスト＋クリック | 出したままの動詞を選び、絵の中の対象を選ぶ |
| `verb_cursor` | アイコン切り替え | 右クリックでカーソルの動詞を切り替え、対象をクリックする |
| `context` | コンテキスト | 動詞を選ばない。対象に合った動詞を実行する。右クリックは「みる」 |

絵の中の対象を選ぶ方式の操作：右クリック、タッチでは長押し（やめる／次の動詞／みる）、Tab・Shift+Tab とゲームパッドの L・R（調べられる場所を順に選ぶ）、Esc（選びかけをやめる）。

**入力機器（プロジェクト設定 `input_devices`）**：`keyboard`、`mouse`、`gamepad`、`touch`。

**セットアップ画面が作るもの**：`adv80s.project.json`（`game_id`、`title`、`template`、`inputs.enabled`、`input_devices`）、`game/assets/`（`bg`、`chara`、`sprite`、`ui`、`bgm`、`se`、`voice`、`font`、`movie`、`manifest.json`）、`game/scenario/main/_scenario.scenario.json`（シナリオ共通の設定）と `chapter1.scenario.json`（最初のチャプター）、`game/main.tscn`。プロジェクト設定の `ext.adv80s_editor.scenario_root` にシナリオのフォルダを書く。

**シナリオエディタ**（「adv80s」画面の種類「シナリオエディタ」）：

| 画面 | できること |
| --- | --- |
| フォルダ | シナリオのフォルダを決める（セットアップで決めていれば出ない） |
| ゲーム | ゲーム共通の設定（プロジェクト設定）とシナリオのカード |
| シナリオ | シナリオ共通の設定（`_scenario.scenario.json`）とチャプターのカード |
| チャプター | チャプターの設定（`<ID>.scenario.json`）とシーンのカード |
| シーン | シーンの設定（背景、もの、出口、スプライト）、セリフの一覧（JSON・Ink）、コマンドの一覧 |
| セリフエディタ | JSON の会話（手順のエディタ）、Ink（`.ink` を書いて inklecate でコンパイル） |
| コマンドエディタ | 対象（入ったとき、初めて入ったとき、シーン、もの、出口）と動詞、手順 |
| 式エディタ | 条件式と変数の計算を複数行で書く。名前の候補、その場の確認 |

- 設定のタブ：初期設定・変数・コマンド・セリフ・アセット・その他。「アセットエディタ…」でマニフェストへ。
- カードの操作：ダブルクリック（Enter）で開く、Ctrl・Shift+クリックで複数選択、右クリックで 開く・名前を変更（F2）・新規作成・複写…（いくつ作るか）・別のシナリオ（チャプター）へ複写…・削除（Delete。ファイルはごみ箱へ）。
- 手順の種類：地の文、台詞、条件分岐、選択肢、選択肢の項目、変数の計算、移動、会話の呼び出し、Ink のノット、そのほか（JSON）。

**マウスカーソルの種類**：`default`、`look`、`talk`、`take`、`use`、`exit`、`wait`、`next`、`text`（自作の種類も書ける）。OS 標準の形：`arrow`、`pointing_hand`、`cross`、`help`、`move`、`busy`、`ibeam`、`wait`。

## 診断コード

「確認」は validate とマニフェストの生成で出るもの、「実行」は遊んでいるとき（開発中）に警告として出るものです。

| コード | いつ | 意味 |
| --- | --- | --- |
| `SCHEMA_VIOLATION` | 確認・実行 | 書き方がスキーマに合わない、必要な引数がない |
| `UNKNOWN_KEY` | 確認 | 知らない項目（書き間違いのことが多い） |
| `JSON_PARSE` | 確認 | JSON として読めない |
| `UNKNOWN_VARIABLE` | 確認・実行 | 宣言も変更もしていない変数を読んでいる |
| `CONST_WRITE` | 確認（エラー）・実行 | 定数を書き換えようとしている |
| `COND_SYNTAX` | 確認・実行 | 条件式・計算式を読めない |
| `MISSING_TARGET` | 確認・実行 | 行き先のシーン・会話・話者・スプライト・アニメーションがない |
| `UNREACHABLE` | 確認（情報） | どこからも来られないシーン |
| `DUPLICATE_ID` | 確認 | ID の重複、プロジェクト設定と同じ名前の変数・定数 |
| `INVALID_ID` | 確認 | ID に `/` を使っている |
| `ASSET_NOT_FOUND` | 確認（エラー）・実行 | 素材がない（実行中は `missing_asset` に従う） |
| `ASSET_UNSUPPORTED` | 確認・実行 | 読めない形式（mp4 などの動画、MNG の未対応の命令、MAKI02 でない MAG） |
| `VARIANT_NOT_FOUND` | 実行 | 差分がないので既定のファイルを使う |
| `NO_DEFAULT_FILE` | 確認 | 機種別の差し替えだけで既定のファイルがない |
| `NAMING` | 確認 | ファイル名に英小文字・数字・`_`・`-` 以外を使っている |
| `UNKNOWN_FOLDER` | 確認 | `presets/` の下の形が違う |
| `MANIFEST_STALE` | 確認 | `manifest.auto.json` が古い |
| `MANIFEST_MISSING` | 実行 | `manifest.auto.json` がないのでフォルダを読んで補う |
| `TOOL_ERROR` | 確認 | 書き出しに失敗した |
| `UNKNOWN_VERB` | 確認・実行 | 知らない動詞 |
| `SLOT_MISMATCH` | 確認 | `slot_mode: standard` で target・with 以外のスロット |
| `UNKNOWN_TRANSITION`、`UNKNOWN_FILTER` | 実行 | 知らない切り替え演出（`cut` にする）・フィルター |
| `TEXT_DENIED` | 実行 | テンプレートで禁止したタグ |
| `FEATURE_DEPENDENCY` | 確認・実行 | 依存が満たせず機能を無効にした |
| `CHOICE_PENDING`、`CHOICE_NONE`、`CHOICE_UNKNOWN` | 実行 | 選択肢の待ち方の食い違い |
| `BUSY` | 実行 | 実行中で受け付けられない（セーブなど） |
| `NO_KEY` | 確認・実行 | セーブの鍵がない（開発中は仮の鍵） |
| `TAMPERED`、`KEY_MISMATCH` | 実行 | セーブが改ざんされている、鍵が違う |
| `GAME_MISMATCH` | 実行 | ほかのゲーム（ゲームIDが違う）のセーブデータ |
| `INK_LOAD`、`INK_VERSION`、`INK_UNSUPPORTED` | 確認 | Ink の JSON が読めない、版が合わない、読めない部分がある |
| `INK_LIST` | 確認 | `LIST` を使っている（未対応） |
| `INK_EXTERNAL` | 確認 | ない外部関数を使っている |
| `INK_MISSING_KNOT` | 確認 | JSON の `{"ink"}` の行き先のノットがない |
| `INK_TAG`、`INK_RUNTIME` | 実行 | タグの JSON が読めない、Ink の実行中のエラー |

## まだのもの

仕様書にあるが、いまは実装していないものと制限です。

| 対象 | いまの動き |
| --- | --- |
| Ink の `LIST` | 未対応（validate が `INK_LIST`） |
| 当時の画像形式 | MAG は読む、PI など他形式は読まない（PNG などに変換して置く）。200ライン用の MAG も縦に伸ばさない |
| mp4 などの動画 | 読まない（`.ogv` に変換して置く） |
