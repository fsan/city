# Bus operators and service agreements

T → Bus operators & service agreements opens procurement, current delivery and the closed agreement register. Choose a line, operator, one to three buses, one to seven days and maximum payment. All three operators are compared against the draft: available fleet/drivers, minimum price and resource/price refusal. Quotes reserve nothing. Publish reserves the entire price; companies review as simulation time advances. A valid but unattractive offer stays open and can be revised or cancelled. An invalid or unaffordable offer changes nothing.

Three authored operators own four, three and two buses. Working capital starts at £600, £300 and £5 respectively. They have separate abstract day/night driver cohorts of 4/2, 3/1 and 2/0. Daytime coverage is 06:00–22:00; all-day coverage includes the 22:00–06:00 night cohort. These are staff abstractions, not resident employment/payroll assignments.

Acceptance and draft quotes share Zig rules. They consider other active lines (including private services), exclude the line being replaced, and distinguish vehicle, driver-coverage, cash-buffer and price refusals. Both coverage cohorts must fit for an all-day offer. Required cash is £12.80 per proposed/other committed bus: £2 prepaid clearance plus 60 seconds at £0.18. This is an acceptance liquidity threshold, not escrow; future payment is never spendable cash. Price covers scheduled seconds at £0.18 plus £2 per bus per day, then 15% margin, rounded upward. Duration is 1–7 whole days. A two-bus daytime day costs at least £137.08; all-day £203.32. Fares are not assumed by procurement.

Each company has one authoritative account: opening balance + fares + funded boarding subsidies + earned agreement receipts − vehicle/clearance costs − driver labour = cash. The UI exposes every component. Costs accrue at full sub-penny precision (£0.06 vehicle and £0.12 labour per bus-second); display rounds to pennies. Fares/subsidies are penny-rounded at policy application and municipal payments settle in pennies. Per-line income/costs only attribute transactions; they never create independent capital. Changing operator transfers no money.

Initial lines belong to Bellwether Transit and Ridgeway Passenger, both daytime. New slots default to Community Bus/daytime; reused slots retain their previous company, window and financial attribution. An empty bus dispatch requires a vehicle, an on-duty driver, and at least £2.18 cash; it immediately expenses a £2 clearance fee. Active service charges only funded time; exhaustion permanently marks that bus for safe retirement. Clearing earns nothing and has no further time debit: the prepaid fee explicitly covers safe completion/unloading and outgoing-driver relief overtime even in long queues. This is a bounded cost abstraction, not hidden debt. The vehicle remains attributed to its original company and occupies its physical resources until empty.

All-day relief occurs at the next junction across a shift boundary without unloading riders solely for relief. Daytime service ends at the next safe junction; riders alight and walk onward. Clearing vehicles can temporarily block new dispatch even when an offer's reserved coverage fits. Labour is charged once, not both as wages and an old combined running charge.

Payment is earned by movement and scheduled dwell by current-route buses; held traffic, unavailable service and buses clearing an old route do not earn it. Expected delivery to date is scheduled contracted seconds × required fleet; off-hours add no target. The final payment denominator uses the same service-window integral. Shift boundaries are resolved at the fixed simulation step (1/30 second). The review shows measured/expected bus-seconds, percentage, earned/paid/reserved money and the payment not earned through under-delivery to date. Payment settles when at least £1 is due, with remaining pennies settled on closure. The expiry step is clipped to the contracted end; no later service earns against a closed agreement.

Current requested fleet is broken into moving, dwelling, held at signals/queues, clearing an old route and unavailable. Waiting passengers are counted for the selected line. These are live states, not historical failure attribution or headway compliance. Remedies use existing street allocations and route editing, or cancellation followed by a replacement offer. The player cannot recover past missed delivery by cancelling.

Cancellation settles earned pennies exactly once and releases the remainder immediately; there is no additional cancellation fee. Line withdrawal does the same even while paused, with a distinct closed outcome. Expiry releases unused municipal reserves; the continuing private route retains its fleet/coverage requirements. Cancellation/expiry leave the route operating privately with its existing fleet, operator and hours; they do not guarantee future funding. Re-offering to a new operator preserves the route and aboard passengers; fleet reduction retires surplus buses safely. Route edits retain the agreement clock and can reduce delivery while old buses clear.

