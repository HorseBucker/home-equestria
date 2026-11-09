extends RefCounted
## Reading text off a picture (OCR), for subtitles ponies could not read otherwise (picture_subs.gd).
## One per hub (main.gd `ocr`), shared by every set; read() blocks, so callers run it on a worker
## thread, and one read runs at a time.
## - Windows: its own OCR engine (Windows.Media.Ocr, English), reached through the PowerShell that
##   comes with Windows, so there is nothing to install. One PowerShell process runs SERVER and stays
##   open: it is sent a picture's path a line at a time (Base64 UTF-8) and answers each with
##   "TEXT " + the words read (Base64 UTF-8). It closes after IDLE_SECONDS without work.
## - Linux (or Windows without English OCR): Tesseract, if installed (`tesseract` on PATH, or
##   C:\Program Files\Tesseract-OCR on Windows), run once per picture.
## `state`: "unknown" until check() or the first read, then "ready" or "missing"; `engine` names it.

const IDLE_SECONDS := 120.0
## The PowerShell side. No backslashes in it (a GDScript string).
const SERVER := """$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = [Text.Encoding]::UTF8
$out = [Console]::Out
try {
	Add-Type -AssemblyName System.Runtime.WindowsRuntime
	$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
	function Await($op, [Type]$type) { $task = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); [void]$task.Wait(-1); $task.Result }
	[void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
	[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
	[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
	$language = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | Where-Object { $_.LanguageTag -like 'en*' } | Select-Object -First 1
	if ($null -eq $language) { $out.WriteLine('NOENGLISH'); $out.Flush(); exit 0 }
	$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
	if ($null -eq $engine) { $out.WriteLine('NOENGLISH'); $out.Flush(); exit 0 }
	$out.WriteLine('READY ' + $language.LanguageTag); $out.Flush()
} catch { $out.WriteLine('FAILED ' + $_.Exception.Message.Replace("`r", ' ').Replace("`n", ' ')); $out.Flush(); exit 0 }
while ($null -ne ($line = [Console]::In.ReadLine())) {
	$text = ''
	try {
		$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line.Trim()))
		$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
		$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
		try {
			$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
			$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
			$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
			$text = (($result.Lines | ForEach-Object { $_.Text }) -join "`n")
			$bitmap.Dispose()
		} finally { $stream.Dispose() }
	} catch {
		$problem = $_.Exception
		while ($null -ne $problem.InnerException) { $problem = $problem.InnerException }
		$out.WriteLine('ERR ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($problem.Message))); $out.Flush()
		continue
	}
	$out.WriteLine('TEXT ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))); $out.Flush()
}
"""

var state := "unknown"
## What reads: "Windows OCR (en-US)", "Tesseract", or "" while none.
var engine := ""
## Why there is none, for the setup page.
var problem := ""
var _mutex := Mutex.new()
var _server: Dictionary = {}
var _tesseract := ""
var _last_used := 0
## Read errors logged so far (a few, not one per frame).
var _errors_told := 0

## Finds an engine (blocks: run it on a worker thread). Safe to call again ("Check again").
func check() -> void:
	_mutex.lock()
	_close_server()
	state = "unknown"; engine = ""; problem = ""; _tesseract = ""
	_find()
	_mutex.unlock()

## The words on the picture at `png` (an absolute path), lines joined with "\n"; "" when none or
## when there is no engine. Blocks.
func read(png: String) -> String:
	_mutex.lock()
	if state == "unknown": _find()
	var text := ""
	if state == "ready":
		text = _read_windows(png) if _tesseract.is_empty() else _read_tesseract(png)
	_last_used = Time.get_ticks_msec()
	_mutex.unlock()
	return text

## Closes the PowerShell process once it has been idle a while (the hub calls this now and then).
func tidy() -> void:
	if not _mutex.try_lock(): return
	if not _server.is_empty() and Time.get_ticks_msec() - _last_used > IDLE_SECONDS * 1000.0: _close_server()
	_mutex.unlock()

