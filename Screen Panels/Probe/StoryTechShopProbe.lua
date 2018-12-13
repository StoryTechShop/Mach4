------------------------------------------------------------------------------
-- Name:        StoryTechShopProbe
-- Author:      Daniel Story
-- License:  	MIT
------------------------------------------------------------------------------

local StoryTechShopProbe = {
	UI = {},
	internal = {
		Probes = { [31] = mc.ISIG_PROBE, [31.1] = mc.ISIG_PROBE1, [31.2] = mc.ISIG_PROBE2, [31.3] = mc.ISIG_PROBE3 },
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
function StoryTechShopProbe.SaveProfile(
		name,
		probe, unit,
		probeMaxTravel,
		probeCycleFeedrate, probeCycleRetract,
		probeHeight, probeHoleDepth, probeHoleX, probeHoleY,
		probeRetract
	)
	
	profile = StoryTechShopProbe.internal.FindProfile(name)
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
	profile, profileIndex = StoryTechShopProbe.internal.FindProfile(name)
	
	StoryTechShopProbe.UI.chProbeProfile:SetSelection(profileIndex-1)
	StoryTechShopProbe.UI.chProbeProfile:SetToolTip(profileName ~= nil and profileName or "")
end

function StoryTechShopProbe.ProbeZ()
	inst = mc.mcGetInstance()
	
	profile = StoryTechShopProbe.internal.SelectedProfile()
	if profile == nil then
		StoryTechShopProbe.internal.Log("ERROR: No probe profile selected or was not found.")
		return false
	end
	
	StoryTechShopProbe.internal.Log("Probing Z-axis with %s.", profile.Name)
	StoryTechShopProbe.internal.PrepareMachineState(profile)
	
	if StoryTechShopProbe.internal.ProbeCycle('Z', -1, profile) and
		StoryTechShopProbe.internal.ProbeRetract('Z', profile.Retract, profile)
	then
		fixtureOffsetZ = StoryTechShopProbe.internal.ProbeStrikePosition('Z')
		fixtureOffsetZ = fixtureOffsetZ - StoryTechShopProbe.internal.ConvertToUnit(profile.ProbeHeight, profile)
		
		StoryTechShopProbe.internal.Debug("Setting fixture Z-axis offset set to %.4f.", fixtureOffsetZ)
		rc = mc.mcAxisSetMachinePos(inst, mc.Z_AXIS, fixtureOffsetZ)
		StoryTechShopProbe.internal.Log("Probe was successful, fixutre Z-axis offset set to %.4f.", fixtureOffsetZ)
	end
	
	StoryTechShopProbe.internal.RestoreMachineState()
end
function StoryTechShopProbe.ProbeXY()

end
function StoryTechShopProbe.ProbeZXY()

end

function StoryTechShopProbe.internal.ExecuteGCode(gCode)
	inst = mc.mcGetInstance()
	StoryTechShopProbe.internal.Debug("Executing GCode %q.", gCode)
	
	rc = mc.MERROR_NOERROR
	if StoryTechShopProbe.internal.co ~= nil then
		rc = mc.mcCntlGcodeExecute(inst, gCode)
		coroutine.yield(rc)
	else
		rc = mc.mcCntlGcodeExecuteWait(inst, gCode)
	end
	
	return rc
end

function StoryTechShopProbe.internal.PrepareMachineState(profile)
	inst = mc.mcGetInstance()
	mc.mcCntlMachineStatePush(inst)
	
	-- Set to positioning mode to Incremental
	StoryTechShopProbe.internal.Debug("Setting machine state to G91 and G%d.", profile.Unit)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, 91)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_6, profile.Unit)
end

function StoryTechShopProbe.internal.RestoreMachineState(profile)
	inst = mc.mcGetInstance()
	StoryTechShopProbe.internal.Debug("Restoring machine state.", gCode)
	mc.mcCntlMachineStatePop(inst)
end

function StoryTechShopProbe.internal.ProbeCycle(axis, direction, profile)
	StoryTechShopProbe.internal.Debug("Starting probe cycle on %s-axis in direction %d.", axis, direction)
	-- Run probe through cycles
	for i,feedrate in ipairs(profile.CycleFeedRate) do
		StoryTechShopProbe.internal.Debug("Probe cycle #%d, feedrate %.4f.", i, feedrate)
		if not StoryTechShopProbe.internal.ProbeAxis(axis, direction, feedrate, profile) then
			return false
		end
	end
	return true
end

