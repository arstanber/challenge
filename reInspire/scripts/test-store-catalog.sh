#!/bin/zsh
set -euo pipefail

test_dir="$(mktemp -d /private/tmp/reinspire-store-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/main.swift" <<'SWIFT'
import Foundation

private var failures: [String] = []
private func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() { failures.append(name) }
}

let expectedSellable: Set<String> = ["reProMonthly", "reProAnnually", "reFamilyAnnually"]
expect(Constants.Store.fallbackSellableProductIDs == expectedSellable, "fallback contains only target products")
expect(Constants.Store.plan(forProductID: Constants.Store.premiumMonthlyID) == .premium, "legacy Pro monthly entitlement")
expect(Constants.Store.plan(forProductID: Constants.Store.premiumAnnualID) == .premium, "legacy Pro annual entitlement")
expect(Constants.Store.plan(forProductID: Constants.Store.premiumForeverID) == .premium, "legacy Pro lifetime entitlement")
expect(Constants.Store.plan(forProductID: Constants.Store.familyMonthlyID) == .family, "legacy Family monthly entitlement")
expect(Constants.Store.plan(forProductID: Constants.Store.familyAnnualID) == .family, "Family annual entitlement")
expect(Constants.Store.plan(forProductID: Constants.Store.maxMonthlyID) == .max, "legacy Max monthly entitlement")
expect(Constants.Store.plan(forProductID: Constants.Store.maxAnnualID) == .max, "legacy Max annual entitlement")
expect(Constants.Store.legacyCompatibleProductIDs.count == 7, "all seven historical products remain restorable")
expect(Constants.Store.plan(forProductID: "unknown") == nil, "unknown product does not grant access")

if failures.isEmpty {
    print("StoreCatalog: 10 tests passed")
} else {
    for failure in failures { print("FAIL: \(failure)") }
    exit(1)
}
SWIFT

CLANG_MODULE_CACHE_PATH="$test_dir/module-cache" \
SWIFT_MODULECACHE_PATH="$test_dir/module-cache" \
xcrun swiftc Models/User.swift Utils/Constants.swift "$test_dir/main.swift" -o "$test_dir/store-catalog-tests"
"$test_dir/store-catalog-tests"
