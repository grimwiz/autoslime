script "autoslime.ash";
since r29000;

// autoslime: spends turns in your clan's Slime Tube the way a good clanmate would.
//   1. Coated in Slime: the tube's debuff hits you at the start of every fight, in the tube or anywhere else, and
//      the hit grows each turn (about 61, 184, 402, 738 with no slime resistance). autoslime reads the hits so
//      far from your session log, guesses the next one, and stops before it could beat you up. Shrugging can't
//      remove the debuff; it wears off over turns spent without fighting (or in a Clan VIP Lounge hot tub).
//   2. Slime resistance: wears the gear with the most of it (and the HP to take the hits) for each fight.
//   3. Engulfed!: tickles the uvula (once a player per instance; it lets one rusty item become slime-covered)
//      and never squeezes the gall bladder (that raises the tube's ML for everyone). After your own tickle it
//      wears one rusty item into the tube so it comes out slime-covered: the clan etiquette is to use only your
//      own tickle, so it never wears rusty gear before yours.
//   4. Mother Slime: never fights her. When she's up it says so once in /slimetube and stops.
//
// Usage (KoLmafia command line):
//   autoslime          fight in the tube until the next slime hit would be too much
//   autoslime N        the same, at most N turns
//   autoslime status   show the tube, your tickle, the debuff and your slime gear, without adventuring
//
// Clan rules (Not Dead Yet): Full Member rank, be in chat on /slimetube and /clan, and boss loot goes to anyone
// who hasn't had any in the past 2 instances (the dungeon masters hand it out).

// ---------------------------------------------------------------- logging and settings
// Settings are ordinary KoLmafia properties, changed with "set autoslime_<name> = <value>".

void sl_info(string msg)
{
	print("[autoslime] " + msg, "blue");
}

void sl_warn(string msg)
{
	print("[autoslime] " + msg, "red");
}

string sl_setting(string name, string fallback)
{
	string value = get_property("autoslime_" + name);
	return value == "" ? fallback : value;
}

string[string] sl_savedPrefs;

void sl_overrideProperty(string prop, string value)
{
	if(!(sl_savedPrefs contains prop))
	{
		sl_savedPrefs[prop] = get_property(prop);
	}
	set_property(prop, value);
}

void sl_restoreProperties()
{
	foreach prop, value in sl_savedPrefs
	{
		set_property(prop, value);
	}
	clear(sl_savedPrefs);
}

int sl_owned(item it)
{
	return item_amount(it) + closet_amount(it) + storage_amount(it) + display_amount(it) + equipped_amount(it);
}

// ---------------------------------------------------------------- the tube and its raid log

// the picture on clan_slimetube.php: 0-9 as the tube fills up, 10 when Mother Slime is waiting, -1 if closed
int sl_stage()
{
	string page = visit_url("clan_slimetube.php");
	if(page.contains_text("tube_boss"))
	{
		return 10;
	}
	matcher m = create_matcher("slimetube/[^\"']*?(\\d+)\\.gif", page);
	return m.find() ? m.group(1).to_int() : -1;
}

record sl_log
{
	int kills;	//slimes defeated by the clan this instance
	int myKills;
	int tickles;
	int squeezes;
	boolean myTickle;
	boolean motherDead;
};

// clan_raidlogs.php, <div id='SlimeTube'>, lines like "Name (#123) defeated a Slime Tube monster (5 turns)"
sl_log sl_readLog()
{
	sl_log log;
	string page = visit_url("clan_raidlogs.php");
	matcher div = create_matcher("<div id='SlimeTube'>(.+?)</div>", page);
	if(!div.find())
	{
		return log;
	}
	string me = "(#" + my_id() + ")";
	foreach i, line in div.group(1).split_string("<br>")
	{
		int turns = 1;
		matcher t = create_matcher("\\(([\\d,]+) turns?\\)", line);
		if(t.find())
		{
			turns = t.group(1).to_int();
		}
		boolean mine = line.contains_text(me);
		if(line.contains_text("defeated  Mother Slime") || line.contains_text("defeated Mother Slime"))
		{
			log.motherDead = true;
		}
		else if(line.contains_text("defeated a") && !line.contains_text("defeated by"))
		{
			log.kills += turns;
			if(mine)
			{
				log.myKills += turns;
			}
		}
		else if(line.contains_text("tickled"))
		{
			log.tickles += turns;
			log.myTickle = log.myTickle || mine;
		}
		else if(line.contains_text("squeezed"))
		{
			log.squeezes += turns;
		}
	}
	return log;
}

