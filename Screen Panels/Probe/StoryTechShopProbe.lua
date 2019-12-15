------------------------------------------------------------------------------
-- Name:        StoryTechShopProbe
-- Author:      Daniel Story
-- License:  	MIT
------------------------------------------------------------------------------

local json = require "json"

local StoryTechShopProbe = {
	UI = {},
	internal = {
		Probes = {[31] = mc.ISIG_PROBE, [31.1] = mc.ISIG_PROBE1, [31.2] = mc.ISIG_PROBE2, [31.3] = mc.ISIG_PROBE3},
		Profiles = {}
	}
}

--- Initialize Probe Panel.
-- @param mcLuaPanel Container Mach4 lua panel for probe UI.
function StoryTechShopProbe.Initialize(mcLuaPanel)
	StoryTechShopProbe.internal.InitUI(mcLuaPanel)
	StoryTechShopProbe.internal.LoadSettings()
	StoryTechShopProbe.internal.ConnectUI()
end

--- Save Probe Profile.
-- @param name Name of profile.
-- @param probe Probe to use (31, 31.1, 31.2, 31.3).
-- @param unit Units to use for travel (20 [in], 21 [mm]).
-- @param probeMaxTravel Maximum travel while probing.
-- @param probeCycleFeedrate Feedrate for each probe cycle (unit/min), also defines number of probe cycles.
-- @param probeCycleRetract Distance to retract between each probe cycle.
-- @param probeHeight Probe height from bottom base to top surface, excluding corner finder rim.
-- @param probeHoleDepth Probe hole depth from top surface.
-- @param probeHoleX Distance between probe hole center to corner finder rim on X-axis.
-- @param probeHoleY Distance between probe hole center to corner finder rim on Y-axis.
-- @param probeRetract Distance to retract on Z-axis after successful probe.
function StoryTechShopProbe.SaveProfile(name, probe, unit, probeMaxTravel, probeCycleFeedrate, probeCycleRetract, probeHeight, probeHoleDepth, probeHoleX, probeHoleY, probeRetract)
	local profile = StoryTechShopProbe.internal.FindProfile(name)
	if profile == nil then
		profile = {Name = name}
		table.insert(StoryTechShopProbe.internal.Profiles, profile)
	end

	profile.Name = name
	profile.Probe = probe
	profile.Unit = unit
	profile.MaxTravel = probeMaxTravel
	profile.CycleFeedRate = probeCycleFeedrate
	profile.CycleRetract = probeCycleRetract
	profile.ProbeHeight = probeHeight
	profile.HoleDepth = probeHoleDepth
	profile.HoleXOrigin = probeHoleX
	profile.HoleYOrigin = probeHoleY
	profile.Retract = probeRetract

	StoryTechShopProbe.internal.SaveSettings()
end

--- Select a probe profile by name.
-- @name Probe profile name.
function StoryTechShopProbe.SelectProfile(name)
	local profileName, profileIndex = StoryTechShopProbe.internal.FindProfile(name)
	if profileName == nil then
		profileIndex = 1
	end

	StoryTechShopProbe.UI.chProbeProfile:SetSelection(profileIndex - 1)
	-- StoryTechShopProbe.UI.chProbeProfile:SetToolTip(profileName ~= nil and profileName or "")
end

function StoryTechShopProbe.ProbeZ()
	local profile = StoryTechShopProbe.internal.SelectedProfile()
	if profile == nil then
		StoryTechShopProbe.internal.Log("ERROR: No probe profile selected or was not found.")
		return false
	end

	StoryTechShopProbe.internal.Log("Probing Z-axis with %s (%s).", profile.Name, profile.Probe)
	StoryTechShopProbe.internal.PrepareMachineState(profile)

	local probeHeight, probeStrikeZ, fixtureOffsetZ, success = false
	if StoryTechShopProbe.internal.ProbeCycle("Z", -1, profile) and StoryTechShopProbe.internal.ProbeRetract("Z", profile.Retract, profile) then
		probeHeight = StoryTechShopProbe.internal.ConvertToUnit(profile.ProbeHeight, profile)
		probeStrikeZ = StoryTechShopProbe.internal.ProbeStrikePosition("Z")
		fixtureOffsetZ = probeStrikeZ - probeHeight
		success = true
	end

	StoryTechShopProbe.internal.RestoreMachineState()
	if success then
		StoryTechShopProbe.internal.Debug("Setting fixture Z-axis offset set to %.4f (probe strike at %.4f, probe height is %.4f).", fixtureOffsetZ, probeStrikeZ, probeHeight)
		if StoryTechShopProbe.internal.SetFixtureOffsets(nil, nil, fixtureOffsetZ) then
			StoryTechShopProbe.internal.Log("Probe successful, fixture offset set to Z%.4f.", fixtureOffsetZ)
		end
	end
