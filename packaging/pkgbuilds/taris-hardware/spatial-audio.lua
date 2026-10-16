-- Copyright (C) 2026 George Dobreff ("Witcher") and contributors
-- SPDX-License-Identifier: GPL-3.0-only

-- TarisOS's spatial audio, run by WirePlumber (/usr/share/wireplumber/scripts/taris/, loaded by
-- 99-taris-spatial-audio.conf). The built-in speakers of the MacBooks get crosstalk cancellation
-- tuned to their spacing, which spreads the sound past the edges of the laptop; headphones (the
-- jack, Bluetooth, USB) get the two channels as two speakers in front of the listener (HRTF, with
-- the MIT KEMAR head libmysofa ships). Each graph runs in the output's own audioconvert, before
-- the output's processing: Asahi's speaker DSP, its volume (which its loudness compensation
-- follows) and the speakers' protection are left as they are, and no new output appears. The
-- speakers also always get a little more bass, whether spatial audio is on or off.
--
-- Spatial audio on or off (the Audio page of Settings), saved across restarts:
--   wpctl settings --save taris.spatial-audio true|false

log = Log.open_topic ("s-taris-spatial-audio")

local SETTING = "taris.spatial-audio"

-- The graphs' slots among the output's audioconvert graphs, the bass before the spatial audio;
-- WirePlumber's own filter-graph rules number theirs from 0
local BASS_KEY = "audioconvert.filter-graph.49"
local GRAPH_KEY = "audioconvert.filter-graph.50"

