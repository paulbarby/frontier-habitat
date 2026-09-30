extends RefCounted
## Version 5 help text (STE), one source for the How to play "People" tab and the Codex "People" tab.
## [id, title, icon, codex category, text]. Keep each sentence short: one instruction or one fact.

const TOPICS := [
	["follow", "Over the shoulder", "follow", "Society",
		"Select a person and press V. The camera goes behind them. Mouse wheel: zoom. Right drag: turn the camera. Q and E: the other shoulder. Tab: the next person. Esc or V: back to the colony. The card at the top left shows their mood, needs, what they do and what they said. The rest of the interface goes dim."],
	["bubbles", "Speech bubbles", "people", "Society",
		"People talk at meals, at work and in leisure places. A bubble shows the name and the line. What they say comes from their mood, their friends and what happened today. In the follow view you see the bubbles of the people near you. The personnel file keeps the last lines."],
	["rag", "The Regolith Rag", "newspaper", "Society",
		"The colony tabloid (key J). A new issue comes out each morning. It prints gossip about couples, feuds and scandals from what really happened. Click a name: the camera goes to that person and their file opens. The Serious news strip at the foot lists the real problems. The header lists the back issues."],
	["file", "Personnel file", "colonists", "People",
		"One person (the File button, or the Follow card). File: rank, role, home, traits, skills, satisfaction and attitude with their reasons. Social: friends, partner, rivals and enemies. A secret crush does not show. Review: write a review, or reward or punish the person. History (File tab): the effects on the person now, with the time left, and what happened to them, newest first."],
	["discipline", "Reviews and discipline", "orders", "People",
		"Rewards (praise, bonus leisure, a gift) raise satisfaction; rivals feel small envy. Punishments (warning, extra shift, ration cut, confinement, demotion, jail) improve attitude now and lower satisfaction. Friends see every punishment. When the person did nothing wrong, the punishment is unfair: fairness falls and unrest rises. Every order shows its effect on the person and on others first. Then you confirm."],
	["unrest", "Unrest", "people", "Society",
		"Unrest is 0 to 100 for each base. It comes from low satisfaction, bad attitudes, punishments, homes below the rank, deaths and ration cuts. Grumbling from 25. Slowdown from 40: work is 15 % slower. Protest from 55. Strike from 70: a department stops work. Riot from 85: fights, damage and break-ins. The top bar shows the stage; a banner shows from Protest up."],
	["responses", "Answering unrest", "sev_warning", "Society",
		"The banner has 7 answers. Each shows its effect. Meet the demand, a leisure day or a party lower unrest; they cost stock or a day of work. Amnesty frees prisoners. Replace the captain of the angry department. Arrest the ringleaders: unrest falls only when people think it is fair. Lock down: a riot cannot spread, but unrest rises. An answer used recently must wait."],
	["love", "Couples and break-ups", "heart", "Society",
		"People who talk often become friends, or rivals and enemies. Two people who like each other start dating. After some days they become partners, and partners can marry. A wedding makes the whole colony happier for a day. A couple that stops getting on breaks up: both are unhappy for 2 days. An affair can come out; then the cheated partner breaks up. A colonist can fall for a visitor (a fling). A toast tells you each of these moments. The Rag prints them."],
	["requests", "Requests from people", "heart", "Society",
		"A colonist in love with a visitor can ask to leave the colony on the visitor's ship. A card at the top of the screen asks you. Let them go: they leave for good, with their skills. You confirm first. Refuse: they stay, but their satisfaction and attitude fall for 3 days. File opens their personnel file. Show moves the camera to them. The card stays until you answer."],
	["families", "Families and children", "home", "People",
		"Partners move in together when a unit has room. When no unit is free, a card asks you: Try again after you build a home, or Keep them apart (both are unhappy for 3 days). Partners and married couples can adopt a child: open the personnel file, Social tab, Adopt a child. It needs a medical bay and a free bunk in their home. A child goes to school at the academy, plays in parks and never works. A child grows up after some days and takes the job of their best school subject."],
	["venues", "Venues, goods and tourists", "cat_civic", "Structures",
		"A retail shop, a park and the super dome hold venues: shops, a bar, a cafe, a gym, the club and more. Select the structure and open the Venues tab. A venue is open when it has power, its staff are at work and, for a shop, goods in stock. Carriers bring the goods (luxury goods, clothing, snacks, drinks, gadgets, gifts) from storage. Colonists use venues for free; a good venue raises their satisfaction. Tourists pay credits for each visit. The super dome is built in 9 stages; the badge in the inspector shows the stage."],
	["ranks", "Ranks and departments", "people", "People",
		"Each base has a Base Commander. Each department (Industry, Science, Food, Maintenance, Security) has a Captain and up to 2 First Hands. The others are Specialists, Crew or Trainees by skill. Leaders make their department faster. Open the Crew window (key U) and drag a person onto a rank. A star marks the simulation's choice. A rank expects a home: the commander and the captains an executive unit."],
	["skills", "Skills", "research", "People",
		"11 skills, 0 to 100, shown as levels 1 to 5: Novice, Trained, Skilled, Expert, Master. A Novice works at x0.7, a Master at x1.4, with fewer mistakes. Skills grow with work and at the academy. A skill not used for a long time falls a little."],
	["academy", "The academy", "research", "People",
		"A course teaches one skill one level up. The student leaves work for the lessons. A teacher needs 60 or more in that skill. Without a teacher, the instructor console teaches up to level 3. Enrol a person in the Crew window, Academy tab. The table there shows every level of the crew."],
	["housing", "Homes", "home", "People",
		"Home quality: dorm 1, family unit 2, executive unit 3, penthouse 4. A person whose home is below what their rank expects is less satisfied. Partners share a unit; a family needs a family unit. The Crew window, Housing tab, shows every home and who waits for a better one. Drag a person onto a unit to move them."],
	["giants", "New structures", "cat_civic", "Structures",
		"Residence tube (M to XL): family or executive units. Apartment block (size XXL): 3 floors, a lift, 10 family units and 2 penthouses. Retail shop and park: leisure places. Academy: courses. Security office: officers patrol and stop fights. Jail: 2, 4 or 8 cells. Super dome (size XXXXL): 5 floors, 16 leisure places, 30 homes, built in 9 stages. XXL and XXXXL are one giant size each. The Civic tab of the build bar has security, jail and the super dome."],
	["floors", "Floor selector", "overlay", "Structures",
		"Select a structure with more than one floor. A strip on the right shows one button for each floor and All. A floor button cuts the building away above that floor, so you see inside. All shows the whole building. PgUp and PgDn step one floor."],
]

## Topic by id ({} when unknown).
static func topic(id: String) -> Array:
	for t in TOPICS:
		if String(t[0]) == id:
			return t
	return []
