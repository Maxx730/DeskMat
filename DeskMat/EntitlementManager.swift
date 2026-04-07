import StoreKit
import Foundation

enum PurchaseResult { case success, cancelled, pending }

@Observable
class EntitlementManager {
    static let productID = "com.deskmat.pro"
    private static let cachedProKey = "cachedIsPro"

    /// Seeded from the UserDefaults cache so the first render is correct
    /// without waiting for StoreKit. StoreKit verification updates the cache.
    var isPro = UserDefaults.standard.bool(forKey: cachedProKey)

    private(set) var product: Product?
    private var transactionListener: Task<Void, Error>?
    #if DEBUG
    // Tracks the last-seen value so the observer only acts on actual transitions,
    // not on every UserDefaults write (which would clear cachedIsPro on each grantPro call).
    // @ObservationIgnored so the Observable macro doesn't require it initialized before self.
    @ObservationIgnored
    private var _lastDebugProOverride = UserDefaults.standard.bool(forKey: "debugProOverride")
    #endif

    init() {
        transactionListener = listenForTransactions()
        Task { await refresh() }

        #if DEBUG
        // Re-evaluate pro state only when debugProOverride actually changes value.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let current = UserDefaults.standard.bool(forKey: "debugProOverride")
            guard current != self._lastDebugProOverride else { return }
            self._lastDebugProOverride = current
            if current {
                Task { @MainActor [weak self] in self?.grantPro() }
            } else {
                self.clearProCache()
                Task { [weak self] in await self?.refresh() }
            }
        }
        #endif
    }

    deinit {
        transactionListener?.cancel()
    }

    /// Sets isPro and persists the value to the UserDefaults cache.
    /// Guards against redundant writes to avoid re-triggering didChangeNotification.
    @MainActor
    func grantPro() {
        isPro = true
        if !UserDefaults.standard.bool(forKey: Self.cachedProKey) {
            UserDefaults.standard.set(true, forKey: Self.cachedProKey)
        }
    }

    /// Clears the UserDefaults cache without touching isPro (used by debug override).
    func clearProCache() {
        if UserDefaults.standard.object(forKey: Self.cachedProKey) != nil {
            UserDefaults.standard.removeObject(forKey: Self.cachedProKey)
        }
    }

    func purchase() async throws -> PurchaseResult {
        guard let product else { return .cancelled }
        switch try await product.purchase() {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await MainActor.run { grantPro() }
                await transaction.finish()
                return .success
            }
            return .cancelled
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refresh()
    }

    @MainActor
    func refresh() async {
        if let products = try? await Product.products(for: [Self.productID]) {
            product = products.first
        }

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID {
                grantPro()
                return
            }
        }
        // Do not set isPro = false here — StoreKit may be unreachable (offline launch).
        // Revocations are delivered via Transaction.updates when connectivity returns.
    }

    private func listenForTransactions() -> Task<Void, Error> {
        // Task (not Task.detached) inherits the calling actor context, avoiding
        // a Swift 6 Sendability error from capturing non-Sendable self in a
        // detached closure. The async-for-await loop yields rather than blocking.
        Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await MainActor.run { self?.grantPro() }
                    await transaction.finish()
                }
            }
        }
    }
}