function StoryTechShopProbe.internal.ProbeAxis(axis, direction, feedrate, profile)
	inst = mc.mcGetInstance()
	-- Probe Z
	distance = profile.MaxTravel*direction
	rc = StoryTechShopProbe.internal.ExecuteGCode(string.format("G%.1f %s%.4f F%.1f", profile.Probe, axis, distance, feedrate))
	if rc ~= mc.MERROR_NOERROR then
		StoryTechShopProbe.internal.Log("ERROR: Failed to probe %s-axis.", axis)
		return false
	end
	probeStrike, rc = mc.mcCntlProbeGetStrikeStatus(inst)
	if rc ~= mc.MERROR_NOERROR or probeStrike ~= 1 then
		StoryTechShopProbe.internal.Log("ERROR: Failed to strike probe on %s-axis.", axis)
		return false
	end
	distance = profile.CycleRetract*direction*-1
	return StoryTechShopProbe.internal.ProbeRetract(axis, distance, profile)
end

function StoryTechShopProbe.internal.ProbeRetract(axis, distance, profile)
	inst = mc.mcGetInstance()
	
	rc = StoryTechShopProbe.internal.ExecuteGCode(inst, string.format("G0 %s%.4f", axis, distance))
	if rc ~= mc.MERROR_NOERROR then
		StoryTechShopProbe.internal.Log("ERROR: Failed to retract %s-axis.", axis)
		return false
	end
	probeHandle = mc.mcSignalGetHandle(inst, StoryTechShopProbe.internal.Probes[profile.Probe])
	if mc.mcSignalGetState(probeHandle) == 1 then
		StoryTechShopProbe.internal.Log("ERROR: Failed to retract %s-axis, probe is still in contact.", axis)
		return false
	end
	return true
end

function StoryTechShopProbe.internal.ProbeStrikePosition(axis)
	if (axis == 'X') then
		return mc.mcAxisGetProbePos(Instance, mc.X_AXIS, 1)
	elseif (axis == 'Y') then
		return mc.mcAxisGetProbePos(Instance, mc.Y_AXIS, 1)
	elseif (axis == 'Z') then
		return mc.mcAxisGetProbePos(Instance, mc.Z_AXIS, 1)
	end
end

function StoryTechShopProbe.internal.ConvertToUnit(units, profile)
	inst = mc.mcGetInstance()
	defaultUnit = mc.mcCntlGetUnitsDefault(inst)
	
	if defaultUnit == 20 and profile.Unit == 21 then
		-- convert mm to in
		return units / 25.4
	elseif defaultUnit == 21 and profile.Unit == 20 then
		-- convert in to mm
		return units * 25.4
	end
	return units
end

--- Find probe profile by name
-- @return Profile,index
function StoryTechShopProbe.internal.FindProfile(name)
	for i,profile in ipairs(StoryTechShopProbe.internal.Profiles) do
		if profile.Name == name then
			return profile,i
		end
	end
	
	return nil,0
end

--- Get selected probe profile
-- @return Profile,index
function StoryTechShopProbe.internal.SelectedProfile()
	profileIndex = StoryTechShopProbe.UI.chProbeProfile:GetSelection()+1
	
	if profileIndex > 0 then
		return StoryTechShopProbe.internal.Profiles[profileIndex]
	end
	return nil
end

