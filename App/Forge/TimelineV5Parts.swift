// Timeline v5.1 parts (DESIGN.md §12, mock tl5-*.png). Pure views; JourneyTimelineView owns the data.

import ForgeCore
import SwiftUI

/// Week header row: month/week pill menu on the left, ellipsis menu on the right.
struct TimelineWeekRowV5<MonthMenu: View, MoreMenu: View>: View {
  let label: String
  let monthTitle: String
  @ViewBuilder let monthMenu: () -> MonthMenu
  @ViewBuilder let moreMenu: () -> MoreMenu

  init(
    label: String,
    monthTitle: String,
    @ViewBuilder monthMenu: @escaping () -> MonthMenu,
    @ViewBuilder moreMenu: @escaping () -> MoreMenu
  ) {
    self.label = label
    self.monthTitle = monthTitle
    self.monthMenu = monthMenu
    self.moreMenu = moreMenu
  }

  var body: some View {
    HStack(alignment: .center) {
      Menu {
        monthMenu()
      } label: {
        HStack(spacing: 4) {
          Text(verbatim: label)
            .forge(15, .semibold)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
            .lineLimit(1)
          Image(systemName: "chevron.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .accessibilityLabel("Month, \(monthTitle)")
      .accessibilityIdentifier("journey.month")

      Spacer(minLength: 8)

      Menu {
        moreMenu()
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(width: 36, height: 36)
          .background(Circle().fill(Theme.fieldControl))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(String(localized: "More timeline options", bundle: L10n.bundle))
      .accessibilityIdentifier("journey.more")
    }
  }
}

/// Markdown summary line with bold runs re-set to semibold forge.
struct TimelineSummaryV5: View {
  let text: AttributedString

  var body: some View {
    Text(emphasized)
      .font(.forge(18))
      .tracking(-0.2)
      .lineSpacing(2)
      .foregroundStyle(Theme.text)
      .monospacedDigit()
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var emphasized: AttributedString {
    var s = text
    let ranges = Array(s.runs)
      .filter { ($0.inlinePresentationIntent ?? []).contains(.stronglyEmphasized) }
      .map(\.range)
    for range in ranges {
      s[range].font = .forge(18, .semibold)
      s[range].inlinePresentationIntent = nil
    }
    return s
  }
}

/// Horizontal filter chips; scrolls to the selected chip on appear.
struct TimelineChipsV5: View {
  let filter: JourneyFilter
  let onChange: (JourneyFilter) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          chip(String(localized: "All", bundle: L10n.bundle),
               id: "journey.filter.all",
               selected: filter.isAll) {
            onChange(.all)
          }
          chip(String(localized: "Workouts", bundle: L10n.bundle),
               id: "journey.filter.workout",
               selected: filter.categories.contains(.workout)) {
            onChange(filter.toggling(.workout))
          }
          chip(String(localized: "Plan changes", bundle: L10n.bundle),
               id: "journey.filter.programChange",
               selected: filter.categories.contains(.programChange)) {
            onChange(filter.toggling(.programChange))
          }
          chip(String(localized: "Body", bundle: L10n.bundle),
               id: "journey.filter.body",
               selected: filter.categories.contains(.body)) {
            onChange(filter.toggling(.body))
          }
          chip(String(localized: "Notes", bundle: L10n.bundle),
               id: "journey.filter.note",
               selected: filter.categories.contains(.note)) {
            onChange(filter.toggling(.note))
          }
        }
      }
      .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
      .onAppear {
        if let id = firstSelectedID {
          var transaction = Transaction()
          transaction.disablesAnimations = true
          withTransaction(transaction) {
            proxy.scrollTo(id, anchor: .center)
          }
        }
      }
    }
  }

  private var firstSelectedID: String? {
    [
      ("journey.filter.all", filter.isAll),
      ("journey.filter.workout", filter.categories.contains(.workout)),
      ("journey.filter.programChange", filter.categories.contains(.programChange)),
      ("journey.filter.body", filter.categories.contains(.body)),
      ("journey.filter.note", filter.categories.contains(.note)),
    ].first(where: \.1)?.0
  }

  private func chip(_ title: String, id: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .forge(15, .medium)
        .foregroundStyle(selected ? Theme.onAccent : Theme.text)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Capsule().fill(selected ? Theme.accentStrong : Theme.timelineRow))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier(id)
    .id(id)
  }
}

