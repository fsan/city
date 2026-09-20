// Named browser-side schema for the scalar Zig ABI. No simulation rules live here.
export const kinds = [
  "Homes",
  "Shops",
  "Offices",
  "Clinic",
  "Town Hall",
  "Park",
  "Works depot",
];
export const statusNames = [
  "Offered",
  "Mobilising",
  "In progress",
  "Completed",
  "Cancelled",
  "Blocked",
];
export const reasons = [
  "Willing to accept",
  "Price below required margin",
  "Crew already committed",
  "No qualified four-person crew",
  "Insufficient operating cash",
  "Site unreachable",
];
export const commandErrors = [
  "Offer published. Funds reserved; awaiting company review.",
  "Invalid values or order is no longer editable.",
  "Work register is full (64 orders per session).",
  "This street already has an active offer or order.",
  "Insufficient uncommitted funds.",
  "This street does not need repair.",
];
export const money = (value) => "£" + Math.round(value).toLocaleString("en-GB");
export const signedMoney = (value) =>
  (Math.round(value) < 0 ? "−" : "+") + money(Math.abs(value));
export function timeLabel(seconds) {
  const minutes = Math.floor(seconds * 3);
  return `D${Math.floor(minutes / 1440) + 1} ${String(Math.floor(minutes / 60) % 24).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}
export function createData(game) {
  const read = (group, id, field) => game.read(group, id, field);
  const metric = (field) => read(0, 0, field);
  const decoder = new TextDecoder();
  const districts = Array.from({ length: metric(16) }, (_, i) =>
    decoder.decode(
      new Uint8Array(
        game.memory.buffer,
        game.name_pointer(i),
        game.name_length(i),
      ),
    ),
  );
  const buildings = Array.from({ length: metric(14) }, (_, i) => ({
    id: i,
    kind: read(1, i, 0),
    district: read(1, i, 1),
    employer: read(1, i, 6),
    node: read(1, i, 11),
  }));
  const companyName = (id) =>
    id < 0
      ? "Jobseeker"
      : read(4, id, 4)
        ? ["Bellwether Civil", "Ridgeway Works", "Millfield Streets"][
            buildings
              .filter((b) => b.kind === 6)
              .findIndex((b) => b.employer === id)
          ]
        : `${kinds[buildings[read(4, id, 0)].kind]} ${id + 1}`;
  return { read, metric, districts, buildings, companyName };
}
