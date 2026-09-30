import ForgeCore
import SwiftUI
import UIKit

/// Trailing mark of a Settings row: push chevron, pop-up menu chevrons, or nothing.
enum SettingsAccessory { case chevron, menu, none }

/// One row of a Settings hairline list: grey glyph or coach face, title, optional subtitle and value, trailing view.
struct SettingsRow<Trailing: View>: View {
  private let glyph: String?
  private let avatar: Bool
  private let title: String
  private let subtitle: String?
  private let value: String?
  private let titleColor: Color
  private let accessory: SettingsAccessory
  private let trailing: () -> Trailing
  @Environment(\.dynamicTypeSize) private var typeSize

  init(glyph: String? = nil, avatar: Bool = false, title: String, subtitle: String? = nil, value: String? = nil,
       titleColor: Color = Theme.text, accessory: SettingsAccessory = .chevron, @ViewBuilder trailing: @escaping () -> Trailing) {
    self.glyph = glyph
    self.avatar = avatar
    self.title = title
    self.subtitle = subtitle
    self.value = value
    self.titleColor = titleColor
    self.accessory = accessory
    self.trailing = trailing
  }

  /// At large text sizes the value drops under the title instead of squeezing it.
  private var stacked: Bool { typeSize >= .xLarge }

  var body: some View {
    HStack(spacing: 12) {
      if avatar {
        CoachAvatar(size: 28).frame(width: 28)
      } else if let glyph {
        Image(systemName: glyph)
          .scaledSystemFont(20)
          .foregroundStyle(Theme.textSecondary)
          .frame(width: 28)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(title).forge(17).foregroundStyle(titleColor)
        if let subtitle { Text(subtitle).forge(15).foregroundStyle(Theme.textSecondary) }
        if stacked, let value { Text(value).forge(15).foregroundStyle(Theme.textSecondary).monospacedDigit() }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if !stacked, let value {
        Text(value).forge(15).foregroundStyle(Theme.textSecondary).monospacedDigit().lineLimit(1)
          .layoutPriority(1)
          .contentTransition(.opacity)
      }
      trailing()
      switch accessory {
      case .chevron: accessoryGlyph("chevron.forward")
      case .menu: accessoryGlyph("chevron.up.chevron.down")
      case .none: EmptyView()
      }
    }
    .padding(.vertical, 8)
    .frame(minHeight: 52)
    .contentShape(Rectangle())
  }

  private func accessoryGlyph(_ name: String) -> some View {
    Image(systemName: name)
      .scaledSystemFont(13, weight: .semibold)
      .foregroundStyle(Theme.textSecondary)
      .accessibilityHidden(true)
  }
}

extension SettingsRow where Trailing == EmptyView {
  init(glyph: String? = nil, avatar: Bool = false, title: String, subtitle: String? = nil, value: String? = nil,
       titleColor: Color = Theme.text, accessory: SettingsAccessory = .chevron) {
    self.init(glyph: glyph, avatar: avatar, title: title, subtitle: subtitle, value: value,
              titleColor: titleColor, accessory: accessory, trailing: { EmptyView() })
  }
}

/// A switch row: title, optional grey line under it, the system switch in the accent.
struct SettingsToggleRow: View {
  let title: String
  var subtitle: String? = nil
  @Binding var isOn: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
    self.title = title
    self.subtitle = subtitle
    self._isOn = isOn
  }

  var body: some View {
    Toggle(isOn: $isOn) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title).forge(17).foregroundStyle(Theme.text)
        if let subtitle { Text(subtitle).forge(15).foregroundStyle(Theme.textSecondary) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      // The whole row flips the switch, not only the knob.
      .onTapGesture { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { isOn.toggle() } }
    }
    .tint(Theme.accent)
    .padding(.vertical, 8)
    .frame(minHeight: 52)
  }
}

/// 1 pt hairline between rows, inset past the 28 pt glyph column when the rows carry glyphs.
struct SettingsHairline: View {
  var inset: Bool = true

  init(inset: Bool = true) {
    self.inset = inset
  }

