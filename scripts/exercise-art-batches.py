import json, os, textwrap

EX = json.load(open('/tmp/forge-art/exercises.json'))
OUT = '/tmp/forge-art/out'
BATCH_DIR = '/tmp/forge-art/batches'
ANCHOR = '/tmp/forge-art/probe/db_lateral_raise.png'
REF = {'wide_grip_inverted_row': '/tmp/forge-art/probe/ref_inverted_row.jpg'}
os.makedirs(OUT, exist_ok=True)
os.makedirs(BATCH_DIR, exist_ok=True)

MUSCLE = {
    'chest': 'the two large chest muscles (pectorals) on the front of the torso',
    'back': 'the large back muscles (latissimus dorsi, the wide muscles on the sides of the back, and the trapezius between the shoulder blades)',
    'quads': 'the front of both thighs (quadriceps)',
    'hamstrings': 'the back of both thighs between buttocks and knee (hamstrings)',
    'glutes': 'the buttocks (glutes), above the thighs',
    'sideDelts': 'the outer cap of both shoulders (side deltoid)',
    'rearDelts': 'the back cap of both shoulders (rear deltoid)',
    'frontDelts': 'the front cap of both shoulders (front deltoid)',
    'triceps': 'the back of both upper arms between shoulder and elbow (triceps); NOT the shoulder caps',
    'biceps': 'the front of both upper arms between shoulder and elbow (biceps); NOT the shoulder caps',
    'calves': 'the back of both lower legs (calves)',
    'abs': 'the abdominal muscles on the front of the stomach (rectus abdominis)',
    'forearms': 'both forearms, wrist to elbow',
}
REAR = {'back', 'rearDelts', 'triceps', 'glutes', 'hamstrings', 'calves'}
EQUIP = {
    'barbell': 'with a barbell', 'dumbbell': 'with dumbbells', 'machine': 'on the machine',
    'cable': 'at a cable station', 'bodyweight': 'with bodyweight only', 'bands': 'with a resistance band',
}
STYLE = ('Same illustration style, same figure, same palette, same figure proportions as the reference. The background must be flat pure white #FFFFFF everywhere: no gray tone, no floor, no shadow, no vignette. '
         'Nothing else in the scene: no extra machines, racks, benches, dumbbells, mirrors or floor beyond what the exercise needs. '
         'Grayscale écorché figure with matte shading and thin dark outlines; equipment in dark charcoal gray. No text, no watermark.')

def prompt(e):
    view = 'three-quarter rear view' if e['primary'] in REAR else 'three-quarter front view'
    syn = [MUSCLE[s] for s in e['synergists'] if s in MUSCLE]
    hl = f"COLOR RULE, follow exactly. Bright royal blue (#0062E6, fully saturated) ONLY on: {MUSCLE[e['primary']]}. Both left and right sides."
    hl += (" Pale sky blue (#A8C8FF, very light, clearly lighter than the royal blue) ONLY on: " + '; '.join(syn) + '. These pale regions must NOT be royal blue.') if syn else ' Nothing is pale blue.'
    hl += ' Every other muscle, including the shoulders, neck, arms and legs not named above, stays plain gray with no blue at all.'
    return (f"{STYLE} Change the exercise to: {e['name']} {EQUIP[e['equipment']]}, mid-repetition, {view}, "
            f"{REDO.get(e['id'], 'pose anatomically correct for this exercise')}. {hl}")

REDO = {}
for line in open('/tmp/forge-art/redo.txt'):
    if '|' in line:
        k, v = line.rstrip('\n').split('|', 1); REDO[k] = v
todo = [e for e in EX if not os.path.exists(f"{OUT}/{e['id']}.jpg")]
SIZE = 26
batches = [todo[i:i + SIZE] for i in range(0, len(todo), SIZE)]
for n, batch in enumerate(batches, 1):
    lines = [textwrap.dedent(f"""\
    Exercise illustrations, batch {n:02d}. Work only; ask nothing; never skip an item.

    Reference image (style anchor): {ANCHOR}
    Output folder: {OUT}

    For EACH item below, in order:
    1. Call image_edit with aspect_ratio "1:1", image [the reference path above], and the item's prompt verbatim.
    2. The tool writes a JPEG into this session's images folder. Immediately copy the newest JPEG there to the item's output path with run_terminal_command:
       f=$(ls -t <session images folder>/*.jpg | head -1); cp "$f" <output path>
       (Find the session images folder once, from the first tool result, and reuse it.)
    3. Move to the next item. Do the calls one at a time so the newest file is never ambiguous.

    At the end run: ls {OUT} | wc -l ; and list any item whose output file is missing or under 20 KB, then retry those once. Report the count and the missing ids in one line.

    Items:
    """)]
    for e in batch:
        ref = f"\n  reference: {REF[e['id']]} (use THIS image as the image_edit reference for this item instead of the anchor)" if e['id'] in REF else ''
        lines.append(f"- id: {e['id']}{ref}\n  output: {OUT}/{e['id']}.jpg\n  prompt: \"{prompt(e)}\"\n")
    open(f'{BATCH_DIR}/{n:02d}.md', 'w').write('\n'.join(lines))
print(len(todo), 'todo,', len(batches), 'batches')