--- Load settings from Mach4 Profile ini
function StoryTechShopProbe.internal.LoadSettings()
	inst = mc.mcGetInstance()
	profileCount = mc.mcProfileGetInt(inst, "StoryTechShopProbe", "ProfileCount", 0)
	if profileCount == 0 then
		-- Create a default profile.
		StoryTechShopProbe.SaveProfile(
			"Beaver CNC Zero2 Probe",
			31, 21, -- Probe G31, Unit 21 (mm)
			20, -- 20mm max probe travel
			{100.0, 50.0}, 3.0, -- 2 probe cycles: 100mm/min and 50mm/min, 3mm cycle retract
			22.0, 10.0, 30.0, 30.0, -- 22mm probe height, 10mm hole depth, 30x30mm to hole center from corner
			40.00 -- 40mm retract after successful probe
		)
		return
	end
	
	for i=1,profileCount do
		profileIndex= "Profile"..i
		profile = {
			Name = mc.mcProfileGetString(inst, "StoryTechShopProbe", profileIndex.."_Name", "Unnamed"),
			Probe = mc.mcProfileGetDouble(inst, "StoryTechShopProbe", profileIndex.."_Probe", 31),
			Unit = mc.mcProfileGetInt(inst, "StoryTechShopProbe", profileIndex.."_Unit", 20),
			MaxTravel = mc.mcProfileGetDouble(inst, "StoryTechShopProbe", profileIndex.."_MaxTravel", 0.0),
			CycleFeedRate = StoryTechShopProbe.internal.ParseDelimitedNumbers(
				mc.mcProfileGetString(inst, "StoryTechShopProbe", profileIndex.."_CycleFeedrate", "0.0")
			),
			CycleRetract = mc.mcProfileGetDouble(inst, "StoryTechShopProbe", profileIndex.."_CycleRetract", 0.0),
			ProbeHeight = mc.mcProfileGetDouble(inst, "StoryTechShopProbe", profileIndex.."_ProbeHeight", 0.0),
			HoleDepth = mc.mcProfileGetDouble(inst, "StoryTechShopProbe", profileIndex.."_HoleDepth", 0.0),
			HoleXOrigin = mc.mcProfileGetDouble(inst, "StoryTechShopProbe", profileIndex.."_HoleXOrigin", 0.0),
			HoleYOrigin = mc.mcProfileGetDouble(inst, "StoryTechShopProbe", profileIndex.."_HoleYOrigin", 0.0),
			Retract = mc.mcProfileGetDouble(inst, "StoryTechShopProbe", profileIndex.."_Retract", 0.0)
		}
		table.insert(StoryTechShopProbe.internal.Profiles, profile)
	end
	StoryTechShopProbe.internal.RefreshUI()
end

--- Save settings to Mach4 profile
-- @param flush Save Mach4 profile to file
function StoryTechShopProbe.internal.SaveSettings(flush)
	inst = mc.mcGetInstance()
	
	count = 0
	for i,profile in ipairs(StoryTechShopProbe.internal.Profiles) do
		count = count + 1
		profileIndex= "Profile"..count
		
		mc.mcProfileWriteString(inst, "StoryTechShopProbe", profileIndex.."_Name", profile.Name)
		mc.mcProfileWriteDouble(inst, "StoryTechShopProbe", profileIndex.."_Probe", profile.Probe)
		mc.mcProfileWriteInt(inst, "StoryTechShopProbe", profileIndex.."_Unit", profile.Unit)
		mc.mcProfileWriteDouble(inst, "StoryTechShopProbe", profileIndex.."_MaxTravel", profile.MaxTravel)
		mc.mcProfileWriteString(inst, "StoryTechShopProbe", profileIndex.."_CycleFeedrate",
			StoryTechShopProbe.internal.ToDelimitedNumbers(profile.CycleFeedRate)
		)
		mc.mcProfileWriteDouble(inst, "StoryTechShopProbe", profileIndex.."_CycleRetract", profile.CycleRetract)
		mc.mcProfileWriteDouble(inst, "StoryTechShopProbe", profileIndex.."_ProbeHeight", profile.ProbeHeight)
		mc.mcProfileWriteDouble(inst, "StoryTechShopProbe", profileIndex.."_HoleDepth", profile.HoleDepth)
		mc.mcProfileWriteDouble(inst, "StoryTechShopProbe", profileIndex.."_HoleXOrigin", profile.HoleXOrigin)
		mc.mcProfileWriteDouble(inst, "StoryTechShopProbe", profileIndex.."_HoleYOrigin", profile.HoleYOrigin)
		mc.mcProfileWriteDouble(inst, "StoryTechShopProbe", profileIndex.."_Retract", profile.Retract)
	end
	
	mc.mcProfileWriteInt(inst, "StoryTechShopProbe", "ProfileCount", count)
	mc.mcProfileWriteInt(inst, "StoryTechShopProbe", "SelectedProfile", StoryTechShopProbe.UI.chProbeProfile:GetSelection()+1)
	
	if flush then
		mc.mcProfileSave(inst)
	end
	
	StoryTechShopProbe.internal.RefreshUI()
end

function StoryTechShopProbe.internal.ParseDelimitedNumbers(s)
	result = {}
    for match in string.gmatch(s, '([^,]+)') do
        table.insert(result, tonumber(match))
    end
    return result
end

function StoryTechShopProbe.internal.ToDelimitedNumbers(table)
	result = ""
    for i,num in ipairs(table) do
    	value = tostring(num)
    	if result ~= "" then
    		result = result..","..value
    	else
			result = value
		end
	end
    return result
end