end
function StoryTechShopProbe.ProbeXY()
	local profile = StoryTechShopProbe.internal.SelectedProfile()
	if profile == nil then
		StoryTechShopProbe.internal.Log("ERROR: No probe profile selected or was not found.")
		return false
	end

	StoryTechShopProbe.internal.Log("Probing X-axis and Y-axis with %s (%s).", profile.Name, profile.Probe)
	StoryTechShopProbe.internal.PrepareMachineState(profile)

	local probeHeight, probeStrikeXp, probeStrikeXn, probeStrikeYp, probeStrikeYn, fixtureOffsetX, fixtureOffsetY, success
	success = true

	if success and StoryTechShopProbe.internal.ProbeCycle("X", -1, profile) then
		probeStrikeXn = StoryTechShopProbe.internal.ProbeStrikePosition("X")
	else
		success = false
	end
	if success and StoryTechShopProbe.internal.ProbeCycle("X", 1, profile) then
		probeStrikeXp = StoryTechShopProbe.internal.ProbeStrikePosition("X")
	else
		success = false
	end
	if success and StoryTechShopProbe.internal.ProbeCycle("Y", -1, profile) then
		probeStrikeYn = StoryTechShopProbe.internal.ProbeStrikePosition("Y")
	else
		success = false
	end
	if success and StoryTechShopProbe.internal.ProbeCycle("Y", 1, profile) then
		probeStrikeYp = StoryTechShopProbe.internal.ProbeStrikePosition("Y")
	else
		success = false
	end

	if success and StoryTechShopProbe.internal.ProbeRetract("Z", profile.Retract, profile) then
		local holeXOrigin = StoryTechShopProbe.internal.ConvertToUnit(profile.HoleXOrigin, profile)
		local holeYOrigin = StoryTechShopProbe.internal.ConvertToUnit(profile.HoleYOrigin, profile)

		fixtureOffsetX = probeStrikeXp - ((probeStrikeXp - probeStrikeXn) / 2) - holeXOrigin
		fixtureOffsetY = probeStrikeYp - ((probeStrikeYp - probeStrikeYn) / 2) - holeYOrigin
	else
		success = false
	end

	StoryTechShopProbe.internal.RestoreMachineState()
	if success then
		StoryTechShopProbe.internal.Debug("Setting fixture X-axis offset set to %.4f and Y-axis offset set to %.4f.", fixtureOffsetX, fixtureOffsetY)
		if StoryTechShopProbe.internal.SetFixtureOffsets(fixtureOffsetX, fixtureOffsetY, nil) then
			StoryTechShopProbe.internal.Log("Probe successful, fixture offset set to X%.4f Y%.4f.", fixtureOffsetX, fixtureOffsetY)
		end
	end
