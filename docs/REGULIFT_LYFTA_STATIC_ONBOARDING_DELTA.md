# Regulift — Lyfta-inspired onboarding, static illustrations only

**Date:** 23 September 2026  
**Status:** Design recommendation and agent handoff; no app implementation, illustration generation, or app tests performed.  
**Decision:** No new mandatory onboarding step. Consider one optional muscle-emphasis disclosure only when existing engine support is verified. Improve presentation before expanding the questionnaire.  
**Current scope change:** Rive and custom illustration animation are out of scope. This document supersedes the animation asset/build tasks in the earlier onboarding/Rive handoff; it does not supersede the planning, privacy, billing, or data-correctness requirements.

## 1. Evidence and limits

### Primary reference: the uploaded Lyfta clip

Source: `__________AI______-_____________________________33______4950_________________Lyfta________________EqZgyJ.mp4`.

The file is approximately 11.75 seconds, 1170 × 2532, and contains an audio track. Review covered the visible timeline using 59 frames at approximately 0.2-second intervals and full-resolution inspection of representative screens. Audio was not evaluated.

This is a recording of an Onbo Hub player displaying a Lyfta onboarding example at a selected 4× playback speed. The embedded playhead reaches approximately 00:43 of a displayed 01:36 total. The upload ends on equipment selection. It does **not** show the complete onboarding, a final generated plan, payment, retention, revenue, or an experiment result. Do not infer the full step count or business performance from the filename or from this excerpt.

Times below are positions in the **uploaded 11.75-second clip**, not the embedded player's time.

### Comparison baseline

The earlier user-uploaded `regulift-onboarding.mp4` showed goal, experience, weekly frequency, duration, equipment, bodyweight/current lifts, constraints, a practice example, plan preview, an offer, and the first Today state. It also showed Coach selection and additional introductory content. These observations are not an inventory of the latest repository: inspect the checkout before changing anything.

Important existing behavior to retain:

- Starting loads are explicitly described as estimates based on bodyweight when current lifts are omitted.
- The practice example says nothing is saved.
- The plan preview leads to the actual paid-access route when needed.
- Required constraints and the actual first-workout/check-in behavior must remain intact.

### Visible Lyfta sequence and proposed decisions

| Clip time | Visible reference | Regulift decision |
|---|---|---|
| 00:00–00:00.6 | LYFTA splash | Do not add another mandatory splash or delay. |
| 00:00.8–00:01.2 | Product preview; "Get stronger. See your progress." | Use one concise introduction, with original static artwork and an immediately available action. |
| 00:01.4–00:02.0 | Gender question with two anatomical figures | Do not add demographic questions just to select an illustration. Audit any genuine engine dependency separately. |
| 00:02.2–00:02.6 | Six illustrated goal tiles; multiple selection | Improve the existing goal choices visually. Keep Regulift's actual supported goals and selection semantics. |
| 00:02.8–00:03.0 | A claim about logged lifts and a two-person illustration | Borrow the coherent illustration style, not the number or an extra proof screen. The claim was not independently verified. |
| 00:03.2–00:03.6 | "What would you like to do most?" — log, follow programs, learn exercises | Keep build-plan and existing import entry points clear. Do not add three product modes or a new logger-only branch. |
| 00:03.8–00:04.8 | Muscle-focus chips and highlighted front/back figures | Candidate optional disclosure, reusing supported muscle-emphasis preferences. No new mandatory page. |
| 00:05.0–00:05.2 | "How did you hear about Lyfta?" | Omit from the required path. A separate optional acquisition survey can be considered later. |
| 00:05.6–00:06.0 | "Why do you track your workouts?" | Do not duplicate the main goal question without a distinct, implemented use. |
| 00:06.4–00:06.8 | Training for an event or personal milestone | Keep specific milestones in the existing Goals destination or optional preview action. Do not add event/peaking support in a UI task. |
| 00:07.0–00:07.2 | Illustrated benefit page about knowing when to push | Consolidate the useful explanation into the existing welcome or practice example. No additional mandatory interstitial. |
| 00:07.4–00:07.8 | Lifting experience choices | Restyle the existing experience question, preserving its model values. |
| 00:08.0–00:08.2 | Rating claim/testimonial illustration | Do not import competitors' claims or fabricated testimonials. No new screen in this pass. |
| 00:08.4–00:08.8 | Weekly frequency from one to seven days, with labels | Use only Regulift's supported configurations. Do not equate more days with a more serious user. |
| 00:09.0–00:09.6 | Workout reminder explanation and notification prompt | Offer reminders after an actual schedule is accepted or when enabling reminders; denial must not block training. |
| 00:09.8–00:10.2 | Commitment-duration question | Omit: available weekly time already supplies the necessary constraint for this scope. |
| 00:10.4–00:10.6 | Commitment graph comparing a few weeks and three months | Omit: no metric, methodology, or individual evidence is established in the clip. |
| 00:10.8–00:11.6 | Equipment rows with pictograms and selected states | Strong visual reference for the existing selector; validate exact equipment contents and combination rules. |

