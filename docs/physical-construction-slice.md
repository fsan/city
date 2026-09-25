# Physical building construction (numbered list item 11; next free slice label 19)

Bounded batch: give the private development permits from item 10 a physical
construction path. A granted permit keeps the existing in-place lot identity,
levy and final enrolment rules, but the building is no longer an abstract timer:
the site must have road access, a contractor crew must travel to it, materials
must be staged and paid for, and the terrain determines the grading and
foundation cost.

The rules below are implemented. The measured table and limits were filled in
after the Docker ReleaseSafe probe and served-asset checks.

## What the town could not do before

`docs/development-proposals-slice.md` recorded the item-10 limit explicitly:
construction had no crews, materials, terrain grading or foundation cost. A
permit immediately reserved a scheduled completion time and the lot changed use
when that time elapsed. The player could see a levy and a deadline, but no
physical work, no access question and no construction account.

## Rules now in force

- **Access is measured, not assumed.** A proposal can only be lodged for a lot
  whose door has a road within the bounded access distance and whose frontage
  node is connected to the street graph. A site beyond the hard access limit is
  not offered. Sites between the free distance and the hard limit carry an
  explicit access cost, so a remote frontage is more expensive but still
  buildable.
- **Terrain is measured across the proposed footprint.** The renderer and the
  simulation both read `city.elevation`; construction samples the proposed
  footprint corners and centre. The height range over the footprint gives a
  bounded slope. A site above the maximum buildable slope is refused with its
  own reason. Otherwise the slope drives a grading cost.
- **Foundation cost is explicit.** The foundation charge is derived from the
  proposed footprint area, height and slope through published constants. It is
  paid from the applicant's own construction budget, never from the municipal
  ledger.
- **Materials are staged, not conjured.** A granted permit has a required
  material quantity and a material cost. Deliveries are spread over the
  construction window and are paid from the same private budget as they arrive.
  Building progress only advances in proportion to material actually delivered,
  so a delayed material delivery delays the building.
- **Contractor crews travel physically.** An approved permit reserves one
  contractor company that already has its four-person crew and no other active
  work order. The crew members use the existing resident movement model, carry
  the construction work order, and are rendered in the existing amber crew
  colour. The job is `mobilising` until all four arrive, `delivering` while
  materials are staged, `building` while work progresses, and `blocked` if the
  contractor or budget can no longer continue.
- **The applicant pays privately; the municipality records only the levy.**
  Each proposal carries its own bounded construction budget and explicit spend.
  Groundwork, foundation, materials and crew labour are paid from that budget to
  the selected contractor. The municipal ledger still records only ledger kind
  12, the development levy, under the application's own number. There is no
  hidden municipal cost and no second levy.
- **Completion uses the existing in-place construction.** Only when the crew is
  present, the materials are delivered and progress reaches one does the lot
  change use. The existing `housing.enroll` and `residents.addEmployer` paths
  remain the only ways a new dwelling or workplace enters the live rolls.
- **Refusals and blocks are explicit.** New reasons distinguish no access,
  terrain too steep, insufficient applicant funds, no contractor crew and a
  construction budget exhausted after work began. A blocked job stays visible
  and does not silently complete.
- **Save/load preserves the whole construction account.** Schema moves to v14;
  v13 and older files are rejected with result 3. Every new proposal field,
  company/crew work-order link and private construction total is validated by
  field, not inferred from native struct bytes.

## Measured

The focused probe ran outside the repository with ReleaseSafe and `checks
failed: 0`:

| check | result |
|-------|--------|
| authored town, unchanged | 820 lots, 1,328 nodes, 1,624 roads, 10 vacant |
| eligible-zoned sites before zoning | 0 |
| first application | parcel 29, apartment, access 1, slope 0.000, budget £416,000.00, estimate £17,308.80, 111.3 material units |
| grant | company 5, crew 4, work order 1000001, levy £1,300.00, initial private spend £5,624.00 |
| crew travel | all four arrived after 13,632 fixed steps |
| completion | lot 29 built, private spend £17,619.39 of £416,000.00, materials 111.30/111.30, progress 1.00 |
| municipal ledger | only the £1,300.00 kind-12 levy moved |
| v14 round trip | result 0, 7,749,309 bytes, built total and private spend preserved |
| v13 file | result 3 |
| inaccessible lot | a vacant lot moved beyond the access limit attracted no application |
| served build | `/output/city.wasm` and served `/build/city.wasm` matched byte for byte during the final publication check |

## Verified

- Docker Compose Zig 0.14.1 ReleaseSafe builds passed after the development,
  persistence, ABI, renderer and panel changes.
- `node --check` passed for the served JavaScript modules, and the served page
  carries the physical Permits fields.
- The probe compiled outside the repository and ran acceptance, contractor
  travel, staged materials, completion, v14 save/load and v13 rejection with
  zero failed checks.
- Independent Zig builds can carry different build metadata, so publication is
  verified by matching the served `/build/city.wasm` to the published
  `/output/city.wasm`, not by expecting two independent builds to hash
  identically.

## Limits

- The proposal ring remains 24 records, at most 8 pending applications and at
  most 2 new applications per day.
- The construction crew is exactly one contractor's bounded four-person roster.
- Material delivery and construction progress are bounded per fixed step.
- Access, grading, foundation, material and labour costs are bounded policy
  numbers, not tendered or market prices.
- No regional trade, supplier firms, heavy equipment or foundation engineering
  is added. Those remain later work.
