# Modern City Management Game Scope Specification

## Purpose

This document defines the gameplay scope for a modern-era city-management simulation inspired by the systemic depth and visible population of *Songs of Syx*. The player is the elected mayor of an already-established small or medium fictional town. Their job is not to build a settlement from nothing, but to govern a living place that grows into a more complex city.

The game should retain the feeling that individual people matter, while moving its subject matter from a feudal settlement to contemporary civic life: homes, employment, streets, public services, institutions, politics, infrastructure, commerce, and public opinion.

This is a scope document. It establishes player-facing systems, their intended relationships, and the topics that will later receive separate feature specifications. It intentionally does not prescribe software architecture, data structures, AI techniques, or other technical implementation choices.

## Design principles

1. **A city of people, not counters.** Every resident has a home, household, life stage, work or education situation, routines, needs, affiliations, and opinions. The player can inspect detail without needing to manually direct every person.
2. **Interconnected civic consequences.** A decision about transport, policing, tax, zoning, education, media, or business should create understandable effects elsewhere in the city.
3. **Legible complexity.** The city may be overwhelming, but it must not feel arbitrary. The player should be able to inspect why a situation exists and identify plausible responses.
4. **Imperfect institutions.** Public and private institutions have incentives, limitations, bias, error, delay, and sometimes corruption. The simulation is not designed to protect the mayor from difficult consequences.
5. **Multiple scales of play.** The player can view the city as an individual, household, street, block, neighbourhood, district, municipality, and regional economy.
6. **Fictional setting with real social logic.** Religions, organisations, parties, newspapers, companies, and locations are fictional. Their social roles can resemble real-world institutions without directly reproducing real people, faiths, or current events.

## Game premise and starting state

Each new game begins from a seed and an initial configuration. It generates a functioning small or medium town rather than an empty map. The starting town includes:

- A defined population with households, homes, jobs, education, relationships, and local affiliations.
- A basic street network, pedestrian paths, traffic patterns, public lighting, water and waste infrastructure, municipal buildings, shops, and service coverage.
- A local economy with businesses, workplaces, income flows, trade relationships, land or property values, and a municipal budget.
- Existing neighbourhood identities, civic groups, religious centres, media organisations, local issues, and an initial political climate.
- At least some unresolved pressures: congestion, uneven services, crime, fiscal strain, housing tension, a business decline, a contentious development, or similar problems.

Starting settings define the town size, economic profile, terrain and regional connections, social diversity, initial prosperity, political difficulty, and the severity of systemic problems. They set the tone of a campaign without determining its outcome.

## Time and campaign cadence

The simulation advances in days. A day takes eight real-time minutes by default, with player-selectable slower and faster settings. This cadence gives daily routines, transport, service delivery, crime, local news, and short-term disruptions room to be observed and managed.

Weeks, months, seasons, fiscal years, school terms, business cycles, and election cycles provide longer planning horizons. Elections occur at a fixed multi-year interval defined by the campaign setting. The mayor must balance immediate emergencies against reforms whose benefits or costs emerge later.

## Core gameplay loop

1. **Observe.** Read city dashboards, neighbourhood reports, local news, alerts, maps, and individual or group stories to understand current pressures.
2. **Diagnose.** Trace a visible problem through the relevant layers. For example, street disorder may connect to unemployment, housing instability, addiction, insufficient treatment, a corrupt unit, reporting choices, and neighbourhood distrust.
3. **Set policy and priorities.** Allocate budget, adjust tax and incentive policy, direct city departments, approve or deny developments, regulate services, and communicate public priorities.
4. **Build and maintain.** Expand, repair, redesign, or regulate streets, utilities, facilities, institutions, and civic spaces.
5. **Respond to consequences.** Residents, households, businesses, neighbourhood groups, media, courts, departments, and outside traders adapt over time.
6. **Build political legitimacy.** Explain choices, negotiate with institutions, manage trust, and pursue reelection while protecting the long-term health of the city.

There is no single “win” condition implied by city size. A successful city is one that remains governable, financially viable, safe enough, opportunity-rich, and politically legitimate as its systems become more complicated. Campaign settings may add particular objectives or failure thresholds.

## Core city metrics

These are the principal lenses that guide play. They should be shown at city, district, neighbourhood, household, and where useful individual levels. Metrics are not a single score; conflict between them is expected.