Every published offer receives a unique agreement number. Revisions archive their replaced offer. The newest 64 closed records retain original terms, offered route stops/version, dates, service window, final target, outcome, delivered/expected service, final payment and released reserve. Records survive later offers and line-slot reuse within this session. Ledger category 8 identifies the actual bus operator and agreement number. The ledger retains its own latest 1,024 transactions independently of the agreement register. Refresh/Restart town clears both; manual local save/load restores both rings, active agreements, evidence, reserves and identity counters. It does not extend their retention limits.

Fleet purchases, sales, maintenance and driver recruitment are now explicit in `operator-workforce-slice.md`: quotes and acceptance read the live owned/serviceable/committed split and the recruited day and night cohorts, so a unit under maintenance or committed to another line is refused before acceptance. Individual driver travel, headway/stop targets and a full tender process remain future increments. See `operator-capital-slice.md` for the earlier scope and verification.

Verification: Docker ReleaseSafe build and JavaScript syntax/diff checks. Temporary WASM runs covered invalid inputs, penny-price thresholds, rejected over-budget revision, capacity competition, cancellation, paused withdrawal, line reuse, expiry, immutable route records, history rollover/reset, ledger reconciliation, finite rendering and passenger conservation. A shared-budget run also completed a physical street repair while paying the bus agreement. Browser checks covered draft comparisons, offer revision, expiry, cancellation/re-offering and the register. No permanent test suite was added.

Stop arrivals and completed interarrival intervals are now reported separately in the Transport Authority; see stop-regularity-slice.md. They are descriptive observations and do not alter delivered bus-seconds, expected coverage, settlement or payment. Route/window observation history is independent of the immutable closed agreement register.

## Optional regularity review target

Offers may include a maximum interarrival interval: 0 disables it, otherwise choose a whole 30–600 simulation seconds. This is an agreed review target, not a financial guarantee: operator quotes still assess resources and price, not headway feasibility. No payment deduction, price uplift, reserve adjustment or automatic remedy is attached to this target. Existing movement/dwell payment rules apply.

Only physical service-stop arrivals after acceptance, through expiry, by the agreed operator on the original offered route count. The report records completed interval pairs, exceeded pairs, worst interval and stops with evidence; it makes no blanket compliance claim from sparse samples. Deployment, clearance and relief-only junction stops remain excluded. Daytime pairs spanning closed hours are omitted, while all-day pairs cross midnight.

Each service window allows one target-length grace period for its first arrival, starting at acceptance if later than opening. The gap state separately identifies awaiting-first, first-arrival overdue, within the current gap allowance, subsequent overdue and off-hours. Grace is only a diagnostic rule, not a payment exemption. A full bus still counts; a bus arrival is not a seat guarantee or resident waiting duration.

Editing the route permanently suspends review against the original route, including while paused, without erasing measured results or restarting the agreement clock. A changed offered route before acceptance is likewise unassessable. Re-offer explicitly to agree a new route/target. Operator/window mismatches also suspend; fleet/lane changes do not erase evidence.

The newest 64 closed agreements retain target, per-stop evidence and gap state at closure, independently of subsequent private operation, route edits and slot reuse. A closure during off-hours records off-hours, not a history of earlier overdue episodes. See regularity-target-slice.md for precise limits and verification.


## Contract enforcement (slice 5)

Only delivered bus-seconds against the agreed windowed target integral are
enforceable. When a whole day of expected service has elapsed and delivery is
below 85%, a 480-simulation-second cure opens with no charge. After the cure,
each measured shortfall adds GBP 0.18 per missing bus-second to a service
credit, capped at 25% of the agreement price. Credits are paid from the
operator's own cash above the GBP 2.18 dispatch floor; anything unpaid is
recorded as waived, never as debt. A route, window or operator change suspends
enforcement and cannot create a charge. Regularity targets remain review-only.
Ledger kind 10 records money actually received, and the agreement report
reconciles accrued = paid + waived + outstanding.
