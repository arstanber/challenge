import Foundation
import Observation
import RevenueCat
import StoreKit
import os.log

private let storeLogger = Logger(subsystem: "com.reinspire", category: "StoreService")

/// Purchase layer. RevenueCat owns the StoreKit plumbing; this type is the
/// app-facing surface (offerings, purchase, restore, current tier).
///
/// `users.plan` is written by the `revenuecat-webhook` edge function, never by
/// this client. After a purchase we set the in-memory plan optimistically so
/// the UI unlocks immediately, then re-read the server row once the webhook
/// has landed.
@Observable
@MainActor
final class StoreService {
    static let shared = StoreService()

    struct CatalogItem: Identifiable {
        let packageIdentifier: String?
        let productID: String
        let plan: UserPlan
        let isFeatured: Bool

        var id: String { productID }
    }

    /// Products from the current offering, keyed by store product ID.
    private(set) var products: [String: StoreProduct] = [:]

    /// Packages from the current offering, keyed by store product ID.
    /// Purchasing a package (rather than a bare product) is what lets
    /// RevenueCat attribute the sale to an offering for paywall A/B tests.
    private(set) var packages: [String: Package] = [:]
    /// Ordered exactly as configured in the active RevenueCat Offering.
    private(set) var catalog: [CatalogItem] = []

    var isPurchasing = false
    var errorMessage: String?
    var isPremium: Bool { AuthService.shared.currentUser?.isPremium ?? false }
    var currentPlan: UserPlan { AuthService.shared.currentUser?.plan ?? .free }

    // Backward-compatible accessors
    var product: StoreProduct? { products[Constants.Store.premiumMonthlyID] }
    var familyProduct: StoreProduct? { products[Constants.Store.familyMonthlyID] }

    private init() {}

    // MARK: - Configure

