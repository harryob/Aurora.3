/*
Asset cache quick users guide:

Make a datum at the bottom of this file with your assets for your thing.
The simple subsystem will most like be of use for most cases.
Then call get_asset_datum() with the type of the datum you created and store the return
Then call .send(client) on that stored return value.

You can set verify to TRUE if you want send() to sleep until the client has the assets.
*/


// Amount of time(ds) MAX to send per asset, if this get exceeded we cancel the sleeping.
// This is doubled for the first asset, then added per asset after
#define ASSET_CACHE_SEND_TIMEOUT 7

#define ASSET_CROSS_ROUND_CACHE_DIRECTORY "tmp/assets"

//all of our asset datums, used for referring to these later
var/list/asset_datums = list()

//get an assetdatum or make a new one
//does NOT ensure it's filled, if you want that use get_asset_datum()
/proc/load_asset_datum(type)
	return asset_datums[type] || new type()

/proc/get_asset_datum(type)
	var/datum/asset/loaded_asset = asset_datums[type] || new type()
	return loaded_asset.ensure_ready()

/proc/simple_asset_ensure_is_sent(client, type)
	var/datum/asset/simple/asset = get_asset_datum(type)

	asset.send(client)

/datum/asset
	var/_abstract = /datum/asset
	var/cached_serialized_url_mappings
	var/cached_serialized_url_mappings_transport_type

	/// Whether or not this asset should be loaded in the "early assets" SS
	var/early = FALSE

	/// Whether or not this asset can be cached across rounds of the same commit under the `CACHE_ASSETS` config.
	/// This is not a *guarantee* the asset will be cached. Not all asset subtypes respect this field, and the
	/// config can, of course, be disabled.
	var/cross_round_cachable = FALSE

/datum/asset/New()
	asset_datums[type] = src
	register()

/// Stub that allows us to react to something trying to get us
/// Not useful here, more handy for sprite sheets
/datum/asset/proc/ensure_ready()
	return src

/// Stub to hook into if your asset is having its generation queued by SSasset_loading
/datum/asset/proc/queued_generation()
	CRASH("[type] inserted into SSasset_loading despite not implementing /proc/queued_generation")

/datum/asset/proc/get_url_mappings()
	return list()

/// Returns a cached tgui message of URL mappings
/datum/asset/proc/get_serialized_url_mappings()
	if (isnull(cached_serialized_url_mappings) || cached_serialized_url_mappings_transport_type != SSassets.transport.type)
		cached_serialized_url_mappings = TGUI_CREATE_MESSAGE("asset/mappings", get_url_mappings())
		cached_serialized_url_mappings_transport_type = SSassets.transport.type

	return cached_serialized_url_mappings

/datum/asset/proc/register()
	return

/datum/asset/proc/send(client)
	return

/// Returns whether or not the asset should attempt to read from cache
/datum/asset/proc/should_refresh()
	return !cross_round_cachable || !config.cache_assets

//If you don't need anything complicated.
/datum/asset/simple
	_abstract = /datum/asset/simple
	/// list of assets for this datum in the form of:
	/// asset_filename = asset_file. At runtime the asset_file will be
	/// converted into a asset_cache datum.
	var/list/assets = list()
	/// Set to true to have this asset also be sent via the legacy browse_rsc
	/// system when cdn transports are enabled?
	var/legacy = FALSE
	/// TRUE for keeping local asset names when browse_rsc backend is used
	var/keep_local_name = FALSE

/datum/asset/simple/register()
	for(var/asset_name in assets)
		var/datum/asset_cache_item/ACI = SSassets.transport.register_asset(asset_name, assets[asset_name])
		if (!ACI)
			log_asset("ERROR: Invalid asset: [type]:[asset_name]:[ACI]")
			continue
		if (legacy)
			ACI.legacy = legacy
		if (keep_local_name)
			ACI.keep_local_name = keep_local_name
		assets[asset_name] = ACI

/datum/asset/simple/send(client)
	. = SSassets.transport.send_assets(client, assets)

