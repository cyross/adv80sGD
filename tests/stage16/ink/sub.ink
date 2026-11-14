EXTERNAL call_scene(id, args, into)
VAR result = 0

=== shop_talk ===
みせに よった。
~ call_scene("shop", "price=7; item=ミルク", "result")
もどった。けっか {result}。
* [おわる]
  おしまい。
  -> DONE