| Metric family | What it represents | Typical decisions that affect it |
| --- | --- | --- |
| Resident wellbeing | Health, housing quality, access to essentials, safety, time burden, social belonging, and personal outlook | Services, transport, housing policy, public spaces, benefits, policing |
| Trust and legitimacy | Confidence in the mayor, city government, police, courts, media, and local institutions | Fairness, transparency, outcomes, communication, scandal response |
| Economic vitality | Jobs, incomes, business survival, investment, productivity, trade, and household purchasing power | Incentives, taxes, zoning or permits, infrastructure, education, trade policy |
| Municipal finances | Recurring revenues, operating costs, debt, reserves, capital commitments, and fiscal resilience | Tax policy, fees, spending, borrowing, development approval |
| Housing stability | Affordability, occupancy, displacement risk, homelessness, ownership and rental security | Development, taxes, tenant or owner policy, public services |
| Mobility and access | Travel time, congestion, safety, walkability, public-transport access, and freight movement | Streets, signals, crossings, parking, service placement |
| Public safety and justice | Crime, victimisation, clearance, emergency response, due process, repeat offending, and institutional integrity | Police priorities, investigation, prevention, courts, treatment, oversight |
| Health and care | Illness burden, care access, response time, capacity, prevention, addiction support, and health inequality | Clinics, hospitals, public health, sanitation, social care |
| Education and opportunity | School access, attainment, skills, career paths, and social mobility | Schools, grants, job incentives, youth services, adult learning |
| Social cohesion | Neighbourhood connection, group conflict, discrimination, participation, and collective problem-solving | Community facilities, representation, public communication, fair service coverage |
| City resilience | Ability to withstand infrastructure failures, economic shocks, emergencies, and institutional crises | Maintenance, reserves, redundancy, emergency planning, diversified economy |

## Population and social simulation

The population model is the central analogue to *Songs of Syx*. Residents are visible subjects of the city rather than anonymous labour units.

Each resident belongs to a household and occupies a life situation that can change: child, student, worker, jobseeker, caregiver, retiree, business owner, public employee, or other civic role. They have a home location, daily destinations, social ties, needs, personal circumstances, and opinions. Their choices are constrained by income, housing, education, health, transport, family obligations, availability of services, and local conditions.

Households pool or share constraints. A household can prosper, become unstable, move, form, split, or fall into crisis. The player normally acts through policy and city systems, not direct personal control, but can inspect representative cases to understand statistical outcomes.

Population growth and change include births, deaths, ageing, arrivals, departures, household formation, and movement between neighbourhoods. The city’s demographics affect demand for homes, schools, jobs, care, mobility, and political priorities.

## Scope modules for later feature specifications

Each heading below is a separate future Markdown specification. The order is a suggested dependency order, not a required production plan.

### 01 City seed and initial conditions

Defines generated starting towns, scenario settings, regional context, initial population composition, infrastructure baseline, economic profile, and starting tensions. It replaces the empty-settlement opening of *Songs of Syx* with a playable civic starting point.

### 02 Simulation time and civic calendar

Defines daily routines and longer cycles: workdays, weekends, school terms, fiscal periods, seasons, election years, business cycles, and how events unfold across them.

### 03 Residents households and life paths

Defines individual residents, households, family and social connections, age and life transitions, living circumstances, daily routines, and population change.

### 04 Neighbourhoods districts and local identity

Defines how streets and nearby households form recognisable places with conditions, character, local priorities, representative groups, and unequal outcomes.

### 05 Housing property and homeowner associations

Defines housing types, renting and ownership, affordability, property condition, landlords, displacement, housing insecurity, property values, homeowner associations, and their influence on local policy.

### 06 Streets traffic pedestrians and signals

Defines roads, street hierarchy, intersections, congestion, pedestrian movement, crossings, parking, freight, traffic signals, street safety, maintenance, and accessibility. Transport decisions should affect daily time, trade, service reach, housing desirability, and public opinion.

### 07 Utilities public realm and infrastructure maintenance

Defines water supply, drainage and waste, electricity or lighting, street furniture, public spaces, underground works, maintenance backlogs, upgrades, failures, and disruption caused by construction.

### 08 Municipal budget taxation and incentives

Defines the city budget, revenue sources, operating commitments, debt and reserves, property or business taxes, fees, tax relief, targeted incentives, and distributional consequences. Tax policy should create incentives as well as revenue.

### 09 Employment businesses and job creation

Defines local employers and job categories across factories, offices, retail, trades, logistics, public services, finance, health, education, and cultural work. It includes job quality, skill requirements, vacancies, hiring, job loss, business incentives, and the benefits and costs of industrial or commercial expansion.

### 10 Markets retail banking and trade

Defines markets, shops, service businesses, commercial districts, banks, financial access, trade centres, import and export flows, supply disruptions, business confidence, and household purchasing power.

### 11 Education skills and youth opportunity

Defines schools, education capacity and quality, access, school catchments, student outcomes, vocational routes, adult learning, youth services, and the relationship between education and employment.

### 12 Health healthcare and social care

