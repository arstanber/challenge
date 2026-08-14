# Subscription catalog migration

## Decision

Keep RevenueCat. It is already the purchase and entitlement layer for the app,
the `revenuecat-webhook` function is the authoritative writer of `users.plan`,
and Offerings allow product-set and pricing experiments without an app release.
Replacing it with direct StoreKit would duplicate receipt synchronization,
server reconciliation, targeting, and experiment attribution.

## Target Offering

The RevenueCat Offering presented to new customers must contain, in display
order:

1. `reProAnnually` (`premium`, featured, seven-day introductory trial)
2. `reProMonthly` (`premium`)
3. `reFamilyAnnually` (`family`, seven-day introductory trial)

Offering metadata:

```json
{
  "featured_package": "PACKAGE_IDENTIFIER_FOR_PRO_ANNUAL",
  "package_tiers": {
    "PACKAGE_IDENTIFIER_FOR_PRO_ANNUAL": "premium",
    "PACKAGE_IDENTIFIER_FOR_PRO_MONTHLY": "premium",
    "PACKAGE_IDENTIFIER_FOR_FAMILY_ANNUAL": "family"
  }
}
```

The package identifiers are RevenueCat identifiers, not App Store product IDs.
Prices, localized product names, subscription periods, and introductory trials
come from App Store Connect through StoreKit. They are not encoded in the app.

## Existing subscribers

All seven historical product IDs remain in
`Constants.Store.legacyCompatibleProductIDs`. They are intentionally excluded
from the fallback sales catalog but are still recognized during restore.

On sign-in the app enumerates `Transaction.currentEntitlements`. If an active,
verified historical transaction exists, it calls RevenueCat `syncPurchases()`.
RevenueCat maps the product to its existing `premium`, `family`, or `max`
entitlement, and the webhook keeps `users.plan` synchronized.

Expected outcomes:

- An active old monthly, annual, or lifetime subscriber keeps the same access.
- Removing a product from the current Offering only hides it from new buyers.
- Taking an old product off sale in App Store Connect does not delete its
  entitlement mapping or cancel existing subscribers.
- Restore Purchases continues to reconcile historical receipts.
- Expiration, refund, revocation, and transfer remain controlled by RevenueCat
  current entitlements and the existing webhook.

Do not delete old products, remove their RevenueCat entitlement attachment, or
move auto-renewable products between subscription groups during this migration.