## 2. What to add versus what to improve

### Add only this optional input, subject to an engine audit

**Title:** Anything you want to emphasize?  
**Helper:** Optional. Choose a focus or keep the standard balance.  
**Location:** A disclosure under the existing goal question, or an Edit focus link on the plan preview. Not a new required step.

Illustrative choices: Balanced training / Chest / Back / Legs / Shoulders / Arms / Glutes. Map to actual supported IDs. Do not introduce unsupported muscle categories simply to match the reference.

Requirements:

1. Find the existing muscle-emphasis consumer and tests. The earlier QA material mentions an emphasis surface, not proof of complete engine support.
2. The untouched state means **no extra emphasis supplied**, not that the user actively reported every preference. Show the existing standard-balanced behavior transparently.
3. Limit choices to a small number if consistent with existing policy; one or two priorities is a proposed UX starting point, not a physiological rule.
4. Maintain whole-plan requirements, equipment availability, time budget, and explicit restrictions. Never blindly add a fixed number of sets in the view.
5. A selection may change approved exercise choices, distribution, or priority only through the existing engine. If no change is feasible, show that honestly instead of claiming personalization occurred.
6. Treat preference separately from discomfort, injury, contraindication, measurement, or an observed weakness. A colored muscle map is not a diagnosis.
7. Change/back/reset must invalidate dependent preview data, not overwrite an active plan silently.
8. Coach may mention a confirmed preference through the existing permitted data projection; it must not invent a volume effect or claim the plan changed without a real decision.
9. When no real engine consumer exists, **do not ship the question**. Keep the illustration work independent from that feature decision.

### Improve the existing entry routes, not the number of steps

Suggested welcome actions:

- Primary: **Build my plan**.
- Secondary: **Import training history**, reusing the existing preview/import/confirmation route.
- Returning user: existing sign-in/restore route.

Training-history import is not the same as importing an executable program. Preserve those distinct formats, previews and activation decisions. Do not promise an import preserves a user's routine unless the implemented path actually does so.

### Improve an existing summary, not add another sales interstitial

Add a concise **Built around your setup** section to the existing plan preview, populated from confirmed inputs:

- Actual days and time preference.
- Actual equipment setup.
- Confirmed emphasis, only if present and meaningfully used.

Do not add a fictional recovery score, projected body transformation, generic claim that everyone gets stronger, or a statement that the app already learned from workouts that did not happen.

## 3. Recommended flow

```text
One welcome
  ├─ Build my plan
  │    → Goal [optional emphasis disclosure only if supported]
  │    → Experience
  │    → Available days and session length
  │    → Actual equipment
  │    → Required starting inputs [optional lift fields collapsed]
  │    → Necessary constraints
  │    → Actual starting-plan preview
  │         └─ Optional existing practice example, always isolated
  │    → Real paid-access decision when required
  │    → Prepare or Start the first workout, per existing policy
  └─ Existing import / returning-user route
       → ask only for missing necessary inputs
       → preview and confirm through existing contracts
```

Do not impose a fixed four-step rule if the engine needs more inputs. Combine related inputs only when readability and large text permit it. The core route should have no additional required question from this Lyfta review.

Optional reminders belong after a real schedule is accepted or at feature use, not before equipment selection just because the reference does it. An accepted reminder preference is not notification permission. Handle denied permission and changing weekdays correctly. [A1]