// ---------------------------------------------------------------- Coated in Slime

// The start-of-fight slime hits since you last picked up Coated in Slime, read from today's and yesterday's
// session logs: the first "Round 1: You lose N hit points" line of each fight. The debuff hits in every fight,
// not only in the tube (2026-10-30: 824, 1,354, 3,133 and 2,774 in the sea right after 12, 85, 254, 557 in the tube).
int[int] sl_hits()
{
	int[int] hits;
	if(have_effect($effect[Coated in Slime]) == 0)
	{
		return hits;	//it's worn off: the next fight starts the count again
	}
	string[int] logs = session_logs(2);
	string text = logs[1] + "\n" + logs[0];
	int start = text.last_index_of("You acquire an effect: Coated in Slime");
	if(start < 0)
	{
		return hits;
	}
	text = text.substring(start);
	matcher adv = create_matcher("\\n\\[\\d+\\] ([^\\n]+)", text);
	int[int] starts;
	string[int] places;
	while(adv.find())
	{
		starts[count(starts)] = adv.start();
		places[count(places)] = adv.group(1);
	}
	//every fight counts, wherever it is: the slime hits first, before the monster's own attacks in round 1
	foreach i, pos in starts
	{
		int stop = (starts contains (i + 1)) ? starts[i + 1] : length(text);
		string fight = text.substring(pos, stop);
		int round2 = fight.index_of("Round 2:");
		matcher hit = create_matcher("Round 1: You lose ([\\d,]+) hit points?", fight);
		if(hit.find() && (round2 < 0 || hit.start() < round2))
		{
			hits[count(hits)] = hit.group(1).to_int();
		}
	}
	return hits;
}

// The next hit, from how the last ones grew: each roughly doubles, a little less each time.
int sl_nextHit(int[int] hits)
{
	int n = count(hits);
	if(n == 0)
	{
		return 0;
	}
	int last = hits[n - 1];
	if(n == 1 || hits[n - 2] <= 0)
	{
		return last * 3 + 50;
	}
	float ratio = max(1.7, (last.to_float() / hits[n - 2]) * 0.9);
	return ceil(last * ratio);
}

string sl_hitList(int[int] hits)
{
	string s = "";
	foreach i, h in hits
	{
		s += (s == "" ? "" : ", ") + h;
	}
	return s == "" ? "none yet" : s;
}

// ---------------------------------------------------------------- slime gear and rusty items

item[item] sl_slimeVersions()
{
	//best first: +2 slime resistance each, then +200 HP
	item[item] m;
	m[$item[rusty compass]] = $item[slime-covered compass];
	m[$item[rusty metal greaves]] = $item[slime-covered greaves];
	m[$item[rusty diving helmet]] = $item[slime-covered helmet];
	m[$item[rusty old lantern]] = $item[slime-covered lantern];
	m[$item[rusty chain necklace]] = $item[slime-covered necklace];
	return m;
}

item[int] sl_rustyOrder()
{
	item[int] order;
	foreach it in $items[rusty compass, rusty metal greaves, rusty diving helmet, rusty old lantern, rusty chain necklace]
	{
		order[count(order)] = it;
	}
	return order;
}

// the rusty item to wear in for a slime-covered one: you have it, can wear both, and don't own the result yet
item sl_rustyToConvert()
{
	item[item] versions = sl_slimeVersions();
	foreach i, rusty in sl_rustyOrder()
	{
		item slimed = versions[rusty];
		if(item_amount(rusty) + closet_amount(rusty) + equipped_amount(rusty) > 0 && can_equip(rusty)
			&& can_equip(slimed) && sl_owned(slimed) == 0)
		{
			return rusty;
		}
	}
	return $item[none];
}