end
function StoryTechShopProbe.ProbeZXY()
	local profile = StoryTechShopProbe.internal.SelectedProfile()
	if profile == nil then
		StoryTechShopProbe.internal.Log("ERROR: No probe profile selected or was not found.")
		return false
	end

	StoryTechShopProbe.internal.Log("Probing X-axis and Y-axis with %s (%s).", profile.Name, profile.Probe)
	StoryTechShopProbe.internal.PrepareMachineState(profile)

	local probeHeight, probeStrikeZ, probeStrikeXp, probeStrikeXn, probeStrikeYp, probeStrikeYn, fixtureOffsetZ, fixtureOffsetX, fixtureOffsetY, success
	success = true

	if success and StoryTechShopProbe.internal.ProbeCycle("Z", -1, profile) then
		probeStrikeZ = StoryTechShopProbe.internal.ProbeStrikePosition("Z")
	else
		success = false
	end
	if success and StoryTechShopProbe.internal.ProbeCycle("X", -1, profile) then
		probeStrikeXn = StoryTechShopProbe.internal.ProbeStrikePosition("X")
	else
		success = false
	end
	if success and StoryTechShopProbe.internal.ProbeCycle("X", 1, profile) then
		probeStrikeXp = StoryTechShopProbe.internal.ProbeStrikePosition("X")
	else
		success = false
	end
	if success and StoryTechShopProbe.internal.ProbeCycle("Y", -1, profile) then
		probeStrikeYn = StoryTechShopProbe.internal.ProbeStrikePosition("Y")
	else
		success = false
	end
	if success and StoryTechShopProbe.internal.ProbeCycle("Y", 1, profile) then
		probeStrikeYp = StoryTechShopProbe.internal.ProbeStrikePosition("Y")
	else
		success = false
	end

	if success and StoryTechShopProbe.internal.ProbeRetract("Z", profile.Retract, profile) then
		probeHeight = StoryTechShopProbe.internal.ConvertToUnit(profile.ProbeHeight, profile)
		local probeHoleDepth = StoryTechShopProbe.internal.ConvertToUnit(profile.HoleDepth, profile)
		local holeXOrigin = StoryTechShopProbe.internal.ConvertToUnit(profile.HoleXOrigin, profile)
		local holeYOrigin = StoryTechShopProbe.internal.ConvertToUnit(profile.HoleYOrigin, profile)

		fixtureOffsetZ = probeStrikeZ - (probeHeight - probeHoleDepth)
		fixtureOffsetX = probeStrikeXp - ((probeStrikeXp - probeStrikeXn) / 2) - holeXOrigin
		fixtureOffsetY = probeStrikeYp - ((probeStrikeYp - probeStrikeYn) / 2) - holeYOrigin
	else
		success = false
	end

	StoryTechShopProbe.internal.RestoreMachineState()
	if success then
		StoryTechShopProbe.internal.Debug(
			"Setting fixture X-axis offset set to %.4f, Y-axis offset set to %.4f and Z-axis offset set to %.4f.",
			fixtureOffsetX,
			fixtureOffsetY,
			fixtureOffsetZ
		)
		if StoryTechShopProbe.internal.SetFixtureOffsets(fixtureOffsetX, fixtureOffsetY, fixtureOffsetZ) then
			StoryTechShopProbe.internal.Log("Probe successful, fixture offset set to X%.4f Y%.4f Z%.4f.", fixtureOffsetX, fixtureOffsetY, fixtureOffsetZ)
		end
	end
end

function StoryTechShopProbe.internal.ExecuteGCode(gCode)
	local inst = mc.mcGetInstance()
	StoryTechShopProbe.internal.Debug("Executing GCode %q.", gCode)

	local rc = mc.MERROR_NOERROR
	if StoryTechShopProbe.internal.co ~= nil then
		rc = mc.mcCntlGcodeExecute(inst, gCode)
		coroutine.yield(rc)
	else
		rc = mc.mcCntlGcodeExecuteWait(inst, gCode)
	end

	return rc
end

function StoryTechShopProbe.internal.PrepareMachineState(profile)
	local inst = mc.mcGetInstance()
	mc.mcCntlMachineStatePush(inst)

	-- Set to positioning mode to Incremental
	StoryTechShopProbe.internal.Debug("Setting machine state to G91 and G%d.", profile.Unit)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, 91)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_6, profile.Unit)
end

function StoryTechShopProbe.internal.RestoreMachineState(profile)
	local inst = mc.mcGetInstance()
	StoryTechShopProbe.internal.Debug("Restoring machine state.", gCode)
	mc.mcCntlMachineStatePop(inst)
end

function StoryTechShopProbe.internal.ProbeCycle(axis, direction, profile)
	StoryTechShopProbe.internal.Debug("Starting probe cycle on %s-axis in direction %d.", axis, direction)
	-- Run probe through cycles
	for i, feedrate in ipairs(profile.CycleFeedRate) do
		StoryTechShopProbe.internal.Debug("Probe cycle #%d, feedrate %.4f.", i, feedrate)
		if not StoryTechShopProbe.internal.ProbeAxis(axis, direction, feedrate, profile) then
			return false
		end
	end
	return true
