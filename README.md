# autoslime

A KoLmafia script that spends your turns in your clan's Slime Tube the way a good clanmate would.

## Usage

```
autoslime           fight in the tube until the next slime hit would be too much
autoslime 10        the same, at most 10 turns
autoslime status    show the tube, your tickle, the debuff and your slime gear, without adventuring
```

Install with `git checkout https://github.com/grimwiz/autoslime.git`.

## Coated in Slime

The tube's debuff hits you at the start of **every** fight while you have it, in the tube or anywhere else, for a
share of your maximum HP that grows as its turns run down. Slime resistance takes 10% off per point (to 30%,
then less per point):

| turns left | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 |
|---|---|---|---|---|---|---|---|---|---|---|
| hit, % of max HP | 1 | 7 | 20 | 44 | 81 | 132 | 202 | 290 | 400 | 533 |

So healing between fights can't help once it's past about 6 turns left. It can't be shrugged off either, but a
chamois from The Bucket by the tube wipes it off (`clan_slimetube.php?action=chamois`).

Before every fight autoslime works out the next hit and, if it would take more than 80% of your max HP
(`set autoslime_hitShare = 0.8`), wipes the slime off first. The next tube fight starts it again from the top. At
the end of a run it wipes it off once more, so it doesn't follow you into other fights
(`set autoslime_wipeAtEnd = false` to keep it). The bucket is shared, so autoslime never takes the last 200
(`set autoslime_bucketReserve = 200`); on 2026-10-30 it went from 1,717 to 1,721 across 5 slime kills and 1 wipe,
so kills seem to put chamois back.

The table is from twistedmage's relay_slime.ash and matches the hits seen on 2026-10-30.

## What it does

- Wears the gear with the most slime resistance, then +ML up to +200 (`set autoslime_maxML = 200`): each kill counts
  its monster level against the tube's total and gives more stats, and the slimes still die in a hit or two: it also
  weighs damage (weapon damage and an effective weapon for your class, or spell damage for Mysticality classes), so
  +ML gear like rave whistles doesn't replace your weapon. It
  stops if the slimes could hit for more than about a sixth of your HP a round. Max HP hardly matters, since the
  slime hits are a share of it. (`set autoslime_maximize = ...` replaces the whole maximizer string.)
- Casts your +ML buff skills (Ur-Kel's Aria of Annoyance and the like, whatever the maximizer finds) up to the same
  cap. Songs only while a song slot stays free for The Ode to Booze.
- Keeps Grimace and Bilious up (+1 slime resistance, +25 ML, 20 turns each) with one slimy sweetbreads and one slimy
  fermented bile bladder when they run out, if you have 15+ adventures left (`set autoslime_buffMinAdventures = 15`).
  It drinks under The Ode to Booze when a song slot is free, and never stops to ask about Ode or Milk of Magnesium.
  They're mediocre food (2-3 adventures), so it never eats them to fill up: when you're out of adventures it says
  how much stomach, liver and spleen is left for better food and drink.
- Engulfed!: tickles the uvula (once a player per instance), never squeezes the gall bladder (that raises the
  tube's ML for everyone).
- Converts a rusty item to its slime-covered version. A tickle lets one rusty item be converted, by whoever in the
  clan wears one first, so the etiquette is to use only your own tickle, and autoslime wears nothing rusty before
  it. The conversion happens in a fight: a slime "blasts you with a massive loogie that sticks to your <item>,
  pulls it off of you", and defeating that slime gives the slime-covered item (losing or running away loses the
  item). Each slime attack has a chance of it, so after your tickle autoslime wears the rusty item and uses a seal
  tooth (1 damage, not used up) on each slime until one takes it, up to 15 rounds a fight, then lets your usual
  combat kill it. If no slime takes it in 5 fights (someone else may have used the tickle) it fights on without it
  (`autoslime_convertRounds`, `autoslime_convertFights`). It picks the first of rusty compass, rusty metal greaves,
  rusty diving helmet, rusty old lantern and rusty chain necklace that you have and can wear, and don't already own
  slimed (whether you can wear the slimed one yet doesn't matter: it keeps). Earlier versions got this wrong: on
  2026-10-30 every slime died before it attacked, and on 2026-11-16 the item came off right after the tickle.
- Never fights Mother Slime. When she's up it says so once in /slimetube and stops.

## Clan rules it keeps (Not Dead Yet)

- Full Member rank; be in chat on /slimetube and /clan.
- Boss loot goes to anyone who hasn't had any in the past 2 instances; the dungeon masters hand it out.