// your tickle is in this instance's log and hasn't been used yet. autoslime_convertedAt holds the clan's kill
// count when your last conversion happened; a lower count now means a new instance.
boolean sl_tickleWaiting(sl_log log)
{
	if(!log.myTickle)
	{
		return false;
	}
	string at = get_property("autoslime_convertedAt");
	return at == "" || log.kills < at.to_int();
}

void sl_wearGear(item rusty)
{
	string spec = sl_setting("maximize", "100 slime resistance, hp, 0.3 mainstat");
	if(rusty != $item[none])
	{
		if(item_amount(rusty) == 0 && closet_amount(rusty) > 0)
		{
			take_closet(1, rusty);
		}
		spec += ", +equip " + rusty;
	}
	maximize(spec, false);
}

// ---------------------------------------------------------------- status

void sl_status()
{
	int stage = sl_stage();
	if(stage < 0)
	{
		sl_warn("Couldn't see the Slime Tube. It may be closed, or you may not have the clan rank to enter.");
	}
	else
	{
		sl_info("The tube: " + (stage >= 10 ? "Mother Slime is waiting" : "stage " + stage + " of 10") + ".");
	}
	sl_log log = sl_readLog();
	sl_info("This instance: the clan has defeated " + log.kills + " slimes (you " + log.myKills + "). Tickles " + log.tickles
		+ ", squeezes " + log.squeezes + (log.motherDead ? ". Mother Slime is dead." : "."));
	int[int] hits = sl_hits();
	int coated = have_effect($effect[Coated in Slime]);
	if(coated == 0)
	{
		sl_info("Coated in Slime: none. The first tube fight starts it.");
	}
	else
	{
		int next = sl_nextHit(hits);
		sl_info("Coated in Slime: " + coated + " turns. Slime hits so far: " + sl_hitList(hits) + ". Next one about " + next
			+ " against your " + my_maxhp() + " max HP" + (next >= my_maxhp() * sl_setting("hitShare", "0.8").to_float()
				? ": too much, so autoslime would wait for it to wear off." : "."));
	}
	sl_info("Slime resistance worn now: " + numeric_modifier("Slime Resistance").to_int() + ".");
	string[int] gear;
	foreach it in $items[chamoisole, crown-shaped beanie, poodle skirt, hopping socks, letterman's jacket,
		slime-covered compass, slime-covered greaves, slime-covered helmet, slime-covered lantern, slime-covered necklace]
	{
		if(sl_owned(it) > 0)
		{
			gear[count(gear)] = it + (can_equip(it) ? "" : " (stats too low to wear)");
		}
	}
	string list = "";
	foreach i, s in gear
	{
		list += (list == "" ? "" : "; ") + s;
	}
	sl_info("Slime gear you own: " + (list == "" ? "none" : list) + ".");
	item rusty = sl_rustyToConvert();
	if(rusty == $item[none])
	{
		sl_info("No rusty item to convert that you could wear afterwards.");
	}
	else if(!log.myTickle)
	{
		sl_info("Next to convert: " + rusty + ". Waiting for your own Engulfed! tickle this instance.");
	}
	else if(sl_tickleWaiting(log))
	{
		sl_info("Your tickle is waiting: autoslime wears " + rusty + " in the tube to make it slime-covered.");
	}
	else
	{
		sl_info("You've used your tickle this instance. Next instance: " + rusty + ".");
	}
}

// ---------------------------------------------------------------- adventuring

