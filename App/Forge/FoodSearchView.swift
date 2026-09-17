import SwiftUI
import SwiftData
import Charts
import ForgeCore

struct FoodSearchView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  let meal: Meal
  var favoritesOnly: Bool = false

  @Query(sort: \FoodItem.uses, order: .reverse) private var items: [FoodItem]
  @State private var query = ""
  @State private var webResults: [FoodItemDraft] = []
  @State private var searching = false
  @State private var lookupFailed = false
  @State private var searched = false
  @State private var showScanner = false
  @State private var showCustom = false
  @State private var gramsTarget: FoodItem?

  private var localMatches: [FoodItem] {
    query.isEmpty ? [] : items.filter {
      $0.name.localizedCaseInsensitiveContains(query) || $0.brand.localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        if query.isEmpty {
          Section {
            ForEach(items) { item in
              itemRow(item, badge: item.uses > 0 ? String(localized: "\(item.uses)×", bundle: L10n.bundle) : nil)
            }
            if items.isEmpty {
              Text("Foods you log show up here.").forgeLabel()
            }
          } header: {
            Text("Favorites").forgeLabel()
          }
        } else {
          Section {
            ForEach(localMatches) { item in
              itemRow(item, badge: nil)
            }
          } header: {
            Text("Saved").forgeLabel()
          }
          Section {
            if searching {
              HStack(spacing: 10) {
                ProgressView()
                Text("Searching Open Food Facts…").forgeLabel()
              }
            }
            if lookupFailed {
              Text("Search unavailable. Try again.").forgeLabel()
            }
            if webResults.isEmpty && !searching && !lookupFailed && searched {
              Text("No results.").forgeLabel()
            }
            ForEach(webResults) { draft in
              draftRow(draft)
            }
          } header: {
            Text("Web").forgeLabel()
          }
        }
        Section {
          Button { showCustom = true } label: {
            Label("Custom food", systemImage: "plus.circle")
              .foregroundStyle(Theme.accent)
          }
        }
      }
      .searchable(text: $query, prompt: "Search foods")
      .onSubmit(of: .search) { searchWeb() }
      .navigationTitle(favoritesOnly ? String(localized: "Quick add", bundle: L10n.bundle) : meal.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button { showScanner = true } label: { Image(systemName: "barcode.viewfinder") }
        }
      }
      .sheet(isPresented: $showScanner) {
        BarcodeScannerSheet { code in
          Task {
            if let draft = try? await OpenFoodFacts.product(barcode: code) {
              let item = convert(draft)
              addEntry(item: item, grams: defaultGrams(item))
            } else {
              lookupFailed = true
            }
          }
        }
      }
      .sheet(item: $gramsTarget) { item in
        GramsSheet(item: item, meal: meal, onSave: addEntry)
      }
      .sheet(isPresented: $showCustom) {
        CustomFoodSheet { item in
          addEntry(item: item, grams: defaultGrams(item))
        }
      }
    }
  }

  private func itemRow(_ item: FoodItem, badge: String?) -> some View {
    HStack(spacing: 8) {
      Button { addEntry(item: item, grams: defaultGrams(item)) } label: {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text(item.name).foregroundStyle(Theme.text).forgeBodyStrong()
            Text(detailLine(name: item.name, brand: item.brand, kcalPer100: item.kcalPer100))
              .foregroundStyle(Theme.textSecondary)
              .forgeCaption()
              .monospacedDigit()
          }
          Spacer()
          if let badge {
            Text(badge)
              .forge(11, .semibold)
              .monospacedDigit()
              .foregroundStyle(Theme.accent)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(Capsule().fill(Theme.accentTint))
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      gramsButton(defaultGrams(item)) { gramsTarget = item }
    }
  }

  private func draftRow(_ draft: FoodItemDraft) -> some View {
    HStack(spacing: 8) {
      Button {
        let item = convert(draft)
        addEntry(item: item, grams: defaultGrams(item))
      } label: {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text(draft.name).foregroundStyle(Theme.text).forgeBodyStrong()
            Text(detailLine(name: draft.name, brand: draft.brand, kcalPer100: draft.kcalPer100))
              .foregroundStyle(Theme.textSecondary)
              .forgeCaption()
              .monospacedDigit()
          }
          Spacer()
          Text("web")
            .forge(11, .semibold)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.accentTint))
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      gramsButton(draft.servingG > 0 ? draft.servingG : 100) { gramsTarget = convert(draft) }
    }
  }

  private func defaultGrams(_ item: FoodItem) -> Double { item.servingG > 0 ? item.servingG : 100 }

  private func gramsButton(_ grams: Double, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 2) {
        Text("\(Int(grams)) g")
        Image(systemName: "chevron.right")
      }
      .forge(11, .semibold)
      .monospacedDigit()
      .foregroundStyle(Theme.accent)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(Capsule().fill(Theme.accentTint))
    }
    .buttonStyle(.plain)
  }

  private func detailLine(name: String, brand: String, kcalPer100: Double) -> String {
    let prefix = brand.isEmpty ? "" : "\(brand) · "
    return String(localized: "\(prefix)\(Int(kcalPer100)) kcal / 100 g", bundle: L10n.bundle)
  }

  private func convert(_ draft: FoodItemDraft) -> FoodItem {
    if let existing = items.first(where: { $0.id == draft.id }) { return existing }
    let item = FoodItem(draft: draft)
    modelContext.insert(item)
    return item
  }

  private func searchWeb() {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return }
    searching = true
    lookupFailed = false
    Task {
      do {
        webResults = try await OpenFoodFacts.search(q)
      } catch {
        webResults = []
        lookupFailed = true
      }
      searching = false
      searched = true
    }
  }

  private func addEntry(item: FoodItem, grams: Double) {
    let factor = grams / 100
    modelContext.insert(FoodEntry(
      date: .now,
      meal: meal,
      itemID: item.id,
      name: item.name,
      grams: grams,
      kcal: item.kcalPer100 * factor,
      proteinG: item.proteinPer100 * factor,
      carbsG: item.carbsPer100 * factor,
      fatG: item.fatPer100 * factor))
    item.uses += 1
    item.lastUsed = .now
    dismiss()
  }
}

