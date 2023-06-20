// These programs are associated with engineering.

/datum/computer_file/program/power_monitor
	filename = "powermonitor"
	filedesc = "Power Monitoring"
	nanomodule_path = /datum/nano_module/power_monitor
	program_icon_state = "power_monitor"
	program_key_icon_state = "yellow_key"
	extended_desc = "This program connects to sensors around the station to provide information about electrical systems"
	ui_header = "power_norm.gif"
	required_access_run = access_engine
	required_access_download = access_ce
	requires_ntnet = TRUE
	network_destination = "power monitoring system"
	usage_flags = PROGRAM_ALL
	size = 9
	var/has_alert = FALSE
	color = LIGHT_COLOR_ORANGE

/datum/computer_file/program/power_monitor/process_tick()
	..()
	var/datum/nano_module/power_monitor/NMA = NM
	if(istype(NMA) && NMA.has_alarm())
		if(!has_alert)
			program_icon_state = "power_monitor_warn"
			ui_header = "power_warn.gif"
			update_computer_icon()
			has_alert = TRUE
	else
		if(has_alert)
			program_icon_state = "power_monitor"
			ui_header = "power_norm.gif"
			update_computer_icon()
			has_alert = FALSE

/datum/computer_file/program/alarm_monitor
	filename = "alarmmonitor"
	filedesc = "Alarm Monitoring"
	program_key_icon_state = "cyan_key"
	nanomodule_path = /datum/nano_module/alarm_monitor/engineering
	ui_header = "alarm_green.gif"
	program_icon_state = "alert:0"
	extended_desc = "This program provides visual interface for station's alarm system."
	requires_ntnet = TRUE
	network_destination = "alarm monitoring network"
	usage_flags = PROGRAM_ALL
	size = 5
	var/has_alert = FALSE
	color = LIGHT_COLOR_CYAN

/datum/computer_file/program/alarm_monitor/process_tick()
	..()
	var/datum/nano_module/alarm_monitor/NMA = NM
	if(istype(NMA) && NMA.has_major_alarms())
		if(!has_alert)
			program_icon_state = "alert:2"
			ui_header = "alarm_red.gif"
			update_computer_icon()
			has_alert = TRUE
	else
		if(has_alert)
			program_icon_state = "alert:0"
			ui_header = "alarm_green.gif"
			update_computer_icon()
			has_alert = FALSE
	return TRUE

/datum/computer_file/program/atmos_control
	filename = "atmoscontrol"
	filedesc = "Atmosphere Control"
	program_icon_state = "atmos_control"
	program_key_icon_state = "cyan_key"
	extended_desc = "This program allows remote control of air alarms around the station. This program can not be run on tablet computers."
	requires_access_to_run = PROGRAM_ACCESS_LIST_ONE
	required_access_run =  list(access_atmospherics)
	required_access_download = list(access_atmospherics)
	requires_ntnet = TRUE
	network_destination = "atmospheric control system"
	requires_ntnet_feature = NTNET_SYSTEMCONTROL
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP | PROGRAM_STATIONBOUND
	size = 17
	color = LIGHT_COLOR_CYAN
	tgui_id = "AtmosAlarmControl"
	tgui_theme = "hephaestus"

	var/list/monitored_alarms = list()

/datum/computer_file/program/atmos_control/New(obj/item/modular_computer/comp, var/list/new_access, var/list/monitored_alarm_ids)
	..()

	if(islist(new_access) && length(new_access))
		required_access_run = new_access

	if(monitored_alarm_ids)
		for(var/obj/machinery/alarm/alarm in SSmachinery.processing)
			if(alarm.alarm_id && (alarm.alarm_id in monitored_alarm_ids) && AreConnectedZLevels(computer.z, alarm.z))
				monitored_alarms += alarm
	else
		for(var/obj/machinery/alarm/alarm in SSmachinery.processing)
			if(AreConnectedZLevels(computer.z, alarm.z))
				monitored_alarms += alarm
	// machines may not yet be ordered at this point
	sortTim(monitored_alarms, GLOBAL_PROC_REF(cmp_name_asc), FALSE)

/datum/computer_file/program/atmos_control/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return

	if(action == "alarm")
		var/obj/machinery/alarm/alarm = locate(params["alarm"]) in (monitored_alarms.len ? monitored_alarms : SSmachinery.processing)
		if(alarm)
			var/datum/ui_state/TS = generate_state(alarm)
			alarm.ui_interact(usr, state = TS) //what the fuck?
		return TRUE

/datum/computer_file/program/atmos_control/ui_data(mob/user)
	var/list/data = initial_data()

	var/alarms = list()
	for(var/obj/machinery/alarm/alarm in monitored_alarms)
		alarms += list(list(
			"name" = sanitize(alarm.name),
			"ref"= "\ref[alarm]",
			"danger" = max(alarm.danger_level, alarm.alarm_area.atmosalm)
		))
	data["alarms"] = alarms

	return data

/datum/computer_file/program/atmos_control/proc/generate_state(air_alarm)
	var/datum/ui_state/air_alarm/state = new()
	state.atmos_control = src
	state.air_alarm = air_alarm
	return state

/datum/ui_state/air_alarm
	var/datum/computer_file/program/atmos_control/atmos_control
	var/obj/machinery/alarm/air_alarm

/datum/ui_state/air_alarm/can_use_topic(var/src_object, var/mob/user)
	var/obj/item/card/id/I = user.GetIdCard()
	if(has_access(req_one_access = atmos_control.required_access_run, accesses = I.GetAccess()))
		return STATUS_INTERACTIVE
	return STATUS_UPDATE

/datum/ui_state/air_alarm/href_list(var/mob/user)
	var/list/extra_href = list()
	extra_href["remote_connection"] = TRUE
	extra_href["remote_access"] = can_access(user)

	return extra_href

/datum/ui_state/air_alarm/proc/can_access(var/mob/user)
	var/obj/item/card/id/I = user.GetIdCard()
	return user && (isAI(user) || has_access(req_one_access = atmos_control.required_access_run, accesses = I.GetAccess()) || atmos_control.computer_emagged || air_alarm.rcon_setting == RCON_YES || (air_alarm.alarm_area.atmosalm && air_alarm.rcon_setting == RCON_AUTO))

// Night-Mode Toggle for CE
/datum/computer_file/program/lighting_control
	filename = "lightctrl"
	filedesc = "Lighting Controller"
	nanomodule_path = /datum/nano_module/lighting_ctrl
	program_icon_state = "power_monitor"
	program_key_icon_state = "yellow_key"
	extended_desc = "This program allows mass-control of the station's lighting systems. This program cannot be run on tablet computers."
	required_access_run = access_heads
	required_access_download = access_ce
	requires_ntnet = TRUE
	network_destination = "APC Coordinator"
	requires_ntnet_feature = NTNET_SYSTEMCONTROL
	usage_flags = PROGRAM_CONSOLE | PROGRAM_STATIONBOUND
	size = 9
	color = LIGHT_COLOR_GREEN
	tgui_theme = "hephaestus"
