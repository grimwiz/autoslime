script "autoslime.ash";
since r29000;

// autoslime: spends turns in your clan's Slime Tube the way a good clanmate would.
//   1. Coated in Slime: the tube's debuff hits you at the start of every fight, in the tube or anywhere else, for
//      a share of your max HP that grows as its turns run down (1% with 10 left, 81% with 6, 290% with 3).
//      Shrugging can't remove it; a chamois from The Bucket by the tube can. autoslime works out the next hit
//      before every fight and wipes the slime off when it would take more than 80% of your HP, and once more
//      at the end of the run so it doesn't follow you into other fights.
//   2. Slime resistance: wears the gear with the most of it (and the HP to take the hits) for each fight.
//   3. Engulfed!: tickles the uvula (once a player per instance; it lets one rusty item become slime-covered)
//      and never squeezes the gall bladder (that raises the tube's ML for everyone). After your own tickle it
//      keeps one rusty item on in the tube. Fighting in it doesn't convert it (2026-10-30: 12 fights after the
//      tickle, still rusty); the conversion seems to come at a later Engulfed!, so it stays on until one. The clan
//      etiquette is to use only your own tickle, so it never wears rusty gear before yours.
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
// The hit at the start of each fight is a share of your maximum HP set by the debuff's turns left (it grows as
// they run down), less your slime resistance. The table is from relay_slime.ash (twistedmage/assorted-kol-scripts)
// and matches 2026-10-30's hits: 12, 85, 254, 557 at 10, 9, 8, 7 turns left on about 1,270 max HP and +1 resistance.

float sl_slimeShare(int turnsLeft)
{
	float[int] share;
	share[0] = 0.0;
	share[1] = 5.3333490;
	share[2] = 4.0014678;
	share[3] = 2.9021937;
	share[4] = 2.0164264;
	share[5] = 1.3243979;
	share[6] = 0.8055476;
	share[7] = 0.4383466;
	share[8] = 0.2000367;
	share[9] = 0.0662078;
	share[10] = 0.0100000;
	return share[max(0, min(10, turnsLeft))];
}

// the slime hit at the start of your next fight
int sl_nextHit()
{
	float resisted = (100.0 - elemental_resistance($element[slime])) / 100.0;
	return ceil(my_maxhp() * sl_slimeShare(have_effect($effect[Coated in Slime])) * resisted);
}

boolean sl_tooMuch(int hit)
{
	return hit >= my_maxhp() * sl_setting("hitShare", "0.8").to_float();
}

// Does the bucket refill as slimes die? Each wipe compares the count with the last wipe's and with how many
// slimes the clan killed in between (same instance only), and keeps a running total in autoslime_bucketEvidence
// ("chamois back,slimes killed").
void sl_bucketEvidence(int count)
{
	int kills = sl_readLog().kills;
	string[int] last = get_property("autoslime_bucketAt").split_string(",");
	if(count(last) == 2 && last[0] != "" && kills >= last[1].to_int())
	{
		int back = count - last[0].to_int() + 1;	//+1: the chamois this wipe took
		int killed = kills - last[1].to_int();
		string[int] total = get_property("autoslime_bucketEvidence").split_string(",");
		int totalBack = back + (count(total) == 2 ? total[0].to_int() : 0);
		int totalKilled = killed + (count(total) == 2 ? total[1].to_int() : 0);
		set_property("autoslime_bucketEvidence", totalBack + "," + totalKilled);
		sl_info("Since your last wipe the clan killed " + killed + " slimes and " + back + " chamois went back in the bucket. So far: "
			+ totalBack + " back for " + totalKilled + " kills.");
	}
	set_property("autoslime_bucketAt", count + "," + kills);
}

