VAR n = 0
~ SEED_RANDOM(42)
R1: {RANDOM(1,6)} {RANDOM(1,6)} {RANDOM(1,100)} {RANDOM(-5,5)} {RANDOM(0,1000000)}
-> loop

=== loop ===
~ n = n + 1
{n}: {~a|b|c|d|e} {~x|y|z} {RANDOM(1,10)}
{shuffle:
- A
- B
- C
- D
}
{n < 14: -> loop}
-> seeds

=== seeds ===
~ SEED_RANDOM(2147483000)
R2: {RANDOM(1,1000)} {RANDOM(1,1000)} {RANDOM(1,1000)} {~p|q|r|s}
~ SEED_RANDOM(-7)
R3: {RANDOM(1,1000)} {RANDOM(1,1000)} {~p|q|r|s}
~ SEED_RANDOM(0)
R4: {RANDOM(1,1000)} {RANDOM(0,2147483646)}
-> END