/// Collects the center point of every timeline dot so the rail can span them.
struct TimelineDotAnchorKey: PreferenceKey {
  static var defaultValue: [Anchor<CGPoint>] = []
  static func reduce(value: inout [Anchor<CGPoint>], nextValue: () -> [Anchor<CGPoint>]) {
    value.append(contentsOf: nextValue())
  }
}

/// Groups entries and draws the 1 pt rail behind their dots.
struct TimelineRailGroupV5<Content: View>: View {
  var showsRail: Bool = true
  @ViewBuilder let content: () -> Content

  init(showsRail: Bool = true, @ViewBuilder content: @escaping () -> Content) {
    self.showsRail = showsRail
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .backgroundPreferenceValue(TimelineDotAnchorKey.self) { anchors in
      GeometryReader { proxy in
        if showsRail && anchors.count > 1 {
          let points = anchors.map { proxy[$0] }
          let top = points.map(\.y).min() ?? 0
          let bottom = points.map(\.y).max() ?? 0
          let x = points.first?.x ?? 0
          ZStack(alignment: .topLeading) {
            Rectangle()
              .fill(Theme.innerSurface)
              .frame(width: 1, height: bottom - top)
              .offset(x: x - 0.5, y: top)
          }
          .accessibilityHidden(true)
          .allowsHitTesting(false)
        }
      }
    }
  }
}

/// One timeline entry: 20 pt gutter with its dot on the rail, content beside it.
struct TimelineEntryV5<Content: View>: View {
  var showsRail: Bool = true
  @ViewBuilder let content: () -> Content

  init(showsRail: Bool = true, @ViewBuilder content: @escaping () -> Content) {
    self.showsRail = showsRail
    self.content = content
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      if showsRail {
        dot
      }
      content()
    }
  }

  private var dot: some View {
    Circle()
      .fill(Theme.textSecondary.opacity(0.6))
      .frame(width: 7, height: 7)
      .anchorPreference(key: TimelineDotAnchorKey.self, value: .center) { [$0] }
      .padding(.leading, 0.5)
      .padding(.top, 18.5)
      .frame(width: 20, alignment: .topLeading)
      .accessibilityHidden(true)
  }
}

/// Leading element of a Timeline row: a tinted glyph tile or the coach avatar.
enum TimelineLeadV5 {
  case glyph(String, Color)
  case coach
}

/// Rounded timeline row: lead tile, title, detail, record pill and caller content.
struct TimelineRowV5<Extra: View>: View {
  let lead: TimelineLeadV5
  let title: String
  var isQuote: Bool = false
  var detail: String? = nil
  var record: String? = nil
  var fill: Color = Theme.timelineRow
  @ViewBuilder var extra: () -> Extra

  init(
    lead: TimelineLeadV5,
    title: String,
    isQuote: Bool = false,
    detail: String? = nil,
    record: String? = nil,
    fill: Color = Theme.timelineRow,
    @ViewBuilder extra: @escaping () -> Extra
  ) {
    self.lead = lead
    self.title = title
    self.isQuote = isQuote
    self.detail = detail
    self.record = record
    self.fill = fill
    self.extra = extra
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      leadView
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: title)
          .forge(15, isQuote ? .regular : .semibold)
          .foregroundStyle(Theme.text)
          .monospacedDigit()
          .lineLimit(isQuote ? 2 : nil)
          .fixedSize(horizontal: false, vertical: true)
        if let detail {
          Text(verbatim: detail)
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
        }
        if let record {
          HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Theme.recordRing)
            Text(verbatim: record)
              .forge(13, .medium)
              .foregroundStyle(Theme.recordInk)
              .monospacedDigit()
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
        }
        extra()
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(fill))
    .contentShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
  }

  @ViewBuilder private var leadView: some View {
    switch lead {
    case .glyph(let name, let tint):
      RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
        .fill(Theme.timelineTile)
        .frame(width: 32, height: 32)
        .overlay(
          Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint))
        .accessibilityHidden(true)
    case .coach:
      CoachAvatar(size: 32)
        .accessibilityHidden(true)
    }
  }
}

