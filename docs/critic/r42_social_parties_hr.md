# Critic round 42 — social: the Rag, social UI, parties, HR

Date: 2026-10-04 · Critic · Rubric `docs/critic/v5_rubrics.md` §3.5, §3.6 · V5_DESIGN §16, §17 · Pass ≥ 0.65.

**Build.** `build/web_v5play3` (e9b1d35, pck 186.2 MB). Save `showcase_v5.fhsave` (134 people, dome, HR, party offers).
**Shots.** `art/critic/r42/social/` (steps files `stepsA..H.json`), 1600×900 and 1280×720, scale 80/100/125 %.
Parties were thrown through SIM's own `answer_request` (debug `simcmd`), at the dome, lounge and cantina.
**Probes (headless, read-only).** `r42_talk_probe.gd` (2 game days of talk lines, cheeky on and off),
`r42_hr_probe.gd` (6 game days in the HR office), `r42_rag_death_probe.gd` (SIM's Rag code on a death lead).

## Scores

| subject | cons. | appeal | style | score | result |
|---|---|---|---|---|---|
| regolith_rag | 0.66 | 0.62 | 0.68 | **0.65** | PASS (narrow) |
| social_ui (+ parties, HR) | 0.64 | 0.63 | 0.70 | **0.66** | PASS (narrow) |

Tone hard checks: **PASS.** No explicit line. No child in a romance, fight or scandal (113 log entries, 6,861
talk lines). Innuendo only between compatible adults (0 faults). Cheeky off: 0 innuendo lines.

## What works

- **The Rag page.** Every §4.3 part is there: red masthead, issue, day, price, kicker, condensed headlines,
  INSIDE TODAY with page numbers, QUOTE OF THE DAY from a real line, THE DUST-UP column, Couple Watch,
  Feud Watch, poll with trend, small ads from stock, Serious news in STE (`c16`, `c17`, `c18`, `g02`).
- **The loop works.** Offer → party → drama → News tab → next dawn the Rag leads with the party fight
  ("SCENE AT THE SUPER DOME 1! OTTO AGUIRRE AND RAGNAR DEMIR IN PUBLIC", `c16`).
- **Content.** 273 headlines with good puns ("HEARTS PRESSURISED!", "HERE COMES THE BRIDE (IN A PRESSURE
  SUIT)"). 140 innuendo and 87 flirt lines, 45 praise and 64 gossip lines: original and funny.
- **Party and AI satire.** "Who is DJ? Is it the AI? It has played the same song four times." (`f14`).
  "The punch is a mystery. I recommend it." (`e07`). "Keep talking like that and the AI will flag us for
  wellbeing." (probe).
- **Crew window.** The org chart reads as a command board (`a16`). Housing flags entitlements (`a17`). Academy
  has a coloured skill matrix (`a18`). Security shows the lockdown cost and prisoner time (`a19`).
- **HR tab.** Public and private values, complaints with predicted effects, transfer Approve/Refuse, survey
  table with top complaints (`a20`, `c19`, `h04`). In the SIM: 12 complaints and 1 survey in 6 days, and the
  officer is at the desk in 34 % of samples.
- **Discipline confirm.** It shows the effect on the person, names the others, the risk and UNFAIR (`a25`).
- **Requests and panels.** The party offer has the venue, hours, effects and deadline (`b02`). The party card
  has a timer, fun, drama lines, Show and Follow a guest (`c10`, `c13`). Unrest is amber for protest and red for
  riot; the tooltip lists causes with numbers (`b06`, `g03`). The centre stays clear.
- **`fx_photo` works when called.** Its photos have the right outfits (prison orange with security). The hug
  reads and the portrait is good (`b01`).

## Faults (most important first)

| # | sev | owner | fault | evidence | fix |
|---|---|---|---|---|---|
| 1 | major | RENDER | Rag photos and file portraits are grey placeholders in game. `world_view.gd` has no `photo()`, so `ui/v5_data.gd photo()` returns null. | `a08`, `c16`, `h02`, `a21`; works by debug in `b01` | Add `func photo(a, place, pose): return photos.photo(a, place, pose)` to `world_view.gd`; redraw the widget when the image is ready. |
| 2 | major | SIM | HR gossip names the **listener**, not the officer: `social.gd:371` puts the other person's name in `{officer}`. 563 of 563 gossip lines; the officer speaks 12 of 22 praise lines. §17.6 does not work. | probe; `f12` "I heard Nadia read the whole handbook" said to Nadia; `e10` | Gossip: `{officer}` = `sim.hr.officer_name(a)`. Praise: only the non-officer speaks it. Add a test that the line holds the officer's name. |
| 3 | major | SIM | Party guests wear work uniforms (§1: social events = casual). `outfit()` has no `party` kind. | `f14`, `e07`, `e10`, `d10_crop` | Add `"party"` to the casual kinds in `people.gd outfit()` (line 782). |
| 4 | major | SIM | The guest of honour can miss the party: Eun works at the gym during her own birthday party. | `f10`, `f15` | Take the honoured person off staff work; start "on" only when the honoured person and half the guests are present. |
| 5 | major | UI | The personnel file truncates its key text at the right-quarter width (327 px; 250 px at 720p). Values are cut, the "Needs improvement" button is blank and the discipline effects are cut. | `a21`, `a22`, `a24`, `h05`, `h06` | Put each label above its value, wrap button labels and put the effect line under each button, or allow 440 px. |
| 6 | major | SIM | The Rag lead fillers break the tone on a death: "COLONY MOURNS ASHA VERRIN … The gossips in the lounge are delighted." (2 of 8 salts) | death probe | One filler pool per kind; death and hazard get sombre or no fillers; add a test. |
| 7 | major | RENDER | A party does not read in 3D: no lights, decoration or cake, and guests stand apart along the walls. The dome party atrium is near empty. SIM: only 8 of 30 are present at the end. | `d10_crop`, `e12`, `c11_crop`, `c14` | Venue dressing while "on" (party light colour, shared-kit bunting, cake table); 2–3 talk circles and a dance spot. SIM: gather time by path length. |
| 8 | minor | SIM | Rag stories do not match the log: "BIRTHDAY BASH: 11 GUESTS" with no party (`{n}` = alive/10); a storm lead with "the pair" and a 2-person photo; 3 birthday stories with one body. | `g02`, `h02`, slog | A no-party birthday kind, real guest count, fillers by actor count, no repeated bodies, a place photo when nobody is named. |
| 9 | minor | UI | The party card always shows "Attendance 0": a 0..1 fraction shown with `int()`. | `c10`, `c13`, `e12`, `f15` | Show "present / invited". |
| 10 | minor | UI | Security tab officer chips are empty cyan dots with no names. | `a19` | Show name and rank as the org chart does. |
| 11 | minor | UI | The urgent line ranks a riot below an HR complaint. | `b06` | Riot first. |
| 12 | minor | UI | Dock card text runs into the left accent bar. | `b06`, `b02` | Fix the content margin. |
| 13 | minor | SIM | 80 of 120 first names have no sex entry, so Otto and Ragnar render as women. | `b01`; `people.json name_sex` = 40 | Complete `name_sex`. |
| 14 | minor | SIM | Private HR reputation hits −100 in 6 days and stays. 10 of 12 complaints repeat two feuds. | HR probe | Decay to the start value; a cooldown per pair. |
| 15 | minor | SIM | Visitors flirt with work lines and are called "Tourist". An offer with no person reads "SOMEONE / the colony set a record". | talk probe, `b02` | Visitor names and pool; capitalise and title the offer. |
| 16 | minor | RENDER | The kiss_brief photo shows the pair 0.84 m apart, holding hands; faces do not meet. Bubbles are cut by the right rail and the follow card. | `b01`, `e07`, `e10` | The pair distance from `npc_pairs.json`; clamp bubbles inside the free view. |

## Not seen

- An innuendo bubble in game (seen in the probe only); the org chart drag; an interview or queue in the HR office.
- A real riot (staged view only); the follow camera often faces a wall (`b07`, `b10`, `f10`; RENDER, round 41).

## To 0.80

The Rag: real photos (fix 1), stories true to the log, AI-boom small ads. Social UI: a readable personnel
file, parties that look like parties, HR gossip about the right person.