end

function StoryTechShopProbe.internal.ProbeAxis(axis, direction, feedrate, profile)
	local inst = mc.mcGetInstance()
	StoryTechShopProbe.internal.Debug("Probing %s-axis in %d direction.", axis, direction)
	local distance = profile.MaxTravel * direction
	local rc = StoryTechShopProbe.internal.ExecuteGCode(string.format("G%.1f %s%.4f F%.1f", profile.Probe, axis, distance, feedrate))
	if rc ~= mc.MERROR_NOERROR then
		StoryTechShopProbe.internal.Log("ERROR: Failed to probe %s-axis.", axis)
		return false
	end
	local probeStrike, rc = mc.mcCntlProbeGetStrikeStatus(inst)
	if rc ~= mc.MERROR_NOERROR or probeStrike ~= 1 then
		StoryTechShopProbe.internal.Log("ERROR: Failed to strike probe on %s-axis.", axis)
		return false
	end
	distance = profile.CycleRetract * direction * -1
	return StoryTechShopProbe.internal.ProbeRetract(axis, distance, profile)
end

function StoryTechShopProbe.internal.ProbeRetract(axis, distance, profile)
	local inst = mc.mcGetInstance()

	StoryTechShopProbe.internal.Debug("Retracting %s-axis by %.4f.", axis, distance)
	local rc = StoryTechShopProbe.internal.ExecuteGCode(string.format("G0 %s%.4f", axis, distance))
	if rc ~= mc.MERROR_NOERROR then
		StoryTechShopProbe.internal.Log("ERROR: Failed to retract %s-axis.", axis)
		return false
	end
	local probeHandle = mc.mcSignalGetHandle(inst, StoryTechShopProbe.internal.Probes[profile.Probe])
	if mc.mcSignalGetState(probeHandle) == 1 then
		StoryTechShopProbe.internal.Log("ERROR: Failed to retract %s-axis, probe is still in contact.", axis)
		return false
	end
	return true
end

function StoryTechShopProbe.internal.ProbeStrikePosition(axis)
	local inst = mc.mcGetInstance()
	local value = nil
	if (axis == "X") then
		value, rc = mc.mcAxisGetProbePos(inst, mc.X_AXIS, 1)
	elseif (axis == "Y") then
		value, rc = mc.mcAxisGetProbePos(inst, mc.Y_AXIS, 1)
	elseif (axis == "Z") then
		value, rc = mc.mcAxisGetProbePos(inst, mc.Z_AXIS, 1)
	end
	return value
end

function StoryTechShopProbe.internal.ConvertToUnit(units, profile)
	local inst = mc.mcGetInstance()
	local defaultUnit = mc.mcCntlGetUnitsDefault(inst)

	if (defaultUnit == 20 or defaultUnit == 200) and profile.Unit == 21 then
		-- convert mm to in
		return units / 25.4
	elseif (defaultUnit == 21 or defaultUnit == 210) and profile.Unit == 20 then
		-- convert in to mm
		return units * 25.4
	end
	return units
end

function StoryTechShopProbe.internal.TruncateNumber(num, dec)
	return tonumber(string.format("%." .. dec .. "f", num))
end

function StoryTechShopProbe.internal.SetFixtureOffsets(offsetX, offsetY, offsetZ)
	local inst = mc.mcGetInstance()

	local varX, varY, varZ, fixtureNumber, currentFixture = StoryTechShopProbe.internal.GetFixOffsetVars()

	local success = true
	if success and (offsetX ~= nil) then
		local rc = mc.mcCntlSetPoundVar(inst, varX, offsetX)
		if rc ~= mc.MERROR_NOERROR then
			StoryTechShopProbe.internal.Log("ERROR: Failed to set fixture X-axis offset to %.4f.", offsetX)
			success = false
		end
	end
	if success and (offsetY ~= nil) then
		local rc = mc.mcCntlSetPoundVar(inst, varY, offsetY)
		if rc ~= mc.MERROR_NOERROR then
			StoryTechShopProbe.internal.Log("ERROR: Failed to set fixture Y-axis offset to %.4f.", offsetY)
			success = false
		end
	end
	if success and (offsetZ ~= nil) then
		local rc = mc.mcCntlSetPoundVar(inst, varZ, offsetZ)
		if rc ~= mc.MERROR_NOERROR then
			StoryTechShopProbe.internal.Log("ERROR: Failed to set fixture Z-axis offset to %.4f.", offsetZ)
			success = false
		end
	end

	return success
