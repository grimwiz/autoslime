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

The tube's debuff hits you at the start of **every** fight while you have it, in the tube or anywhere else,
and the hit grows each turn. Two runs with the same character:

| fight after the first | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| no slime resistance | 61 | 184 | 402 | 738 (beaten up) | | |
| +1 slime resistance | 12 | 85 | 254 | 557 | 824 | 1,354 |

It can't be shrugged off. It wears off as its turns run out, so spend those turns without fighting
(resting, noncombats), or soak in a Clan VIP Lounge hot tub if you have one.

autoslime reads the hits so far from your session log, guesses the next one from how they've been growing, and
stops before the next could take more than 80% of your maximum HP (`set autoslime_hitShare = 0.8`).

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
