import Foundation

/// Carries a value NIO wants as Sendable through a closure we control.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