boolean sl_turn()
{
	int stage = sl_stage();
	if(stage < 0)
	{
		sl_warn("Couldn't see the Slime Tube. It may be closed, or you may not have the clan rank to enter.");
		return false;
	}
	if(stage >= 10)
	{
		if(!get_property("_autoslime_bossAnnounced").to_boolean())
		{
			chat_clan("Mother Slime is waiting in the Slime Tube.", "slimetube");
			set_property("_autoslime_bossAnnounced", "true");
		}
		sl_info("Mother Slime is waiting. autoslime doesn't fight her; that's for the clan to arrange.");
		return false;
	}
	int[int] hits = sl_hits();
	int next = sl_nextHit(hits);
	if(next >= my_maxhp() * sl_setting("hitShare", "0.8").to_float())
	{
		sl_info("Coated in Slime would hit for about " + next + " next fight (hits so far: " + sl_hitList(hits) + "), against your "
			+ my_maxhp() + " max HP. Stopping. It hits in every fight, anywhere, so spend its last "
			+ have_effect($effect[Coated in Slime]) + " turns without fighting (rest, or noncombats).");
		return false;
	}

	sl_log log = sl_readLog();
	item rusty = sl_tickleWaiting(log) ? sl_rustyToConvert() : $item[none];
	item slimed = rusty == $item[none] ? $item[none] : sl_slimeVersions()[rusty];
	int before = slimed == $item[none] ? 0 : sl_owned(slimed);
	sl_wearGear(rusty);
	if(rusty != $item[none] && equipped_amount(rusty) == 0)
	{
		sl_warn("Couldn't put on " + rusty + "; fighting without it.");
	}
	next = sl_nextHit(hits);	//max HP may have changed with the gear
	if(next >= my_maxhp() * sl_setting("hitShare", "0.8").to_float())
	{
		sl_info("With the slime gear on, the next hit (about " + next + ") is still too much for your " + my_maxhp() + " max HP. Stopping.");
		return false;
	}
	restore_hp(my_maxhp());
	if(my_hp() <= next + 50 || have_effect($effect[Beaten Up]) > 0)
	{
		sl_warn("Couldn't heal enough for the next slime hit (HP " + my_hp() + ", hit about " + next + ").");
		return false;
	}

	int turnsBefore = my_turncount();
	boolean ok = adv1($location[The Slime Tube], -1, "");
	if(have_effect($effect[Beaten Up]) > 0)
	{
		sl_warn("Beaten up in the tube. Stopping.");
		return false;
	}
	if(!ok && my_turncount() == turnsBefore)
	{
		sl_warn("The adventure in the Slime Tube didn't happen. KoLmafia's reason is in the CLI just above.");
		return false;
	}
	if(get_property("lastEncounter") == "Engulfed!")
	{
		sl_info("Engulfed!: tickled the uvula.");
	}
	if(slimed != $item[none] && sl_owned(slimed) > before)
	{
		set_property("autoslime_convertedAt", sl_readLog().kills.to_string());
		sl_info("Your " + rusty + " came out as a " + slimed + ".");
	}
	return true;
}

void sl_run(int maxTurns)
{
	int start = my_turncount();
	int stuck = 0;
	while(maxTurns < 0 || my_turncount() - start < maxTurns)
	{
		if(my_adventures() == 0)
		{
			sl_info("Out of adventures.");
			break;
		}
		int before = my_turncount();
		if(!sl_turn())
		{
			break;
		}
		stuck = my_turncount() == before ? stuck + 1 : 0;
		if(stuck >= 3)
		{
			sl_warn("Three steps in a row spent no turn. Stopping so it doesn't spin.");
			break;
		}
	}
	sl_info("Spent " + (my_turncount() - start) + " turns.");
}

void main(string... args)
{
	string joined = "";
	foreach i, a in args
	{
		joined += " " + a;
	}
	string[int] words = (joined == "" ? "" : joined.substring(1)).to_lower_case().split_string(" ");
	if(words[0] == "status")
	{
		sl_status();
		return;
	}
	if(words[0] != "" && words[0].to_int() <= 0)
	{
		sl_warn("Usage: autoslime [turns] | autoslime status");
		return;
	}
	int turns = words[0] == "" ? -1 : words[0].to_int();
	try
	{
		sl_overrideProperty("choiceAdventure326", "0");	//Mother Slime: stop, never fight her
		sl_overrideProperty("choiceAdventure337", "1");	//Engulfed!: tickle the uvula, never squeeze
		sl_run(turns);
	}
	finally
	{
		sl_restoreProperties();
	}
}
