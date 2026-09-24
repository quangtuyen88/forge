## Source and requirement provenance

- **S1 — REGULIFT_E2E_VIDEO_REVIEW_GOAL.md**, 20 September 2026: G00–G18, acceptance T01–T62 and release definition. AU cases preserve every original expected outcome. The user now reports this goal completed; the earlier video is not evidence of the new build.
- **S2 — REGULIFT_SHARE_CARDS_V2_GOAL.md**, 20 September 2026: §13 T01–T46, selected-field/privacy policy, feature flags and staged rollout. SC cases preserve the outcomes; enable only the shipped subset.
- **S3 — REGULIFT_JEV_GOAL.md**, 20 September 2026: §13 AT-01–AT-28, §12 per-locale evaluation and §14 flags. JV cases preserve outcomes; planned work is not presumed enabled.
- **S4 — FORGECORE_INTEGRATION.md**, 20 September 2026: local engine boundary, real decision evidence, exact-preview consent, idempotency, Health export policy and migration. Repository names remain unverified.
- **S5 — OVERVIEW(1).md**, 17 September 2026: documented product surfaces. Old free-launch/pricing details are superseded by the release manifest; do not freeze draft prices from that file.
- **Q — Proposed release-coverage additions** in this handoff: expanded steps, fixture data, priorities, matrix selection, workflow scripts, qualitative UI checks, additional cases and evidence/go-no-go process. These are not claims of newly found bugs or newly required features. Thresholds/budgets must be agreed before testing.

### External platform references checked 20 September 2026

These references inform the listed platform checks only. The user-provided specifications remain the source of product behavior. This is not an App Review or legal-compliance certification.

- **A1 — App Review Guidelines**, especially completeness, truthful metadata, UGC and privacy/third-party AI disclosures. Use for release review, not invented training requirements. `https://developer.apple.com/app-store/review/guidelines/`
- **A2 — Auto-renewable Subscriptions**: clear billed price/period and access to restoration. `https://developer.apple.com/app-store/subscriptions/`
- **A3 — StoreKit sandbox testing**: distinguish local simulations from account/backend integration and label the test environment. `https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox`
- **A4 — RevenueCat Sandbox Testing**: use the actual configured test environment and record differences from production rather than treating a simulated purchase as production proof. `https://www.revenuecat.com/docs/test-and-launch/sandbox`
- **A5 — Offering account deletion**: distinguish deleting app data/account from ending a store subscription. `https://developer.apple.com/support/offering-account-deletion-in-your-app/`
- **A6 — Apple accessibility guidance**: verify usable controls, adaptive text and assistive interaction on actual targets. Proposed quantitative UI targets in Q are not a certification. `https://developer.apple.com/design/human-interface-guidelines/accessibility`
- **A7 — HealthKit authorization**: missing samples are not a trustworthy indicator that read access was granted or denied; test both without inventing data. `https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data`
