# Orbit Math — Shorts engine
Data-driven, narrated YouTube Shorts. One episode = `episodes/<slug>/episode.json` + `data.csv`.

    tools/setup.sh                        # fresh workspace
    tools/render.sh episodes/<slug>       # narrate, render, loudness-normalize, QA sheet

Script syntax: `{display|spoken}` (caption vs voice), `^word` (emphasis), `Word~Word` (keep together).
Beats: `at`/`atWord`, `target`, `label`, `counter`, `chip`, `headline`, `pan`, `overview`, `connector`, `big`, `card`, `cardAccent`.
Voice: free Kokoro model (am_michael). Premium voice (Higgsfield) replaces `narration.wav` once connected.
Music: `public/music/bed.wav` placeholder — replace with YouTube Audio Library tracks in `public/music/`.
Log every run in `runlog.csv`; pick topics from `topics.md`.
