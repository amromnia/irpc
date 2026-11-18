import Foundation

/// Non-sensitive account IDs. Slots are never reused, so a removed account cannot
/// inherit credentials from another local profile.
struct AccountRegistry: Codable {
    private(set) var slots: [Int]
    private(set) var nextSlot: Int

    init(legacySlots: [Int] = []) {
        slots = legacySlots.sorted()
        nextSlot = (slots.max() ?? 0) + 1
    }

    init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
        guard slots.allSatisfy({ $0 > 0 }), Set(slots).count == slots.count,
              nextSlot > (slots.max() ?? 0) else { throw RegistryError.invalid }
    }

    mutating func add() throws -> Int {
        guard nextSlot < Int.max else { throw RegistryError.invalid }
        let slot = nextSlot
        nextSlot += 1
        slots.append(slot)
        return slot
    }

    mutating func remove(_ slot: Int) { slots.removeAll { $0 == slot } }
    func data() throws -> Data { try JSONEncoder().encode(self) }

    enum RegistryError: Error { case invalid }
}
