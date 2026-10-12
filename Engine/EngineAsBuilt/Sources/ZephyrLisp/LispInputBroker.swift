// LispInputBroker: exactly-once suspension bridge for interactive input.
//
// The evaluator awaits request(); UI event handlers answer with offer().
// At most one request is outstanding per broker (Lisp evaluation is
// single-threaded). A bounded FIFO holds events that arrive early
// (notably for grread, which drains the queue first).
//
// Leak-proofing by construction:
// - settle() checks the generation token, takes-and-nils the slot FIRST,
//   then resumes. Under MainActor isolation the check-and-take is atomic,
//   so double-resume and stale-resume are impossible; stale offers are
//   ignored and counted.
// - The continuation never escapes this type: every outcome (value,
//   cancel, task-cancel) funnels through settle().
// - Checked continuations trap on misuse in debug builds, turning any
//   future protocol violation into a loud test failure.

/// One interactive input transaction.
@MainActor
public final class LispInputBroker: Sendable {
    /// What the evaluator is waiting for.
    public enum RequestKind: Sendable, Equatable {
        case point(prompt: String)
        case line(prompt: String)
        case entity(prompt: String)
        case device
    }

    /// One answered input. Mismatched kinds never settle a request.
    public enum Event: Sendable, Equatable {
        case point([Double]?)
        case line(String?)
        case entity(handle: String?, point: [Double]?)
        case device(LispValue)
    }

    public nonisolated static let queueBound = 64

    private var generation = 0
    private var slot: (token: Int, kind: RequestKind,
        continuation: CheckedContinuation<Event, Error>)?
    /// Armed by task cancellation; consumed by the next request() pre-check.
    /// Everything here runs on MainActor, so the arm/check/store sequence
    /// cannot interleave: cancellation is never lost and never double-fires.
    private var cancelArmed = false

    private var queue: [Event] = []

    // MARK: - Test hooks (counters only; no behavior)

    /// Successful settles (exactly one per completed request).
    public private(set) var settleCount = 0
    /// Offers ignored as stale or mismatched.
    public private(set) var staleCount = 0
    public var queuedCount: Int { queue.count }
    public var hasPending: Bool { slot != nil }
    /// The outstanding request kind, if any. The CAD driver uses this to
    /// offer exactly one matching event per UI gesture (offering several
    /// would queue the losers as stale input after the first settles).
    public var pendingKind: RequestKind? { slot?.kind }

    public init() {}

    // MARK: - Await side (evaluator, via the host)

    /// Suspends until a matching event arrives. Throws .userCancel on
    /// cancellation (explicit cancel, task cancel, or cancel event).
    public func request(_ kind: RequestKind) async throws -> Event {
        if cancelArmed {
            cancelArmed = false
            throw LispError.userCancel
        }
        // Drain the first queued match before suspending (grread pattern).
        if let index = queue.firstIndex(where: { matches($0, kind: kind) }) {
            let event = queue.remove(at: index)
            settleCount += 1
            return event
        }
        generation += 1
        let token = generation
        precondition(slot == nil, "LispInputBroker supports one outstanding request")
        return try await withCheckedThrowingContinuation { continuation in
            slot = (token, kind, continuation)
        }
    }

    /// Settles the pending request as cancelled (Esc path). No-op when idle.
    public func cancelPending() {
        guard let current = slot else { return }
        settle(token: current.token, outcome: .failure(LispError.userCancel))
    }

    // MARK: - Offer side (UI event handlers)

    /// Offers one event: settles a matching pending request, else queues
    /// (bounded, drop-oldest). Never blocks, never throws.
    public func offer(_ event: Event) {
        if let current = slot {
            if matches(event, kind: current.kind) {
                settle(token: current.token, outcome: .success(event))
            } else {
                staleCount += 1
            }
            return
        }
        queue.append(event)
        if queue.count > Self.queueBound {
            queue.removeFirst(queue.count - Self.queueBound)
        }
    }

    /// Clears queued events and disarms cancellation (command boundaries).
    /// Pending requests are untouched.
    public func drainQueue() {
        queue.removeAll()
        cancelArmed = false
    }

    // MARK: - Choke point

    private enum Outcome {
        case success(Event)
        case failure(Error)
    }

    private func settle(token: Int, outcome: Outcome) {
        // Take-before-resume: only the live token settles, exactly once.
        guard let current = slot, current.token == token else {
            staleCount += 1
            return
        }
        slot = nil
        settleCount += 1
        switch outcome {
        case let .success(event): current.continuation.resume(returning: event)
        case let .failure(error): current.continuation.resume(throwing: error)
        }
    }

    private func matches(_ event: Event, kind: RequestKind) -> Bool {
        switch (event, kind) {
        case (.point, .point), (.line, .line),
            (.entity, .entity), (.device, .device):
            return true
        default:
            return false
        }
    }
}

// MARK: - Task-cancellation adapter (host-side helper)

extension LispInputBroker {
    /// request() that also settles on Swift task cancellation: the
    /// cancellation handler funnels through cancelPending(), preserving
    /// exactly-once even when the awaiting task is cancelled first.
    public func requestCancellable(_ kind: RequestKind) async throws -> Event {
        if Task.isCancelled { throw LispError.userCancel }
        return try await withTaskCancellationHandler {
            try await request(kind)
        } onCancel: {
            Task { await MainActor.run { self.armCancel() } }
        }
    }

    private func armCancel() {
        cancelArmed = true
        cancelPending()
    }
}
