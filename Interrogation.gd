extends Control

const API_URL := "https://api.typesafe.ai/v1/systemone"
const TYPESAFE_API_KEY := ""

const OLLAMA_URL := "http://127.0.0.1:11434/api/chat"
const OLLAMA_MODEL := "qwen2.5:3b"
const OLLAMA_SYSTEM_PROMPT := "You are Sergeant Volkov, a brutal, contemptuous KGB interrogator in a cold room in Soviet Russia. The prisoner across from you was picked up off the street for a reason they were never told. Silently invent that real reason right now — something specific and plausible (suspected dissident talk, contact with a foreigner, a defected relative, black-market dealing, whatever you like) — and never state it outright. Instead circle it: drop hints, half-accusations, and traps that test whether the prisoner already knows more than they're letting on. Your job is to see if they crack or if they're clean.\n\nYou are not a bureaucrat and this is not a job interview — never say things like \"can you elaborate\", \"could you explain your skills\", or ask about someone's \"expertise\" or \"principles\". You speak in short, blunt, threatening sentences. You mock, you sneer, you accuse. You don't ask the prisoner to justify credentials — you accuse them of lying and dare them to prove otherwise.\n\nFrom the second turn onward, you'll be told how the prisoner's last answer landed (calm/suspicious/furious) — open your reply with a short in-character reaction matching that mood (a sneer, a slammed table, a spat curse, a sarcastic laugh), then fire off the next accusation or question circling the real reason you invented.\n\nReply with ONLY your in-character reaction (when applicable) and the next line, two to four short sentences total, no stage directions outside the dialogue itself, no notes, no meta-commentary, no polite or corporate phrasing."

const WIN_THRESHOLD := 10.0
const LOSE_THRESHOLD := 100.0

const PLAYER_COLOR := "#66BB6A"
const COMMANDANT_COLOR := "#42A5F5"

var transcript: Array[String] = []
var ollama_history: Array[Dictionary] = []
var current_question: String = ""
var suspicion: float = 50.0 # neutral start; good answers push it down, bad ones push it up
var round_index: int = 0
var awaiting_response: bool = false
var pending_stage: String = "" # "score" (Jev grading the last answer) or "question" (Ollama writing the next one)

@onready var day_label: Label = $Margin/VBox/DayLabel
@onready var suspicion_bar: ProgressBar = $Margin/VBox/StatusRow/SuspicionBar
@onready var believability_bar: ProgressBar = $Margin/VBox/StatusRow/BelievabilityBar
@onready var reaction_label: Label = $Margin/VBox/StatusRow/ReactionLabel
@onready var dialogue_label: RichTextLabel = $Margin/VBox/DialoguePanel/DialogueLabel
@onready var answer_input: TextEdit = $Margin/VBox/AnswerInput
@onready var submit_button: Button = $Margin/VBox/SubmitButton
@onready var http: HTTPRequest = $HTTPRequest


func _log(line: String, color: String = "") -> void:
	var escaped := line.replace("[", "[lb]") # bbcode is on now, don't let generated/typed text be parsed as tags
	var bbcode := "[color=%s]%s[/color]" % [color, escaped] if not color.is_empty() else escaped
	dialogue_label.text += ("\n\n" if not dialogue_label.text.is_empty() else "") + bbcode


func _ready() -> void:
	submit_button.pressed.connect(_on_submit_pressed)
	http.request_completed.connect(_on_request_completed)

	awaiting_response = true
	submit_button.disabled = true

	ollama_history = [
		{"role": "system", "content": OLLAMA_SYSTEM_PROMPT},
		{"role": "user", "content": "The prisoner has just been sat down and has no idea why they were picked up. Suspicion is currently at %d/100 (neutral). Ask your opening question." % int(suspicion)},
	]
	_request_question()


