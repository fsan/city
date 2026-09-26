# Property valuation and sunlight (numbered list item 12; next free slice label 20)

Bounded batch: replace the flat assessed value and the one-line sunlight proxy
with a measured obstruction assessment, and make the result a real development
trade-off. A building's assessed value now depends on the sunlight its own
footprint actually receives and on how far its door is from a carriageway. A
proposed building shades its neighbours, and the applicant pays those
neighbours for the measured loss; a proposal that would push a neighbour below
the sunlight floor is refused outright.

The label is recorded as 20 because 18 and 19 are taken by the development
proposal and physical construction batches. Numbered item 12 collides with the
second traffic-signal note, so this is the item-12 batch and not "slice 12".

## What the town could not do before

`docs/scene.md` recorded the inherited state: "Building values include a
0.9-1.1 sunlight multiplier from a southern-neighbour height proxy." The proxy
was one comparison per pair - any lot more than 0 m and less than 35 m to the
south, within 9 m laterally, shaved a fixed amount - and no player decision
could change it. A completed development redeveloped its lot in place, but
`development.zig` re-used the flat `city.lotValue(kind)` for the assessment, the
levy and the applicant's budget, so two sites with completely different
surroundings were priced identically and a tall neighbour cost nobody anything.

## Rules now in force

- **Sunlight is measured, not proxied.** The sun stands at a fixed published
  altitude and azimuth. A building of height `h` casts a shadow of length
  `h / tan(altitude)` towards the north with a fixed lateral spread. A
  receiver's occlusion is the depth and lateral overlap of every obstruction
  that actually reaches it, sampled over the receiver's own footprint corners
  and centre. Sunlight is `1 - occlusion`, bounded below by `sun_floor`
  (0.35). The renderer's daylight shading stays illustrative; this is a
  valuation model, not a ray-traced solar simulation.
- **Assessment is measured.** A lot's assessed value is its authored base value
  for its use, times the measured sunlight multiplier `0.9 + 0.2 * sunlight`,
  times a bounded road-access multiplier that rewards a frontage near a
  carriageway and a higher street class. Values are rounded to pennies, so the
  assessment roll, the levy and the reports agree exactly.
- **Development pays for the shadow it casts.** A proposal measures the sun
  each neighbouring lot receives now and the sun it would receive with the
  proposed building standing. The summed assessed-value loss is the proposal's
  `shadow_loss`. The applicant pays a fixed share of that loss
  (`shadow_share`) to the affected owners: a home's owner cash, or a
  workplace's company cash. This is private money; the municipal ledger still
  records only the development levy.
- **A hard conflict is refused.** If the proposed building would push any
  neighbour below the neighbour sunlight floor (0.25), the permit is refused
  with its own reason. Otherwise the trade-off is priced, not forbidden.
- **The levy follows the assessment.** Granting a permit recomputes the
  proposed use's assessed value at the site's measured sunlight and access, and
  takes `levy_rate` (0.0005) of that assessed value as the development levy,
  rounded to pennies, as ledger kind 12. A shaded site is worth less and
  therefore pays a smaller levy.
- **Completion updates the roll.** When a job completes, the new lot takes its
  use and footprint and the whole town is reassessed, so neighbours' sunlight,
  assessed value and property tax bill change. Rents already enrolled stay
  sticky, exactly as authored rents do.
- **Save/load preserves the assessment.** Schema moves to v15; v14 and older
  files are rejected with result 3. Every new proposal field and the two new
  private shadow totals are validated field by field, and each stored building's
  sunlight and value must sit inside the published bounds.

## Measured

The focused probe ran outside the repository with ReleaseSafe. The dense town is
fixed, so it reports the same authored baseline the earlier slice notes record:

| check | result |
|-------|--------|
| authored town, unchanged | 820 lots, 1,328 nodes, 1,624 roads, 10 vacant |
| measured sunlight | mean 0.975, darkest 0.624, 185 lots below full sun |
| assessed roll | 612 rated lots, GBP 1,388,097,604.64, 0 mismatches against the model |
| valuation trade-off | lot 89 sun 0.638 assessed GBP 2,342,869.92 vs GBP 2,508,000.02 unshaded |
| tall-building detector | a downtown office shades 3 lots, darkest 0.879, loss GBP 57,396.69 |
| first application | parcel 80, home, assessed GBP 2,098,799.93, levy GBP 1,049.40, budget GBP 335,807.99 |
| sunlight conflict | measured darkest 0.179, refused, reason 13, GBP 0.00 moved |
| shadow compensation | office plan shades 2 lots, loss GBP 239,587.97, compensation GBP 14,375.28, levy GBP 1,254.00 |
| completion | built in place, phase 5, progress 1.00, spend GBP 58,504.32 of GBP 401,280.00, materials 287.36/287.36, assessed GBP 2,508,000.02 |
| neighbour reassessment | lot 11 GBP 1,980,000.04 to GBP 1,816,991.47 after the build |
| v15 round trip | result 0 at init and after the session; the shadow trade-off survives |
| v14 file | result 3 |
| municipal ledger | only the levy moved; the maximum kind remains 12 |

## Verified

The consolidated probe reports **`checks: 41, failures: 0`**, and the served
`/build/city.wasm` sha256 `91fa225c...` matches the published `/output/city.wasm`
byte for byte (`docker compose up web`, `curl /build/city.wasm` against the build
volume). The served page carries the sunlight/shadow wording and the served
`planning.js` carries the sunlight field.

- Docker Compose Zig 0.14.1 ReleaseSafe builds passed after the city,
  development, persistence, ABI and panel changes, and `make build` published a
  fresh `/output/city.wasm`.
- `node --check` passed for the served JavaScript modules, and the served page
  carries the sunlight, shadow and assessment fields.
- One ReleaseSafe probe outside the repository exercised the measured baseline,
  the assessment model, the valuation trade-off, the shadow detector, demand
  lodgement, the sunlight-conflict refusal, a shadow-priced grant with real
  owner compensation, the physical completion, the neighbour reassessment and
  the v15 round trip with the v14 rejection.
- Three pre-existing save-path defects were found and repaired while chasing the
  round trip: an orphaned `road.works` flag in the development plan, an
  over-strict owner-cash invariant, and a kerbside occupancy bound compared
  against all parking facilities instead of kerbside spaces.

## Limits

- One fixed sun position, one shadow shape and a bounded footprint sample.
  Seasons, time-of-day solar geometry, terrain shading and reflected light are
  not modelled.
- The compensation share is a bounded policy number, not a negotiated or
  adjudicated settlement, and only the four largest neighbour losses are
  retained on the proposal.
- Assessment uses the authored base value, measured sunlight and road access.
  Floor area, condition, frontage width and market comparables are still out of
  scope.
- The shadow scan is bounded by the town's authored lot count.
