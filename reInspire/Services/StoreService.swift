import Foundation
import StoreKit
import Observation
import Supabase
import PostgREST
import os.log

private let storeLogger = Logger(subsystem: "com.reinspire", category: "StoreService")

@Observable
final class StoreService {
    static let shared = StoreService()

    /// All loaded StoreKit products keyed by product ID.
    private(set) var products: [String: Product] = [:]

    var isPurchasing = false
    var errorMessage: String?
    var isPremium: Bool { AuthService.shared.currentUser?.isPremium ?? false }
    var currentPlan: UserPlan { AuthService.shared.currentUser?.plan ?? .free }

    // Backward-compatible accessors
    var product: Product? { products[Constants.Store.premiumMonthlyID] }
    var familyProduct: Product? { products[Constants.Store.familyMonthlyID] }

    /// Set once this install has observed its own StoreKit entitlement.
    /// Guards against downgrading users whose plan was granted server-side
    /// (family members upgraded by the buyer have no local transaction).
    private let hadLocalEntitlementKey = "store_had_local_entitlement_v1"

    private init() {
        Task { await loadProducts() }
        Task { await recomputeEntitlements() }
        listenForTransactions()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Constants.Store.allProductIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            storeLogger.error("loadProducts error: \(error)")
        }
    }

    // Keep backward-compatible alias
    func loadProduct() async { await loadProducts() }

    func product(for id: String) -> Product? { products[id] }

    /// Which plan a product ID unlocks. nil = unknown/foreign product.
    static func plan(for productID: String) -> UserPlan? {
        switch productID {
        case Constants.Store.premiumMonthlyID,
             Constants.Store.premiumAnnualID,
             Constants.Store.premiumForeverID:
            return .premium
        case Constants.Store.familyMonthlyID,
             Constants.Store.familyAnnualID:
            return .family
        case Constants.Store.maxMonthlyID:
            return .max
        default:
            return nil
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(productID: String) async -> Bool {
        guard let product = products[productID] else { return false }
        return await doPurchase(product)
    }

    // Backward-compatible entry points
    @discardableResult
    func purchase() async -> Bool { await purchase(productID: Constants.Store.premiumMonthlyID) }

    @discardableResult
    func purchaseFamily() async -> Bool { await purchase(productID: Constants.Store.familyMonthlyID) }

    // MARK: - Restore

    func restore() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await recomputeEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func doPurchase(_ product: Product) async -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await recomputeEntitlements()
                return true
            case .userCancelled: return false
            case .pending:       return false
            @unknown default:    return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func listenForTransactions() {
        Task(priority: .background) {
            for await result in Transaction.updates {
                guard let transaction = try? checkVerified(result) else { continue }
                await transaction.finish()
                await recomputeEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value):      return value
        }
    }

    /// Scans all active entitlements and applies the highest tier
    /// (max > family > premium). Family purchases also upgrade members.
    @MainActor
    private func recomputeEntitlements() async {
        var best: UserPlan = .free
        var hasFamily = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  transaction.revocationDate == nil,
                  let plan = Self.plan(for: transaction.productID) else { continue }
            if plan > best { best = plan }
            if plan == .family { hasFamily = true }
        }

        let defaults = UserDefaults.standard
        if best > .free {
            defaults.set(true, forKey: hadLocalEntitlementKey)
            await setRemotePlan(best)
            if hasFamily { await upgradeFamilyMembers() }
        } else if defaults.bool(forKey: hadLocalEntitlementKey) {
            // Own entitlement expired/revoked -- downgrade. Users granted a plan
            // server-side (family members) never set this flag and are untouched.
            defaults.set(false, forKey: hadLocalEntitlementKey)
            await setRemotePlan(.free)
        }
    }

    @MainActor
    private func setRemotePlan(_ plan: UserPlan) async {
        guard let userId = AuthService.shared.currentUser?.id,
              AuthService.shared.currentUser?.plan != plan else { return }
        do {
            try await supabase
                .from("users")
                .update(["plan": plan.rawValue])
                .eq("id", value: userId.uuidString)
                .execute()
            AuthService.shared.currentUser?.plan = plan
            AnalyticsService.shared.track(
                plan == .free ? .premiumRevoked : .premiumPurchased
            )
        } catch {
            storeLogger.error("setRemotePlan error: \(error)")
        }
    }

    /// Sets all members of the buyer's family to premium (#18).
    @MainActor
    private func upgradeFamilyMembers() async {
        guard let familyId = AuthService.shared.currentUser?.familyId else { return }
        do {
            // Fetch child user IDs from family_members
            struct FamilyMemberRow: Decodable {
                let childUserId: UUID
                enum CodingKeys: String, CodingKey { case childUserId = "child_user_id" }
            }
            let members: [FamilyMemberRow] = try await supabase
                .from("family_members")
                .select("child_user_id")
                .eq("family_id", value: familyId.uuidString)
                .execute()
                .value
            for m in members {
                try await supabase
                    .from("users")
                    .update(["plan": UserPlan.premium.rawValue])
                    .eq("id", value: m.childUserId.uuidString)
                    .execute()
            }
        } catch {
            storeLogger.error("upgradeFamilyMembers error: \(error)")
        }
    }
}