  var body: some View {
    Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, inset ? 40 : 0).accessibilityHidden(true)
  }
}

/// Grey section label above a hairline list.
struct SettingsSectionLabel: View {
  private let title: String

  init(_ title: String) { self.title = title }

  var body: some View {
    Text(title)
      .forge(15, .semibold)
      .foregroundStyle(Theme.textSecondary)
      .padding(.top, 24)
      .padding(.bottom, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A Settings page's one-sentence hero on the field: bold statement, grey line, optional clay art at the trailing top.
struct SettingsHero: View {
  let title: String
  var subtitle: String? = nil
  var art: String? = nil

  var body: some View {
    ZStack(alignment: .topTrailing) {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.forge(28, .bold, relativeTo: .title))
          .tracking(-0.5)
          .foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
          .contentTransition(.opacity)
          .accessibilityAddTraits(.isHeader)
        if let subtitle {
          Text(subtitle).forge(15).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
        }
      }
      .padding(.trailing, art == nil ? 0 : 76)
      .frame(maxWidth: .infinity, alignment: .leading)
      if let art {
        Image(art).resizable().scaledToFit().frame(width: 64, height: 64)
          .offset(y: -2).allowsHitTesting(false).accessibilityHidden(true)
      }
    }
    .padding(.top, 2)
  }
}

/// A pushed Settings page: the hero block on the peach field, hairline lists on the white page below.
struct SettingsFieldPage<Field: View, Content: View>: View {
  private let title: String
  private let field: Field
  private let content: Content

  init(title: String, @ViewBuilder field: () -> Field, @ViewBuilder content: () -> Content) {
    self.title = title; self.field = field(); self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        FieldSection { field }
        VStack(alignment: .leading, spacing: 0) { content }
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 40)
          .frame(maxWidth: .infinity, alignment: .leading)
          // The page runs past short content, so the field behind the nav bar never shows below it.
          .background(Theme.page.padding(.bottom, -1000))
      }
    }
    .progressFieldPage(title)
  }
}

/// Marks where a chip sits inside a localized plan-sentence line.
enum PlanSentence { static let slot = "\u{FFFC}" }

/// One line of the plan sentence: localized words around one chip.
struct PlanSentenceLine<Chip: View>: View {
  private let prefix: String
  private let suffix: String
  private let chip: Chip
  @Environment(\.dynamicTypeSize) private var typeSize

  init(template: String, @ViewBuilder chip: () -> Chip) {
    let parts = template.components(separatedBy: PlanSentence.slot)
    prefix = (parts.first ?? "").trimmingCharacters(in: .whitespaces)
    suffix = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
    self.chip = chip()
  }

  var body: some View {
    Group {
      if typeSize.isAccessibilitySize {
        // A vertical list replaces the sentence: each chip becomes its own full-width row.
        chip
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        HStack(spacing: 7) {
          if !prefix.isEmpty { words(prefix) }
          chip
          if !suffix.isEmpty { words(suffix) }
        }
        .padding(.leading, prefix.isEmpty ? -10 : 0)
        .frame(minHeight: 44, alignment: .leading)
      }
    }
  }

  private func words(_ text: String) -> some View {
    Text(text).font(.forge(23, .medium)).tracking(-0.35).foregroundStyle(Theme.text)
      .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
      .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.7)
  }
}

