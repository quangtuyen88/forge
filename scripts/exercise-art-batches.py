#!/usr/bin/env python3
"""Exercise illustrations with the GPT image model through the Codex CLI.

Style and verification rubric: docs/design/exercise-art-style.md.
Reads ForgeCore/Sources/ForgeCore/ExerciseDB.swift and writes one prompt per exercise to $ART_DIR/prompts.
With --run N it generates every missing $ART_DIR/out/<id>.png with N parallel `codex exec` calls.
Pass ids after the flags to limit the set. Verify every image against the rubric, convert the keepers to
JPEG in one folder, then run scripts/import-exercise-art.py <folder>.
"""
import argparse, os, re, subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = Path(os.environ.get('ART_DIR', '/tmp/forge-art2'))
ANCHOR = WORK / 'anchor.png'
if not ANCHOR.exists():
    ANCHOR = ROOT / 'App/Forge/Assets.xcassets/ExerciseArt/ex-back_squat.imageset/ex-back_squat.jpg'
STYLE = ROOT / 'docs/design/exercise-art-style.md'
# Pose notes that fixed images failing verification, one `id|note` per line.
NOTES = dict(l.split('|', 1) for l in (ROOT / 'scripts/exercise-art-notes.txt').read_text().splitlines() if '|' in l)

MUSCLE = {
    'chest': 'the chest (both pectoral muscles on the front of the torso)',
    'back': 'the back (latissimus dorsi on both sides of the back plus the trapezius and rhomboids between the shoulder blades)',
    'quads': 'the quadriceps (front of both thighs, hip to knee)',
    'hamstrings': 'the hamstrings (back of both thighs, between buttocks and knee)',
    'glutes': 'the glutes (both buttocks)',
    'sideDelts': 'the side deltoids (outer cap of both shoulders)',
    'rearDelts': 'the rear deltoids (back cap of both shoulders)',
    'frontDelts': 'the front deltoids (front cap of both shoulders)',
    'triceps': 'the triceps (back of both upper arms, shoulder to elbow)',
    'biceps': 'the biceps (front of both upper arms, shoulder to elbow)',
    'calves': 'the calves (back of both lower legs, knee to ankle)',
    'abs': 'the abdominals (rectus abdominis and obliques on the front and sides of the stomach)',
    'forearms': 'the forearms (both forearms, wrist to elbow)',
}
GRAY = {
    'chest': 'chest', 'back': 'back and trapezius', 'quads': 'front thighs', 'hamstrings': 'back thighs',
    'glutes': 'buttocks', 'sideDelts': 'shoulders', 'rearDelts': 'shoulders', 'frontDelts': 'shoulders',
    'triceps': 'upper arms', 'biceps': 'upper arms', 'calves': 'lower legs', 'abs': 'stomach', 'forearms': 'forearms',
}
UPPER_TRAPS = 'the upper trapezius only (the slope between the neck and the top of the shoulders); the lats and the rest of the back stay plain gray'
# Upright rows and carries load the upper traps, not the lats that `back` also covers.
OVERRIDE = {i: {'back': UPPER_TRAPS} for i in ('barbell_upright_row', 'db_upright_row', 'cable_upright_row', 'wide_grip_upright_row', 'suitcase_carry')}
REAR = {'back', 'rearDelts', 'triceps', 'glutes', 'hamstrings', 'calves'}
EQUIP = {
    'barbell': 'with a barbell', 'dumbbell': 'with dumbbells', 'machine': 'on the machine built for it',
    'cable': 'at a cable station', 'bodyweight': 'with bodyweight only', 'bands': 'with a resistance band',
}


def exercises() -> list[dict]:
    src = (ROOT / 'ForgeCore/Sources/ForgeCore/ExerciseDB.swift').read_text()
    pat = re.compile(r'Exercise\(\s*id:\s*"([^"]+)",\s*name:\s*"([^"]+)",\s*pattern:\s*\.\w+,\s*primary:\s*\.(\w+),'
                     r'\s*synergists:\s*\[([^\]]*)\],\s*isCompound:\s*\w+,\s*equipment:\s*\.(\w+)', re.S)
    return [dict(id=m[1], name=m[2], primary=m[3], equipment=m[5],
                 synergists=[s.strip().lstrip('.') for s in m[4].split(',') if s.strip()]) for m in pat.finditer(src)]


def prompt(e: dict) -> str:
    colored = {e['primary'], *e['synergists']}
    desc = {**MUSCLE, **OVERRIDE.get(e['id'], {})}
    view = 'three-quarter rear view' if e['primary'] in REAR else 'three-quarter front view'
    rule = f"PRIMARY, royal blue #0062E6: {desc[e['primary']]}."
    syn = [desc[s] for s in e['synergists'] if s in desc]
    rule += (' SECONDARY, pale sky blue #A8C8FF: ' + '; '.join(syn) + '.') if syn else ' No secondary muscles: nothing is pale blue.'
    gray = sorted({GRAY[m] for m in MUSCLE if m not in colored} - {GRAY[m] for m in colored})
    rule += ' Everything else stays plain gray, in particular: ' + ', '.join(gray) + '.'
    return (f'Read {STYLE} and follow its Style section exactly. First open and look at {ANCHOR}: the new image must match '
            'its figure, line weight, shading, gray tones, blue tones and white background exactly (use it as the reference '
            'image if your image tool accepts one). Use your image generation tool to create ONE square image: '
            f"{e['name']} {EQUIP[e['equipment']]}, middle of a repetition, {view}, turned so the primary and every secondary "
            'muscle are clearly visible (lying exercises: side three-quarter view from slightly above). '
            f"{NOTES.get(e['id'], 'Anatomically correct pose, grip and stance for this exercise.')} {rule} "
            'Request an opaque white background. Then copy the generated PNG '
            f"to {WORK / 'out' / (e['id'] + '.png')} and print its path. Do not create any other files.")


def generate(e: dict) -> str:
    out = WORK / 'out' / f"{e['id']}.png"
    env = {**os.environ, 'OPENAI_BASE_URL': os.environ.get('CODEX_BASE_URL', 'http://localhost:8787/v1')}
    with open(WORK / 'logs' / f"{e['id']}.log", 'w') as log:
        subprocess.run(['codex', '--dangerously-bypass-approvals-and-sandbox', '--model',
                        os.environ.get('CODEX_MODEL', 'gpt-5.6-sol'), 'exec', prompt(e)], env=env, stdout=log, stderr=log)
    return f"{e['id']} {'ok' if out.exists() and out.stat().st_size else 'MISSING'}"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--run', type=int, default=0, help='generate missing images with N parallel Codex calls')
    ap.add_argument('ids', nargs='*')
    args = ap.parse_args()
    for d in ('prompts', 'out', 'logs'):
        (WORK / d).mkdir(parents=True, exist_ok=True)
    todo = [e for e in exercises() if not args.ids or e['id'] in args.ids]
    for e in todo:
        (WORK / 'prompts' / f"{e['id']}.txt").write_text(prompt(e))
    print(len(todo), 'prompts in', WORK / 'prompts')
    if args.run:
        missing = [e for e in todo if not (WORK / 'out' / f"{e['id']}.png").exists()]
        with ThreadPoolExecutor(args.run) as pool:
            for line in pool.map(generate, missing):
                print(line, flush=True)


if __name__ == '__main__':
    main()