/datum/asset/simple/get_url_mappings()
	. = list()
	for (var/asset_name in assets)
		.[asset_name] = SSassets.transport.get_asset_url(asset_name, assets[asset_name])

/datum/asset/group
	_abstract = /datum/asset/group
	var/list/children

/datum/asset/group/register()
	for(var/type in children)
		get_asset_datum(type)

/datum/asset/group/send(client/C)
	for(var/type in children)
		var/datum/asset/A = get_asset_datum(type)
		A.send(C) || .

/datum/asset/group/get_url_mappings()
	. = list()
	for(var/type in children)
		var/datum/asset/A = get_asset_datum(type)
		. += A.get_url_mappings()
/datum/asset/group/goonchat
	children = list(
		/datum/asset/simple/jquery,
		/datum/asset/simple/goonchat,
		/datum/asset/simple/namespaced/fontawesome,
		/datum/asset/spritesheet/goonchat
	)

// spritesheet implementation
#define SPR_SIZE 1
#define SPR_IDX 2
#define SPRSZ_COUNT 1
#define SPRSZ_ICON 2
#define SPRSZ_STRIPPED 3

/datum/asset/spritesheet
	_abstract = /datum/asset/spritesheet
	var/name
	var/list/sizes = list()		// "32x32" -> list(10, icon/normal, icon/stripped)
	var/list/sprites = list()	// "foo_bar" -> list("32x32", 5)
	var/verify = FALSE

/datum/asset/spritesheet/register()
	if(!name)
		CRASH("spritesheet [type] cannot register without a name")
	ensure_stripped()

	var/res_name = "spritesheet_[name].css"
	var/fname = "data/spritesheets/[res_name]"
	dll_call(RUST_G, "file_write", generate_css(), fname)
	SSassets.transport.register_asset(res_name, file(fname))

	for(var/size_id in sizes)
		var/size = sizes[size_id]
		SSassets.transport.register_asset("[name]_[size_id].png", size[SPRSZ_STRIPPED])

/datum/asset/spritesheet/send(client/C)
	if(!name)
		return
	var/all = list("spritesheet_[name].css")
	for(var/size_id in sizes)
		all += "[name]_[size_id].png"
	. = SSassets.transport.send_assets(C, all)

/datum/asset/spritesheet/proc/ensure_stripped(sizes_to_strip = sizes)
	for(var/size_id in sizes_to_strip)
		var/size = sizes[size_id]
		if (size[SPRSZ_STRIPPED])
			continue

		var/fname = "data/spritesheets/[name]_[size_id].png"
		fcopy(size[SPRSZ_ICON], fname)
		var/error = dll_call(RUST_G, "dmi_strip_metadata", fname)
		if(length(error))
			crash_with("Failed to strip [name]_[size_id].png: [error]")
		size[SPRSZ_STRIPPED] = icon(fname)

/datum/asset/spritesheet/proc/generate_css()
	var/list/out = list()

	for (var/size_id in sizes)
		var/size = sizes[size_id]
		var/icon/tiny = size[SPRSZ_ICON]
		out += ".[name][size_id]{display:inline-block;width:[tiny.Width()]px;height:[tiny.Height()]px;background:url('[name]_[size_id].png') no-repeat;}"

	for (var/sprite_id in sprites)
		var/sprite = sprites[sprite_id]
		var/size_id = sprite[SPR_SIZE]
		var/idx = sprite[SPR_IDX]
		var/size = sizes[size_id]

		var/icon/tiny = size[SPRSZ_ICON]
		var/icon/big = size[SPRSZ_STRIPPED]
		var/per_line = big.Width() / tiny.Width()
		var/x = (idx % per_line) * tiny.Width()
		var/y = round(idx / per_line) * tiny.Height()

		out += ".[name][size_id].[sprite_id]{background-position:-[x]px -[y]px;}"

	return out.Join("\n")

