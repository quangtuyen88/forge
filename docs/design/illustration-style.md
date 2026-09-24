# Illustration style sheet

The 20 onboarding, empty-state, goal and equipment illustrations (names listed below) are generated with the GPT image model through the Codex CLI from this sheet as a 1024 px transparent PNG, then installed at 200/400/600 px under their existing asset names.

## Style

- Friendly soft-3D objects: matte clay / soft plastic look, generously rounded edges, chunky proportions, clean simple shapes. Think premium app-icon objects, not realistic renders.
- View: three-quarter isometric from slightly above, centered, filling about 80 % of the canvas with even margins.
- Light: soft key light from the upper left, gentle ambient occlusion, one soft contact shadow directly under the object group. No rim glow, no sparkles, no lens effects.
- Palette (use only these, plus white and a warm light gray for neutral parts):
  - Regulift blue #2F7BFF (lead color, on the main object)
  - Coral #FF7A59
  - Sunny yellow #FFC83D
  - Mint green #3CCB8A
  - Sky blue #8CC8FF
  - Dark details only in soft charcoal #3A3F4B
- Background: fully transparent (PNG with alpha). No floor, no backdrop, no frame, no text, no letters, no numbers, no logos, no people, no hands.
- Mood: cheerful, encouraging, tidy. Same scale feel and lighting across every image.
- The goal symbols may show one stylized arm made of Regulift blue clay (no skin tone, no face); nothing else shows people or hands.
- Output: one square PNG, 1024 × 1024, transparent background.

## Subjects

| Asset | Subject |
| --- | --- |
| art-plan | a training plan clipboard with three checked rows and a coach whistle beside it |
| art-schedule | a friendly desk calendar with a few day squares marked in blue, mint and coral, and a small blue dumbbell leaning against it |
| art-goal | a bullseye target with blue and white rings and a coral arrow in the center, with a small yellow trophy beside it |
| art-equipment | a small gym set: a compact dumbbell rack holding three pairs of dumbbells, a kettlebell and a coiled resistance band in front |
| art-numbers | a bathroom scale with a blank display beside a small stack of weight plates in blue, coral and yellow |
| art-empty-progress | a bar chart with four rising rounded bars from sky blue to blue and a mint upward arrow curving over them |
| art-empty-coach | two rounded chat bubbles: a blue one in front with a small white dumbbell shape on it and a sky blue one behind it |
| art-injury | a mint foam roller with a coiled coral resistance band and a small blue ice pack |
| art-pro | a glossy yellow trophy cup with a blue star emblem on the front, standing on a small blue base |
| art-rest | a round stopwatch in blue and white with a coral start button and the hand pointing straight up |
| art-welcome | a flat bench, one blue dumbbell and a blank training-log card with two mint checks, a paler next-session card behind it |
| goal-hypertrophy | a stylized blue clay arm flexing its biceps |
| goal-strength | a short heavy barbell with thick blue plates and yellow outer plates, the bar bowing under the load |
| goal-both | the goal-hypertrophy arm rising behind the goal-strength barbell |
| eq-barbell | a barbell loaded with one blue and one coral plate on each side, three-quarter view, filling the width |
| eq-dumbbell | a pair of hexagonal dumbbells with blue heads and charcoal handles, one standing upright and one lying down |
| eq-machine | a selectorized weight-stack machine with a stack of blue plates, a selector pin and a simple padded seat |
| eq-cable | a cable pulley tower with a coral handle hanging from the cable |
| eq-bands | three looped resistance bands in coral, yellow and mint, loosely stacked |
| eq-bodyweight | a rolled mint exercise mat standing beside a small blue pull-up bar |

## Generate one image

```bash
codex exec "Read docs/design/illustration-style.md and follow the Style section exactly. Use your image generation tool to create ONE image: <subject>. Request a transparent background. Copy the generated PNG to /tmp/<asset>.png."
```

New members of the family are generated with two or three existing images attached as style references (`codex exec -i <image.png> …`).

Match a new image against an existing one from the family before installing it; install by resizing to 200, 400 and 600 px into `App/Forge/Assets.xcassets/<asset>.imageset/` under the existing file names.
