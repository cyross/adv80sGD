extends RefCounted
## manifest_cli.gd から呼ばれる本体。
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

const EXIT_OK := 0
const EXIT_ERRORS := 10
const EXIT_STRICT_WARNINGS := 11
const EXIT_STALE := 12
const EXIT_USAGE := 20
const EXIT_TOOL := 30

var command := "generate"
var up_to_date := false
var roots: PackedStringArray = []
var project_path := AdvProject.DEFAULT_PATH
var strict := false
var scenario_check := true
var report_path := ""
var format := "text"
var verbosity := 1   # 0 quiet、1 通常、2 詳しく


func run(args: PackedStringArray) -> int:
	var usage := _parse_args(args)
	if usage != "":
		printerr("adv80s manifest: " + usage)
		printerr("usage: -- [generate|check] [--up-to-date] [--root <dir>]... [--project <file>] [--strict] [--no-scenario-check] [--report <file>] [--format text|json] [--quiet|--verbose]")
		return EXIT_USAGE

	var diags: Array = []
	var project := AdvProject.load_project(project_path, diags)
	var folders := project.asset_folders()
	if roots.is_empty():
		roots = AdvManifestGenerator.project_roots(project, diags)

	var tool_failed := false
	var stale: PackedStringArray = []
	var generated: Dictionary = {}   # root → マニフェスト
	for root in roots:
		var res := AdvManifestGenerator.scan(root, folders)
		diags.append_array(res["diags"])
		diags.append_array(AdvManifestGenerator.check_manual(root))
		generated[root] = res["manifest"]
		if command == "generate":
			var err := AdvManifestGenerator.write(root, res["manifest"])
			if err == OK:
				_log(2, "wrote %s/%s" % [root, AdvManifestGenerator.AUTO_NAME])
			elif err != ERR_ALREADY_EXISTS:
				tool_failed = true
				diags.append(AdvDiag.make("error", "TOOL_ERROR", "書き出しに失敗しました: %s（%s）" % [root, error_string(err)],
					"Failed to write: %s (%s)" % [root, error_string(err)], root))
		elif up_to_date and not AdvManifestGenerator.is_up_to_date(root, res["manifest"]):
			stale.append(root)
			diags.append(AdvDiag.make("error", "MANIFEST_STALE", "manifest.auto.json が古くなっています: %s" % root,
				"manifest.auto.json is out of date: %s" % root, root + "/" + AdvManifestGenerator.AUTO_NAME))

	if scenario_check:
		diags.append_array(_check_scenarios(project, generated, folders))

	var errors := 0
	var warnings := 0
	for d in diags:
		match String(d["severity"]):
			"error": errors += 1
			"warning": warnings += 1
	var code := EXIT_OK
	if tool_failed:
		code = EXIT_TOOL
	elif errors - stale.size() > 0:
		code = EXIT_ERRORS
	elif not stale.is_empty():
		code = EXIT_STALE
	elif strict and warnings > 0:
		code = EXIT_STRICT_WARNINGS

	var out := _format(diags, errors, warnings, code)
	if report_path != "":
		var f := FileAccess.open(report_path, FileAccess.WRITE)
		if f == null:
			printerr("adv80s manifest: cannot write report: %s" % report_path)
			return EXIT_TOOL
		f.store_string(out)
		f.close()
	if verbosity > 0 or code != EXIT_OK:
		print(out.strip_edges())
	return code


func _parse_args(args: PackedStringArray) -> String:
	var i := 0
	var seen_command := false
	while i < args.size():
		var a := args[i]
		match a:
			"generate", "check":
				if seen_command:
					return "command given twice: %s" % a
				command = a
				seen_command = true
			"--up-to-date": up_to_date = true
			"--strict": strict = true
			"--no-scenario-check": scenario_check = false
			"--quiet": verbosity = 0
			"--verbose": verbosity = 2
			"--root", "--report", "--format", "--project":
				if i + 1 >= args.size():
					return "%s needs a value" % a
				i += 1
				var v := args[i]
				match a:
					"--root": roots.append(_res_path(v))
					"--report": report_path = v
					"--project": project_path = _res_path(v)
					"--format":
						if not v in ["text", "json"]:
							return "unknown format: %s" % v
						format = v
			_:
				return "unknown argument: %s" % a
		i += 1
	if up_to_date and command != "check":
		return "--up-to-date can only be used with check"
	return ""


static func _res_path(p: String) -> String:
	return p if p.contains("://") or p.is_absolute_path() else "res://" + p.trim_prefix("./")


func _check_scenarios(project: AdvProject, generated: Dictionary, folders: Dictionary) -> Array:
	var out: Array = []
	for d in AdvManifestGenerator.check_scenarios(project, generated, folders):
		if d["severity"] == "info" and verbosity < 2:
			continue
		out.append(d)
	return out


func _format(diags: Array, errors: int, warnings: int, code: int) -> String:
	if format == "json":
		return JSON.stringify({
			"command": command, "roots": Array(roots), "diagnostics": diags,
			"summary": {"errors": errors, "warnings": warnings}, "exit_code": code,
		}, "  ") + "\n"
	var lines := PackedStringArray()
	for d in diags:
		if verbosity == 0 and d["severity"] != "error":
			continue
		var where := String(d.get("file", ""))
		if String(d.get("path", "")) != "":
			where += " " + String(d["path"])
		lines.append("%s %s: %s  [%s]" % [d["severity"], d["code"], d["message"], where.strip_edges()])
	lines.append("adv80s manifest %s: %d error(s), %d warning(s), %d root(s), exit %d" % [command, errors, warnings, roots.size(), code])
	return "\n".join(lines) + "\n"


func _log(level: int, s: String) -> void:
	if verbosity >= level:
		print(s)