/datum/asset/spritesheet/proc/Insert(sprite_name, icon/I, icon_state="", dir=SOUTH, frame=1, moving=FALSE, icon/forced=FALSE)
	if (sprites[sprite_name])
		return

	if(!forced)
		I = icon(I, icon_state=icon_state, dir=dir, frame=frame, moving=moving)
	else
		I = forced
	if (!I || !length(icon_states(I)))  // that direction or state doesn't exist
		return
	var/size_id = "[I.Width()]x[I.Height()]"
	var/size = sizes[size_id]

	if (size)
		var/position = size[SPRSZ_COUNT]++
		var/icon/sheet = size[SPRSZ_ICON]
		size[SPRSZ_STRIPPED] = null
		sheet.Insert(I, icon_state=sprite_name)
		sprites[sprite_name] = list(size_id, position)
	else
		sizes[size_id] = size = list(1, I, null)
		sprites[sprite_name] = list(size_id, 0)

/datum/asset/spritesheet/proc/InsertAll(prefix, icon/I, list/directions)
	if (length(prefix))
		prefix = "[prefix]-"

	if (!directions)
		directions = list(SOUTH)

	for (var/icon_state_name in icon_states(I))
		for (var/direction in directions)
			var/prefix2 = (directions.len > 1) ? "[dir2text(direction)]-" : ""
			Insert("[prefix][prefix2][icon_state_name]", I, icon_state=icon_state_name, dir=direction)

/datum/asset/spritesheet/proc/css_tag()
	return {"<link rel="stylesheet" href="spritesheet_[name].css" />"}

/datum/asset/spritesheet/proc/css_filename()
	return SSassets.transport.get_asset_url("spritesheet_[name].css")

/datum/asset/spritesheet/proc/icon_tag(sprite_name, var/html=TRUE)
	var/sprite = sprites[sprite_name]
	if (!sprite)
		return null
	var/size_id = sprite[SPR_SIZE]
	if(html)
		return {"<span class="[name][size_id] [sprite_name]"></span>"}
	return "[name][size_id] [sprite_name]"

#undef SPR_SIZE
#undef SPR_IDX
#undef SPRSZ_COUNT
#undef SPRSZ_ICON
#undef SPRSZ_STRIPPED


/datum/asset/spritesheet/simple
	_abstract = /datum/asset/spritesheet/simple
	var/list/assets

/datum/asset/spritesheet/simple/register()
	for (var/key in assets)
		Insert(key, assets[key])
	..()

//Generates assets based on iconstates of a single icon
/datum/asset/simple/icon_states
	_abstract = /datum/asset/simple/icon_states
	var/icon
	var/list/directions = list(SOUTH)
	var/frame = 1
	var/movement_states = FALSE
	var/prefix = "default" //asset_name = "[prefix].[icon_state_name].png"
	var/generic_icon_names = FALSE //generate icon filenames using generate_asset_name() instead the above format

/datum/asset/simple/icon_states/register(_icon = icon)
	for(var/icon_state_name in icon_states(_icon))
		for(var/direction in directions)
			var/asset = icon(_icon, icon_state_name, direction, frame, movement_states)
			if (!asset)
				continue
			asset = fcopy_rsc(asset) //dedupe
			var/prefix2 = (directions.len > 1) ? "[dir2text(direction)]." : ""
			var/asset_name = sanitize_filename("[prefix].[prefix2][icon_state_name].png")
			if (generic_icon_names)
				asset_name = "[generate_asset_name(asset)].png"
			SSassets.transport.register_asset(asset_name, asset)

/datum/asset/simple/icon_states/multiple_icons
	_abstract = /datum/asset/simple/icon_states/multiple_icons
	var/list/icons

/datum/asset/simple/icon_states/multiple_icons/register()
	for(var/i in icons)
		..(i)

//DEFINITIONS FOR ASSET DATUMS START HERE.

/datum/asset/simple/faction_icons
	legacy = TRUE
	assets = list(
		"faction_EPMC.png" = 'html/images/factions/ECFlogo.png',
		"faction_Zeng.png" = 'html/images/factions/zenghulogo.png',
		"faction_Zavod.png" = 'html/images/factions/zavodlogo.png',
		"faction_NT.png" = 'html/images/factions/nanotrasenlogo.png',
		"faction_Idris.png" = 'html/images/factions/idrislogo.png',
		"faction_Hepht.png" = 'html/images/factions/hephlogo.png',
		"faction_INDEP.png" = 'html/images/factions/unaffiliatedlogo.png',
		"faction_PMCG.png" = 'html/images/factions/pmcglogo.png',
		"faction_Orion.png" = 'html/images/factions/orionlogo.png',
		"faction_SCC.png" = 'html/images/factions/scclogo.png'
	)

