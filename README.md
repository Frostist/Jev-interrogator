# Jev-Interrogator

A short text-based interrogation game built in Godot 4.7 (mobile renderer). You play a prisoner answering a Commandant's questions; an LLM judges each answer and drives a suspicion meter toward "shot" or "one shot at escape."

<img width="1151" height="645" alt="image" src="https://github.com/user-attachments/assets/0f555941-6da2-4dc3-b6ad-b240b43b87a1" />

<img width="1149" height="645" alt="image" src="https://github.com/user-attachments/assets/ee646a86-2d8f-4d3b-8fd9-0845148f91bc" />

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
The game play can be a bit of an issue due to the fact that local models can not reason very well and can lack "creative intent" so the game can loop a bit and feels a bit dumb.
But it is a prototype after all and it's fun to see all the different use cases for Jev AI
