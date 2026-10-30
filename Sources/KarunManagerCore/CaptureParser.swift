import Foundation

/// Lets a capture field pick a category via an optional prefix, e.g. "buy: oat milk" or "call: Mom".
/// Every category also answers to its tag name ("things-to-buy:", "work:"). Without a prefix the
/// task lands in the first category.
public enum CaptureParser {
    private static let aliases: [String: String] = [
        "todo": TaskCategory.thingsToDo,
        "do": TaskCategory.thingsToDo,
        "buy": TaskCategory.thingsToBuy,
        "call": TaskCategory.peopleToCall,
    ]

    /// `hadPrefix` tells callers whether the category came from the text (and should win over a menu).
    public static func parse(
        _ input: String,
        categories: [String] = TaskCategory.defaults
    ) -> (title: String, categoryName: String, hadPrefix: Bool)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fallback = categories.first ?? TaskCategory.thingsToDo

        if let colon = trimmed.firstIndex(of: ":"),
           let category = category(forPrefix: trimmed[..<colon].lowercased(), in: categories) {
            let title = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return (title, category, true) }
        }
        return (trimmed, fallback, false)
    }

    /// "Things to buy" → "things-to-buy"
    public static func slug(_ categoryName: String) -> String {
        categoryName.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-")
    }

    private static func category(forPrefix prefix: String, in categories: [String]) -> String? {
        if let alias = aliases[prefix], categories.contains(alias) { return alias }
        return categories.first { slug($0) == prefix }
    }
}
