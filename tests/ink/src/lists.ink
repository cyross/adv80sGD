// LIST の確かめ用（tests/ink/lists.expected.txt は inklecate -p の出力）
LIST colors = red, (green), blue = 5, yellow
LIST sizes = (small), medium = 3, large
LIST doors = (front), back, cellar
VAR inv = ()
VAR mix = ()
VAR empty_colors = ()
~ SEED_RANDOM(17)
A: {colors} / {sizes} / [{inv}] / {LIST_COUNT(colors)}
~ inv = colors(5)
B: {inv} {LIST_VALUE(inv)} {colors(1)} [{colors(9)}]
~ inv += red
~ inv += yellow
C: {inv} {LIST_COUNT(inv)} {LIST_MIN(inv)} {LIST_MAX(inv)}
~ inv -= blue
D: {inv} {inv ? red} {inv ? blue} {inv !? blue} {inv has yellow} {inv hasnt green}
~ inv += green
E: {inv} {LIST_ALL(inv)} {LIST_INVERT(inv)} {LIST_INVERT(colors)}
F: {LIST_RANGE(LIST_ALL(colors), 2, 5)} {LIST_RANGE(LIST_ALL(colors), green, yellow)} [{LIST_RANGE(inv, 100, 200)}]
~ mix = colors + sizes + large
G: {mix} {LIST_COUNT(mix)} {LIST_MIN(mix)} {LIST_MAX(mix)} {LIST_VALUE(mix)}
H: {mix ^ (red, green, small)} {(red, green) == (green, red)} {(red) != (green)} {(red) < (blue)} {(red, blue) > (green)} {(red, blue) >= (red)} {(red) <= (red, blue)}
I: {red + 1} {blue - 3} [{yellow + 1}] {(red, green) + 1} {LIST_VALUE(yellow)}
J: {not inv} {not empty_colors} {inv && 1} {empty_colors || 0} {inv and empty_colors}
~ empty_colors = colors
~ empty_colors -= colors
K: [{empty_colors}] {LIST_ALL(empty_colors)} {LIST_INVERT(empty_colors)}
~ temp t = (front, cellar)
~ t -= front
~ t += back
~ t += front
L: {t} {LIST_RANDOM(t)} {LIST_RANDOM(t)} {LIST_RANDOM(colors + sizes)} {LIST_RANDOM(LIST_ALL(doors))}
{inv ? red: M: has red|M: no red}
{empty_colors: N: not empty|N: empty}
~ temp n = 0
- (loop)
~ n++
{n <= 6: R{n}: {LIST_RANDOM(LIST_ALL(colors))} {LIST_RANDOM(LIST_ALL(sizes) + LIST_ALL(doors))} -> loop}
-> fn_test

=== fn_test ===
O: {pick(colors)} {pick(inv)} {describe(LIST_ALL(doors))}
P: {"{inv}" + "!"} {inv == (red, green, yellow)} {doors}
~ doors = cellar
~ doors++
Q: [{doors}]
~ doors = front
~ doors++
Q2: {doors} {doors + 1} {LIST_ALL(doors) - doors}
-> END

=== function pick(l)
~ return LIST_MAX(l) + LIST_MIN(l)

=== function describe(x)
{x:
- (front, back, cellar): all doors
- else: some doors
}
