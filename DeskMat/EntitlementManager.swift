import StoreKit
import Foundation

enum PurchaseResult { case success, cancelled, pending }

@Observable
class EntitlementManager {
    static let productID = "com.deskmat.pro"

    var isPro = false

    private(set) var product: Product?
    private var transactionListener: Task<Void, Error>?

    init() {
        transactionListener = listenForTransactions()
        Task { await refresh() }

        #if DEBUG
        // Re-evaluate pro state whenever the debug override is toggled
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if UserDefaults.standard.bool(forKey: "debugProOverride") {
                self.isPro = true
            } else {
                Task { await self.refresh() }
            }
        }
        #endif
    }

    deinit {
        transactionListener?.cancel()
    }

    func purchase() async throws -> PurchaseResult {
        guard let product else { return .cancelled }
        switch try await product.purchase() {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await MainActor.run { isPro = true }
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
                isPro = true
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
                    await MainActor.run { self?.isPro = true }
                    await transaction.finish()
                }
            }
        }
    }
}
