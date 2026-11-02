// 段階1のサンプルに足した、Ink で書いた会話の場面。
// 変換：inklecate -o tests/stage1/scenario/stage1_talk.ink.json tests/stage1/scenario/src/stage1_talk.ink
// JSON のシナリオから {"ink": "window_talk"} で呼ばれ、終わると JSON に戻る。

EXTERNAL has_item(id)
EXTERNAL event(type, args)

// JSON のシナリオと同じ名前の変数は、値が同期する
VAR met_ayumi = false
VAR knocks = 0
VAR saw_lights = false

=== window_talk ===
@ayumi まどの そと？
{not met_ayumi:
    @ayumi ……しらない ひとには はなせない。
    -> DONE
}
@ayumi あなたなら はなしても いいかな。
- (opts)
* [あかりの ことを きく]
    @ayumi よるに なると、 むこうの やかたに あかりが ともるの。
    @ayumi だれも すんでいない はずなのに。
    ~ saw_lights = true
    ~ event("notebook.add", "\{\"id\": \"lights\", \"category\": \"てがかり\", \"title\": \"やかたの あかり\", \"body\": \"よるに なると、 むこうの やかたに あかりが ともるらしい。\"\}")
    -> opts
* {has_item("key")} [かぎを みせる]
    @ayumi その もよう…… やかたの もんと おなじだわ。
    -> opts
* {knocks >= 3} [ドアを なんども たたいた ことを あやまる]
    @ayumi ふふ。 すこし びっくりしたけどね。
    -> opts
+ [はなしを おえる]
    {saw_lights:
        @ayumi あの やかたに、 なにか あるのかも しれない。
    - else:
        @ayumi また なにか あったら きいてね。
    }
    -> DONE

// Inky で遊ぶときの代わりの関数（ゲームでは adv80s の外部関数が使われる）
=== function has_item(id) ===
~ return false

=== function event(type, args) ===
~ return
