extends Control

var lesson_container_scene: PackedScene = preload("res://sources/language_tool/lesson_container.tscn")
var gp_label_scene: PackedScene = preload("res://sources/language_tool/lesson_gp_label.tscn")
var lessons: Dictionary[int, LessonContainer] = {}

@onready var lessons_container: VBoxContainer = $%LessonsContainer
@onready var unused_gp_container: GridContainer = $%UnusedGPContainer


func _ready() -> void:
	Database.db.query("Select Grapheme, Phoneme, LessonNb, Lessons.ID AS LessonID, GPID FROM Lessons
		INNER JOIN GPsInLessons ON GPsInLessons.LessonID = Lessons.ID
		INNER JOIN GPs ON GPsInLessons.GPID = GPs.ID
		ORDER BY LessonNb")
	for element: Dictionary in Database.db.query_result:
		if lessons.has(element.LessonNb):
			(lessons[element.LessonNb] as LessonContainer).add_gp({grapheme = element.Grapheme, phoneme = element.Phoneme, gp_id = element.GPID})
		else:
			var lesson_container: LessonContainer = lesson_container_scene.instantiate()
			lessons_container.add_child(lesson_container)
			lesson_container.add_gp({grapheme = element.Grapheme, phoneme = element.Phoneme, gp_id = element.GPID})
			lesson_container.number = element.LessonNb
			lesson_container.lesson_id = element.LessonID
			lesson_container.lesson_dropped.connect(_on_lesson_dropped)
			lessons[element.LessonNb] = lesson_container
	
	Database.db.query("SELECT Grapheme, Phoneme, GPs.ID as GPID FROM GPs
		WHERE NOT EXISTS(SELECT 1 FROM GPsInLessons WHERE GPs.ID=GPsInLessons.GPID)")
	for element: Dictionary in Database.db.query_result:
		var gp_label: LessonGPLabel = gp_label_scene.instantiate()
		unused_gp_container.add_child(gp_label)
		gp_label.grapheme = element.Grapheme
		gp_label.phoneme = element.Phoneme
		gp_label.gp_id = element.GPID
		gp_label.gp_dropped.connect(_on_gp_dropped)
	
	unused_gp_container.set_drag_forwarding(Callable(), _can_drop_in_gp_container, _drop_data_in_gp_container)


func _on_plus_button_pressed() -> void:
	var lesson_container: LessonContainer = lesson_container_scene.instantiate()
	lessons_container.add_child(lesson_container)
	lesson_container.lesson_dropped.connect(_on_lesson_dropped)
	var current_max_lesson_number: int = 0
	for element: LessonContainer in lessons.values():
		if element.number > current_max_lesson_number:
			current_max_lesson_number = element.number
	lesson_container.number = current_max_lesson_number + 1
	lessons[current_max_lesson_number + 1] = lesson_container


func _can_drop_in_gp_container(_at_position: Vector2, data: Variant) -> bool:
	@warning_ignore("unsafe_method_access")
	return data.has("gp_id")


func _drop_data_in_gp_container(_at_position: Vector2, data: Variant) -> void:
	@warning_ignore("unsafe_method_access")
	if not data.has("gp_id"):
		return
	var new_gp_label: LessonGPLabel = gp_label_scene.instantiate()
	new_gp_label.grapheme = data.grapheme
	new_gp_label.phoneme = data.phoneme
	new_gp_label.gp_id = data.gp_id
	new_gp_label.gp_dropped.connect(_drop_data_in_gp_container)
	unused_gp_container.add_child(new_gp_label)


func _on_gp_dropped(_before: bool, data: Dictionary) -> void:
	_drop_data_in_gp_container(Vector2.ZERO, data)


func _on_lesson_dropped(before: bool, number: int, dropped_number: int) -> void:
	var dropped_lesson: LessonContainer = lessons[dropped_number]
	var where_lesson: LessonContainer = lessons[number]
	var index: int = where_lesson.get_index()
	if not before:
		index += 1
	lessons_container.move_child(dropped_lesson, index)
	var children: Array[Node] = lessons_container.get_children()
	for ind: int in range(children.size()):
		var child: LessonContainer = children[ind]
		child.number = ind + 1
		lessons[child.number] = child


## Writes the lessons in their on-screen order onto the Lessons rows, by number,
## then moves every booklet chapter to the row its lesson's content now sits on,
## so a chapter follows its lesson when lessons are dragged around. Refuses to
## save when a lesson that has chapters is left without GPs: it would vanish
## from the list on the next load, and its chapters would be stranded.
func _on_save_button_pressed() -> void:
	var children: Array[Node] = lessons_container.get_children()
	var chapters_by_lesson: Dictionary[int, Array] = _chapter_ids_by_lesson()
	var stranded: PackedStringArray = []
	for child: LessonContainer in children:
		if child.lesson_id >= 0 and child.get_gp_count() == 0 and chapters_by_lesson.has(child.lesson_id):
			stranded.append(str(child.number))
	if not stranded.is_empty():
		_show_refusal("Lessons %s have booklet chapters but no GP left. Give them GPs, or move or delete their chapters in Booklet Chapters first." % ", ".join(stranded))
		return

	Database.db.query("DELETE FROM GPsInLessons")
	var target_ids: Dictionary[int, int] = {} # lesson row a container came from -> row it now sits on
	for index: int in range(children.size()):
		var child: LessonContainer = children[index]
		Database.db.query_with_bindings("SELECT * FROM Lessons WHERE LessonNb = ?", [index + 1])
		var lesson_id: int = -1
		if Database.db.query_result.is_empty():
			Database.db.insert_row("Lessons",
			{
				LessonNb = index + 1
			})
			lesson_id = Database.db.last_insert_rowid
		else:
			lesson_id = Database.db.query_result[0].ID
		if child.lesson_id >= 0:
			target_ids[child.lesson_id] = lesson_id
		
		for gp_id: int in child.get_gp_ids():
			Database.db.insert_row("GPsInLessons",
			{
				GPID = gp_id,
				LessonID = lesson_id,
			})

	# By chapter ID, from the list read before anything moved: lessons can swap.
	for origin_id: int in chapters_by_lesson:
		var target_id: int = target_ids.get(origin_id, origin_id)
		if target_id == origin_id:
			continue
		for chapter_id: int in chapters_by_lesson[origin_id]:
			Database.db.query_with_bindings("UPDATE BookletChapters SET LessonID = ? WHERE ID = ?", [target_id, chapter_id])
	for child: LessonContainer in children:
		child.lesson_id = target_ids.get(child.lesson_id, child.lesson_id)

	# A lesson that still has chapters is not deleted (ON DELETE RESTRICT).
	Database.db.query_with_bindings("DELETE FROM Lessons WHERE LessonNb > ? AND ID NOT IN (SELECT LessonID FROM BookletChapters)", [children.size()])


func _chapter_ids_by_lesson() -> Dictionary[int, Array]:
	var by_lesson: Dictionary[int, Array] = {}
	Database.db.query("SELECT ID, LessonID FROM BookletChapters")
	for row: Dictionary in Database.db.query_result:
		if not by_lesson.has(int(row.LessonID)):
			by_lesson[int(row.LessonID)] = []
		by_lesson[int(row.LessonID)].append(int(row.ID))
	return by_lesson


func _show_refusal(text: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Not saved"
	dialog.dialog_text = text
	add_child(dialog)
	dialog.popup_centered()


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/prof_tool_menu.tscn")
