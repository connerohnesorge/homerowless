import Foundation
import AXCore
import Discovery
import Geometry

/// The seam: AX scanner today, grid fallback now, Vision OCR in v1.1.
public protocol ElementSource: Sendable {
    func elements(in window: AXWindow, clip: AXRect) -> AsyncStream<[ActionableElement]>
}

public struct AXElementSource: ElementSource {
    public let scanner: ElementScanner
    public init(scanner: ElementScanner) { self.scanner = scanner }
    public func elements(in window: AXWindow, clip: AXRect) -> AsyncStream<[ActionableElement]> {
        AsyncStream { cont in
            let t = Task {
                let (stream, statsTask) = await scanner.scan(window: window, clip: clip)
                for await b in stream { cont.yield(b) }
                _ = await statsTask.value
                cont.finish()
            }
            cont.onTermination = { _ in t.cancel() }
        }
    }
}
