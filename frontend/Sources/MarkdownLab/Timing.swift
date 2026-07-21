import Foundation

extension Duration {
    /// The duration expressed in fractional milliseconds.
    var inMilliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
