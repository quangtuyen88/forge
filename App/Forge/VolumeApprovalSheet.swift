import ForgeCore
import SwiftUI

struct VolumeApprovalSheet: View {
  let increase: VolumeIncrease
  let coachName: String
  let onApprove: () -> Void
  let onKeep: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          CoachAvatar(size: 30)
          Text(String(localized: "\(coachName) suggests", bundle: L10n.bundle))
            .forge(15, .semibold)
            .foregroundStyle(Theme.textSecondary)
        }
        HStack(spacing: 14) {
          WorkoutArtTile(exercise: increase.exercise, size: 56)
          VStack(alignment: .leading, spacing: 2) {
            Text(increase.exercise.localizedName)
              .forge(22, .bold)
              .foregroundStyle(Theme.text)
            Text(
              String(
                localized: "\(localizedDayName(increase.dayName)) · this week", bundle: L10n.bundle)
            )
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
          }
        }
        .padding(.top, 18)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(String(localized: "\(increase.fromSets) →", bundle: L10n.bundle))
            .forge(26, .medium)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
          Text(
            String(
              localized: "\(increase.toSets) set\(L10n.pluralSuffix(increase.toSets))",
              bundle: L10n.bundle)
          )
          .forge(40, .bold)
          .foregroundStyle(Theme.text)
          .monospacedDigit()
          Spacer(minLength: 8)
          HStack(spacing: 5) {
            ForEach(0..<min(increase.toSets, 8), id: \.self) { index in
              Capsule()
                .fill(index >= increase.fromSets ? Theme.accent : Theme.track)
                .frame(width: 10, height: 26)
            }
          }
          .accessibilityHidden(true)
        }
        .padding(.top, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          Text(
            String(
              localized: "\(increase.fromSets) to \(increase.toSets) sets", bundle: L10n.bundle)))
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text(String(localized: "\(increase.muscle.a11yName) per week", bundle: L10n.bundle))
              .forge(15)
              .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(
              String(
                localized: "\(increase.weeklyFrom) → \(increase.weeklyTo) sets", bundle: L10n.bundle)
            )
            .forge(15, .semibold)
            .monospacedDigit()
          }
          if let max = increase.weeklyMax, max > 0 {
            Capsule()
              .fill(Theme.track)
              .overlay(alignment: .leading) {
                GeometryReader { geometry in
                  HStack(spacing: 0) {
                    Capsule()
                      .fill(Theme.textSecondary)
                      .frame(width: geometry.size.width * CGFloat(increase.weeklyFrom) / CGFloat(max))
                    Capsule()
                      .fill(Theme.accent)
                      .frame(
                        width: geometry.size.width * CGFloat(increase.weeklyTo - increase.weeklyFrom)
                          / CGFloat(max))
                  }
                }
              }
              .clipShape(Capsule())
              .frame(height: 6)
              .accessibilityHidden(true)
          }
          Text(
            String(
              localized: "Every set hit the top of the rep range last week. This week only.",
              bundle: L10n.bundle)
          )
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.innerSurface))
        .padding(.top, 18)
        Button {
          onApprove()
          dismiss()
        } label: {
          Text(String(localized: "Approve", bundle: L10n.bundle))
        }
        .buttonStyle(PillButtonStyle())
        .accessibilityIdentifier("volumeApproval.approve")
        .padding(.top, 20)
        Button {
          onKeep()
          dismiss()
        } label: {
          Text(
            String(
              localized: "Keep \(increase.fromSets) set\(L10n.pluralSuffix(increase.fromSets))",
              bundle: L10n.bundle)
          )
          .forge(16, .semibold)
          .foregroundStyle(Theme.text)
          .frame(maxWidth: .infinity, minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("volumeApproval.keep")
        .padding(.top, 6)
      }
      .padding(.horizontal, 22)
      .padding(.top, 24)
      .padding(.bottom, 12)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(Theme.page)
    .presentationDetents([.height(560), .large])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(32)
  }
}
