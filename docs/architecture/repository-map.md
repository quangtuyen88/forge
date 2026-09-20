# ReguLift repository map

This map records the existing implementation used by `docs/REGULIFT_IMPLEMENTATION_PLAN.md`. Proposed roadmap names must map to these real modules before code is added.

| Concern | Existing implementation | Primary verification |
|---|---|---|
| Deterministic program engine | `ForgeCore/Sources/ForgeCore/Program.swift`, `Progression.swift`, `Mesocycle.swift`, `Adjustments.swift`, `Fatigue.swift`, `WeekRepair.swift` | `ProgramTests`, `ProgressionTests`, `MesocycleTests`, `AutoregulationTests`, `WeekRepairTests` |
| Exercise and equipment catalogue | `ForgeCore/Sources/ForgeCore/Exercise.swift`, `Substitution.swift`; app Gym Profiles in `TrainingFeaturesView.swift` and `UserProfile.trainingConstraints` | `ProgramTests`, `SubstitutionTests`, `TrainingFeaturesTests` |
| Workout/session persistence | `App/Forge/Models.swift` (`WorkoutSession`, `LoggedSet`), `WorkoutView.swift` | Maestro `03-logger`, `10-abandoned-session`, `12-workout-tools` |
| Decision ledger | `ForgeCore/Sources/ForgeCore/DecisionLedger.swift`, app `DecisionLogEntry` in `Models.swift` | `DecisionLedgerTests`, `DecisionTests` |
| Coach context and routing | `ForgeCore/Sources/ForgeCore/CoachContext.swift`, `App/Forge/CoachAPI.swift`, `OnDeviceCoach.swift`, `server/src/app.ts`, `server/src/providers.ts` | server context/output-guard tests, Maestro `06-coach`, `13-coach-security` |
| Coach actions and memory | `App/Forge/CoachTools.swift`, `CoachView.swift`, typed `CoachNote` in `CoachMessage.swift` | `coach-notes.test.ts`, server output guards, app build |
| Imports and plan audit | `ImportView.swift`, `PlanAuditView.swift`, `ForgeCore/ImportAudit.swift` | Maestro onboarding/profile flow, `ImportAuditTests` |
| Training experiments | `ForgeCore/TrainingFeatures.swift`, `TrainingFeaturesView.swift`, profile experiment payload | `TrainingFeaturesTests`, Maestro `14-adaptive-features` |
| SwiftData schema | `ForgeApp.sharedContainer`, model declarations in `Models.swift`, `NutritionModels.swift`, `CoachMessage.swift` | fresh-install and retained-store simulator flows |
| Sync and conflicts | `App/Forge/SyncEngine.swift`, Worker sync routes in `server/src/app.ts` | server sync tests and app build |
| Entitlements/paywall | `Store.swift`, `PaywallView.swift`, Worker purchase webhooks | Store tests and onboarding E2E |
| Voice | `VoiceControl.swift`, `VoicePipelineAdapters.swift`, `SpeechInput.swift`, deterministic `ForgeCore/VoiceCommand.swift` | voice parser/stability tests, Maestro `12-workout-tools` |
| Watch/widgets/shortcuts | `App/ForgeWatch`, `Widgets`, `ForgeAppIntents.swift`, `WatchSync.swift` | build targets and bridge tests |
| Analytics | `App/Forge/Analytics.swift`; allowlisted Worker events | server/app tests and event review |

## Commands

- iOS simulator build: `make build-ios`
- ForgeCore: `swift test --package-path ForgeCore`
- Worker: `pnpm --dir server run build && pnpm --dir server test`
- Stateful app E2E: `make test-app-e2e`

## Boundaries

- ForgeCore owns deterministic prescriptions and typed comparison rules.
- SwiftData remains offline-first; sync carries domain results, not replayed Coach text.
- HealthKit inputs stay device-local and outside Coach, analytics and public templates.
- Model output is advisory until deterministic validation and required confirmation succeed.