/// A tappable value inside the plan sentence: bold value, orange chevron, white chip on the field.
struct PlanChip: View {
  let value: String
  let label: String
  let action: () -> Void
  @ScaledMetric(relativeTo: .body) private var height: CGFloat = 34
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    Button(action: action) {
      Group {
        if typeSize.isAccessibilitySize {
          HStack(spacing: 8) {
            Text(label)
              .font(.forge(23, .medium)).tracking(-0.35)
              .foregroundStyle(Theme.text)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value)
              .font(.forge(23, .bold)).tracking(-0.35)
              .foregroundStyle(Theme.text)
              .multilineTextAlignment(.trailing)
              .contentTransition(reduceMotion ? .opacity : .numericText())
            Image(systemName: "chevron.down")
              .scaledSystemFont(13, weight: .heavy)
              .foregroundStyle(Theme.accent)
              .accessibilityHidden(true)
          }
          .padding(.leading, 12)
          .padding(.trailing, 8)
          .frame(minHeight: 44)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.fieldChip))
        } else {
          HStack(spacing: 5) {
            Text(value)
              .font(.forge(23, .bold)).tracking(-0.35)
              .foregroundStyle(Theme.text)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .contentTransition(reduceMotion ? .opacity : .numericText())
            Image(systemName: "chevron.down")
              .scaledSystemFont(13, weight: .heavy)
              .foregroundStyle(Theme.accent)
              .accessibilityHidden(true)
          }
          .padding(.leading, 10)
          .padding(.trailing, 8)
          .frame(minHeight: height)
          .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.fieldChip))
        }
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .accessibilityLabel(label)
    .accessibilityValue(value)
  }
}

/// One option in a plan bottom sheet: the pick, its detail, weekly sets, "Now" on the current plan.
struct PlanOptionRow: View {
  let title: String
  let detail: String
  let sets: Int
  var delta: Int? = nil
  let isCurrent: Bool
  let selected: Bool
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(title: String, detail: String, sets: Int, delta: Int? = nil, isCurrent: Bool, selected: Bool,
       action: @escaping () -> Void) {
    self.title = title
    self.detail = detail
    self.sets = sets
    self.delta = delta
    self.isCurrent = isCurrent
    self.selected = selected
    self.action = action
  }

  private var setsText: String { Fmt.int(Double(sets)) }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 8) {
            Text(title).forge(17, .semibold).foregroundStyle(selected ? Theme.onAccent : Theme.text)
            if isCurrent && !selected { nowTag }
          }
          Text(detail).forge(15).foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 8) {
          if selected, let delta, delta != 0 { deltaTag(delta) }
          Text(setsText)
            .forge(17, .medium)
            .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
            .monospacedDigit()
        }
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .scaledSystemFont(24)
          .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary.opacity(0.85))
          .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
      }
      .padding(.leading, 16)
      .padding(.trailing, 14)
      .padding(.vertical, 10)
      .frame(minHeight: 44)
      .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
        .fill(selected ? Theme.accentStrong : Theme.innerSurface))
      .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: selected)
      .contentShape(Rectangle())
    }
    .buttonStyle(OptionPressStyle())
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }

  private var nowTag: some View {
    Text(String(localized: "Now", bundle: L10n.bundle))
      .font(.forge(12, .semibold))
      .foregroundStyle(Theme.text)
      .padding(.horizontal, 7)
      .frame(height: 18)
      .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.track))
  }

  private func deltaTag(_ delta: Int) -> some View {
    Text(PlanPreview.deltaText(delta))
      .font(.forge(13, .bold))
      .monospacedDigit()
      .foregroundStyle(Theme.accentStrong)
      .padding(.horizontal, 7)
      .frame(height: 20)
      .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(.white))
  }

  private var accessibilityText: String {
    var text = "\(title), \(detail), " + String(localized: "\(setsText) sets a week", bundle: L10n.bundle)
    if isCurrent { text += ", " + String(localized: "current plan", bundle: L10n.bundle) }
    return text
  }
}

/// Plan option press: the same control feedback at a gentler scale.
private struct OptionPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PressFeedback(isPressed: configuration.isPressed, scale: 0.98) {
      configuration.label
    }
  }
}

/// A plan sheet's content: title with the check that applies the pick, "Sets a week" column label, options, consequence footer.
/// The sheet's height follows its content.
struct PlanChoiceSheetScaffold<Options: View>: View {
  private let title: String
  private let footer: String
  private let advice: String?
  private let onConfirm: () -> Void
  private let options: Options
  @State private var contentHeight: CGFloat = 460
  @Environment(\.dismiss) private var dismiss