end

--- Find probe profile by name
-- @return Profile,index
function StoryTechShopProbe.internal.FindProfile(name)
	if name ~= nil and name ~= "" then
		for i, profile in ipairs(StoryTechShopProbe.internal.Profiles) do
			if profile.Name == name then
				return profile, i
			end
		end
	end

	return nil
end

--- Get UI selected probe profile
-- @return Profile,index
function StoryTechShopProbe.internal.SelectedProfile()
	local profileIndex = StoryTechShopProbe.UI.chProbeProfile:GetSelection() + 1

	if profileIndex > 0 then
		return StoryTechShopProbe.internal.Profiles[profileIndex], profileIndex
	end
	return nil
end

--- Load settings
function StoryTechShopProbe.internal.LoadSettings()
	local inst = mc.mcGetInstance()

	local machDir, rc = mc.mcCntlGetMachDir(inst)
	if rc ~= mc.MERROR_NOERROR then
		StoryTechShopProbe.internal.Log("Failed to load StoryTechShop Probe settings")
		return
	end
	local settingsFile = machDir .. "/StoryTechShop.Probe.json"
	local settingsJson = StoryTechShopProbe.internal.ReadFile(settingsFile)

	local settings = {Profiles = {}, SelectedProfile = ""}
	if settingsJson ~= nil and settingsJson ~= "" then
		settings = json.decode(settingsJson)
	end

	if StoryTechShopProbe.internal.Length(settings.Profiles) < 1 then
		-- Create a default profile.
		StoryTechShopProbe.SaveProfile(
			"Beaver CNC Zero2 Probe",
			31,
			21, -- Probe G31, Unit 21 (mm)
			20, -- 20mm max probe travel
			{100.0, 50.0},
			3.0, -- 2 probe cycles: 100mm/min and 50mm/min, 3mm cycle retract
			22.0,
			10.0,
			30.0,
			30.0, -- 22mm probe height, 10mm hole depth, 30x30mm to hole center from corner
			40.00 -- 40mm retract after successful probe
		)
		return
	end

	StoryTechShopProbe.internal.Profiles = settings.Profiles

	StoryTechShopProbe.internal.RefreshUI(settings.SelectedProfile)
end

--- Save settings
function StoryTechShopProbe.internal.SaveSettings()
	local inst = mc.mcGetInstance()

	local machDir, rc = mc.mcCntlGetMachDir(inst)
	if rc ~= mc.MERROR_NOERROR then
		StoryTechShopProbe.internal.Log("Failed to save StoryTechShop Probe settings")
		return
	end
	local settingsFile = machDir .. "/StoryTechShop.Probe.json"

	local selectedProfile = StoryTechShopProbe.internal.SelectedProfile()
	if selectedProfile ~= nil then
		selectedProfile = selectedProfile.Name or ""
	else
		selectedProfile = ""
	end

	local settingsJson =
		json.encode(
		{
			Profiles = StoryTechShopProbe.internal.Profiles or {},
			SelectedProfile = selectedProfile
		}
	)
	StoryTechShopProbe.internal.WriteFile(settingsFile, settingsJson)

	StoryTechShopProbe.internal.RefreshUI(selectedProfile)
end

function StoryTechShopProbe.internal.ParseDelimitedNumbers(s)
	local result = {}
	for match in string.gmatch(s, "([^,]+)") do
		table.insert(result, tonumber(match))
	end
	return result
end

function StoryTechShopProbe.internal.ToDelimitedNumbers(table)
	local result = ""
	for i, num in ipairs(table) do
		local value = tostring(num)
		if result ~= "" then
			result = result .. "," .. value
		else
			result = value
		end
	end
	return result
end