## 4. Illustration direction — static, original, task-related

**Direction:** Calm, approachable strength training. Keep the active Regulift theme and semantic tokens. The latest review direction used blue with neutral surfaces; confirm the repository rather than switching back to an older lime concept.

### Asset inventory

| Asset | Placement | Content and function | Priority |
|---|---|---|---|
| `onboarding_training_log` | Single welcome | One original, ordinary-looking lifter beside a dumbbell and a training-log card. At most one faint next-session card; no numerical chart or fake PR. | P0 |
| `goal_symbols` | Existing goal rows | A small coordinated symbol for each supported goal. Same bounding box, stroke/shape language and optical weight. Labels remain native. | P0 |
| `equipment_symbols` | Existing equipment choices | Recognizable barbell/rack, dumbbells, bands or machine objects only for supported categories. No false equipment implication. | P0 |
| `schedule_symbol` | Days/time header, if it replaces text | Simple blank calendar plus clock; actual days, numbers and selection are native. Reuse a native icon when sufficient. | Optional polish |
| `focus_body_map` | Optional emphasis disclosure | Neutral, readable front/back silhouette with discrete selected regions. Static fills react to state; native labeled choices are the interaction. | Conditional on emphasis shipping |

Do not require a large hero on every page. On numbers and constraints screens, useful controls take precedence over artwork. The actual week/session list is the visual content on the plan preview.

### Shared artwork brief

```text
Create original static artwork for an approachable strength-training app.
Use one coherent editorial vector-like style, clear silhouettes, restrained
shading, and the supplied Regulift palette. Transparent background.
No text, embedded UI, numbers, logos, screenshots, trophies, progress graphs,
medical claims, exaggerated transformation, or decorative particle effects.
Avoid plastic 3D, generic glowing gradients, and an oversized heroic physique.
Leave breathing room around the object. The result must remain recognizable
at its real in-app size and against both supported appearance backgrounds.
```

This is an asset brief for later generation or illustration, not an asset generated in this handoff. Supply the actual palette and output sizes from the target layout before production.

### Scene-specific prompts

**Welcome:** An original adult lifter in ordinary gym clothing, relaxed beside a bench and dumbbell, with a small blank training-log card. One clear group, no crowded scene. Suggest preparation and recording rather than a miraculous result. This is decorative artwork, not exercise-technique instruction.

**Goal symbols:** A matching family of compact symbols for the actual supported goal labels. Distinct shape as well as color. Do not use a before/after body comparison or imply one appearance represents failure.

**Equipment symbols:** Isolated, readable equipment objects viewed from the same angle. Draw only the equipment named in the intended choice. A Home or Hotel location name is not an equipment inventory.

**Optional focus map:** Neutral standing front/back silhouettes on transparent background. Separate reviewable region shapes; no red pain markers, growth guarantees, or sex-based strength inference. Pair every region with a native text choice. Prefer reusing an existing reviewed map when one exists.

### Production integration

- Keep editable originals and documented ownership/license; do not extract Lyfta characters or reuse its screenshots as product assets.
- Use the asset pipeline already supported by the iOS project; don't introduce a new SVG renderer simply for these illustrations.
- Keep all labels, values, selected marks, buttons, and accessibility semantics native and localized.
- Bundle production assets; a network image load must never gate Continue.
- A failed/missing asset falls back to a plain native icon or no decoration without changing the workflow.
- Make artwork shrink or disappear when large text or the keyboard needs space. Never shrink essential text to save a hero image.
- Keep visual selection identifiable by a checkmark and/or label, not color alone. [A2]
- Use one shared component and spacing system; do not mix independent illustration/icon families on one screen. [U3]
- No Rive SDK, `.riv` file, animation state machine, motion agent, or Rive export task in this scope.

## 5. Agent implementation prompt