  init(title: String, footer: String, advice: String?, onConfirm: @escaping () -> Void,
       @ViewBuilder options: () -> Options) {
    self.title = title
    self.footer = footer
    self.advice = advice
    self.onConfirm = onConfirm
    self.options = options()
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ZStack {
          Text(title).forge(17, .semibold).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
          HStack {
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark")
                .scaledSystemFont(16, weight: .semibold)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(ControlPressStyle())
            .accessibilityLabel(String(localized: "Cancel", bundle: L10n.bundle))
            Spacer()
            Button(action: onConfirm) {
              Image(systemName: "checkmark")
                .scaledSystemFont(18, weight: .bold)
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.accentStrong))
            }
            .buttonStyle(ControlPressStyle())
            .accessibilityLabel(String(localized: "Save", bundle: L10n.bundle))
            .accessibilityIdentifier("settings.sheet.confirm")
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .frame(minHeight: 58)
        Text(String(localized: "Sets a week", bundle: L10n.bundle))
          .forge(13, .semibold).foregroundStyle(Theme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.trailing, 70)          // 16 sheet inset + 54 over the numbers
          .padding(.top, 2).padding(.bottom, 6)
          .accessibilityHidden(true)
        VStack(spacing: 8) { options }.padding(.horizontal, 16)
        VStack(alignment: .leading, spacing: 6) {
          Text(footer).forge(15).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true).contentTransition(.opacity)
          if let advice {
            Text(advice).forge(15).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.top, 14)
        .padding(.bottom, 24)
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    }
    .scrollBounceBehavior(.basedOnSize)
    .presentationDetents([.height(contentHeight)])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.page)
  }
}

/// A gym preset chip on the peach field: white pill, accent-strong fill with a check when selected.
struct SettingsChip: View {
  let title: String
  let selected: Bool
  let action: () -> Void

  init(title: String, selected: Bool, action: @escaping () -> Void) {
    self.title = title
    self.selected = selected
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if selected {
          Image(systemName: "checkmark")
            .scaledSystemFont(13, weight: .bold)
            .accessibilityHidden(true)
        }
        Text(title)
          .forge(15, selected ? .semibold : .medium)
          .lineLimit(1)
          .fixedSize()
      }
      .foregroundStyle(selected ? Theme.onAccent : Theme.text)
      .padding(.horizontal, 13)
      .frame(height: 36)
      .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
        .fill(selected ? Theme.accentStrong : Theme.fieldChip))
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// One piece of equipment on the Gym page: clay art, name, ownership badge. Tapping toggles it.
struct EquipmentTile: View {
  let equipment: Equipment
  let owned: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 7) {
        Image("eq-\(equipment.rawValue)").resizable().scaledToFit()
          .frame(width: 80, height: 60)
          .opacity(owned ? 1 : 0.38)
          .grayscale(owned ? 0 : 1)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        Text(equipment.name).forge(15, .medium).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
      }
      .padding(.bottom, 12)
      .frame(maxWidth: .infinity, minHeight: 116, alignment: .bottom)
      .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
      .overlay(alignment: .topTrailing) { badge.padding(7) }
      .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .sensoryFeedback(.selection, trigger: owned)
    .accessibilityLabel(equipment.name)
    .accessibilityAddTraits(owned ? .isSelected : [])
  }

  private var badge: some View {
    ZStack {
      if owned {
        Circle().fill(Theme.accentStrong)
        Image(systemName: "checkmark").scaledSystemFont(11, weight: .bold).foregroundStyle(Theme.onAccent)
      } else {
        Circle().strokeBorder(Theme.textSecondary.opacity(0.8), lineWidth: 1.5)
      }
    }
    .frame(width: 22, height: 22)
    .accessibilityHidden(true)
  }
}

/// One plate on the Plates page: a coloured disc you own, a dashed outline you could add.
struct PlateDisc: View {
  let weight: Double
  let usesLb: Bool
  let owned: Bool
  let action: () -> Void

  init(weight: Double, usesLb: Bool, owned: Bool, action: @escaping () -> Void) {
    self.weight = weight
    self.usesLb = usesLb
    self.owned = owned
    self.action = action
  }

  private var weightText: String { Fmt.num(weight, max: 2) }

