import Foundation
import MLXLMCommon
import Tokenizers

/// Wraps a loaded MLX model + tokenizer behind a handle.
final class CowMLXModel: @unchecked Sendable {
    let container: ModelContainer
    let configuration: ModelConfiguration
    let id: Int64

    nonisolated(unsafe) private static var nextId: Int64 = 0
    private static let idLock = NSLock()

    init(container: ModelContainer, configuration: ModelConfiguration) {
        self.container = container
        self.configuration = configuration
        CowMLXModel.idLock.lock()
        self.id = CowMLXModel.nextId
        CowMLXModel.nextId += 1
        CowMLXModel.idLock.unlock()
    }
}