function StoryTechShopProbe.internal.RefreshUI(selectedProfileName)
	local inst = mc.mcGetInstance()

	StoryTechShopProbe.UI.chProbeProfile:Clear()
	local count = 0
	for i, profile in ipairs(StoryTechShopProbe.internal.Profiles) do
		count = count + 1
		StoryTechShopProbe.UI.chProbeProfile:Append(profile.Name)
	end

	StoryTechShopProbe.SelectProfile(selectedProfileName)
end

function StoryTechShopProbe.internal.UpdateUI()
	local inst = mc.mcGetInstance()
	local mcState, rc = mc.mcCntlGetState(inst)
	local co = StoryTechShopProbe.internal.co

	if co ~= nil and mcState == 0 then
		local state = coroutine.status(co)

		if state == "suspended" then
			local coerrorcheck, rc = coroutine.resume(co)
			if coerrorcheck == false or rc ~= mc.MERROR_NOERROR then
				co = nil
			end
		elseif state == "dead" then
			co = nil
		end

		StoryTechShopProbe.internal.co = co
	end

	local enabled = co == nil and mcState == 0
	StoryTechShopProbe.UI.chProbeProfile:Enable(enabled)
	StoryTechShopProbe.UI.btnProbeEdit:Enable(enabled)
	StoryTechShopProbe.UI.btnProbeEdit:Enable(enabled)

	local profile = StoryTechShopProbe.internal.SelectedProfile()
	StoryTechShopProbe.UI.btnProbeOpZ:Enable(enabled and profile ~= nil)
	StoryTechShopProbe.UI.btnProbeOpXY:Enable(enabled and profile ~= nil)
	StoryTechShopProbe.UI.btnProbeOpZXY:Enable(enabled and profile ~= nil)
end

function StoryTechShopProbe.internal.ConnectUI()
	StoryTechShopProbe.UI.chProbeProfile:Connect(
		wx.wxEVT_COMMAND_CHOICE_SELECTED,
		function(event)
			index = event:GetSelection()
			profileName = StoryTechShopProbe.UI.chProbeProfile:GetString(index)

			StoryTechShopProbe.SelectProfile(profileName)

			event:Skip()
		end
	)

	StoryTechShopProbe.UI.Panel:Connect(
		wx.wxEVT_UPDATE_UI,
		function(event)
			StoryTechShopProbe.internal.UpdateUI()
			event:Skip()
		end
	)

	StoryTechShopProbe.UI.btnProbeOpZ:Connect(
		wx.wxEVT_COMMAND_BUTTON_CLICKED,
		function(event)
			StoryTechShopProbe.internal.co = coroutine.create(StoryTechShopProbe.ProbeZ)
			-- StoryTechShopProbe.ProbeZ()
			event:Skip()
		end
	)

	StoryTechShopProbe.UI.btnProbeOpXY:Connect(
		wx.wxEVT_COMMAND_BUTTON_CLICKED,
		function(event)
			StoryTechShopProbe.internal.co = coroutine.create(StoryTechShopProbe.ProbeXY)
			-- StoryTechShopProbe.ProbeXY()
			event:Skip()
		end
	)

	StoryTechShopProbe.UI.btnProbeOpZXY:Connect(
		wx.wxEVT_COMMAND_BUTTON_CLICKED,
		function(event)
			StoryTechShopProbe.internal.co = coroutine.create(StoryTechShopProbe.ProbeZXY)
			-- StoryTechShopProbe.ProbeZXY()
			event:Skip()
		end
	)
end

function StoryTechShopProbe.internal.Log(message, ...)
	local eventMessage = string.format(message, table.unpack({...}))
	if mc.mcInEditor() == 1 then
		print(eventMessage)
	end
	mc.mcCntlSetLastError(mc.mcGetInstance(), eventMessage)
end

function StoryTechShopProbe.internal.Debug(message, ...)
	local eventMessage = string.format(message, table.unpack({...}))
	if mc.mcInEditor() == 1 then
		print(eventMessage)
	end
	mc.mcCntlSetLastError(mc.mcGetInstance(), eventMessage)
end

function StoryTechShopProbe.internal.Length(table)
	local count = 0
	for _ in pairs(table) do
		count = count + 1
	end
	return count
end

function StoryTechShopProbe.internal.ReadFile(filename)
	local f = io.open(filename, "r")
	if f == nil then
		return nil
	end
	local content = f.read(f, "*a")
	f.close()
	return content