func close() -> void:
	_mutex.lock()
	_close_server()
	_mutex.unlock()

func _find() -> void:
	if OS.get_name() == "Windows":
		var answer := _start_server()
		if answer.begins_with("READY"):
			state = "ready"
			engine = "Windows OCR (%s)" % answer.trim_prefix("READY").strip_edges()
			return
		problem = "Windows has no English OCR: add English in Windows Settings → Time & language → Language & region." if answer == "NOENGLISH" else "Windows OCR did not start (%s)." % (answer if not answer.is_empty() else "no answer from PowerShell")
		_close_server()
	var found := _find_tesseract()
	if not found.is_empty():
		_tesseract = found
		state = "ready"
		engine = "Tesseract"
		problem = ""
		return
	state = "missing"
	if problem.is_empty(): problem = "No OCR found: install Tesseract (on Linux: the tesseract-ocr package, with English)."

# --- Windows ---------------------------------------------------------------------------------------

## Starts the PowerShell server; its first answer ("READY en-US", "NOENGLISH", "FAILED …"), or "".
func _start_server() -> String:
	var encoded := Marshalls.raw_to_base64(SERVER.to_utf16_buffer())
	_server = OS.execute_with_pipe("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-OutputFormat", "Text", "-EncodedCommand", encoded]))
	if _server.is_empty(): return ""
	var answer := _answer(["READY", "NOENGLISH", "FAILED"])
	if answer.is_empty(): _close_server()
	return answer

## The next line starting with one of `starts` (PowerShell may print other lines first).
func _answer(starts: Array) -> String:
	var pipe: FileAccess = _server.get("stdio")
	var pid := int(_server.get("pid", -1))
	for attempt: int in 40:
		if pipe == null: return ""
		var line := pipe.get_line().strip_edges()
		for start: String in starts:
			var at := line.find(start)
			if at >= 0: return line.substr(at)
		if line.is_empty() and not OS.is_process_running(pid): return ""
	return ""

func _read_windows(png: String) -> String:
	if _server.is_empty() or not OS.is_process_running(int(_server.get("pid", -1))):
		_server = {}
		if not _start_server().begins_with("READY"): return ""
	var pipe: FileAccess = _server.get("stdio")
	# Windows' StorageFile refuses a path with "/" in it, Godot's way of writing paths.
	pipe.store_string(Marshalls.raw_to_base64(png.replace("/", "\\").to_utf8_buffer()) + "\n")
	pipe.flush()
	var answer := _answer(["TEXT", "ERR"])
	if answer.is_empty():
		_close_server()
		return ""
	if answer.begins_with("ERR"):
		if _errors_told < 3:
			_errors_told += 1
			print("[watch_party] OCR: Windows OCR could not read a picture: %s" % Marshalls.base64_to_utf8(answer.trim_prefix("ERR").strip_edges()).replace("\r", " ").replace("\n", " "))
		return ""
	return Marshalls.base64_to_utf8(answer.trim_prefix("TEXT").strip_edges())

func _close_server() -> void:
	var pid := int(_server.get("pid", -1))
	if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	_server = {}

# --- Tesseract ------------------------------------------------------------------------------------

static func _find_tesseract() -> String:
	var tries := PackedStringArray(["tesseract"])
	if OS.get_name() == "Windows":
		tries.append("C:/Program Files/Tesseract-OCR/tesseract.exe")
		tries.append("C:/Program Files (x86)/Tesseract-OCR/tesseract.exe")
	for candidate: String in tries:
		if candidate != "tesseract" and not FileAccess.file_exists(candidate): continue
		var output: Array = []
		if OS.execute(candidate, PackedStringArray(["--version"]), output, false, false) == 0: return candidate
	return ""

func _read_tesseract(png: String) -> String:
	var output: Array = []
	# --psm 6: one block of text, which is what a subtitle is.
	if OS.execute(_tesseract, PackedStringArray([png, "stdout", "-l", "eng", "--psm", "6"]), output, false, false) != 0: return ""
	return str(output[0]) if not output.is_empty() else ""
