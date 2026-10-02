// Adds the story kinds of V5_DESIGN sections 16 and 17 to content/tabloid.json (run once; safe to run again).
//   node tools/content_src/tabloid_add.js
const fs = require("fs");
const path = require("path");
const file = path.resolve(__dirname, "..", "..", "content", "tabloid.json");
const t = JSON.parse(fs.readFileSync(file, "utf8"));
const add = {
  party_birthday: {
    h: ["HAPPY BIRTHDAY, {a}! THE {place} ROCKS", "CAKE, CANDLES AND CHAOS FOR {a}", "{a} BLOWS OUT THE CANDLES", "BIRTHDAY BASH: {n} GUESTS FOR {a}", "ONE YEAR OLDER, NO WISER: {a}"],
    b: ["The colony threw {a} a birthday party in the {place}.", "{a} turned a year older and the {place} was full of people with cake.", "Friends of {a} sang. Not well. With feeling."]
  },
  party_drama: {
    h: ["OOPS! PARTY MISHAP AT THE {place}", "{a} IS THE TALK OF THE {place}", "DRINKS, DANCES AND DISASTERS", "AWKWARD! {a} AND {b} AT THE PARTY", "PARTY FOUL IN THE {place}"],
    b: ["Something small went wrong at the party in the {place}. Everybody saw it.", "{a} had a moment at the party. {b} was there for it.", "Nobody was hurt. Several were embarrassed."]
  },
  party_scene: {
    h: ["SCENE AT THE {place}! {a} AND {b} IN PUBLIC", "PARTY DRAMA: {a} AND {b} CAUSE A STIR", "THE PARTY STOPPED WHEN {a} SPOKE", "BIG NIGHT, BIGGER SCENE AT THE {place}", "THE {place} WILL NOT FORGET THIS NIGHT"],
    b: ["A party in the {place} ended in a scene between {a} and {b}. The whole colony has heard.", "{a} and {b} gave the party something to talk about.", "Witnesses say the music stopped. Then the music started again, a little softer."]
  },
  awkward: {
    h: ["{a} SHOOTS, MISSES: {b} NOT AMUSED", "A MOVE ON {b} FALLS FLAT", "WRONG NUMBER: {a} TRIES {b}", "OOF. {a} AND {b} IN THE {place}"],
    b: ["{a} tried a line on {b}. {b} found something to look at on the wall.", "It did not land. Both are pretending it did not happen."]
  },
  hr: {
    h: ["HR SAYS: BREATHE", "THE HR OFFICE HEARD YOU", "STAFF SURVEY: WHO IS UNHAPPY?", "COMPLAINT BOX FULL ON {base}", "HR: YOUR FEELINGS ARE VALID (PENDING REVIEW)"],
    b: ["The HR office on {base} heard another complaint.", "HR ran a staff survey. The results are less cheerful than the poster.", "The wellbeing kiosk told somebody to breathe."]
  },
  hr_transfer: {
    h: ["{a} LEAVES {base} ON A TRANSFER", "GOODBYE, {a}: OFF WORLD AT LAST", "{a} GETS THE TRANSFER", "ONE LESS ON {base}: {a} IS GOING HOME"],
    b: ["{a} asked HR for a transfer and got it. The next ship takes {a} away.", "Friends of {a} came to wave. Some of them were crying. Some of them were jealous."]
  }
};
for (const k of Object.keys(add)) {
  t.headlines[k] = add[k].h;
  t.bodies[k] = add[k].b;
}
const hrg = [
  "Which colleague has the gentlest voice and the longest folder? Rhymes with 'age'.",
  "The kiosk in the HR office has now asked 400 people to breathe. Three did.",
  "Somebody put a padlock on the suggestion box. Somebody else put a note in it: 'Thank you.'",
  "A certain HR officer is loved by all. A certain HR officer is also gossiped about by all. Same people."
];
for (const l of hrg) if (!t.columns.gossip.includes(l)) t.columns.gossip.push(l);
const pg = [
  "Who danced on the table at the last party? Not us. The photos will tell.",
  "Somebody left the party with somebody else's jacket. Return it. Discreetly."
];
for (const l of pg) if (!t.columns.gossip.includes(l)) t.columns.gossip.push(l);
fs.writeFileSync(file, JSON.stringify(t, null, 2) + "\n");
console.log("tabloid kinds:", Object.keys(t.headlines).length);
