public enum ShortcutClash {
    /// The id of another action already using `key`, if any. Each action's key is looked up
    /// through `keyFor`, so defaults and cleared shortcuts count as they are.
    public static func owner<Key: Equatable>(of key: Key, for id: String, among ids: [String], keyFor: (String) -> Key?) -> String? {
        ids.first { $0 != id && keyFor($0) == key }
    }
}