// The Bucket by the tube: a chamois wipes the debuff off (KoLmafia can't shrug it), free. It's shared by the clan,
// so autoslime leaves the last autoslime_bucketReserve (default 200) for others; the count left is shown after each
// wipe and remembered for the day in _autoslime_bucketLeft. On 2026-10-30 it went 1,717 -> 1,721 across 5 kills and 1 wipe, so
// it looks like slime kills put chamois back.
boolean sl_chamois()
{
	if(have_effect($effect[Coated in Slime]) == 0)
	{
		return true;
	}
	string known = get_property("_autoslime_bucketLeft");
	int reserve = sl_setting("bucketReserve", "200").to_int();
	if(known != "" && known.to_int() <= reserve)
	{
		sl_warn("The bucket had only " + known + " chamois last time; leaving them for the clan (autoslime_bucketReserve = " + reserve + ").");
		return false;
	}
	int turnsBefore = my_turncount();
	string page = visit_url("clan_slimetube.php?action=chamois");
	matcher left = create_matcher("There (?:are|is) ([\\d,]+) chamoi", page);
	boolean counted = left.find();
	if(counted)
	{
		set_property("_autoslime_bucketLeft", left.group(1).to_int().to_string());
	}
	if(have_effect($effect[Coated in Slime]) > 0)
	{
		sl_warn("The chamois didn't wipe off the slime.");
		return false;
	}
	sl_info("Wiped off the slime with a chamois" + (counted ? " (" + left.group(1) + " left in the bucket)" : "")
		+ (my_turncount() > turnsBefore ? "; it took a turn." : "."));
	if(counted)
	{
		sl_bucketEvidence(left.group(1).to_int());
	}
	return true;
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
	int coated = have_effect($effect[Coated in Slime]);
	if(coated == 0)
	{
		sl_info("Coated in Slime: none. The first tube fight starts it.");
	}
	else
	{
		int next = sl_nextHit();
		sl_info("Coated in Slime: " + coated + " turns left. Your next fight anywhere starts with a hit of about " + next
			+ " against your " + my_maxhp() + " max HP" + (sl_tooMuch(next) ? ": too much, so autoslime wipes it off with a chamois first." : "."));
	}
	sl_info("Slime resistance worn now: " + numeric_modifier("Slime Resistance").to_int() + " (" + elemental_resistance($element[slime]).to_int() + "% off each hit).");
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
		sl_info("Your tickle is waiting: autoslime keeps " + rusty + " on in the tube until an Engulfed! slimes it.");
	}
	else
	{
		sl_info("You've used your tickle this instance. Next instance: " + rusty + ".");
	}
}

// ---------------------------------------------------------------- adventuring

// The tube's own food and drink are mediocre (2-3 adventures each), so they're only for their buffs: one slimy
// sweetbreads for Grimace and one slimy fermented bile bladder for Bilious (+1 slime resistance and +25 ML each,
// 20 turns), when that buff has run out and there are enough adventures left to use most of it. Better food and
// drink fill the rest of the stomach and liver.
void sl_slimeBuffs()
{
	if(my_adventures() < sl_setting("buffMinAdventures", "15").to_int())
	{
		return;
	}
	if(have_effect($effect[Grimace]) == 0 && item_amount($item[slimy sweetbreads]) > 0 && fullness_limit() > my_fullness())
	{
		eat(1, $item[slimy sweetbreads]);
	}
	if(have_effect($effect[Bilious]) == 0 && item_amount($item[slimy fermented bile bladder]) > 0 && inebriety_limit() > my_inebriety())
	{
		drink(1, $item[slimy fermented bile bladder]);
	}
}

// out of adventures even after "autosea diet": say what room is left
void sl_outOfAdventures()
{
	int full = fullness_limit() - my_fullness();
	int drunk = inebriety_limit() - my_inebriety();
	int spleen = spleen_limit() - my_spleen_use();
	if(full + drunk + spleen > 0)
	{
		sl_info("Out of adventures, with " + full + " fullness, " + drunk + " drunkenness and " + spleen
			+ " spleen still free, but autosea diet found nothing worth eating or drinking for it.");
	}
	else
	{
		sl_info("Out of adventures, and your stomach, liver and spleen are full.");
	}
}

