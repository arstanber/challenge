#!/bin/zsh
set -euo pipefail

test_dir="$(mktemp -d /private/tmp/reinspire-review-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/main.swift" <<'SWIFT'
import Foundation

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() { failures.append(name) }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let now = Date(timeIntervalSince1970: 2_000_000_000)
let day: TimeInterval = 24 * 60 * 60

func context(
    trigger: ReviewPromptPolicy.Trigger = .thirdConsecutiveVerifiedDay,
    installedAt: Date? = nil,
    lastAskedAt: Date? = nil,
    lastNegativeAt: Date? = nil
) -> ReviewPromptPolicy.Context {
    .init(
        trigger: trigger,
        now: now,
        installedAt: installedAt ?? now.addingTimeInterval(-2 * day),
        lastAskedAt: lastAskedAt,
        lastNegativeExperienceAt: lastNegativeAt
    )
}

expect(ReviewPromptPolicy.shouldAsk(context()), "eligible third verified day")
expect(ReviewPromptPolicy.shouldAsk(context(trigger: .duelVictory)), "eligible duel victory")
expect(!ReviewPromptPolicy.shouldAsk(context(installedAt: now.addingTimeInterval(-day + 1))), "blocked during first 24 hours")
expect(ReviewPromptPolicy.shouldAsk(context(installedAt: now.addingTimeInterval(-day))), "eligible at 24-hour boundary")
expect(!ReviewPromptPolicy.shouldAsk(context(lastNegativeAt: now.addingTimeInterval(-48 * 60 * 60 + 1))), "blocked for 48 hours after failure")
expect(ReviewPromptPolicy.shouldAsk(context(lastNegativeAt: now.addingTimeInterval(-48 * 60 * 60))), "eligible at 48-hour boundary")
expect(!ReviewPromptPolicy.shouldAsk(context(lastAskedAt: now.addingTimeInterval(-120 * day + 1))), "blocked for 120 days after request")
expect(ReviewPromptPolicy.shouldAsk(context(lastAskedAt: now.addingTimeInterval(-120 * day))), "eligible at 120-day boundary")

let today = calendar.startOfDay(for: now)
let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
expect(ReviewPromptPolicy.isThirdConsecutiveDay(adding: today, to: [twoDaysAgo, yesterday], calendar: calendar), "three consecutive verified days")
expect(!ReviewPromptPolicy.isThirdConsecutiveDay(adding: today, to: [threeDaysAgo, yesterday], calendar: calendar), "gap breaks verified-day sequence")
expect(!ReviewPromptPolicy.isThirdConsecutiveDay(adding: today, to: [yesterday, yesterday], calendar: calendar), "duplicate day does not count twice")

if failures.isEmpty {
    print("ReviewPromptPolicy: 11 tests passed")
} else {
    for failure in failures { print("FAIL: \(failure)") }
    exit(1)
}
SWIFT

CLANG_MODULE_CACHE_PATH="$test_dir/module-cache" \
SWIFT_MODULECACHE_PATH="$test_dir/module-cache" \
xcrun swiftc Services/ReviewPromptPolicy.swift "$test_dir/main.swift" -o "$test_dir/review-policy-tests"
"$test_dir/review-policy-tests"
