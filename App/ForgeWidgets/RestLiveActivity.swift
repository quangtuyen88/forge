import SwiftUI
import WidgetKit

struct RestLiveActivity: Widget {

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RestActivityAttributes.self) { context in
      HStack(spacing: 12) {
        ZStack {
          Circle().fill(WidgetTheme.accent)
          Image(systemName: "flame.fill").foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
        VStack(alignment: .leading) {
          Text("Rest · \(context.state.exerciseName)")
            .font(.system(.subheadline, weight: .semibold))
          Text(context.state.nextSet <= context.state.totalSets
            ? String(localized: "Set \(context.state.nextSet) of \(context.state.totalSets) next")
            : String(localized: "Next exercise"))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 6) {
          countdown(end: context.state.endDate, style: .title, weight: .bold, width: 92)
          if let hr = context.state.heartRate {
            Label("\(hr)", systemImage: "heart.fill")
              .font(.system(.caption, weight: .semibold))
              .foregroundStyle(.secondary)
          }
          HStack(spacing: 6) {
            if context.state.canLogNext {
              Button(intent: LogNextSetIntent()) {
                Label("Log set", systemImage: "checkmark")
                  .foregroundStyle(.white)
              }
              .buttonStyle(.borderedProminent)
              .tint(WidgetTheme.accent)
              .controlSize(.small)
            }
            Button(intent: SkipRestIntent()) {
              Text("Skip")
                .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(WidgetTheme.accent)
            .controlSize(.small)
          }
        }
      }
      .padding(14)
      .foregroundStyle(.primary)
      .activityBackgroundTint(WidgetTheme.background)
      .activitySystemActionForegroundColor(.primary)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 6) {
            Image(systemName: "flame.fill").foregroundStyle(WidgetTheme.accent)
            Text("Rest")
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          countdown(end: context.state.endDate, style: .title, weight: .bold, width: nil)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 10) {
            Text(context.state.nextSet <= context.state.totalSets
              ? String(localized: "\(context.state.exerciseName) · set \(context.state.nextSet) of \(context.state.totalSets)")
              : String(localized: "Next exercise"))
              .font(.footnote)
              .foregroundStyle(.secondary)
            Spacer()
            if let hr = context.state.heartRate {
              Label("\(hr)", systemImage: "heart.fill")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
              if context.state.canLogNext {
                Button(intent: LogNextSetIntent()) {
                  Label("Log set", systemImage: "checkmark")
                    .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(WidgetTheme.accent)
                .controlSize(.small)
              }
              Button(intent: SkipRestIntent()) {
                Text("Skip")
                  .foregroundStyle(.white)
              }
              .buttonStyle(.borderedProminent)
              .tint(WidgetTheme.accent)
              .controlSize(.small)
            }
          }
        }
      } compactLeading: {
        Image(systemName: "flame.fill").foregroundStyle(WidgetTheme.accent)
      } compactTrailing: {
        countdown(end: context.state.endDate, style: .subheadline, weight: .semibold, width: 44)
      } minimal: {
        Image(systemName: "timer")
      }
    }
  }

  @ViewBuilder
  private func countdown(end: Date, style: Font.TextStyle, weight: Font.Weight, width: CGFloat?) -> some View {
    if end <= .now {
      Text("Go")
        .font(.system(style, design: .rounded, weight: weight))
        .monospacedDigit()
        .foregroundStyle(WidgetTheme.accentText)
        .frame(width: width, alignment: .trailing)
    } else {
      Text(timerInterval: Date.now...end, countsDown: true)
        .font(.system(style, design: .rounded, weight: weight))
        .monospacedDigit()
        .foregroundStyle(WidgetTheme.accentText)
        .frame(width: width, alignment: .trailing)
    }
  }
}