/datum/asset/simple/jquery
	legacy = TRUE
	assets = list(
		"jquery.min.js"            = 'code/modules/goonchat/browserassets/js/jquery.min.js',
	)

/datum/asset/simple/goonchat
	legacy = TRUE
	assets = list(
		"json2.min.js"             = 'code/modules/goonchat/browserassets/js/json2.min.js',
		"browserOutput.js"         = 'code/modules/goonchat/browserassets/js/browserOutput.js',
		"browserOutput.css"	       = 'code/modules/goonchat/browserassets/css/browserOutput.css',
		"browserOutput_white.css"  = 'code/modules/goonchat/browserassets/css/browserOutput_white.css'
	)

/datum/asset/simple/namespaced/fontawesome
	legacy = TRUE
	assets = list(
		"fa-regular-400.eot"  = 'html/font-awesome/webfonts/fa-regular-400.eot',
		"fa-regular-400.woff" = 'html/font-awesome/webfonts/fa-regular-400.woff',
		"fa-solid-900.eot"    = 'html/font-awesome/webfonts/fa-solid-900.eot',
		"fa-solid-900.woff"   = 'html/font-awesome/webfonts/fa-solid-900.woff',
		"v4shim.css"          = 'html/font-awesome/css/v4-shims.min.css'
	)
	parents = list("font-awesome.css" = 'html/font-awesome/css/all.min.css')

/datum/asset/simple/namespaced/tgfont
	assets = list(
		"tgfont.eot" = file("tgui/packages/tgfont/static/tgfont.eot"),
		"tgfont.woff2" = file("tgui/packages/tgfont/static/tgfont.woff2"),
	)
	parents = list(
		"tgfont.css" = file("tgui/packages/tgfont/static/tgfont.css"),
	)

/datum/asset/simple/misc
	legacy = TRUE
	assets = list(
		"search.js" = 'html/search.js',
		"panels.css" = 'html/panels.css',
		"loading.gif" = 'html/images/loading.gif',
		"ie-truth.min.js" = 'html/iestats/ie-truth.min.js',
		"conninfo.min.js" = 'html/iestats/conninfo.min.js',
		"copyright_infrigement.png" = 'html/images/copyright_infrigement.png',
		"88x31.png" = 'html/images/88x31.png'
	)

