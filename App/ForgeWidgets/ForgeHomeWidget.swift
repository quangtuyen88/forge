import SwiftUI
import WidgetKit

private let widgetAccent = Color(red: 0x38 / 255, green: 0x66 / 255, blue: 0xD6 / 255)
private let widgetBackground = Color(red: 0.07, green: 0.10, blue: 0.20)

struct HomeEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot?
}

struct HomeProvider: TimelineProvider {
  func placeholder(in context: Context) -> HomeEntry {
    HomeEntry(date: .now, snapshot: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
    completion(HomeEntry(date: .now, snapshot: WidgetBridge.load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
    completion(Timeline(entries: [HomeEntry(date: .now, snapshot: WidgetBridge.load())], policy: .never))
  }
}

struct ForgeHomeWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "app.regulift.home", provider: HomeProvider()) { entry in
      HomeWidgetView(entry: entry)
    }
    .configurationDisplayName("Today's session")
    .description("Your next session, streak and weekly volume.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
  }
}

private struct HomeWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: HomeEntry

  var body: some View {
    switch family {
    case .systemMedium:
      medium.containerBackground(for: .widget) { widgetBackground }
    case .accessoryRectangular:
      rectangular.containerBackground(for: .widget) { Color.clear }
    case .accessoryCircular:
      circular.containerBackground(for: .widget) { Color.clear }
    default:
      small.containerBackground(for: .widget) { widgetBackground }
    }
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 6) {
      sessionBody
      Spacer(minLength: 0)
      if let s = entry.snapshot {
        Text("Week sets \(s.weekSets)/\(s.weekTarget)")
          .font(.system(size: 13, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(.white)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(14)
  }

  private var medium: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        sessionBody
        Spacer(minLength: 0)
        if let s = entry.snapshot {
          Text("Week sets \(s.weekSets)/\(s.weekTarget)")
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
        }
      }
      Spacer(minLength: 0)
      if let s = entry.snapshot {
        VStack(spacing: 6) {
          ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 5)
            Circle()
              .trim(from: 0, to: progress)
              .stroke(widgetAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Text("\(s.streakWeeks) wk")
              .font(.system(size: 13, weight: .bold))
              .monospacedDigit()
              .foregroundStyle(.white)
              .minimumScaleFactor(0.7)
          }
          .frame(width: 64, height: 64)
          Text("streak")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.7))
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(14)
  }

  private var sessionBody: some View {
    Group {
      if let s = entry.snapshot {
        HStack(spacing: 8) {
          ZStack {
            Circle().fill(widgetAccent)
            Image(systemName: "flame.fill")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.white)
          }
          .frame(width: 26, height: 26)
          VStack(alignment: .leading, spacing: 2) {
            Text(s.dayName)
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.6)
            Text("≈ \(s.minutes) min · \(s.exercises) exercises")
              .font(.system(size: 13))
              .foregroundStyle(.white.opacity(0.7))
          }
        }
      } else {
        Text("Open Regulift")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
      }
    }
  }

  private var rectangular: some View {
    Group {
      if let s = entry.snapshot {
        VStack(alignment: .leading, spacing: 2) {
          Text(s.dayName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
          Text("sets \(s.weekSets)/\(s.weekTarget)")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      } else {
        Text("Open Regulift").font(.system(size: 14, weight: .semibold))
      }
    }
  }

  private var circular: some View {
    Group {
      if entry.snapshot != nil {
        Gauge(value: progress, in: 0...1) {
          Text("Week")
        } currentValueLabel: {
          Text("\(entry.snapshot?.weekSets ?? 0)")
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
      } else {
        Text("Open Regulift").font(.system(size: 11, weight: .semibold))
      }
    }
  }

  private var progress: Double {
    guard let s = entry.snapshot, s.weekTarget > 0 else { return 0 }
    return min(1, Double(s.weekSets) / Double(s.weekTarget))
  }
}
