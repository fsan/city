# Economy and public works

Municipal cash begins at £180,000. Initial operating disbursements immediately pay £625, leaving £179,375. Every municipal cash change records simulation time, amount, resulting balance, category, source/recipient and order ID. Keep amounts rounded to pennies at transaction boundaries. The ledger retains the latest 1,024 entries; lifetime revenue/spending totals remain available after older entries roll off. The UI shows 80 and can export all retained entries.

Residential and commercial property have separate assessed bases and annual rates (0–5%). Bills are property value × annual rate / 100 / 360, rounded per property and collected at midnight. Policy drafts do not apply until confirmed. Residential owners are assumed liquid; business bills draw from company cash, with unpaid amounts retained as arrears. Resident tax shares divide their home's bill among its residents for inspection, not a household cash simulation.

Non-contractors receive a simplified £12 operating surplus per employee daily, before tax. Contractors rely on orders. All employment totals derive from assignments within employer capacities. No hiring/firing, wages for ordinary jobs, demand market or bankruptcy is modelled yet.

Operating spending occurs every 30 simulation seconds: other services £4,000/day plus street maintenance £2,000 / £6,000 / £11,000 per day. Each disbursement pays 1/16 of the daily amount. Funded maintenance takes effect for the following interval; protected order reserves cannot be spent on operations. Funding shortfalls reduce maintenance coverage rather than creating money. The other-service budget is a financial aggregate; service outcomes are not yet simulated.

Street condition changes per second by `0.03 × active funding tier × paid fraction − 0.025`, bounded 5–100. Fully funded daily changes are −12 / +2.4 / +16.8 points. Local trust approaches `20 + 0.65 × mean local street condition`, with a 120-second response timescale. This narrow trust measure is explicitly labelled in reports.

Orders specify one street, 5–60 requested condition points (capped by remaining need), and a price. Reserve the full offered amount immediately. One active order per street; at most 64 orders are retained per session. Unaccepted offers can change price or be cancelled without payment.

Three local street contractors each have one four-person crew, drawn from their actual employees. Every five seconds they evaluate offers in publication order; firms are considered in stable register order. This is direct acceptance, not a lowest-bid tender auction. Minimum price covers an £800 setup cost, estimated crew travel and productive labour, plus the firm's margin. Rejection reasons include price, existing commitment, missing capability, cash or unreachable site. Estimates change with actual worker location.

Acceptance binds the crew and price and pays setup from company cash. Crew members finish their current segment or leave the current frontage and travel to the site. Companies pay their own labour costs during mobilisation/work. Progress requires all four workers on site and operating cash; low cash blocks delivery and is inspectable. One condition point requires three worker-seconds. Disruption applies only while work is in progress.

Completion applies delivered condition points, pays the agreed amount, releases reserves and returns the crew to normal routines. Accepted cancellation pays `price × (0.05 + 0.95 × delivered fraction)`, capped at the offer, and retains the partial street improvement. The UI shows this compensation before confirmation. Orders expose status, assigned company, progress, incurred contractor costs, city payment and crew links.

All simulation state is local to the current tab. Save/load, regional markets, materials and multistage tenders remain future work.

Bus operators have independent authored accounts, separate from ordinary employers. Their opening capital, receipts, vehicle/clearance costs and driver labour reconcile in Transport Authority; see `service-agreements.md`. Driver cohorts do not alter resident employment. Municipal subsidies still spend only uncommitted cash.