// Engulfed! (choice 337), handled here rather than by KoLmafia so its options and result get logged: wearing a
// rusty item through two Engulfed!s after a tickle didn't convert it (2026-10-30), so how the conversion works is
// still unknown. Takes an option that mentions rusty or slime-covered gear if the game offers one, otherwise 1
// (tickle; 2 squeezes the gall bladder, which raises the ML for everyone). The page is saved to
// data/autoslime_engulfed.html.
void sl_engulfed()
{
	string[int] options = available_choice_options();
	int pick = 1;
	foreach n, text in options
	{
		sl_info("Engulfed! option " + n + ": " + text);
		if(n != 1 && n != 2 && (text.to_lower_case().contains_text("rusty") || text.to_lower_case().contains_text("slime-covered")))
		{
			pick = n;
		}
	}
	string page = run_choice(pick);
	buffer_to_file(page.to_buffer(), "autoslime_engulfed.html");
	string words = create_matcher("\\s+", create_matcher("<[^>]*>", page).replace_all(" ")).replace_all(" ");
	int at = words.index_of("Engulfed");
	if(at >= 0)
	{
		words = words.substring(at);
	}
	sl_info("Engulfed!: took option " + pick + ". The game said: " + (length(words) > 500 ? words.substring(0, 500) + "..." : words));
}

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
	sl_slimeBuffs();
	sl_log log = sl_readLog();
	item rusty = sl_tickleWaiting(log) ? sl_rustyToConvert() : $item[none];
	item slimed = rusty == $item[none] ? $item[none] : sl_slimeVersions()[rusty];
	int before = slimed == $item[none] ? 0 : sl_owned(slimed);
	sl_wearGear(rusty);
	if(rusty != $item[none] && equipped_amount(rusty) == 0)
	{
		sl_warn("Couldn't put on " + rusty + "; fighting without it.");
	}
	int next = sl_nextHit();	//with the gear on: slime resistance and max HP both count
	if(sl_tooMuch(next))
	{
		if(!sl_chamois())
		{
			sl_info("Coated in Slime would hit for about " + next + " against your " + my_maxhp() + " max HP, and it couldn't be wiped off. Stopping.");
			return false;
		}
		next = sl_nextHit();
	}
	if(have_effect($effect[Beaten Up]) > 0)
	{
		cli_execute("uneffect Beaten Up");
	}
	if(have_effect($effect[Beaten Up]) > 0)
	{
		sl_warn("You're Beaten Up (" + have_effect($effect[Beaten Up]) + " turns) and KoLmafia couldn't remove it. Remove it, or spend those turns without fighting, then run autoslime again.");
		return false;
	}
	restore_hp(my_maxhp());
	if(my_hp() <= next + 50)
	{
		sl_warn("Couldn't heal enough for the next slime hit (HP " + my_hp() + ", hit about " + next + ").");
		return false;
	}

	int turnsBefore = my_turncount();
	boolean ok = adv1($location[The Slime Tube], -1, "");
	boolean engulfed = handling_choice() && last_choice() == 337;
	if(engulfed)
	{
		sl_engulfed();
	}
	if(have_effect($effect[Beaten Up]) > 0)
	{
		sl_warn("Beaten up in the tube. Stopping.");
		return false;
	}
	if(!ok && !engulfed && my_turncount() == turnsBefore)
	{
		sl_warn("The adventure in the Slime Tube didn't happen. KoLmafia's reason is in the CLI just above.");
		return false;
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
			cli_execute("autosea diet");	//eat and drink rather than stop (autosea fills the organs for every auto script)
		}
		if(my_adventures() == 0)
		{
			sl_outOfAdventures();
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
		sl_overrideProperty("choiceAdventure337", "0");	//Engulfed!: sl_engulfed() handles and logs it; never squeezes
		sl_run(turns);
		//it hits in every fight, anywhere, and grows as it runs down: wipe it if you've turns left to fight with today.
		//With none left it stays for the next autoslime, which carries on the cycle and wipes only when it must.
		if(have_effect($effect[Coated in Slime]) > 0 && my_adventures() > 0 && sl_setting("wipeAtEnd", "true").to_boolean())
		{
			sl_chamois();
		}
	}
	finally
	{
		sl_restoreProperties();
	}
}
