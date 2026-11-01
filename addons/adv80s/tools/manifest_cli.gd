extends SceneTree
## 自動生成マニフェストの生成と確認をコマンドラインで行う（5.6）。
##
##   godot --headless --path <プロジェクト> --script res://addons/adv80s/tools/manifest_cli.gd -- generate --strict
##
## 指定：
##   generate（既定）        素材フォルダを読んで確認し、manifest.auto.json を書き出す
##   check                   確認だけ行う
##   --up-to-date            （check と一緒に）コミット済みの manifest.auto.json が最新かも確かめる
##   --root <パス>           対象の素材フォルダ（複数指定可）。省略時はプロジェクト設定などにあるすべての素材フォルダ
##   --project <パス>        プロジェクト設定のファイル（既定 res://adv80s.project.json）
##   --strict                警告もエラーとして扱う
##   --no-scenario-check     シナリオの参照チェックを省く
##   --report <ファイル>     結果をファイルに出力する
##   --format text|json      結果の形式（既定 text）
##   --quiet / --verbose     出力の量
##
## 終了コード：0 成功、10 エラーあり、11 --strict で警告あり、12 マニフェストが古い、20 引数の誤り、30 ツール自体の失敗

const CLASS_CACHE := "res://.godot/global_script_class_cache.cfg"
const MAIN := "res://addons/adv80s/tools/adv_manifest_cli_main.gd"


func _initialize() -> void:
	# まだ一度も読み込み（インポート）していないプロジェクトでは、クラス名が使えない。
	# そのときは先にインポートを行ってから、同じ引数で自分自身を実行し直す。
	if not FileAccess.file_exists(CLASS_CACHE) and not OS.get_cmdline_user_args().has("--no-reimport"):
		quit(_reimport_and_rerun())
		return
	var main = load(MAIN).new()
	quit(main.run(_user_args()))


func _user_args() -> PackedStringArray:
	var r := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a != "--no-reimport":
			r.append(a)
	return r


func _reimport_and_rerun() -> int:
	var exe := OS.get_executable_path()
	var dir := ProjectSettings.globalize_path("res://")
	var out: Array = []
	printerr("adv80s manifest: importing the project first...")
	var rc := OS.execute(exe, ["--headless", "--path", dir, "--import"], out, true)
	if rc != 0 and not FileAccess.file_exists(CLASS_CACHE):
		printerr("adv80s manifest: import failed (%d)" % rc)
		return 30
	var args := PackedStringArray(["--headless", "--path", dir, "--script", "res://addons/adv80s/tools/manifest_cli.gd", "--"])
	args.append_array(OS.get_cmdline_user_args())
	args.append("--no-reimport")
	out.clear()
	rc = OS.execute(exe, args, out, true)
	for line in out:
		printraw(line)
	return rc
