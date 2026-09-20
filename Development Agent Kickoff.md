# Development Agent Kickoff

## Mission

Develop a playable modern city-management game in which the player is the elected mayor of a living fictional town. The game should grow from a manageable small or medium town into a dense, complicated city. Its core appeal is governing real civic trade-offs through interconnected systems—not simply placing buildings or maximising population.

The project takes structural inspiration from *Songs of Syx*: a large visible population, individual lives that contribute to city-scale outcomes, interconnected needs, and a city that becomes harder to govern as it grows. The setting, institutions, problems, and player role are modern and original.

The canonical scope is in [Modern City Management Game Scope Specification.md](<Modern City Management Game Scope Specification.md>). Read it before proposing or beginning development work.

## Player fantasy

The player is the mayor. They inherit a functioning town rather than founding a settlement from nothing. The town has people, homes, workplaces, streets, public institutions, businesses, social tensions, and existing problems before the player takes office.

The player should feel the authority and pressure of civic leadership:

- They can decide priorities, budgets, public investment, policies, incentives, departmental direction, and public communication.
- They cannot simply command every resident or force every institution to behave as intended.
- Their decisions have visible benefits, costs, delays, unintended effects, political opposition, and long-term consequences.
- They must seek reelection every few in-game years while still making decisions that protect the city beyond the next election.

The game is not intended to flatter the player. It should provide enough information to make difficult choices intelligently, then let the city respond according to its people, institutions, incentives, and existing conditions.

## The intended experience

At any moment, the player should be able to move between several perspectives:

- An individual resident on a trip to work, school, home, a clinic, or a civic institution.
- A household dealing with rent, a job loss, care needs, transport access, or a neighbourhood change.
- A street experiencing traffic, pedestrian activity, retail life, lighting failures, maintenance work, or visible disorder.
- A neighbourhood with a distinctive identity, service quality, political mood, housing situation, local groups, and social pressures.
- The whole city, viewed through finances, employment, trade, wellbeing, public safety, infrastructure, trust, and election prospects.

The player should regularly encounter problems that do not have a one-button answer. A drug-related street-crime problem, for example, may be affected by enforcement, investigation quality, corruption, treatment access, housing stability, employment, education, media framing, and public trust. A response can be defensible and still create costs elsewhere.

## Non-negotiable design values

### People remain visible

Residents are not merely workers or tax units. They have homes, households, daily routines, work or education, needs, relationships, affiliations, and opinions. Aggregate dashboards are essential, but they must be explainable through the lives and places underneath them.

### Complexity must be inspectable

The city may be demanding and occasionally overwhelming. It must not feel arbitrary. When a metric worsens, a player should be able to investigate what changed, which populations or places are affected, and which systems contribute to it.

### Institutions are imperfect

Police, courts, departments, businesses, homeowner associations, neighbourhood groups, banks, newspapers, and religious centres all have incentives and limitations. They can be effective, underfunded, biased, compromised, self-interested, or corrupt. These failures should be meaningful gameplay situations, not unexplained random punishments.

### Trade-offs are the game

There should rarely be a free benefit. New factories create jobs and revenue but may bring traffic and resistance. Strong enforcement can reduce visible disorder but harm trust if it is unfair or corrupt. Tax relief can retain businesses but reduce service funding. Better streets can improve access while changing land value and displacement pressure.

### Fictional but socially credible

Use original fictional names, organisations, parties, media outlets, religions, companies, neighbourhoods, and city history. Real social dynamics can inform the game, but it should not portray identifiable real individuals or directly recreate real religious or political institutions.

## Core gameplay loop

1. Observe the city through alerts, maps, reports, local news, neighbourhood views, and individual stories.
2. Diagnose what is causing a problem and which groups or places are affected.
3. Choose policy, spending, staffing, infrastructure, regulation, incentives, communication, or oversight actions.
4. Let time pass and observe responses from residents, institutions, businesses, and the regional economy.
5. Adapt to the intended and unintended consequences.
6. Maintain legitimacy and govern through the next election while building a city that remains viable at greater scale.

The default day length is eight real-time minutes. This is deliberately slow enough for the player to see daily life and intervene thoughtfully. Longer cycles—weeks, fiscal periods, school terms, business cycles, and elections—create the strategic horizon.

## Major gameplay domains

The future game must support, in an expandable form:

- Population, households, life paths, and neighbourhood identity.
- Housing, property, rentals, ownership, homeowner associations, and displacement pressure.
- Streets, traffic, pedestrians, signals, freight, parking, safety, and accessibility.
- Utilities and civic infrastructure, including pipes, lighting, maintenance, public space, upgrades, and failures.
- Municipal finance, taxes, incentives, debt, reserves, and service budgets.
- Employers, job creation, factories, offices, retail, services, skills, and trade.
- Markets, stores, banks, trade centres, imports, exports, and household purchasing power.
- Education, healthcare, addiction support, social care, cultural institutions, and fictional religious centres.
- Law, crime, policing, investigation, courts, judges, punishment, rehabilitation, and oversight.
- Corruption, conflicts of interest, accountability, audits, scandals, and institutional reform.
- Newspapers and local media that influence opinion but have incentives and interests of their own.
- Civic groups, neighbourhood organisations, lobbying, consultation, protest, and participation.
- Elections, approval, constituencies, public trust, and mayoral legitimacy.

These systems need not all be built at once. The product should be developed in small, playable increments, with every new system connected to a clear player decision and a legible city outcome.

## Key measures the player should govern

Do not reduce city health to a single happiness number. The main recurring measures are resident wellbeing, public trust, economic vitality, municipal finances, housing stability, mobility and access, public safety and justice, health and care, education and opportunity, social cohesion, and city resilience.

Each measure must be meaningful at more than one scale. A city-wide value can look healthy while a particular neighbourhood or group is struggling. The player needs to see both the aggregate and the uneven distribution.

## Scope boundaries

The first game is about governing a municipality and its surrounding economic region. It does not currently need national politics, military conquest, inter-state diplomacy, or a grand-strategy empire layer.

Do not begin with an empty-map city builder. Start every campaign with a generated, operational town and active civic problems. Do not begin by simulating every aspect of a real city; instead, build a coherent first playable slice that makes people, streets, jobs, services, and mayoral decisions feel connected.

## Direction for the next development agent

Start by reading the scope specification and then produce a non-technical development plan for the first playable vertical slice. The plan should:

1. Identify the smallest experience that proves the game’s core promise: a mayor governs a populated town through an understandable civic problem.
2. Select a small set of systems that make that experience possible, rather than attempting the entire catalogue.
3. State what the player can observe, decide, and see change during a short play session.
4. Explain the proposed player-facing relationship between people, streets, employment, services, money, and public opinion.
5. List explicit exclusions for the first slice so scope remains controlled.
6. Name the next feature specifications that should be written before any detailed technical design begins.

Do not write implementation architecture, select an engine, prescribe code structure, or begin development until that plan has been reviewed. The immediate task is to establish an intentional, testable first gameplay slice—not to solve the full city simulation at once.