/datum/asset/simple/paper
	legacy = TRUE
	assets = list(
		"talisman.png" = 'html/images/talisman.png',
		"barcode0.png" = 'html/images/barcode0.png',
		"barcode1.png" = 'html/images/barcode1.png',
		"barcode2.png" = 'html/images/barcode2.png',
		"barcode3.png" = 'html/images/barcode3.png',
		"scclogo.png" = 'html/images/factions/scclogo.png',
		"scclogo_small.png" = 'html/images/factions/scclogo_small.png',
		"nanotrasenlogo.png" = 'html/images/factions/nanotrasenlogo.png',
		"nanotrasenlogo_small.png" = 'html/images/factions/nanotrasenlogo_small.png',
		"zhlogo.png" = 'html/images/factions/zenghulogo.png',
		"zhlogo_small.png" = 'html/images/factions/zenghulogo_small.png',
		"idrislogo.png" = 'html/images/factions/idrislogo.png',
		"idrislogo_small.png" = 'html/images/factions/idrislogo_small.png',
		"eridanilogo.png" = 'html/images/factions/ECFlogo.png',
		"eridanilogo_small.png" = 'html/images/factions/ECFlogo_small.png',
		"pmcglogo.png" = 'html/images/factions/pmcglogo.png',
		"pmcglogo_small.png" = 'html/images/factions/pmcglogo_small.png',
		"zavodlogo.png" = 'html/images/factions/zavodlogo.png',
		"zavodlogo_small.png" = 'html/images/factions/zavodlogo_small.png',
		"orionlogo.png" = 'html/images/factions/orionlogo.png',
		"orionlogo_small.png" = 'html/images/factions/orionlogo_small.png',
		"hplogolarge.png" = 'html/images/hplogolarge.png',
		"hplogo.png" = 'html/images/factions/hephlogo.png',
		"hplogo_small.png" = 'html/images/factions/hephlogo_small.png',
		"beflag.png" = 'html/images/beflag.png',
		"beflag_small.png" = 'html/images/beflag_small.png',
		"elyraflag.png" = 'html/images/elyraflag.png',
		"elyraflag_small.png" = 'html/images/elyraflag_small.png',
		"solflag.png" = 'html/images/solflag.png',
		"solflag_small.png" = 'html/images/solflag_small.png',
		"cocflag.png" = 'html/images/cocflag.png',
		"cocflag_small.png" = 'html/images/cocflag_small.png',
		"domflag.png" = 'html/images/domflag.png',
		"domflag_small.png" = 'html/images/domflag_small.png',
		"nralakkflag.png" = 'html/images/nralakkflag.png',
		"nralakkflag_small.png" = 'html/images/nralakkflag_small.png',
		"praflag.png" = 'html/images/praflag.png',
		"praflag_small.png" = 'html/images/praflag_small.png',
		"dpraflag.png" = 'html/images/dpraflag.png',
		"dpraflag_small.png" = 'html/images/dpraflag_small.png',
		"nkaflag.png" = 'html/images/nkaflag.png',
		"nkaflag_small.png" = 'html/images/nkaflag_small.png',
		"izweskiflag.png" = 'html/images/izweskiflag.png',
		"izweskiflag_small.png" = 'html/images/izweskiflag_small.png',
		"goldenlogo.png" = 'html/images/factions/goldenlogo.png',
		"goldenlogo_small.png" = 'html/images/factions/goldenlogo_small.png',
		//scan images that appear on sensors
		"no_data.png" = 'html/images/scans/no_data.png',
		"horizon.png" = 'html/images/scans/horizon.png',
		"intrepid.png" = 'html/images/scans/intrepid.png',
		"spark.png" = 'html/images/scans/spark.png',
		"corvette.png" = 'html/images/scans/corvette.png',
		"elyran_corvette.png" = 'html/images/scans/elyran_corvette.png',
		"dominian_corvette.png" = 'html/images/scans/dominian_corvette.png',
		"tcfl_cetus.png" = 'html/images/scans/tcfl_cetus.png',
		"unathi_corvette.png" = 'html/images/scans/unathi_corvette.png',
		"ranger.png" = 'html/images/scans/ranger.png',
		"oe_platform.png" = 'html/images/scans/oe_platform.png',
		"hospital.png" = 'html/images/scans/hospital.png',
		"skrell_freighter.png" = 'html/images/scans/skrell_freighter.png',
		"diona.png" = 'html/images/scans/diona.png',
		"hailstorm.png" = 'html/images/scans/hailstorm.png',
		"headmaster.png" = 'html/images/scans/headmaster.png',
		"pss.png" = 'html/images/scans/pss.png',
		"nka_freighter.png" = 'html/images/scans/nka_freighter.png',
		"pra_freighter.png" = 'html/images/scans/pra_freighter.png',
		"tramp_freighter.png" = 'html/images/scans/tramp_freighter.png',
		"line_cruiser.png" = 'html/images/scans/line_cruiser.png',
		//planet scan images
		"exoplanet_empty.png" = 'html/images/scans/exoplanets/exoplanet_empty.png',
		"barren.png" = 'html/images/scans/exoplanets/barren.png',
		"lava.png" = 'html/images/scans/exoplanets/lava.png',
		"grove.png" = 'html/images/scans/exoplanets/grove.png',
		"desert.png" = 'html/images/scans/exoplanets/desert.png',
		"snow.png" = 'html/images/scans/exoplanets/snow.png',
		"adhomai.png" = 'html/images/scans/exoplanets/adhomai.png',
		"raskara.png" = 'html/images/scans/exoplanets/raskara.png',
		"comet.png" = 'html/images/scans/exoplanets/comet.png',
		"asteroid.png" = 'html/images/scans/exoplanets/asteroid.png',
		//end scan images
		"bluebird.woff" = 'html/fonts/OFL/Bluebird.woff',
		"grandhotel.woff" = 'html/fonts/OFL/GrandHotel.woff',
		"lashema.woff" = 'html/fonts/OFL/Lashema.woff',
		"sourcecodepro.woff" = 'html/fonts/OFL/SourceCodePro.woff',
		"sovjetbox.woff" = 'html/fonts/OFL/SovjetBox.woff',
		"torsha.woff" = 'html/fonts/OFL/Torsha.woff',
		"web3of9ascii.woff" = 'html/fonts/OFL/Web3Of9ASCII.woff',
		"zeshit.woff" = 'html/fonts/OFL/zeshit.woff',
		"bilboinc.woff" = 'html/fonts/OFL/BilboINC.woff',
		"fproject.woff" = 'html/fonts/OFL/FProject.woff',
		"gelasio.woff" = 'html/fonts/OFL/Gelasio.woff',
		"mo5v56.woff" = 'html/fonts/OFL/Mo5V56.woff',
		"runasans.woff" = 'html/fonts/OFL/RunaSans.woff',
		"classica.woff" = 'html/fonts/OFL/Classica.woff',
		"stormning.woff" = 'html/fonts/OFL/Stormning.woff',
		"copt-b.woff" = 'html/fonts/OFL/Copt-B.woff',
		"ducados.woff" = 'html/fonts/OFL/Ducados.woff',
		"kawkabmono.woff" = 'html/fonts/OFL/KawkabMono.woff',
		"kaushanscript.woff" = 'html/fonts/OFL/KaushanScript.woff'
	)

