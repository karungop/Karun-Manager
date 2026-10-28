import Foundation

/// Lets the single "What's on your mind?" field pick a category via an optional prefix,
/// e.g. "buy: oat milk" or "call: Mom". Anything else lands in "Things to do".
public enum CaptureParser {
    private static let prefixes: [String: String] = [
        "todo": TaskCategory.thingsToDo,
        "do": TaskCategory.thingsToDo,
        "buy": TaskCategory.thingsToBuy,
        "call": TaskCategory.peopleToCall,
    ]

    public static func parse(_ input: String) -> (title: String, categoryName: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let colon = trimmed.firstIndex(of: ":"),
           let category = prefixes[trimmed[..<colon].lowercased()] {
            let title = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return (title, category) }
        }
        return (trimmed, TaskCategory.thingsToDo)
    }
}
