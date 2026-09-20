# First playable slice (historical)
This records the original prototype. Its fixed repair timer and budgets have been replaced by the management slice; see `economy.md` for current behaviour.
The mayor inherits Bellwether: Westbank's streets are worn, while Station Quarter has better access. Observe people moving between homes and jobs, compare neighbourhood condition and trust, commission repairs, and choose an ongoing maintenance budget. Let time pass to see travel conditions and public trust change.

Repairs cost £12,000 immediately, take 40 simulation seconds, and add 42 condition points on completion. During works Westbank walking speed is multiplied by 0.65. Funding is £300 / £900 / £1,800 daily; revenue after other services is £1,600. Condition changes −16.8 / +4.8 / +26.4 points per day. Trust gradually approaches 20 + 0.65 × street condition. These are tuning rules, not claims of realism. A depleted reserve forces reduced maintenance.

This establishes observation → decision → visible consequences. There is no win screen. The next specifications should cover resident routines / building occupancy, street graph and routing, budget accounting, and save format. Households, service capacity, traffic, elections and city generation remain separate future increments.
