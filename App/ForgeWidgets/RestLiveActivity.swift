import SwiftUI
import WidgetKit

struct RestLiveActivity: Widget {
  private let accent = Color(red: 0x38 / 255, green: 0x66 / 255, blue: 0xD6 / 255)
  private let background = Color(red: 0.07, green: 0.10, blue: 0.20)

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RestActivityAttributes.self) { context in
      HStack(spacing: 12) {
        ZStack {
          Circle().fill(accent)
          Image(systemName: "flame.fill").foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
        VStack(alignment: .leading) {
          Text("Rest · \(context.state.exerciseName)")
            .font(.system(size: 15, weight: .semibold))
          Text(context.state.nextSet <= context.state.totalSets
            ? "Set \(context.state.nextSet) of \(context.state.totalSets) next"
            : "Next exercise")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 6) {
          countdown(end: context.state.endDate, size: 30, weight: .bold, width: 92)
          if let hr = context.state.heartRate {
            Label("\(hr)", systemImage: "heart.fill")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.secondary)
          }
          Button(intent: SkipRestIntent()) {
            Text("Skip")
          }
          .buttonStyle(.borderedProminent)
          .tint(accent)
          .controlSize(.small)
        }
      }
      .padding(14)
      .foregroundStyle(.white)
      .activityBackgroundTint(background)
      .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 6) {
            Image(systemName: "flame.fill").foregroundStyle(accent)
            Text("Rest")
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          countdown(end: context.state.endDate, size: 26, weight: .bold, width: nil)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 10) {
            Text(context.state.nextSet <= context.state.totalSets
              ? "\(context.state.exerciseName) · set \(context.state.nextSet) of \(context.state.totalSets)"
              : "Next exercise")
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
            Spacer()
            if let hr = context.state.heartRate {
              Label("\(hr)", systemImage: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            Button(intent: SkipRestIntent()) {
              Text("Skip")
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.small)
          }
        }
      } compactLeading: {
        Image(systemName: "flame.fill").foregroundStyle(accent)
      } compactTrailing: {
        countdown(end: context.state.endDate, size: 14, weight: .semibold, width: 44)
      } minimal: {
        Image(systemName: "timer")
      }
    }
  }

  @ViewBuilder
  private func countdown(end: Date, size: CGFloat, weight: Font.Weight, width: CGFloat?) -> some View {
    if end <= .now {
      Text("Go")
        .font(.system(size: size, weight: weight, design: .rounded))
        .monospacedDigit()
        .frame(width: width, alignment: .trailing)
    } else {
      Text(timerInterval: Date.now...end, countsDown: true)
        .font(.system(size: size, weight: weight, design: .rounded))
        .monospacedDigit()
        .frame(width: width, alignment: .trailing)
    }
  }
}
