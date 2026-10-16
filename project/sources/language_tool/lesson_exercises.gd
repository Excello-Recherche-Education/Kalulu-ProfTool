extends Control

const LESSON_EXERCISE_CONTAINER_SCENE: PackedScene = preload("res://sources/language_tool/lesson_exercises_container.tscn")

@onready var lessons_container: VBoxContainer = %LessonsContainer


func _ready() -> void:
	# The pack's schema -- LessonsExercises without foreign keys on the minigame
	# slots, ExerciseTypes matching MinigameTypes.NAMES -- is settled by
	# PackSchema.upgrade() when the menu opens the pack, not here.
	var sentences_by_lesson: Dictionary = Database.get_sentences_by_lessons()
	Database.db.query("Select * FROM Lessons")
	for result: Dictionary in Database.db.query_result:
		var container: LessonExerciseContainer = LESSON_EXERCISE_CONTAINER_SCENE.instantiate()
		lessons_container.add_child(container)
		container.sentences_by_lesson = sentences_by_lesson
		container.lesson_number = result.LessonNb
		container._on_save_button_pressed()


func _on_save_button_pressed() -> void:
	for container: LessonExerciseContainer in lessons_container.get_children():
		container._on_save_button_pressed()


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/prof_tool_menu.tscn")
