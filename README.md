# Jev-Interrogator

A short text-based interrogation game built in Godot 4.7 (mobile renderer). You play a prisoner answering a Commandant's questions; an LLM judges each answer and drives a suspicion meter toward "shot" or "one shot at escape."

## How it works

- `Interrogation.tscn` / `Interrogation.gd` is the entire game — one scene, one script.
- The Commandant asks the 4 fixed questions in `QUESTIONS` (`Interrogation.gd:7`), one per day.
- Each answer you type is sent, along with the full transcript so far, to the [TypeSafe AI System One](https://typesafe.ai) API (`_on_submit_pressed`, `Interrogation.gd:34`), which returns structured judgments:
  - `believability` (0–3 score)
  - `consistent` (true/false)
  - `reaction` (calm / suspicious / furious)
- Those judgments update a 0–100 `suspicion` meter (`_on_request_completed`, `Interrogation.gd:86`). Hit 100 and you're shot.
- After the 4th question, if suspicion is below `ESCAPE_THRESHOLD` (55), you get one final round: convince the Commandant to let you walk out unescorted. The API is asked a single yes/no (`escape_believed`) for this round instead of the usual three-question rubric.

## Running it

Open the project folder in Godot 4.7 and run the main scene (`Interrogation.tscn`), or `godot --path . run/main_scene` from the CLI.

## Known issue

The TypeSafe API key is hardcoded in `Interrogation.gd:4` for local prototyping. It must move to an environment variable or a server-side proxy before this is committed to a shared repo or shipped anywhere.