```text
Read REGULIFT_LYFTA_STATIC_ONBOARDING_DELTA.md.

This is an original STATIC-ILLUSTRATION and onboarding-hierarchy task.
Rive is out of scope. Do not add an animation dependency.

Inspect the latest onboarding views, required engine inputs, goal selection,
equipment presets, actual muscle-emphasis support, import routes, plan preview,
paid-access routing, and supported appearance/locales before changing code.
Do not assume the last video exactly matches the current checkout.

Borrow from the supplied Lyfta excerpt:
- Illustrated goal choices with concise labels.
- Recognizable equipment pictograms and obvious selection.
- A coherent original illustration family.
- Optional muscle-focus presentation only if the existing engine supports it.

Do not copy its full sequence, demographic gate, acquisition survey,
duplicate motivation questions, commitment chart, rating/lift-count claims,
notification timing, artwork, or one-to-seven-day product scope.
Do not turn its application-intent question into new Regulift product modes.

Create a KEEP / COLLAPSE / MOVE / OPTIONAL map for current onboarding content.
Do not remove required starting inputs, restrictions, consent or billing terms.

Build the first approval slice only:
1. Restyle the existing Goal screen with original static symbols.
2. Restyle the existing Equipment screen using the same design system.
3. Put one small approved welcome illustration into the existing welcome
   only after the two choice screens establish the asset style.

Do not add mandatory screens. Keep the optional focus question disabled
until its real engine consumer and tests are identified. Preserve goal and
focus semantics; multiple goals are not enabled just because Lyfta allows it.

Render default, selected, invalid/unsupported, Back-restored, smallest-phone,
large-text, and supported light/dark states. Use native controls and actual
layout screenshots, not a single composite image as implementation evidence.

Return changed files, content map, asset inventory/provenance, screenshots,
tests actually run, and unresolved behavior. Stop for approval before expanding.
```

## 6. Focused acceptance checks

These are requirements for the coder/QA; none has been executed on the app by this reviewer.

| ID | Scenario | Required outcome |
|---|---|---|
| LS-01 | Complete ordinary manual setup | No added required question from this change; same supported valid configuration. |
| LS-02 | Select goal, Back, return | Selection/draft preserved; no new goal mapping or multiple-selection semantics. |
| LS-03 | Skip optional focus | Standard existing behavior; no fabricated explicit preference. |
| LS-04 | Apply supported emphasis | Preview changes only through the existing engine; actual effect traceable or limitation shown. |
| LS-05 | Focus conflicts with restrictions/equipment/time | Constraint policy respected; no hidden extra volume or unsupported claim. |
| LS-06 | Change goal/focus/equipment after preview | Dependent preview invalidated; historical data and active plan unchanged before approval. |
| LS-07 | Import training history | Original preview/confirmation works; history is not misrepresented as an executable plan. |
| LS-08 | Optional lift values collapsed/blank | True required inputs remain validated; estimates labeled; no invented observed load. |
| LS-09 | Enter practice example and close/retry | No workout, PR, streak, goal progress, or real plan mutation from the example. |
| LS-10 | VoiceOver and large text | Native labels/selection/Back/Continue work; optional artwork does not hide controls. |
| LS-11 | Light/dark, longest supported translations, small phone | Clear contrast, no critical clipping; two-column choices stack when needed. |
| LS-12 | Artwork unavailable and offline launch | Onboarding remains usable; no blocking download or new privacy export. |
| LS-13 | Trial ineligible/returning subscriber/purchase cancelled | Existing entitlement truth and correct action; setup retained; no fictional free offer. |
| LS-14 | Reminder denied or deferred | Training still works; no prompt loop or claimed enabled notification. |
| LS-15 | First Today after activation | Correct week/session; no fictional past progress; prepare/check-in/start sequence unchanged and explicit. |
| LS-16 | Static mock and actual preview compared | All numbers/labels remain real native state; illustration cannot carry stale values. |

Ask a small group of target lifters to choose a setup without coaching. Record where they hesitate and whether they can explain their starting plan. A small usability check reveals obstacles; it does not establish a revenue or conversion uplift.

## 7. Interface-polish review coverage

**Mode:** Full, scoped to the visible Lyfta excerpt and its proposed adaptation to Regulift.  
**Framework target:** Existing SwiftUI/native iOS and project styling. Repository components were not inspected here.