function StoryTechShopProbe.internal.RefreshUI()
	inst = mc.mcGetInstance()
	
	StoryTechShopProbe.UI.chProbeProfile:Clear()
	count=0
	for i,profile in ipairs(StoryTechShopProbe.internal.Profiles) do
		count = count + 1
		StoryTechShopProbe.UI.chProbeProfile:Append(profile.Name)
	end
	selectedProfile = mc.mcProfileGetInt(inst, "StoryTechShopProbe", "SelectedProfile", 0)
	if selectedProfile > 0 and selectedProfile <= count then
		StoryTechShopProbe.SelectProfile(StoryTechShopProbe.internal.Profiles[selectedProfile].Name)
	else
		StoryTechShopProbe.SelectProfile(nil)
	end
end

function StoryTechShopProbe.internal.UpdateUI()
	inst = mc.mcGetInstance()
	mcState, rc = mc.mcCntlGetState(inst)
	co = StoryTechShopProbe.internal.co
	
	if co ~= nil and mcState == 0 then
		state = coroutine.status(co)
		
		if state == "suspended" then
			coerrorcheck, rc = coroutine.resume(co)
			if coerrorcheck == false or rc ~= mc.MERROR_NOERROR then
				co = nil
			end
		elseif state == "dead" then
			co = nil
		end
		
		StoryTechShopProbe.internal.co = co
	end
	
	enabled = co == nil and mcState == 0
	StoryTechShopProbe.UI.chProbeProfile:Enable(enabled)
	StoryTechShopProbe.UI.btnProbeEdit:Enable(enabled)
	StoryTechShopProbe.UI.btnProbeEdit:Enable(enabled)
	
	profile = StoryTechShopProbe.internal.SelectedProfile()
	StoryTechShopProbe.UI.btnProbeOpZ:Enable(enabled and profile ~= nil)
	StoryTechShopProbe.UI.btnProbeOpXY:Enable(enabled and profile ~= nil)
	StoryTechShopProbe.UI.btnProbeOpZXY:Enable(enabled and profile ~= nil)
end

function StoryTechShopProbe.internal.ConnectUI()
	StoryTechShopProbe.UI.chProbeProfile:Connect( wx. wxEVT_COMMAND_CHOICE_SELECTED,
		function(event)
			index = event:GetSelection()
			profileName = StoryTechShopProbe.UI.chProbeProfile:GetString(index)
			
			StoryTechShopProbe.SelectProfile(profileName)
			
			event:Skip()
		end
	)
	
	StoryTechShopProbe.UI.Panel:Connect( wx.wxEVT_UPDATE_UI,
		function(event)
			StoryTechShopProbe.internal.UpdateUI()
			event:Skip()
		end
	)
	
	StoryTechShopProbe.UI.btnProbeOpZ:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED,
		function(event)
			StoryTechShopProbe.internal.co = coroutine.create(StoryTechShopProbe.ProbeZ)
			-- StoryTechShopProbe.ProbeZ()
			event:Skip()
		end
	)
end

function StoryTechShopProbe.internal.Log(message, ...)
	eventMessage = string.format(message, unpack({...}))
	if mc.mcInEditor() == 1 then
		print(eventMessage)
	end
	mc.mcCntlSetLastError(mc.mcGetInstance(), eventMessage)
end

function StoryTechShopProbe.internal.Debug(message, ...)
	eventMessage = string.format(message, unpack({...}))
	if mc.mcInEditor() == 1 then
		print(eventMessage)
	end
end

