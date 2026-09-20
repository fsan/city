# Scene scheme

X/Z are the ground plane; Y is elevation, in abstract metres. Bellwether has 18 × 16 authored lots (288), 12 neighbourhoods, 323 street nodes and 610 bidirectional segments over 252 × 224 metres. The fixed ASCII plan in `src/scene/city.zig` is the source of building uses. No random generator is involved.

Terrain is an authored height function: two eastward rises (8 m and 11 m) and a southern terrace (+5 m), joined by slopes. Buildings use level foundations at their footprint's highest corner. Entry ramps connect street nodes to frontages; residents interpolate height along those ramps and follow terrain height along streets. Residents remain visible on frontages while dwelling; interior occupancy is not modelled.

Street records contain endpoints, 3D length, absolute grade, district, condition and permissions. A shared all-pairs next-hop table minimises length × (1 + 3 × grade) / (0.7 + condition / 100). It refreshes every 60 simulation seconds and after order completion/cancellation. Existing travellers finish their segment before taking a new next hop. Temporary works slow movement by 35%; rerouting around temporary disruption is not yet included in route estimates.

Building-to-node links and the reverse entry lookup are explicit. Residents have home/employer IDs, current/next/destination nodes, travel time, frontage movement phase and optional work-order assignment. Ordinary commuters have shortened waits and a simple day/night preference. Crews override their routines until released. These are adult placeholders, not full household schedules.

Rendering consumes scene and simulation data without advancing them. Geometry is batched into a single depth-tested vertex stream: XYZ clip coordinates plus RGB. Residents remain one six-vertex upright quad each. Selected residents show their route in gold; active crews wear amber. The orthographic camera supports rotation, pan, cursor-centred zoom and report-driven focus. Bounds and depth range derive from town dimensions. Picking intersects elevated building boxes.

The current buffer holds 300,000 vertices; this town produces roughly 223,000, with some variation for route highlighting. Geometry is still rebuilt each frame. Profile before expanding further; cached static world meshes and GPU camera transforms are the next rendering optimisations. Residents, buildings, roads and orders retain stable array IDs for the session.
