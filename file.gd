func _ready():
	_probe_fileaccess("res://test2.txt")  # adjust if your path differs
	# ... your existing _ready() ...

func _probe_fileaccess(p: String) -> void:
	print("--- FILEACCESS PROBE ---")
	print("Godot sees FileAccess class? ", ClassDB.class_exists("FileAccess"))
	print("res:// exists?  ", FileAccess.file_exists("res://"))
	print("user:// exists? ", FileAccess.file_exists("user://"))
	print("target path:    ", p)
	print("file exists?    ", FileAccess.file_exists(p))

	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		var err := FileAccess.get_open_error()
		print("open error: ", error_string(err), " (", err, ")")
	else:
		print("open ok, bytes: ", f.get_length())
		# optional: preview first line
		var s := f.get_as_text()
		print("first 60 chars: ", s.substr(0, min(60, s.length())))

	# user:// write/read sanity check
	var up := "user://__fa_probe__.txt"
	var wf := FileAccess.open(up, FileAccess.WRITE)
	if wf:
		wf.store_line("hello")
		wf = null
		print("wrote user file. exists? ", FileAccess.file_exists(up))
	else:
		var uerr := FileAccess.get_open_error()
		print("user write failed: ", error_string(uerr), " (", uerr, ")")

	# absolute paths for clarity
	print("res abs:  ", ProjectSettings.globalize_path("res://"))
	print("user abs: ", ProjectSettings.globalize_path("user://"))
	print("p abs:    ", ProjectSettings.globalize_path(p))
