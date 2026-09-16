import Foundation

struct FoodItemDraft: Identifiable, Hashable {
  let barcode: String?
  let name: String
  let brand: String
  let kcalPer100: Double
  let proteinPer100: Double
  let carbsPer100: Double
  let fatPer100: Double
  let servingG: Double

  var id: String { barcode ?? "\(name)|\(brand)" }
}

enum OpenFoodFacts {
  private static let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 8
    config.timeoutIntervalForResource = 8
    return URLSession(configuration: config)
  }()

  static func product(barcode: String) async throws -> FoodItemDraft? {
    guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,brands,nutriments,serving_quantity"),
          let obj = try await get(url) as? [String: Any],
          let product = obj["product"] as? [String: Any] else { return nil }
    return draft(from: product, barcode: barcode)
  }

  static func search(_ q: String) async throws -> [FoodItemDraft] {
    var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
    comps.queryItems = [
      URLQueryItem(name: "search_terms", value: q),
      URLQueryItem(name: "search_simple", value: "1"),
      URLQueryItem(name: "action", value: "process"),
      URLQueryItem(name: "json", value: "1"),
      URLQueryItem(name: "page_size", value: "20"),
      URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments,serving_quantity"),
    ]
    guard let url = comps.url else { return [] }
    let obj: Any
    do {
      obj = try await get(url)
    } catch {
      try? await Task.sleep(for: .seconds(1))
      obj = try await get(url)
    }
    guard let dict = obj as? [String: Any],
          let products = dict["products"] as? [[String: Any]] else { return [] }
    return products.compactMap { draft(from: $0, barcode: $0["code"] as? String) }
  }

  private static func get(_ url: URL) async throws -> Any {
    var req = URLRequest(url: url)
    req.setValue("Regulift iOS (kenz4788@gmail.com)", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await session.data(for: req)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw URLError(.badServerResponse)
    }
    return try JSONSerialization.jsonObject(with: data)
  }

  private static func draft(from product: [String: Any], barcode: String?) -> FoodItemDraft? {
    let name = (product["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed"
    let nutriments = product["nutriments"] as? [String: Any] ?? [:]
    let protein = num(nutriments["proteins_100g"])
    let carbs = num(nutriments["carbohydrates_100g"])
    let fat = num(nutriments["fat_100g"])
    var kcal = num(nutriments["energy-kcal_100g"])
    if kcal == 0 { kcal = protein * 4 + carbs * 4 + fat * 9 }
    let serving = num(product["serving_quantity"])
    guard kcal > 0 || protein + carbs + fat > 0 else { return nil }
    return FoodItemDraft(
      barcode: barcode,
      name: name,
      brand: product["brands"] as? String ?? "",
      kcalPer100: kcal,
      proteinPer100: protein,
      carbsPer100: carbs,
      fatPer100: fat,
      servingG: serving > 0 ? serving : 100)
  }

  private static func num(_ any: Any?) -> Double {
    if let d = any as? Double { return d }
    if let i = any as? Int { return Double(i) }
    if let s = any as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    return 0
  }
}
