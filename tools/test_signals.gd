extends SceneTree
## Checks that finished fires exactly once for every line, however it ends,
## and that interrupted marks cut-off lines. Exits with code 1 on failure.
## godot --headless --path . -s tools/test_signals.gd

var failures := 0
var finished_n := 0
var interrupted_n := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _init() -> void:
	var label := RichTextLabel.new()
	root.add_child(label)
	var b := Blabbermouth.new()
	b.label = label
	b.voice = BlabberVoice.preset("critter")
	root.add_child(b)
	b.finished.connect(func() -> void: finished_n += 1)
	b.interrupted.connect(func() -> void: interrupted_n += 1)
	await process_frame

	# Cut off by a new line.
	b.speak("This is a fairly long line that will not get to finish.")
	await _frames(5)
	b.speak("Second line.")
	check(finished_n == 1 and interrupted_n == 1, "new speak() ends the old line (%d finished, %d interrupted)" % [finished_n, interrupted_n])
	check(b.is_speaking(), "new line is playing")

	# stop() ends it, and anything awaiting finished wakes up.
	var woke := [false]
	var waiter := func() -> void:
		await b.finished
		woke[0] = true
	waiter.call()
	b.stop()
	check(woke[0], "await finished returns after stop()")
	check(finished_n == 2 and interrupted_n == 2, "stop() emits interrupted and finished")
	b.stop()
	check(finished_n == 2, "stop() when idle does nothing")

	# skip() reveals everything and is not an interruption.
	b.speak("Skip me please, I am in a hurry.")
	await _frames(3)
	b.skip()
	check(finished_n == 3 and interrupted_n == 2, "skip() emits finished only")
	check(label.visible_characters == label.get_total_character_count() or label.visible_characters == -1, "skip() reveals the line")

	# Played to the end.
	b.speak("Short.")
	var t := 0.0
	while b.is_speaking() and t < 5.0:
		await process_frame
		t += root.get_process_delta_time()
	check(finished_n == 4 and interrupted_n == 2, "a line that plays out emits finished only")

	# A dialogue loop that starts the next line from its finished handler,
	# interrupted from outside: nothing should hang, and the outside line wins.
	var loop_done := [false]
	var lines := ["One two three four five six.", "Seven eight nine ten.", "Eleven twelve."]
	var loop := func() -> void:
		for line in lines:
			b.speak(line)
			await b.finished
		loop_done[0] = true
	loop.call()
	await _frames(3)
	b.speak("[shout]Interruption![/shout]")
	check(loop_done[0], "a dialogue loop doesn't hang when interrupted")
	check(b.is_speaking() and label.text.contains("Interruption"), "the interrupting line is the one playing")
	b.stop()

	print("signal tests: ", "all passed" if failures == 0 else "%d failed" % failures)
	quit(1 if failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