extension TimelineRowV5 where Extra == EmptyView {
  init(
    lead: TimelineLeadV5,
    title: String,
    isQuote: Bool = false,
    detail: String? = nil,
    record: String? = nil,
    fill: Color = Theme.timelineRow
  ) {
    self.init(lead: lead, title: title, isQuote: isQuote, detail: detail, record: record, fill: fill) {
      EmptyView()
    }
  }
}

/// The coach's pending program change that needs the lifter's OK.
struct TimelineAskRowV5: View {
  let title: String
  let detail: String
  let onReview: () -> Void

  var body: some View {
    TimelineRowV5(lead: .coach, title: title, detail: detail, fill: Theme.accentTint) {
      HStack(spacing: 10) {
        reviewButton
        Text(String(localized: "Needs your OK", bundle: L10n.bundle))
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
      }
      .padding(.top, 9)
    }
    .accessibilityElement(children: .contain)
  }

  private var reviewButton: some View {
    Button(action: onReview) {
      Text(String(localized: "Review", bundle: L10n.bundle))
        .forge(15, .semibold)
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Capsule().fill(Theme.accentStrong))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityLabel(String(localized: "Review \(title)", bundle: L10n.bundle))
  }
}

/// "Today · Tue, Sep 29" day divider heading.
struct TimelineDayHeadingV5: View {
  let word: String?
  let date: String

  var body: some View {
    HStack(spacing: 0) {
      if let word {
        Text(verbatim: word).foregroundStyle(Theme.text)
        Text(verbatim: " · ").foregroundStyle(Theme.textSecondary)
      }
      Text(verbatim: date).foregroundStyle(Theme.textSecondary)
    }
    .forge(13, .semibold)
    .monospacedDigit()
    .lineLimit(1)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// "Week 3 · Sep 21 – 27" label between rail groups.
struct TimelineWeekLabelV5: View {
  let title: String
  let detail: String?

  var body: some View {
    VStack(spacing: 2) {
      HStack(spacing: 12) {
        hair
        Text(verbatim: title)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .monospacedDigit()
          .lineLimit(1)
          .layoutPriority(1)
        hair
      }
      if let detail {
        Text(verbatim: detail)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 28)
    .padding(.bottom, 12)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }

  private var hair: some View {
    Rectangle().fill(Theme.ring).frame(height: 1)
  }
}

/// Glass bar pinned over the list while scrolling a week: week menu, stat, chips.
struct TimelinePinnedBarV5<MonthMenu: View, Chips: View>: View {
  let label: String
  let monthTitle: String
  let stat: String
  @ViewBuilder let monthMenu: () -> MonthMenu
  @ViewBuilder let chips: () -> Chips

  init(
    label: String,
    monthTitle: String,
    stat: String,
    @ViewBuilder monthMenu: @escaping () -> MonthMenu,
    @ViewBuilder chips: @escaping () -> Chips
  ) {
    self.label = label
    self.monthTitle = monthTitle
    self.stat = stat
    self.monthMenu = monthMenu
    self.chips = chips
  }

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 10) {
        Menu {
          monthMenu()
        } label: {
          HStack(spacing: 4) {
            Text(verbatim: label)
              .forge(15, .semibold)
              .foregroundStyle(Theme.text)
              .monospacedDigit()
              .lineLimit(1)
            Image(systemName: "chevron.down")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Theme.textSecondary)
          }
          .frame(minHeight: 40)
          .contentShape(Rectangle())
        }
        .accessibilityLabel("Month, \(monthTitle)")
        .accessibilityIdentifier("journey.pinned.month")

        Spacer(minLength: 8)

        Text(verbatim: stat)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .lineLimit(1)
      }
      .padding(.horizontal, 16)
      .frame(height: 40)
      .floatingGlass(Capsule())
      .padding(.horizontal, 16)

      chips()
    }
    .padding(.top, 6)
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity)
    .background(Theme.page)
  }
}

