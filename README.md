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

- Wears the gear with the most slime resistance, then HP (`set autoslime_maximize = ...` to change it).
- Engulfed!: tickles the uvula (once a player per instance), never squeezes the gall bladder (that raises the
  tube's ML for everyone).
- After your own tickle, wears one rusty item in the tube so it comes out slime-covered. It picks the first of
  rusty compass, rusty metal greaves, rusty diving helmet, rusty old lantern and rusty chain necklace that you
  have, can wear both before and after, and don't already own slimed. It never wears rusty gear before your own
  tickle: using someone else's is bad manners.
- Never fights Mother Slime. When she's up it says so once in /slimetube and stops.

## Clan rules it keeps (Not Dead Yet)

- Full Member rank; be in chat on /slimetube and /clan.
- Boss loot goes to anyone who hasn't had any in the past 2 instances; the dungeon masters hand it out.