| Category | Evidence inspected | Result / boundary |
|---|---|---|
| Typography | Full-resolution goal, focus, intent, benefit, and equipment screens | Clear hierarchy is useful; exact point sizes, contrast and Dynamic Type not verified. |
| Surfaces | Choice rows/tiles, selection, footer controls | Reuse consistent shapes; actual tap targets/safe-area behavior not verified from video. |
| Animations | Visible accelerated transitions; current user scope | Real timing not evaluated. No new custom illustration animation proposed. |
| Icons | Goal symbols and equipment pictograms | Borrow readability and consistency; create original assets. |
| Performance | Metadata and sampling only | App startup, asset decoding, memory and frame timing not tested. |

### Findings for the proposed Regulift adaptation

These are design risks to address in the handoff, not findings that Lyfta violates a policy.

| Severity | Location | Before / candidate | After | Why |
|---|---|---|---|---|
| MEDIUM | Goal/equipment | Add all reference options and symbols | Keep supported categories, original consistent small assets | Avoids false choices and visual overload. |
| MEDIUM | Optional focus | Another mandatory questionnaire screen | Disclosure with a tested engine consumer or omit | Reduces task burden and avoids cosmetic personalization. |
| MEDIUM | Intro/benefit screens | More mandatory proof/benefit pages | One original welcome and existing optional practice | Avoids repeated explanation before useful action. |
| MEDIUM | Artwork placement | Large hero on all steps | One welcome scene, compact choice symbols | Preserves room for controls and required fields. |
| MEDIUM | Preview | Unsupported improvement chart | Real starting plan, estimates and confirmed preferences | Keeps data meaning truthful. |
| MEDIUM | Permissions | Reminder request before a usable schedule | Contextual optional reminder with a real schedule | Separates setup from optional access. |
| LOW | Icon surfaces | Different art/outline weights per page | One shared icon/illustration family | Improves visual continuity. |

### Considered but rejected

| Candidate | Rejected because |
|---|---|
| Full anatomical/gender gate | Not necessary merely to choose visual assets; genuine input dependencies must be justified separately. |
| Three product modes (log / programs / learn) | Expands product/navigation scope rather than simplifying the existing adaptive-plan journey. |
| Commitment chart and obligatory pledge | Adds no verified plan input in this scope; displayed chart does not establish a measurable forecast. |
| Asset or animation on every screen | Adds repeated visual competition and a larger content pipeline without a demonstrated task benefit. |

### Verification and verdict

- Read media metadata with `ffprobe`; inspected 59 sampled frames and representative full-size crops.
- Compared with the visible prior Regulift onboarding evidence; no new repository inspection.
- Checked official Apple onboarding/accessibility guidance on 23 September 2026.
- This Markdown and referenced source inventory were checked for consistency.
- No assets generated, no app build changed, and no QA acceptance test executed.

**Design verdict: Needs changes to the proposed adaptation before implementation approval.** Approve the first static choice screens, not a copied Lyfta flow. Unverified: runtime layout, real accessibility, pipeline output, performance, engine mapping, purchase and persistence behavior.

## Sources

[V1] Current Lyfta upload, filename in Section 1. A cropped reference still retains its clip timestamp; the internal working evidence manifest records full-frame times and crop bounds. Marketing numbers are attributed to the displayed reference, not verified.

[U1] Prior user upload `regulift-onboarding.mp4`: baseline/current lifts at approximately 00:29–00:34, constraints around 00:37, isolated practice around 00:42–00:48, plan at 00:51–00:52, offer around 00:54, first Today around 00:59.

[U2] Supplied `REGULIFT_QA_RESULTS(1).md`, revision 2, 21 September 2026: workflow W04 mentions the muscle-emphasis surface. This is not validation of an unseen engine consumer or a later build.

[U3] Supplied `make-interfaces-feel-better` skill: use existing styling; stable dynamic numbers; readable separated touch targets; consistent icons; static feedback and restrained motion. Web-specific CSS recipes are not native Swift implementation instructions.

[A1] Apple, Human Interface Guidelines — Onboarding, consulted 23 September 2026. `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/onboarding.json`

[A2] Apple, Human Interface Guidelines — Accessibility, consulted 23 September 2026. `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.json`

---

**First task:** inspect the existing Goal and Equipment views, create a small original static asset family, render those two screens with existing behavior, and stop for visual approval. No new mandatory onboarding step.