/datum/asset/simple/changelog
	legacy = TRUE
	assets = list(
		"changelog.css" = 'html/changelog.css',
		"changelog.js" = 'html/changelog.js'
	)

/datum/asset/simple/vueui
	legacy = TRUE
	assets = list(
		"vueui.js" = 'vueui/dist/app.js',
		"vueui.css" = 'vueui/dist/app.css'
	)

/datum/asset/spritesheet/goonchat
	name = "chat"

/datum/asset/spritesheet/goonchat/register()
	var/icon/I = icon('icons/accent_tags.dmi')
	for(var/path in subtypesof(/datum/accent))
		var/datum/accent/A = new path
		if(A.tag_icon)
			Insert(A.tag_icon, I, A.tag_icon)
	..()

/datum/asset/spritesheet/vending
	name = "vending"

/datum/asset/spritesheet/vending/register()
	var/vending_products = list()
	for(var/obj/machinery/vending/vendor as anything in typesof(/obj/machinery/vending))
		vendor = new vendor()
		for(var/each in list(vendor.products, vendor.contraband, vendor.premium))
			vending_products |= each
		qdel(vendor)

	for(var/path in vending_products)
		var/atom/item = path
		if(!ispath(item, /atom))
			continue

		var/icon_file = initial(item.icon)
		var/icon_state = initial(item.icon_state)

		#ifdef UNIT_TEST
		var/icon_states_list = icon_states(icon_file)
		if(!(icon_state in icon_states_list))
			var/icon_states_string
			for(var/s in icon_states_list)
				if(!icon_states_string)
					icon_states_string = "[json_encode(s)](\ref[s])"
				else
					icon_states_string += ", [json_encode(s)](\ref[s])"

			stack_trace("[item] has an invalid icon state, icon=[icon_file], icon_state=[json_encode(icon_state)](\ref[icon_state]), icon_states=[icon_states_string]")
			continue
		#endif

		var/icon/I = icon(icon_file, icon_state, SOUTH)
		var/c = initial(item.color)
		if(!isnull(c) && c != "#FFFFFF")
			I.Blend(c, ICON_MULTIPLY)

		var/imgid = ckey("[item]")
		item = new item()

		if(ispath(item, /obj/item/seeds))
			// thanks seeds for being overlays defined at runtime
			var/obj/item/seeds/S = item
			if(!S.seed && S.seed_type && !isnull(SSplants.seeds) && SSplants.seeds[S.seed_type])
				S.seed = SSplants.seeds[S.seed_type]
			I = S.update_appearance(TRUE)
			Insert(imgid, I, forced=I)
		else
			item.update_icon()
			if(item.overlay_queued)
				item.compile_overlays()
			if(item.overlays.len)
				I = getFlatIcon(item) // forgive me for my performance sins
				Insert(imgid, I, forced=I)
			else
				Insert(imgid, I)

		qdel(item)
	return ..()