-- Asahi's speaker DSP of each MacBook TarisOS supports: how much later the far ear hears each
-- speaker (for the speakers' spacing, at 50 cm), and the frequency where the cancellation's first
-- dip falls, above which it's left out. Numbers stay strings: Lua's own formatting follows the
-- locale's decimal separator. The Mac mini and Mac Studio have one speaker: nothing to cancel.
local SPEAKERS = {
	["audio_effect.j293-convolver"] = { delay = "0.000122", top = "4000" }, -- MacBook Pro 13", M1
	["audio_effect.j493-convolver"] = { delay = "0.000122", top = "4000" }, -- MacBook Pro 13", M2
	["audio_effect.j313-convolver"] = { delay = "0.000108", top = "4600" }, -- MacBook Air 13", M1
	["audio_effect.j413-convolver"] = { delay = "0.000103", top = "4800" }, -- MacBook Air 13", M2
	["audio_effect.j415-convolver"] = { delay = "0.000122", top = "4000" }, -- MacBook Air 15", M2
	["audio_effect.j314-convolver"] = { delay = "0.000127", top = "3900" }, -- MacBook Pro 14", M1
	["audio_effect.j414-convolver"] = { delay = "0.000127", top = "3900" }, -- MacBook Pro 14", M2
	["audio_effect.j316-convolver"] = { delay = "0.000140", top = "3500" }, -- MacBook Pro 16", M1
	["audio_effect.j416-convolver"] = { delay = "0.000140", top = "3500" }, -- MacBook Pro 16", M2
}

-- The built-in headphone jack, the same on every model
local JACK = "alsa_output.platform-sound.HiFi__Headphones__sink"

-- Crosstalk cancellation (RACE) on the side channel (L - R) only: what's in the middle, voices
-- most of all, reaches both ears from both speakers anyway, so it stays as it is. The side channel
-- between 250 Hz and the first dip goes round a loop that adds it back delayed by the far ear's
-- delay, which cancels what each ear hears from the other speaker. 0.7 is how much of it returns
-- each time: more cancels more, and boosts the side channel's low end more.
local SPEAKER_GRAPH = [[
{
	nodes = [
		{ type = builtin label = copy name = inL }
		{ type = builtin label = copy name = inR }
		{ type = builtin label = mixer name = mid control = { "Gain 1" = 0.5 "Gain 2" = 0.5 } }
		{ type = builtin label = mixer name = side control = { "Gain 1" = 0.5 "Gain 2" = -0.5 } }
		{ type = builtin label = bq_highpass name = low control = { "Freq" = 250 "Q" = 0.707 } }
		{ type = builtin label = bq_lowpass name = high control = { "Freq" = @TOP@ "Q" = 0.707 } }
		{
			type = builtin label = delay name = cross
			config = { "max-delay" = 0.001 }
			control = { "Delay (s)" = @DELAY@ "Feedback" = 0.7 }
		}
		{ type = builtin label = mixer name = wide control = { "Gain 1" = 1.0 "Gain 2" = 0.7 } }
		{ type = builtin label = mixer name = outL control = { "Gain 1" = 1.0 "Gain 2" = 1.0 } }
		{ type = builtin label = mixer name = outR control = { "Gain 1" = 1.0 "Gain 2" = -1.0 } }
	]
	links = [
		{ output = "inL:Out" input = "mid:In 1" }
		{ output = "inR:Out" input = "mid:In 2" }
		{ output = "inL:Out" input = "side:In 1" }
		{ output = "inR:Out" input = "side:In 2" }
		{ output = "side:Out" input = "low:In" }
		{ output = "low:Out" input = "high:In" }
		{ output = "high:Out" input = "cross:In" }
		{ output = "side:Out" input = "wide:In 1" }
		{ output = "cross:Out" input = "wide:In 2" }
		{ output = "mid:Out" input = "outL:In 1" }
		{ output = "wide:Out" input = "outL:In 2" }
		{ output = "mid:Out" input = "outR:In 1" }
		{ output = "wide:Out" input = "outR:In 2" }
	]
	inputs = [ "inL:In" "inR:In" ]
	outputs = [ "outL:Out" "outR:Out" ]
}
]]

-- The speakers' bass: 3 dB more below 200 Hz, ahead of Asahi's bass enhancer and its limiters,
-- which keep the speakers within what they take
local BASS_GRAPH = [[
{
	nodes = [
		{ type = builtin label = bq_lowshelf name = bassL control = { "Freq" = 200 "Q" = 0.707 "Gain" = 3.0 } }
		{ type = builtin label = bq_lowshelf name = bassR control = { "Freq" = 200 "Q" = 0.707 "Gain" = 3.0 } }
	]
	inputs = [ "bassL:In" "bassR:In" ]
	outputs = [ "bassL:Out" "bassR:Out" ]
}
]]

-- Each channel as a speaker 30 degrees to its side, as stereo is meant to be heard. Both ears
-- hear both speakers, so each ear's sum is halved: the middle stays as loud as without it.
local HEADPHONE_GRAPH = [[
{
	nodes = [
		{
			type = sofa label = spatializer name = left
			config = { filename = "/usr/share/libmysofa/MIT_KEMAR_normal_pinna.sofa" normalize = true }
			control = { "Azimuth" = 30.0 "Elevation" = 0.0 "Radius" = 1.4 }
		}
		{
			type = sofa label = spatializer name = right
			config = { filename = "/usr/share/libmysofa/MIT_KEMAR_normal_pinna.sofa" normalize = true }
			control = { "Azimuth" = 330.0 "Elevation" = 0.0 "Radius" = 1.4 }
		}
		{ type = builtin label = mixer name = outL control = { "Gain 1" = 0.5 "Gain 2" = 0.5 } }
		{ type = builtin label = mixer name = outR control = { "Gain 1" = 0.5 "Gain 2" = 0.5 } }
	]
	links = [
		{ output = "left:Out L" input = "outL:In 1" }
		{ output = "right:Out L" input = "outL:In 2" }
		{ output = "left:Out R" input = "outR:In 1" }
		{ output = "right:Out R" input = "outR:In 2" }
	]
	inputs = [ "left:In" "right:In" ]
	outputs = [ "outL:Out" "outR:Out" ]
}
]]

-- Outputs that have the spatial graph now, and speakers that have the bass, by object id
local applied = {}
local bassApplied = {}

nodes_om = ObjectManager {
	Interest {
		type = "node",
		Constraint { "media.class", "=", "Audio/Sink", type = "pw-global" },
	},
}

devices_om = ObjectManager {
	Interest { type = "device" },
}

-- Headphones other than the jack: Bluetooth in its music profiles (not the mono call profile) and
-- USB, by the form factor their device reports. Bluetooth's nodes don't carry it, their device does.
local function isHeadphones (node)
	local props = node.properties
	if props["node.name"] == JACK then
		return true
	end
	if props["audio.channels"] ~= nil and props["audio.channels"] ~= "2" then
		return false
	end

	local formFactor = props["device.form-factor"]
	local profile = props["api.bluez5.profile"]
	if profile ~= nil then
		if profile ~= "a2dp-sink" and profile ~= "bap-sink" then
			return false
		end
		local deviceId = props["device.id"]
		local device = deviceId and devices_om:lookup {
			Constraint { "bound-id", "=", deviceId, type = "gobject" },
		}
		formFactor = device and device.properties["device.form-factor"]
	elseif props["api.alsa.path"] == nil then
		return false
	end

	return formFactor == "headphone" or formFactor == "headset"
end

local function graphFor (node)
	local speakers = SPEAKERS[node.properties["node.name"]]
	if speakers ~= nil then
		return (SPEAKER_GRAPH:gsub ("@DELAY@", speakers.delay):gsub ("@TOP@", speakers.top))
	end
	if isHeadphones (node) then
		return HEADPHONE_GRAPH
	end
	return nil
end

local function setGraph (node, key, graph)
	node:set_params ("Props", Pod.Object {
		"Spa:Pod:Object:Param:Props", "Props",
		params = Pod.Struct { key, graph or Pod.None () },
	})
end

-- Puts the spatial graph on an output, or takes it off, as the setting says; speakers get the
-- bass once
local function update (node)
	if SPEAKERS[node.properties["node.name"]] ~= nil and not bassApplied[node.id] then
		setGraph (node, BASS_KEY, BASS_GRAPH)
		bassApplied[node.id] = true
	end

	local graph = Settings.get_boolean (SETTING) and graphFor (node) or nil

	if graph ~= nil and not applied[node.id] then
		log:info (node, "spatial audio on " .. node.properties["node.name"])
		setGraph (node, GRAPH_KEY, graph)
		applied[node.id] = true
	elseif graph == nil and applied[node.id] then
		log:info (node, "spatial audio off " .. node.properties["node.name"])
		setGraph (node, GRAPH_KEY, nil)
		applied[node.id] = nil
	end
end

local function updateAll ()
	for node in nodes_om:iterate () do
		update (node)
	end
end

nodes_om:connect ("object-added", function (_, node)
	update (node)
end)

-- A removed node's proxy is no longer bound: keyed by its object id, as software-dsp.lua does
nodes_om:connect ("object-removed", function (_, node)
	applied[node.id] = nil
	bassApplied[node.id] = nil
end)

-- A Bluetooth device can show up after its nodes
devices_om:connect ("object-added", updateAll)

Settings.subscribe (SETTING, updateAll)

devices_om:activate ()
nodes_om:activate ()