  var body: some View {
    Button(action: action) {
      ZStack {
        if owned {
          Circle().fill(Theme.plateColor(weight, usesLb: usesLb))
            .overlay(Circle().strokeBorder(Theme.ring, lineWidth: 1))
          VStack(spacing: 0) {
            Text(weightText).font(.forge(20, .bold)).tracking(-0.3).monospacedDigit()
            Text(usesLb ? "lb" : "kg").font(.forge(11, .medium)).opacity(0.75)
          }
          .foregroundStyle(Theme.plateLabelColor(weight, usesLb: usesLb))
        } else {
          Circle().strokeBorder(Theme.textSecondary.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
          VStack(spacing: 0) {
            Text(weightText).font(.forge(20, .bold)).tracking(-0.3).monospacedDigit()
            Image(systemName: "plus").scaledSystemFont(11, weight: .bold)
          }
          .foregroundStyle(Theme.textSecondary)
        }
      }
      .frame(width: 72, height: 72)
      .contentShape(Circle())
    }
    .buttonStyle(ControlPressStyle())
    .sensoryFeedback(.selection, trigger: owned)
    .accessibilityLabel(String(localized: "\(weightText) \(usesLb ? "lb" : "kg") plate", bundle: L10n.bundle))
    .accessibilityAddTraits(owned ? .isSelected : [])
  }
}

/// Side view of the loaded bar: sleeves, collars, shaft and the plates stacked on each end.
struct BarbellDiagram: View {
  let perSide: [Double]
  let usesLb: Bool
  var highlight: Double? = nil

  init(perSide: [Double], usesLb: Bool, highlight: Double? = nil) {
    self.perSide = perSide
    self.usesLb = usesLb
    self.highlight = highlight
  }

  var body: some View {
    Canvas { context, size in
      let s = size.width / 350
      let cy: CGFloat = 96

      func scaled(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
      }
      func metal(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat) {
        context.fill(Path(roundedRect: scaled(x, y, w, h), cornerRadius: radius * s), with: .color(Theme.textSecondary))
      }

      metal(6, cy - 7, 102, 14, radius: 4)      // sleeve
      metal(242, cy - 7, 102, 14, radius: 4)    // sleeve
      metal(106, cy - 16, 10, 32, radius: 3)    // collar
      metal(234, cy - 16, 10, 32, radius: 3)    // collar
      metal(116, cy - 4, 118, 8, radius: 4)     // shaft

      let gap: CGFloat = 10
      var x: CGFloat = 246
      var stack: [(x: CGFloat, w: CGFloat, h: CGFloat, weight: Double)] = []
      for weight in perSide.sorted(by: >) {
        let dims = plateSize(PlateMath.sizeRank(weight, usesLb: usesLb))
        stack.append((x, dims.width, dims.height, weight))
        x += dims.width + gap
      }
      if let last = stack.last, last.x + last.w > 344 {
        let factor = (344 - 246) / (last.x + last.w - 246)
        var next: CGFloat = 246
        stack = stack.map { plate in
          let moved = (next, plate.w * factor, plate.h, plate.weight)
          next += plate.w * factor + gap * factor
          return moved
        }
      }

      for plate in stack {
        for sideX in [plate.x, 350 - plate.x - plate.w] {
          let path = Path(roundedRect: scaled(sideX, cy - plate.h / 2, plate.w, plate.h), cornerRadius: 4 * s)
          context.fill(path, with: .color(Theme.plateColor(plate.weight, usesLb: usesLb)))
          context.stroke(path, with: .color(Theme.ring), lineWidth: 1)
        }
      }
      var highlighted = false
      var lastLabelEnd = -CGFloat.infinity
      var raised = false
      for plate in stack {
        let isHighlight = !highlighted && highlight != nil && abs(plate.weight - (highlight ?? 0)) < 0.01
        let label = context.resolve(
          Text(Fmt.num(plate.weight, max: 2))
            .font(.forge(12, isHighlight ? .bold : .semibold))
            .foregroundStyle(isHighlight ? Theme.accentText : Theme.textSecondary))
        let width = label.measure(in: size).width
        let center = (plate.x + plate.w / 2) * s
        // A label that would touch its neighbour moves up one row.
        raised = center - width / 2 < lastLabelEnd + 3 ? !raised : false
        context.draw(label, at: CGPoint(x: center, y: (cy - 62 - (raised ? 14 : 0)) * s), anchor: .bottom)
        lastLabelEnd = center + width / 2
        if isHighlight { highlighted = true }
      }
    }
    .aspectRatio(350.0 / 160.0, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .accessibilityElement()
    .accessibilityLabel(String(localized: "Each side: \(ListFormatter.localizedString(byJoining: perSide.map { Fmt.num($0, max: 2) })) \(usesLb ? "lb" : "kg")", bundle: L10n.bundle))
  }

  /// Plate width and height in design units for a catalogue size rank (0 = heaviest).
  private func plateSize(_ rank: Int) -> (width: CGFloat, height: CGFloat) {
    switch rank {
    case 0: return (22, 118)
    case 1: return (20, 110)
    case 2: return (18, 98)
    case 3: return (16, 84)
    case 4: return (14, 70)
    case 5: return (12, 56)
    case 6: return (10, 44)
    default: return (8, 34)
    }
  }
}

/// A coach on the Coach page: photo, name with the selection mark, tagline. Selected = accent-strong ring.
struct CoachChoiceCard: View {
  let coach: Coach
  let selected: Bool
  let action: () -> Void