/// Label for secondary capsule buttons (continue-to-month, etc.).
struct TimelinePillLabelV5: View {
  let title: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
      Text(verbatim: title)
        .forge(16, .semibold)
    }
    .foregroundStyle(Theme.text)
    .padding(.horizontal, 18)
    .frame(height: 40)
    .background(Capsule().fill(Theme.timelineRow))
    .frame(minHeight: 44)
    .contentShape(Capsule())
  }
}

/// Filtered-out empty state with illustration and actions.
struct TimelineEmptyV5<Actions: View>: View {
  let title: String
  let message: String
  @ViewBuilder let actions: () -> Actions

  init(
    title: String,
    message: String,
    @ViewBuilder actions: @escaping () -> Actions
  ) {
    self.title = title
    self.message = message
    self.actions = actions
  }

  var body: some View {
    VStack(spacing: 0) {
      Image("art-empty-notes")
        .resizable()
        .scaledToFill()
        .frame(width: 150, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
            .strokeBorder(Theme.imageOutline, lineWidth: 1))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      Text(verbatim: title)
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
        .multilineTextAlignment(.center)
        .padding(.top, 14)
      Text(verbatim: message)
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)
      VStack(spacing: 10) {
        actions()
      }
      .padding(.top, 16)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 22)
  }
}

/// "Start of September" marker at the month boundary with its continue button.
struct TimelineMonthEndV5: View {
  let title: String
  let caption: String
  let continueTitle: String?
  let onContinue: () -> Void

  var body: some View {
    VStack(spacing: 4) {
      Text(verbatim: title)
        .forge(15, .semibold)
        .foregroundStyle(Theme.text)
      Text(verbatim: caption)
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      if let continueTitle {
        Button(action: onContinue) {
          TimelinePillLabelV5(title: continueTitle, systemImage: "chevron.down")
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("journey.month.continue")
        .padding(.top, 12)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 32)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("journey.monthEnd")
  }
}

#Preview("Timeline v5.1 parts") {
  ScrollView {
    VStack(alignment: .leading, spacing: 0) {
      TimelineWeekRowV5(
        label: "Sep 28 – Oct 4",
        monthTitle: "September 2026",
        monthMenu: { Button("September 2026") {} },
        moreMenu: { Button("More timeline options") {} }
      )
      TimelineSummaryV5(
        text: (try? AttributedString(markdown: "This week you trained **1 of 3** days and set **3 records**.")) ?? ""
      )
      .background(Theme.field)
      TimelineChipsV5(filter: .all) { _ in }
      TimelineRailGroupV5 {
        TimelineEntryV5 {
          TimelineRowV5(
            lead: .glyph("dumbbell.fill", Theme.accentText),
            title: "Session · Lower A",
            detail: "35 min · 12 sets · 4,200 kg",
            record: "Back Squat 115 kg × 8 · +2 more"
          )
        }
        TimelineEntryV5 {
          TimelineAskRowV5(
            title: "Add 2 Lateral Raise sets",
            detail: "Kai · Side delts short of its minimum",
            onReview: {}
          )
        }
        TimelineEntryV5 {
          TimelineRowV5(
            lead: .glyph("quote.opening", Theme.textSecondary),
            title: "Felt strong today, kept the rest tight.",
            isQuote: true
          )
        }
      }
      TimelineWeekLabelV5(title: "Week 3 · Sep 21 – 27", detail: "3 of 3 sessions · 9 records")
      TimelineEmptyV5(
        title: "No notes yet",
        message: "Ask Kai to remember anything from a session."
      ) {
        TimelinePillLabelV5(title: "Log a note", systemImage: "square.and.pencil")
      }
      TimelineMonthEndV5(
        title: "Start of September",
        caption: "Only your own records appear here. Works offline.",
        continueTitle: "Continue to August",
        onContinue: {}
      )
    }
    .padding(.horizontal, Theme.margin)
  }
}