function StoryTechShopProbe.internal.InitUI(mcLuaPanel)
	if mcLuaPanel == nil then
		StoryTechShopProbe.UI.Panel = wx.wxDialog(wx.NULL, wx.wxID_ANY, "StoryTechShop Probe", wx.wxDefaultPosition, wx.wxSize( 900,530 ), wx.wxCAPTION + wx.wxCLOSE_BOX + wx.wxRESIZE_BORDER )
		-- wx.wxPanel (wx.NULL, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxTAB_TRAVERSAL )
	else
		StoryTechShopProbe.UI.Panel = mcLuaPanel
	end
	
	StoryTechShopProbe.UI.fgCtnrProbe = wx.wxFlexGridSizer( 2, 1, 0, 0 )
	StoryTechShopProbe.UI.fgCtnrProbe:AddGrowableCol( 0 )
	StoryTechShopProbe.UI.fgCtnrProbe:AddGrowableRow( 1 )
	StoryTechShopProbe.UI.fgCtnrProbe:SetFlexibleDirection( wx.wxBOTH )
	StoryTechShopProbe.UI.fgCtnrProbe:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )

	StoryTechShopProbe.UI.fgCntrProbeProfile = wx.wxFlexGridSizer( 0, 2, 0, 0 )
	StoryTechShopProbe.UI.fgCntrProbeProfile:AddGrowableCol( 0 )
	StoryTechShopProbe.UI.fgCntrProbeProfile:SetFlexibleDirection( wx.wxBOTH )
	StoryTechShopProbe.UI.fgCntrProbeProfile:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_SPECIFIED )

	StoryTechShopProbe.UI.chProbeProfileChoices = {}
	StoryTechShopProbe.UI.chProbeProfile = wx.wxChoice( StoryTechShopProbe.UI.Panel, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, StoryTechShopProbe.UI.chProbeProfileChoices, 0 )
	StoryTechShopProbe.UI.chProbeProfile:SetSelection( 0 )
	StoryTechShopProbe.UI.fgCntrProbeProfile:Add( StoryTechShopProbe.UI.chProbeProfile, 0, wx.wxALL + wx.wxEXPAND, 5 )

	StoryTechShopProbe.UI.btnProbeEdit = wx.wxButton( StoryTechShopProbe.UI.Panel, wx.wxID_ANY, "...", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxBU_EXACTFIT )
	StoryTechShopProbe.UI.btnProbeEdit:SetToolTip( "Edit probe profiles." )

	StoryTechShopProbe.UI.fgCntrProbeProfile:Add( StoryTechShopProbe.UI.btnProbeEdit, 0, wx.wxALL, 5 )


	StoryTechShopProbe.UI.fgCtnrProbe:Add( StoryTechShopProbe.UI.fgCntrProbeProfile, 1, wx.wxEXPAND, 5 )

	StoryTechShopProbe.UI.fgCntrProbeOps = wx.wxFlexGridSizer( 0, 3, 0, 0 )
	StoryTechShopProbe.UI.fgCntrProbeOps:AddGrowableCol( 0 )
	StoryTechShopProbe.UI.fgCntrProbeOps:AddGrowableCol( 1 )
	StoryTechShopProbe.UI.fgCntrProbeOps:AddGrowableCol( 2 )
	StoryTechShopProbe.UI.fgCntrProbeOps:SetFlexibleDirection( wx.wxBOTH )
	StoryTechShopProbe.UI.fgCntrProbeOps:SetNonFlexibleGrowMode( wx.wxFLEX_GROWMODE_NONE )

	StoryTechShopProbe.UI.btnProbeOpZ = wx.wxButton( StoryTechShopProbe.UI.Panel, wx.wxID_ANY, "Probe Z", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	StoryTechShopProbe.UI.btnProbeOpZ:SetToolTip( "Probe top surface for Z-axis fixture offset." )

	StoryTechShopProbe.UI.fgCntrProbeOps:Add( StoryTechShopProbe.UI.btnProbeOpZ, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )

	StoryTechShopProbe.UI.btnProbeOpXY = wx.wxButton( StoryTechShopProbe.UI.Panel, wx.wxID_ANY, "Probe XY", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	StoryTechShopProbe.UI.btnProbeOpXY:SetToolTip( "Probe inside hole for X-axis and Y-axis fixture offsets." )

	StoryTechShopProbe.UI.fgCntrProbeOps:Add( StoryTechShopProbe.UI.btnProbeOpXY, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )

	StoryTechShopProbe.UI.btnProbeOpZXY = wx.wxButton( StoryTechShopProbe.UI.Panel, wx.wxID_ANY, "Probe ZXY", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
	StoryTechShopProbe.UI.btnProbeOpZXY:SetToolTip( "Probe inside hole for Z-axis, X-axis, and Y-axis fixture offsets." )

	StoryTechShopProbe.UI.fgCntrProbeOps:Add( StoryTechShopProbe.UI.btnProbeOpZXY, 0, wx.wxALIGN_CENTER + wx.wxALL, 5 )


	StoryTechShopProbe.UI.fgCtnrProbe:Add( StoryTechShopProbe.UI.fgCntrProbeOps, 1, wx.wxEXPAND, 5 )


	StoryTechShopProbe.UI.Panel:SetSizer( StoryTechShopProbe.UI.fgCtnrProbe )
	StoryTechShopProbe.UI.Panel:Layout()
end

if mc.mcInEditor() == 1 then
	StoryTechShopProbe.Initialize()
	StoryTechShopProbe.UI.Panel:ShowModal()
end

return StoryTechShopProbe