Defines hospitals, clinics, ambulances, preventive health, care capacity, public-health issues, disability support, mental health, addiction treatment, and the interaction between health, housing, work, crime, and family life.

### 13 Civic culture fictional religions and public gathering

Defines fictional faith traditions and their centres, community halls, cultural institutions, festivals, charitable roles, neighbourhood belonging, and conflicts over land use or public influence. The design should use original names, practices, and aesthetics rather than direct real-world representations.

### 14 Law crime policing and investigation

Defines crime types, victim impact, visible street disorder, organised activity, reporting, police deployment, investigation, prevention, emergency response, trust, and the trade-offs between enforcement and community legitimacy. Drug-related street crime is an example problem class: it may require policing, investigation, treatment, housing support, youth opportunity, and community trust rather than a single response.

### 15 Justice courts punishment and institutional integrity

Defines courts, prosecutors or equivalent offices, judges, legal process, evidence, sentencing, rehabilitation, detention, oversight, and due process. Institutions can have leniency or severity tendencies, conflicts of interest, backlogs, and corruption risks. These factors must be inspectable and manageable, not hidden random punishment.

### 16 Corruption accountability and oversight

Defines corruption, patronage, misuse of city resources, conflicts of interest, whistleblowing, audits, independent oversight, investigations, scandal, reform, and the trade-offs of policing institutions that police themselves.

### 17 Newspapers media and public opinion

Defines newspapers and other fictional local media as active institutions with audiences, editorial direction, commercial pressures, access to sources, and indirect interests. Media can influence what residents believe about the mayor and city problems, but must not function as an unexplained popularity switch. The player can communicate, disclose information, build credibility, and face hostile or compromised coverage.

### 18 Civic groups lobbying and neighbourhood participation

Defines homeowner associations, tenant groups, business associations, labour organisations, advocacy groups, neighbourhood committees, petitions, protests, consultations, and local alliances. These groups give residents collective power and create support or resistance to mayoral action.

### 19 Elections parties and mayoral legitimacy

Defines election timing, candidates or opponents, political constituencies, campaign issues, approval, turnout, promises, endorsements, scandals, mandate, and defeat. The player is accountable to voters but should not be rewarded only for short-term popularity.

### 20 Emergency events shocks and city resilience

Defines infrastructure failures, public-health incidents, economic contraction, transport disruption, weather or environmental events, institutional scandals, and other crises. Events reveal existing weaknesses and create new choices; they should not be arbitrary unavoidable losses.

### 21 Mayor tools information and intervention

Defines the player’s authority: budgets, policies, appointments, department priorities, capital projects, permits, incentives, public messages, investigations, emergency actions, and the limits placed on mayoral power. It also defines dashboards, maps, reports, alerts, comparison views, and drill-downs needed to make complexity legible.

## Intended system relationships

The city should create chains of consequence without assuming a single correct solution. A few illustrative relationships follow:

- New factory incentives can create jobs and tax revenue, while adding freight traffic, environmental burden, land-value pressure, and political conflict.
- Better street design can reduce travel time and injuries, improve pedestrian access to shops and schools, and change which neighbourhoods become desirable or expensive.
- Raising property taxes can finance services but strain households and small businesses; targeted relief may protect some groups while reducing fiscal capacity or attracting criticism.
- An enforcement-focused response to a crime hotspot can improve visible order, but unchecked misconduct or corruption can reduce reporting and legitimacy, impairing investigations over time.
- A credible newspaper investigation can reveal genuine wrongdoing, lower short-term approval, and ultimately strengthen trust if the mayor responds transparently; a captured newspaper may conceal or distort different interests.
- School investment may be expensive before it improves employment, while weak education can amplify unemployment, poverty, crime vulnerability, and dissatisfaction later.

## Boundaries for this phase

The initial scope focuses on one municipality and its surrounding trade or regional context. It does not yet require national politics, international diplomacy, military conflict, direct conquest, or a full grand-strategy layer. Those are possible later extensions, but the core game is the escalating complexity of governing one city well.

Likewise, the scope does not require a perfect simulation of every real-world issue. The aim is a coherent, inspectable civic simulation where serious problems have causes, stakeholders, and trade-offs—not a claim of complete realism.

## Relationship to Songs of Syx

The intended inheritance from *Songs of Syx* is systemic, not thematic: visible inhabitants, population needs, work and logistics, an economy tied to growth, institutions that constrain expansion, and a city that becomes harder to govern as it succeeds.

The modern-city analogue changes the governing questions. Instead of managing a feudal settlement’s production and expansion into an empire, the mayor manages mobility, infrastructure, service quality, social trust, employment, law, public opinion, and electoral legitimacy within a dense civic system.