private struct GramsSheet: View {
  @Environment(\.dismiss) private var dismiss
  let item: FoodItem
  let meal: Meal
  let onSave: (FoodItem, Double) -> Void
  @State private var grams: Double

  init(item: FoodItem, meal: Meal, onSave: @escaping (FoodItem, Double) -> Void) {
    self.item = item
    self.meal = meal
    self.onSave = onSave
    _grams = State(initialValue: item.servingG > 0 ? item.servingG : 100)
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        VStack(alignment: .leading, spacing: 4) {
          Text(item.name).forgeSection()
          Text("\(Int(item.kcalPer100)) kcal · \(Int(item.proteinPer100))P / \(Int(item.carbsPer100))C / \(Int(item.fatPer100))F per 100 g")
            .forgeLabel()
            .monospacedDigit()
        }
        HStack {
          Text("Grams").forgeBodyStrong()
          Spacer()
          Stepper("\(Int(grams)) g", value: $grams, in: 1...2000, step: 10)
            .forgeBodyStrong()
            .monospacedDigit()
        }
        .innerSurface()
        HStack(spacing: 8) {
          ForEach([50.0, 100, 150, 200], id: \.self) { preset in
            Button { grams = preset } label: {
              Text("\(Int(preset)) g")
                .forge(13, .medium)
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(grams == preset ? Theme.accentTint : Theme.track))
            }
            .buttonStyle(.plain)
          }
        }
        HStack(spacing: 10) {
          StatTile(symbol: "flame.fill", value: "\(Int((item.kcalPer100 * grams / 100).rounded()))", label: String(localized: "kcal", bundle: L10n.bundle))
          StatTile(symbol: "fish.fill", value: "\(Int((item.proteinPer100 * grams / 100).rounded())) g", label: String(localized: "protein", bundle: L10n.bundle))
        }
        Spacer()
        Button("Add to \(meal.name)") {
          onSave(item, grams)
          dismiss()
        }
        .buttonStyle(PillButtonStyle())
      }
      .padding(Theme.margin)
      .background(Theme.page)
      .navigationTitle(meal.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
    }
    .presentationDetents([.medium])
    .presentationBackground(Theme.page)
  }
}

private struct CustomFoodSheet: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  let onSave: (FoodItem) -> Void
  @State private var name = ""
  @State private var kcal = ""
  @State private var protein = ""
  @State private var carbs = ""
  @State private var fat = ""
  @State private var serving = "100"

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.groupGap) {
          field(String(localized: "Name", bundle: L10n.bundle), $name)
          field(String(localized: "kcal / 100 g", bundle: L10n.bundle), $kcal, keyboard: .decimalPad)
          field(String(localized: "protein / 100 g", bundle: L10n.bundle), $protein, keyboard: .decimalPad)
          field(String(localized: "carbs / 100 g", bundle: L10n.bundle), $carbs, keyboard: .decimalPad)
          field(String(localized: "fat / 100 g", bundle: L10n.bundle), $fat, keyboard: .decimalPad)
          field(String(localized: "serving g", bundle: L10n.bundle), $serving, keyboard: .decimalPad)
          Button("Save food") {
            let item = FoodItem(
              id: "custom-\(UUID().uuidString)",
              name: name,
              brand: "",
              kcalPer100: Double(kcal) ?? 0,
              proteinPer100: Double(protein) ?? 0,
              carbsPer100: Double(carbs) ?? 0,
              fatPer100: Double(fat) ?? 0,
              servingG: Double(serving) ?? 100)
            modelContext.insert(item)
            onSave(item)
            dismiss()
          }
          .buttonStyle(PillButtonStyle())
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Theme.margin)
      }
      .background(Theme.page)
      .navigationTitle("Custom food")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
    }
    .presentationBackground(Theme.page)
  }

  private func field(_ title: String, _ value: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
    HStack {
      Text(title).forgeBodyStrong()
      Spacer()
      TextField("0", text: value)
        .keyboardType(keyboard)
        .multilineTextAlignment(.trailing)
        .forgeBody()
        .monospacedDigit()
        .frame(width: 120)
    }
    .innerSurface()
  }
}
