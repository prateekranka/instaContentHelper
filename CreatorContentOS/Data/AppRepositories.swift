import Foundation

struct WorkspaceContext: Hashable, Sendable {
    let workspaceID: UUID
    let creatorID: UUID
    let memberID: UUID

    static let creatorFixture = WorkspaceContext(
        workspaceID: UUID(uuidString: "D9F0C7CF-BC12-4D9C-9B2F-172930AA1201")!,
        creatorID: UUID(uuidString: "F0F6DA51-4F75-4D18-A01D-0C9E3C1E6A5C")!,
        memberID: UUID(uuidString: "3A0D2B4D-2D8E-4E6D-A8DE-65D2B75F6CC1")!
    )
}