end

function StoryTechShopProbe.internal.WriteFile(filename, content)
	local f = io.open(filename, "w")
	f.write(f, content)
	f.close()
end

function StoryTechShopProbe.internal.InitUI(mcLuaPanel)
	if mcLuaPanel == nil then
		-- wx.wxPanel (wx.NULL, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxTAB_TRAVERSAL )
		StoryTechShopProbe.UI.Panel =
			wx.wxDialog(wx.NULL, wx.wxID_ANY, "StoryTechShop Probe", wx.wxDefaultPosition, wx.wxSize(900, 530), wx.wxCAPTION + wx.wxCLOSE_BOX + wx.wxRESIZE_BORDER)
	else
		StoryTechShopProbe.UI.Panel = mcLuaPanel
	end

	StoryTechShopProbe.UI.fgCtnrProbe = wx.wxFlexGridSizer(2, 1, 0, 0)
	StoryTechShopProbe.UI.fgCtnrProbe:AddGrowableCol(0)
	StoryTechShopProbe.UI.fgCtnrProbe:AddGrowableRow(1)
	StoryTechShopProbe.UI.fgCtnrProbe:SetFlexibleDirection(wx.wxBOTH)
	StoryTechShopProbe.UI.fgCtnrProbe:SetNonFlexibleGrowMode(wx.wxFLEX_GROWMODE_SPECIFIED)

	StoryTechShopProbe.UI.fgCntrProbeProfile = wx.wxFlexGridSizer(0, 2, 0, 0)
	StoryTechShopProbe.UI.fgCntrProbeProfile:AddGrowableCol(0)
	StoryTechShopProbe.UI.fgCntrProbeProfile:SetFlexibleDirection(wx.wxBOTH)
	StoryTechShopProbe.UI.fgCntrProbeProfile:SetNonFlexibleGrowMode(wx.wxFLEX_GROWMODE_SPECIFIED)

	StoryTechShopProbe.UI.chProbeProfileChoices = {}
	StoryTechShopProbe.UI.chProbeProfile =
		wx.wxChoice(StoryTechShopProbe.UI.Panel, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, StoryTechShopProbe.UI.chProbeProfileChoices, 0)
	StoryTechShopProbe.UI.chProbeProfile:SetSelection(0)
	StoryTechShopProbe.UI.fgCntrProbeProfile:Add(StoryTechShopProbe.UI.chProbeProfile, 0, wx.wxALL + wx.wxEXPAND, 5)

	StoryTechShopProbe.UI.btnProbeEdit = wx.wxButton(StoryTechShopProbe.UI.Panel, wx.wxID_ANY, "...", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxBU_EXACTFIT)
	StoryTechShopProbe.UI.btnProbeEdit:SetToolTip("Edit probe profiles.")

	StoryTechShopProbe.UI.fgCntrProbeProfile:Add(StoryTechShopProbe.UI.btnProbeEdit, 0, wx.wxALL, 5)

	StoryTechShopProbe.UI.fgCtnrProbe:Add(StoryTechShopProbe.UI.fgCntrProbeProfile, 1, wx.wxEXPAND, 5)

	StoryTechShopProbe.UI.fgCntrProbeOps = wx.wxFlexGridSizer(0, 3, 0, 0)
	StoryTechShopProbe.UI.fgCntrProbeOps:AddGrowableCol(0)
	StoryTechShopProbe.UI.fgCntrProbeOps:AddGrowableCol(1)
	StoryTechShopProbe.UI.fgCntrProbeOps:AddGrowableCol(2)
	StoryTechShopProbe.UI.fgCntrProbeOps:SetFlexibleDirection(wx.wxBOTH)
	StoryTechShopProbe.UI.fgCntrProbeOps:SetNonFlexibleGrowMode(wx.wxFLEX_GROWMODE_NONE)

	StoryTechShopProbe.UI.btnProbeOpZ = wx.wxButton(StoryTechShopProbe.UI.Panel, wx.wxID_ANY, "Probe Z", wx.wxDefaultPosition, wx.wxDefaultSize, 0)
	StoryTechShopProbe.UI.btnProbeOpZ:SetToolTip("Probe top surface for Z-axis fixture offset.")

	StoryTechShopProbe.UI.fgCntrProbeOps:Add(StoryTechShopProbe.UI.btnProbeOpZ, 0, wx.wxALIGN_CENTER + wx.wxALL, 5)

	StoryTechShopProbe.UI.btnProbeOpXY = wx.wxButton(StoryTechShopProbe.UI.Panel, wx.wxID_ANY, "Probe XY", wx.wxDefaultPosition, wx.wxDefaultSize, 0)
	StoryTechShopProbe.UI.btnProbeOpXY:SetToolTip("Probe inside hole for X-axis and Y-axis fixture offsets.")

	StoryTechShopProbe.UI.fgCntrProbeOps:Add(StoryTechShopProbe.UI.btnProbeOpXY, 0, wx.wxALIGN_CENTER + wx.wxALL, 5)

	StoryTechShopProbe.UI.btnProbeOpZXY = wx.wxButton(StoryTechShopProbe.UI.Panel, wx.wxID_ANY, "Probe ZXY", wx.wxDefaultPosition, wx.wxDefaultSize, 0)
	StoryTechShopProbe.UI.btnProbeOpZXY:SetToolTip("Probe inside hole for Z-axis, X-axis, and Y-axis fixture offsets.")

	StoryTechShopProbe.UI.fgCntrProbeOps:Add(StoryTechShopProbe.UI.btnProbeOpZXY, 0, wx.wxALIGN_CENTER + wx.wxALL, 5)

	StoryTechShopProbe.UI.fgCtnrProbe:Add(StoryTechShopProbe.UI.fgCntrProbeOps, 1, wx.wxEXPAND, 5)

	StoryTechShopProbe.UI.Panel:SetSizer(StoryTechShopProbe.UI.fgCtnrProbe)
	StoryTechShopProbe.UI.Panel:Layout()
