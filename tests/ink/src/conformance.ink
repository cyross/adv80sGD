// adv80s の Ink 実行部分の確かめ用（inklecate の出力と比べる）
EXTERNAL has_item(id)
EXTERNAL fallback_fn(x)
VAR met = false
VAR coins = 3
VAR target = -> shop
CONST LIMIT = 5

Hello <>
world! # greeting
-> start

=== start ===
{met: Again.|First time.}
~ met = true
{&Cycle A|Cycle B}
{Once one|Once two|Once three}
{stopping 1|stopping 2}
* [Ask about the key #intent:ASK:ayumi] "The key?" # q
  She nods.
  -> start
* Leave <>
  quietly.
  -> math
+ {met} [Sticky]
  Sticky chosen.
  -> start

=== math ===
~ temp x = 7
~ temp y = 2
{x / y} {x % y} {x * y - 1} {7.0 / 2} {x > y and not met} {"ab" + "cd"} {"hello" ? "ell"}
~ double(x)
x is {x}.
{add(1, 2)} {fallback_fn(4)}
{LIMIT} {coins >= LIMIT}
~ coins = add(coins, 2)
Coins: {coins}
-> tun ->
After tunnel. Visits start {start} turns {TURNS_SINCE(-> start)}.
-> threads

=== function add(a, b) ===
~ return a + b

=== function double(ref v) ===
~ v = v * 2

=== function fallback_fn(x) ===
~ return x * 10

=== tun ===
Inside tunnel.
->->

=== threads ===
<- side
* Main option
  Main picked.
- (gather) Gathered.
-> stitches.second

= unused
Never.
-> DONE

=== side ===
* Side option
  Side picked.
  -> stitches.second

=== stitches ===
= first
First stitch.
-> DONE
= second
Second stitch {second}.
-> var_divert

=== var_divert ===
~ target = -> fallback
-> target

=== fallback ===
* Visible once
  Saw visible.
  -> fallback
* ->
  Auto fallback.
  -> nested

=== nested ===
* Outer A
  ** Inner A1
     A1.
  ** Inner A2
     A2.
  -- Inner gather.
* Outer B
  B.
- Outer gather. {has_item("key"): Has key.|No key.}
-> END

=== shop ===
Shop.
-> END

=== function has_item(id) ===
~ return false
