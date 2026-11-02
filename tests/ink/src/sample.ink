// テスト用のサンプル（tests/run_tests.gd の Ink のテストで使う）
EXTERNAL event(type, args)
EXTERNAL has_item(id)
EXTERNAL item_add(id)
VAR met = false
VAR coins = 3

Hello <>
world! # greeting
-> start

=== start ===
{met: Again.|First time.}
~ met = true
* [Ask about the key #intent:ASK:ayumi] "The key?" # intent:ASK
  She nods.
  -> start
* Leave
  Quietly.
  -> END

=== shop ===
# shop_tag
~ coins = add(coins, 2)
Coins: {coins}
~ event("se.play", "\{\"id\":\"knock\"\}")
Visited start {start} times.
{coins > 5:
  Rich.
- else:
  Poor.
}
-> DONE

=== function add(a, b) ===
~ return a + b

=== auto ===
* ->
  Auto.
  -> DONE

=== tun ===
-> inner ->
Back.
-> DONE

=== inner ===
Inside.
->->

=== check ===
{has_item("key"):
  Have key.
  ~ item_add("coin")
- else:
  No key.
}
-> DONE

=== talk ===
# voice:ayumi_key_01
@ayumi Hi there.
Narration. # speaker:ayumi
# bg:hallway
# \{"bgm.play": \{"id": "theme"\}\}
Mood. # custom
-> END