end

---------------------------------------------------------------
-- Sourced from Screen Set load script
-- Get fixtue offset pound variables function Updated 5-16-16
---------------------------------------------------------------
function StoryTechShopProbe.internal.GetFixOffsetVars()
	local inst = mc.mcGetInstance()

	local FixOffset = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_14)
	local Pval = mc.mcCntlGetPoundVar(inst, mc.SV_BUFP)
	local FixNum, whole, frac
	local PoundVarX, PoundVarY, PoundVarZ, CurrentFixture

	if (FixOffset ~= 54.1) then --G54 through G59
		whole, frac = math.modf(FixOffset)
		FixNum = (whole - 53)
		PoundVarX = ((mc.SV_FIXTURES_START - mc.SV_FIXTURES_INC) + (FixNum * mc.SV_FIXTURES_INC))
		CurrentFixture = string.format("G" .. tostring(FixOffset))
	else --G54.1 P1 through G54.1 P100
		FixNum = (Pval + 6)
		CurrentFixture = string.format("G54.1 P" .. tostring(Pval))
		if (Pval > 0) and (Pval < 51) then -- G54.1 P1 through G54.1 P50
			PoundVarX = ((mc.SV_FIXTURE_EXPAND - mc.SV_FIXTURES_INC) + (Pval * mc.SV_FIXTURES_INC))
		elseif (Pval > 50) and (Pval < 101) then -- G54.1 P51 through G54.1 P100
			PoundVarX = ((mc.SV_FIXTURE_EXPAND2 - mc.SV_FIXTURES_INC) + (Pval * mc.SV_FIXTURES_INC))
		end
	end
	PoundVarY = (PoundVarX + 1)
	PoundVarZ = (PoundVarX + 2)
	return PoundVarX, PoundVarY, PoundVarZ, FixNum, CurrentFixture
	--PoundVar(Axis) returns the pound variable for the current fixture for that axis (not the pound variables value).
	--CurretnFixture returned as a string (examples G54, G59, G54.1 P12).
	--FixNum returns a simple number (1-106) for current fixture (examples G54 = 1, G59 = 6, G54.1 P1 = 7, etc).
end

if mc.mcInEditor() == 1 then
	StoryTechShopProbe.Initialize()
	StoryTechShopProbe.UI.Panel:ShowModal()
end

return StoryTechShopProbe