  /// The approved mock's photos: Nova's hero shot and Kai pointing.
  private var photo: String { coach == .nova ? coach.hero : coach.point }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        Color.clear
          .frame(height: 176)
          .overlay(alignment: .top) { Image(photo).resizable().scaledToFill().allowsHitTesting(false) }
          .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.radiusCard, topTrailingRadius: Theme.radiusCard, style: .continuous))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 8) {
            Text(coach.name).forge(17, .semibold).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
            badge
          }
          Text(coach.tagline).forge(15).foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 13).padding(.trailing, 12).padding(.top, 11).padding(.bottom, 13)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.card))
      .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
      .overlay {
        if selected {
          RoundedRectangle(cornerRadius: Theme.radiusCard + 4.5, style: .continuous)
            .strokeBorder(Theme.accentStrong, lineWidth: 2.5)
            .padding(-4.5)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
    .buttonStyle(ControlPressStyle())
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(coach.name), \(coach.tagline)")
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }

  private var badge: some View {
    ZStack {
      if selected {
        Circle().fill(Theme.accentStrong)
        Image(systemName: "checkmark").scaledSystemFont(11, weight: .bold).foregroundStyle(Theme.onAccent)
      } else {
        Circle().strokeBorder(Theme.textSecondary.opacity(0.8), lineWidth: 1.5)
      }
    }
    .frame(width: 22, height: 22)
    .accessibilityHidden(true)
  }
}

/// What the next reminder banner says: app icon, title, "now", body.
struct NotificationPreview: View {
  let title: String
  private let message: String

  init(title: String, body: String) {
    self.title = title
    self.message = body
  }

  var body: some View {
    HStack(alignment: .top, spacing: 11) {
      AppIconImage()
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 8) {
          Text(title).forge(15, .semibold).foregroundStyle(Theme.text)
          Spacer(minLength: 8)
          Text(String(localized: "now", bundle: L10n.bundle)).forge(15).foregroundStyle(Theme.textSecondary)
        }
        Text(message).forge(15).foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
    .accessibilityElement(children: .combine)
  }
}

/// The app icon as the notification banner shows it, with a flame fallback when the asset is missing.
private struct AppIconImage: View {
  var body: some View {
    Group {
      if let name = primaryIconName, let image = UIImage(named: name) {
        Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false)
      } else {
        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accent)
          .overlay(Image(systemName: "flame.fill").scaledSystemFont(20, weight: .bold).foregroundStyle(Theme.onAccent))
      }
    }
    .frame(width: 38, height: 38)
    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    .accessibilityHidden(true)
  }

  private var primaryIconName: String? {
    let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
    let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
    return (primary?["CFBundleIconFiles"] as? [String])?.last
  }
}

/// The system share sheet, for sharing a file from a confirmation dialog.
struct ActivityView: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
