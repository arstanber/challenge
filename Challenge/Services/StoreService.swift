import Foundation
import StoreKit
import Observation
import Supabase
import PostgREST
import os.log

private let storeLogger = Logger(subsystem: "com.challenge", category: "StoreService")

@Observable
final class StoreService {
    static let shared = StoreService()

    // Individual monthly plan
    var product: Product?
    // Family plan (#18)
    var familyProduct: Product?

    var isPurchasing = false
    var errorMessage: String?
    var isPremium: Bool { AuthService.shared.currentUser?.isPremium ?? false }

    private init() {
        Task { await loadProducts() }
        Task { await checkCurrentEntitlements() }
        listenForTransactions()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [
                Constants.Store.monthlyProductID,
                Constants.Store.familyProductID
            ])
            product       = products.first { $0.id == Constants.Store.monthlyProductID }
            familyProduct = products.first { $0.id == Constants.Store.familyProductID }
        } catch {
            storeLogger.error("loadProducts error: \(error)")
        }
    }

    // Keep backward-compatible alias
    func loadProduct() async { await loadProducts() }

    // MARK: - Purchase individual

    @discardableResult
    func purchase() async -> Bool {
        guard let product else { return false }
        return await doPurchase(product)
    }

    // MARK: - Purchase family (#18)

    @discardableResult
    func purchaseFamily() async -> Bool {
        guard let familyProduct else { return false }
        return await doPurchase(familyProduct)
    }

    // MARK: - Restore

    func restore() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()
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
                await handleVerified(transaction)
                await transaction.finish()
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

    private func checkCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            await handleVerified(transaction)
            await transaction.finish()
        }
    }

    private func listenForTransactions() {
        Task(priority: .background) {
            for await result in Transaction.updates {
                guard let transaction = try? checkVerified(result) else { continue }
                await handleVerified(transaction)
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value):      return value
        }
    }

    @MainActor
    private func handleVerified(_ transaction: Transaction) async {
        let isIndividual = transaction.productID == Constants.Store.monthlyProductID
        let isFamily     = transaction.productID == Constants.Store.familyProductID
        guard isIndividual || isFamily else { return }

        let active = transaction.revocationDate == nil
        let plan: UserPlan = active ? .premium : .free

        await setRemotePlan(plan)

        // For family plans, also upgrade all family members (#18)
        if isFamily && active {
            await upgradeFamilyMembers()
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
                plan == .premium ? .premiumPurchased : .premiumRevoked
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