    /// Call once, as early as possible in the app lifecycle.
    /// Configuring with no appUserID starts RevenueCat in anonymous mode; the
    /// identity is upgraded to the Supabase user ID by `identify(userId:)`
    /// once a profile is loaded.
    func configure() {
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .info
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: Constants.RevenueCat.apiKey)
        observeCustomerInfo()
        Task { await loadProducts() }
    }

    // MARK: - Identity

    /// Aliases the anonymous RevenueCat user onto the Supabase user ID so the
    /// same subscription follows the account across devices, and so webhook
    /// events carry an app_user_id we can resolve to a `users` row.
    func identify(userId: UUID) async {
        guard Purchases.isConfigured else { return }
        do {
            let (info, _) = try await Purchases.shared.logIn(userId.uuidString)
            await applyOptimisticPlan(from: info)
            await reconcileLegacyStoreKitEntitlements()
        } catch {
            storeLogger.error("RevenueCat logIn failed: \(error)")
        }
    }

    /// Makes sure RevenueCat is aliased onto the signed-in user before a
    /// purchase is allowed to start.
    ///
    /// configure() begins anonymous and identify() only runs once the Supabase
    /// profile has loaded, which leaves a window on cold start where a purchase
    /// would attach to $RCAnonymousID. Those events reach the webhook with an
    /// app_user_id that resolves to no users row, so it skips them: the customer
    /// is charged and never receives the tier. Observed in sandbox, where a
    /// purchase made in that window pulled the existing subscription over to the
    /// anonymous ID with it.
    private func ensureIdentified() async {
        guard let userId = AuthService.shared.currentUser?.id else { return }
        guard Purchases.shared.appUserID != userId.uuidString else { return }
        await identify(userId: userId)
    }

    /// Returns RevenueCat to an anonymous identity so the next account on this
    /// device does not inherit the previous user's entitlements.
    func resetIdentity() async {
        guard Purchases.isConfigured else { return }
        do {
            _ = try await Purchases.shared.logOut()
        } catch {
            storeLogger.error("RevenueCat logOut failed: \(error)")
        }
    }

    // MARK: - Products

    /// Loads prices through three fallbacks so the paywall shows real,
    /// correctly-localized prices in every configuration state:
    ///
    ///   1. the current RevenueCat offering  -- full attribution, A/B testing
    ///   2. RevenueCat product lookup by ID  -- offering missing or incomplete
    ///   3. StoreKit directly                -- RevenueCat not configured yet
    ///
    /// Step 3 matters because prices must never depend on dashboard setup being
    /// finished. Every path returns App Store prices in the user's own
    /// currency; nothing here is ever hardcoded.
    func loadProducts() async {
        var loadedProducts: [String: StoreProduct] = [:]
        var loadedPackages: [String: Package] = [:]
        var loadedCatalog: [CatalogItem] = []

        if Purchases.isConfigured {
            do {
                let offerings = try await Purchases.shared.offerings()
                let offering = offerings.current
                    ?? offerings.offering(identifier: Constants.RevenueCat.defaultOffering)
                if let offering {
                    let featuredPackage = offering.metadata["featured_package"] as? String
                    let configuredTiers = offering.metadata["package_tiers"] as? [String: Any] ?? [:]
                    for package in offering.availablePackages {
                        let id = package.storeProduct.productIdentifier
                        loadedProducts[id] = package.storeProduct
                        loadedPackages[id] = package
                        let configuredPlan = (configuredTiers[package.identifier] as? String)
                            .flatMap(UserPlan.init(rawValue:))
                        if let plan = configuredPlan ?? Constants.Store.plan(forProductID: id) {
                            loadedCatalog.append(.init(
                                packageIdentifier: package.identifier,
                                productID: id,
                                plan: plan,
                                isFeatured: package.identifier == featuredPackage
                            ))
                        }
                    }
                } else {
                    storeLogger.error("No current RevenueCat offering configured")
                }
            } catch {
                storeLogger.error("offerings error: \(error)")
            }

        }

        // Last resort: ask StoreKit only for the three target products. Legacy
        // products remain restorable but never reappear for new customers.
        if loadedCatalog.isEmpty {
            do {
                let skProducts = try await Product.products(for: Constants.Store.fallbackSellableProductIDs)
                for skProduct in skProducts {
                    loadedProducts[skProduct.id] = StoreProduct(sk2Product: skProduct)
                    if let plan = Constants.Store.plan(forProductID: skProduct.id) {
                        loadedCatalog.append(.init(
                            packageIdentifier: nil,
                            productID: skProduct.id,
                            plan: plan,
                            isFeatured: skProduct.id == Constants.Store.premiumAnnualID
                        ))
                    }
                }
                loadedCatalog.sort { fallbackOrder($0.productID) < fallbackOrder($1.productID) }
            } catch {
                storeLogger.error("StoreKit product fallback error: \(error)")
            }
        }

        products = loadedProducts
        packages = loadedPackages
        catalog = loadedCatalog
    }

    // Keep backward-compatible alias
    func loadProduct() async { await loadProducts() }

    func product(for id: String) -> StoreProduct? { products[id] }

    private func fallbackOrder(_ id: String) -> Int {
        switch id {
        case Constants.Store.premiumAnnualID: return 0
        case Constants.Store.premiumMonthlyID: return 1
        case Constants.Store.familyAnnualID: return 2
        default: return 99
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(productID: String) async -> Bool {
        guard Purchases.isConfigured else {
            errorMessage = String(localized: "The store is unavailable. Please try again later.")
            storeLogger.error("purchase: Purchases not configured")
            return false
        }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        await ensureIdentified()

        do {
            let result: PurchaseResultData
            if let package = packages[productID] {
                result = try await Purchases.shared.purchase(package: package)
            } else if let product = products[productID] {
                // Product exists but is not in the current offering -- still
                // purchasable, just without offering attribution.
                result = try await Purchases.shared.purchase(product: product)
            } else {
                // Neither the offering nor the store knows this ID -- almost
                // always a product missing from the current RevenueCat offering
                // or not yet Ready to Submit in App Store Connect. Surfaced
                // rather than swallowed: a silent false reads as "the button
                // did nothing", which is indistinguishable from a hung app.
                errorMessage = String(localized: "This plan is unavailable right now. Please try again later.")
                storeLogger.error("purchase: unknown product \(productID)")
                return false
            }
            if result.userCancelled { return false }
            await applyOptimisticPlan(from: result.customerInfo)
            // Detached: the tier is already unlocked optimistically, so blocking
            // the button on webhook delivery would just show a spinner over a
            // purchase that already succeeded.
            Task { await waitForServerPlan() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            storeLogger.error("purchase error: \(error)")
            return false
        }
    }

    // Backward-compatible entry points
    @discardableResult
    func purchase() async -> Bool { await purchase(productID: Constants.Store.premiumMonthlyID) }

    @discardableResult
    func purchaseFamily() async -> Bool { await purchase(productID: Constants.Store.familyMonthlyID) }

    // MARK: - Restore

    func restore() async {
        guard Purchases.isConfigured else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        await ensureIdentified()
        do {
            let info = try await Purchases.shared.restorePurchases()
            await applyOptimisticPlan(from: info)
            Task { await waitForServerPlan() }
        } catch {
            errorMessage = error.localizedDescription
            storeLogger.error("restore error: \(error)")
        }
    }

    // MARK: - Entitlements

    /// Audits every active StoreKit 2 entitlement, including products removed
    /// from the current Offering, then asks RevenueCat to sync the receipt. The
    /// RevenueCat entitlement and webhook remain authoritative; this bridge is
    /// what preserves access for subscribers on retired SKUs after an update.
    private func reconcileLegacyStoreKitEntitlements() async {
        var foundLegacyEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  Constants.Store.legacyCompatibleProductIDs.contains(transaction.productID) else {
                continue
            }
            foundLegacyEntitlement = true
        }
        guard foundLegacyEntitlement else { return }
        do {
            let info = try await Purchases.shared.syncPurchases()
            await applyOptimisticPlan(from: info)
        } catch {
            storeLogger.error("Legacy StoreKit entitlement sync failed: \(error)")
        }
    }

    /// Highest plan unlocked by the active entitlements (max > family > premium).
    ///
    /// MainActor-isolated like the rest of the type: both the entitlement lookup
    /// and UserPlan's Comparable conformance are, and reaching them from a
    /// nonisolated context is an error under the Swift 6 language mode. The sole
    /// caller already runs on the main actor.
    static func plan(from info: CustomerInfo) -> UserPlan {
        var best: UserPlan = .free
        for id in info.entitlements.active.keys {
            guard let plan = Constants.RevenueCat.plan(forEntitlement: id) else { continue }
            if plan > best { best = plan }
        }
        return best
    }

    /// Pushes entitlement changes (renewals, expirations, cancellations made on
    /// another device) into the UI without waiting for an app relaunch.
    private func observeCustomerInfo() {
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                await self?.applyOptimisticPlan(from: info)
            }
        }
    }

    /// Unlocks the UI immediately after a local entitlement change.
    /// In-memory only -- the `users.plan` row is owned by the webhook, so this
    /// never writes to Supabase. It also never downgrades: a user granted a
    /// plan server-side (a family member, a referral PRO grant) has no local
    /// entitlement, and clearing their tier here would lock them out.
    private func applyOptimisticPlan(from info: CustomerInfo) async {
        let plan = Self.plan(from: info)
        guard plan > .free,
              let current = AuthService.shared.currentUser?.plan,
              plan > current else { return }
        AuthService.shared.currentUser?.plan = plan
        AnalyticsService.shared.track(.premiumPurchased)
    }

    /// Re-reads the users row a few times so the authoritative, webhook-written
    /// plan replaces the optimistic one. Webhook delivery is typically under a
    /// second but is not guaranteed to beat the purchase callback.
    private func waitForServerPlan() async {
        for delay in [1.0, 3.0, 6.0] {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await AuthService.shared.refreshProfile()
            if AuthService.shared.currentUser?.plan ?? .free > .free { return }
        }
    }
}