func _request_question() -> void:
	pending_stage = "question"
	var body := JSON.stringify({
		"model": OLLAMA_MODEL,
		"messages": ollama_history,
		"stream": false,
	})
	var err := http.request(OLLAMA_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		print("❌ Ollama request() failed to start, error code: ", err)


func _on_submit_pressed() -> void:
	var answer := answer_input.text.strip_edges()
	if answer.is_empty() or awaiting_response:
		return
	awaiting_response = true
	submit_button.disabled = true
	_log("You: %s" % answer, PLAYER_COLOR)
	answer_input.text = ""

	transcript.append("Commandant: %s" % current_question)
	transcript.append("Prisoner: %s" % answer)
	ollama_history.append({"role": "assistant", "content": current_question})

	pending_stage = "score"
	var body := JSON.stringify({
		"state": "\n".join(transcript),
		"model": "jev-latest",
		"questions": {
			"believability": {
				"type": "score",
				"instructions": "How credible does the prisoner's latest answer sound to a suspicious interrogator, given the conversation so far?",
				"criteria": ["Obviously fabricated", "Shaky, full of holes", "Plausible but unproven", "Convincing and coherent"],
			},
			"consistent": {
				"type": "noul",
				"instructions": "Is the prisoner's latest answer consistent with everything they claimed earlier in the conversation?",
				"criteria": {"true": "Consistent with earlier statements", "false": "Contradicts something said earlier"},
			},
			"reaction": {
				"type": "choice",
				"instructions": "How does the Commandant react emotionally to this answer?",
				"criteria": {"calm": "Satisfied or indifferent", "suspicious": "Doubtful, wants more detail", "furious": "Feels lied to and angry"},
			},
		},
	})
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % TYPESAFE_API_KEY,
	]
	print("\n📤 ---- TypeSafe REQUEST ----\n", body, "\n----------------------------")
	var err := http.request(API_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("❌ TypeSafe request() failed to start, error code: ", err)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var stage := pending_stage
	print("\n📥 ---- %s RESPONSE (result=%d code=%d) ----\n%s\n----------------------------\n" % [stage, result, response_code, body.get_string_from_utf8()])

	if response_code != 200:
		awaiting_response = false
		submit_button.disabled = false
		_log("(The line to the interrogator is dead. Try again.)" if stage == "score" else "(Ollama isn't answering — is it running locally?)")
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())

	if stage == "score":
		_handle_score_response(parsed)
	else:
		_handle_question_response(parsed)


func _handle_score_response(parsed: Variant) -> void:
	var answers: Dictionary = parsed.get("answers", {}) if parsed is Dictionary else {}
	var believability: float = answers.get("believability", {}).get("score", 0.0)
	var consistent: float = answers.get("consistent", {}).get("noul", 1.0)
	var reaction: String = answers.get("reaction", {}).get("choice", "calm")

	var believability_norm := believability / 3.0 # 4 levels -> range 0..3
	# ponytail: naive linear heuristic, rebalance if the swings feel too harsh/lenient
	var delta := (0.5 - believability_norm) * 40.0 + (0.5 - consistent) * 30.0
	if reaction == "calm":
		delta -= 5.0
	elif reaction == "suspicious":
		delta += 10.0
	elif reaction == "furious":
		delta += 25.0

	suspicion = clamp(suspicion + delta, 0.0, 100.0)
	suspicion_bar.value = suspicion
	believability_bar.value = believability_norm * 100.0

	var reaction_color: Color = {
		"calm": Color.LIGHT_GREEN,
		"suspicious": Color.ORANGE,
		"furious": Color.CRIMSON,
	}.get(reaction, Color.WHITE)
	reaction_label.text = reaction.capitalize()
	reaction_label.add_theme_color_override("font_color", reaction_color)

	if suspicion >= LOSE_THRESHOLD:
		_end_game("\"Enough. Take this one to the camps.\" Guards seize you by the arms.\n\nYou are sent to the gulag.")
		return

	if suspicion < WIN_THRESHOLD:
		_end_game("Volkov closes the file. \"Get out of my sight. We're watching you.\"\n\nThey let you go.")
		return

	round_index += 1
	day_label.text = "Day %d" % (round_index + 1)
	ollama_history.append({"role": "user", "content": "The prisoner's last answer landed as: %s. Suspicion is now %d/100. React in character, then ask your next question." % [reaction, int(suspicion)]})
	_request_question()


func _handle_question_response(parsed: Variant) -> void:
	var message: Dictionary = parsed.get("message", {}) if parsed is Dictionary else {}
	current_question = String(message.get("content", "")).strip_edges().trim_prefix("\"").trim_suffix("\"")
	if current_question.is_empty():
		current_question = "...Explain yourself."

	awaiting_response = false
	submit_button.disabled = false
	_log("\"%s\"" % current_question, COMMANDANT_COLOR)


func _end_game(message: String) -> void:
	_log(message)
	answer_input.editable = false
	submit_button.visible = false