/datum/asset/spritesheet/chem_master
	name = "chemmaster"
	var/list/bottle_sprites = list("bottle-1", "bottle-2", "bottle-3", "bottle-4", "bottle-5", "bottle-6")
	var/max_pill_sprite = 20

/datum/asset/spritesheet/chem_master/register()
	for (var/i = 1 to max_pill_sprite)
		Insert("pill[i]", 'icons/obj/chemical.dmi', "pill[i]")

	for (var/sprite in bottle_sprites)
		Insert(sprite, icon('icons/obj/chemical.dmi', sprite))
	return ..()

/// Namespace'ed assets (for static css and html files)
/// When sent over a cdn transport, all assets in the same asset datum will exist in the same folder, as their plain names.
/// Used to ensure css files can reference files by url() without having to generate the css at runtime, both the css file and the files it depends on must exist in the same namespace asset datum. (Also works for html)
/// For example `blah.css` with asset `blah.png` will get loaded as `namespaces/a3d..14f/f12..d3c.css` and `namespaces/a3d..14f/blah.png`. allowing the css file to load `blah.png` by a relative url rather then compute the generated url with get_url_mappings().
/// The namespace folder's name will change if any of the assets change. (excluding parent assets)
/datum/asset/simple/namespaced
	_abstract = /datum/asset/simple/namespaced
	/// parents - list of the parent asset or assets (in name = file assoicated format) for this namespace.
	/// parent assets must be referenced by their generated url, but if an update changes a parent asset, it won't change the namespace's identity.
	var/list/parents = list()

/datum/asset/simple/namespaced/register()
	if (legacy)
		assets |= parents
	var/list/hashlist = list()
	var/list/sorted_assets = sort_list(assets)

	for (var/asset_name in sorted_assets)
		var/datum/asset_cache_item/ACI = new(asset_name, sorted_assets[asset_name])
		if (!ACI?.hash)
			log_asset("ERROR: Invalid asset: [type]:[asset_name]:[ACI]")
			continue
		hashlist += ACI.hash
		sorted_assets[asset_name] = ACI
	var/namespace = md5(hashlist.Join())

	for (var/asset_name in parents)
		var/datum/asset_cache_item/ACI = new(asset_name, parents[asset_name])
		if (!ACI?.hash)
			log_asset("ERROR: Invalid asset: [type]:[asset_name]:[ACI]")
			continue
		ACI.namespace_parent = TRUE
		sorted_assets[asset_name] = ACI

	for (var/asset_name in sorted_assets)
		var/datum/asset_cache_item/ACI = sorted_assets[asset_name]
		if (!ACI?.hash)
			log_asset("ERROR: Invalid asset: [type]:[asset_name]:[ACI]")
			continue
		ACI.namespace = namespace

	assets = sorted_assets
	..()

/// Get a html string that will load a html asset.
/// Needed because byond doesn't allow you to browse() to a url.
/datum/asset/simple/namespaced/proc/get_htmlloader(filename)
	return url2htmlloader(SSassets.transport.get_asset_url(filename, assets[filename]))

/// Generate a filename for this asset
/// The same asset will always lead to the same asset name
/// (Generated names do not include file extention.)
/proc/generate_asset_name(file)
	return "asset.[md5(fcopy_rsc(file))]"
