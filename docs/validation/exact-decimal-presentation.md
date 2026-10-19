# Exact decimal presentation foundation

This is the numeric-display portion of Apple [#58](https://github.com/Pick-Your-AI/pick-your-ai-apple/issues/58).
The accepted engineering scope permits localization preparation; it does not
establish additional-market, UI, theme or accessibility acceptance.

## Behavior and integration

`ExactDecimalFormatter` takes an explicit Foundation `Locale` and a validated
`ContractDecimal`. It substitutes only the locale's decimal mark and positional
decimal digits. It keeps every integer digit and all supplied fractional digits,
including trailing zeros. There is no grouping, rounding, scientific notation,
unit conversion or currency conversion. The complete amount never passes through
`Double`, `NSNumber`, `Foundation.Decimal` or `NSDecimalNumber`.

Only the individual integers zero through nine pass through `NumberFormatter` to
discover the locale's digit glyphs. Each must be one Unicode decimal-number scalar
with the expected value; algorithmic numeral output is unsupported. Missing or
unsupported symbols throw `unsupportedNumberingSystem` instead of returning a
guessed amount. The immutable result retains no mutable Foundation formatter and
is safe to pass between tasks. Construct another value when the selected locale
changes; do not silently retain an old locale in UI state.

`presentation(for:)` returns a localized amount and the original uppercase currency
code as separate fields. It does not guess a currency symbol from the user's
region or apply a currency's customary minor-unit rounding. Keep the currency code
visible when rendering money. The calling UI owns accessible labels, localized
field placement and bidirectional layout; the numeric helper preserves logical
digit order and does not claim visual RTL qualification.

Use the original `ContractDecimal.rawValue` and canonical currency code for
arithmetic, comparison, persistence and export. The display string is not a new
wire representation or an input parser. An absent amount remains absent; the
helper accepts only an existing validated value and does not supply zero.

## Synthetic locale matrix

| Locale | Numeric behavior tested | Scope |
| --- | --- | --- |
| `en_US` | Decimal point; 200 integer digits and twelve fractional digits preserved | Exact numeric presentation |
| `de_DE`, `fr_FR` | Decimal comma; no grouping or discarded fractional zeros | Exact numeric presentation |
| `en_IN` | Canonical bytes and exact arithmetic unchanged | Numeric invariance; grouping is intentionally absent |
| `ar_EG@numbers=arab` | Arabic decimal digits and mark, preserved logical order and explicit zero precision | Numeric RTL input; visual layout unverified |
| `fa_IR@numbers=arabext` | Persian decimal digits and mark, preserved logical order | Numeric RTL input; visual layout unverified |
| `en_US@numbers=roman`, `zh_Hans_CN@numbers=hans` | Unsupported algorithmic output rejected; switching to a supported locale recovers without changing source data | Failure/recovery of numeric presentation |

Numbering-system extensions pin the intended numeral variants in the Arabic and
Persian tests. These synthetic locale checks do not approve localized copy or
market availability. Currency tests retain USD, JPY, KWD and the structurally valid
XXX code without a value-changing minor-unit policy.

## Reproduce and receiving gates

Run `swift test --package-path Packages/PlannerCore` and the optimized core suite,
then satisfy the repository's applicable macOS and iOS SDK/simulator checks.
`ExactDecimalFormatterTests` verifies precision, comma and non-Latin output,
zero/fraction distinction, algorithmic rejection/recovery, currency identity,
canonical JSON/arithmetic invariance and concurrent use of distinct locale values. These are library tests, not
screenshots or VoiceOver evidence. The delivering PR records actual compiler,
OS, command, artifact identity and receiving disposition.

The existing #58 criteria still require theme and locale changes through real
screens; dates, units, pluralization, canonical-ID/display-label separation,
long labels, compact/large layouts, accessibility text sizes, keyboard navigation,
light/dark appearance, Reduce Motion, VoiceOver and screenshots. #54's accessible
control prerequisites and receiving UX/accessibility review remain applicable.
No issue closure follows from this helper.

## Primary API references

Apple's [NumberFormatter](https://developer.apple.com/documentation/foundation/numberformatter),
[locale](https://developer.apple.com/documentation/foundation/numberformatter/locale),
[decimalSeparator](https://developer.apple.com/documentation/foundation/numberformatter/decimalseparator)
and [string(from:)](https://developer.apple.com/documentation/foundation/numberformatter/string(from:))
documentation were checked on 2026-10-18. The implementation uses Foundation only
for local symbol discovery; canonical frozen-v1 decimal arithmetic and source
data are unchanged.
