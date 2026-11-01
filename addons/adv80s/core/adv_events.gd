class_name AdvEvents
extends RefCounted
## 出力イベント（5.4）の補助。イベントの形：{type, args, wait, id, log, ext}

## 状態を変えるイベント（Core が適用する）。
const STATE_TYPES := ["state.set", "item.add", "item.remove", "scene.goto", "state.mark"]


static func make(type: String, args: Dictionary = {}, wait: Variant = null) -> Dictionary:
	var ev := {"type": type, "args": args}
	if wait != null:
		ev["wait"] = wait
	return ev


static func text(body: String, speaker: String = "", name: String = "", id: String = "") -> Dictionary:
	var args := {"body": body}
	if speaker != "":
		args["speaker"] = speaker
	if name != "":
		args["name"] = name
	var ev := make("text.show", args)
	if id != "":
		ev["id"] = id
	return ev


## 種類ごとの既定の待ち方（イベントに wait がないときに使う）。
static func default_wait(ev: Dictionary) -> Variant:
	var args: Dictionary = ev.get("args", {})
	match String(ev.get("type", "")):
		"text.show", "text.append":
			return "click"
		"image.show", "image.hide":
			return "end" if args.has("transition") else "none"
		"effect.play", "scene.goto", "group", "template.switch", "layout.set":
			return "end"
		"choice.show", "input.request", "save.request":
			return "input"
		"wait":
			return float(args.get("seconds", 0.0))
	return "none"


static func wait_of(ev: Dictionary) -> Variant:
	return ev["wait"] if ev.has("wait") else default_wait(ev)


static func is_state_event(ev: Dictionary) -> bool:
	return String(ev.get("type", "")) in STATE_TYPES
