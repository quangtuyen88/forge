# Roadmap baseline regression matrix

This matrix freezes existing behavior before the advanced roadmap extends persistence and action contracts.

| Workflow | Automated evidence | Required invariant |
|---|---|---|
| Onboarding and generated plan | `.maestro/01-onboarding.yaml`, `e2e/onboarding-profile.yaml`, `ProgramTests` | Profile and first week persist; back cannot re-enter completed onboarding. |
| CSV history import and plan audit | `ImportAuditTests`, onboarding/profile E2E | Unknown exercises remain unresolved; imported history never silently mutates completed sessions. |
| Workout start, logging and resume | `.maestro/03-logger.yaml`, `10-abandoned-session.yaml`, `12-workout-tools.yaml` | Logged sets and active session survive relaunch; finishing is explicit. |
| Next-set adaptation | `ProgressionTests`, `AutoregulationTests` | Same input yields the same load decision and bounded increment. |
| Missed-workout recovery | `WeekRepairTests` and Today repair UI | Protected/completed work is not rewritten; each alternative explains the trade-off. |
| Injury/equipment substitution | `SubstitutionTests`, `ProgramTests` | Substitution respects available equipment and injury flags. |
| Deload | `MesocycleTests`, `AutoregulationTests` | Week 6 lowers sets and caps effort without rewriting history. |
| Confirmed Coach action | server output/action guard tests, `.maestro/13-coach-security.yaml` | No mutation occurs before validation and visible confirmation. |
| Prompt-attack handling | `PromptSecurityTests`, server guard tests | Direct, indirect and split-turn attacks do not reach mutation tools. |
| Nutrition and program roadmap | `NutritionTests`, `.maestro/15-plan-fuel.yaml` | Base targets remain intact; roadmap is deterministic and muscle percentages are labeled as planned set share. |
| Load semantics | `LoadSemanticsTests` | Legacy loads stay ambiguous; incompatible equipment/conventions do not compare. |

## Release gates

1. `make build-ios`
2. `swift test --package-path ForgeCore`
3. `pnpm --dir server run build && pnpm --dir server test`
4. `make test-app-e2e`
5. Retained-store launch after additive model changes

Failures in this matrix block feature rollout. New roadmap work must add a row or extend an existing invariant rather than creating an isolated test path.
