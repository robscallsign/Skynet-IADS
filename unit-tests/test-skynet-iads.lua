do
TestSkynetIADS = {}

function TestSkynetIADS:setUp()
	self.numSAMSites = SKYNET_UNIT_TESTS_NUM_SAM_SITES_RED 
	self.numEWSites = SKYNET_UNIT_TESTS_NUM_EW_SITES_RED
	self.testIADS = SkynetIADS:create()
	self.testIADS:addEarlyWarningRadarsByPrefix('EW')
	self.testIADS:addSAMSitesByPrefix('SAM')
end

function TestSkynetIADS:tearDown()
	if	self.testIADS then
		self.testIADS:deactivate()
	end
	self.testIADS = nil
end

-- this function checks constants in DCS that the IADS relies on. A change to them might indicate that functionallity is broken.
-- In the code constants are refereed to with their constant name calue, not the values the represent.
function TestSkynetIADS:testDCSContstantsHaveNotChanged()
	lu.assertEquals(Weapon.Category.MISSILE, 1)
	lu.assertEquals(Weapon.Category.SHELL, 0)
	lu.assertEquals(world.event.S_EVENT_SHOT, 1)
	lu.assertEquals(world.event.S_EVENT_DEAD, 8)
	lu.assertEquals(Unit.Category.AIRPLANE, 0)
end

function TestSkynetIADS:testCaclulateNumberOfSamSitesAndEWRadars()
	self:tearDown()
	self.testIADS = SkynetIADS:create()
	lu.assertEquals(#self.testIADS:getSAMSites(), 0)
	lu.assertEquals(#self.testIADS:getEarlyWarningRadars(), 0)
	self.testIADS:addEarlyWarningRadarsByPrefix('EW')
	self.testIADS:addSAMSitesByPrefix('SAM')
	lu.assertEquals(#self.testIADS:getSAMSites(), self.numSAMSites)
	lu.assertEquals(#self.testIADS:getEarlyWarningRadars(), self.numEWSites)
end

function TestSkynetIADS:testCaclulateNumberOfSamSitesAndEWRadarsWhenAddMethodsCalledTwice()
	self:tearDown()
	self.testIADS = SkynetIADS:create()
	lu.assertEquals(#self.testIADS:getSAMSites(), 0)
	lu.assertEquals(#self.testIADS:getEarlyWarningRadars(), 0)
	self.testIADS:addEarlyWarningRadarsByPrefix('EW')
	self.testIADS:addEarlyWarningRadarsByPrefix('EW')
	self.testIADS:addSAMSitesByPrefix('SAM')
	self.testIADS:addSAMSitesByPrefix('SAM')
	lu.assertEquals(#self.testIADS:getSAMSites(), self.numSAMSites)
	lu.assertEquals(#self.testIADS:getEarlyWarningRadars(), self.numEWSites)
end

function TestSkynetIADS:testDoubleActivateCall()
	self.testIADS:activate()
	self.testIADS:activate()
	local ews = self.testIADS:getEarlyWarningRadars()
	for i = 1, #ews do
		local ew = ews[i]
		local category = ew:getDCSRepresentation():getDesc().category
		if category ~= Unit.Category.AIRPLANE and category ~= Unit.Category.SHIP then
			--env.info(tostring(ew:isScanningForHARMs()))
			lu.assertEquals(ew:isScanningForHARMs(), true)
		end
	end
end

function TestSkynetIADS:testWrongCaseStringWillNotLoadSAMGroup()
	self:tearDown()
	self.testIADS = SkynetIADS:create()
	self.testIADS:addSAMSitesByPrefix('sam')
	lu.assertEquals(#self.testIADS:getSAMSites(), 0)
end	

function TestSkynetIADS:testWrongCaseStringWillNotLoadEWRadars()
	self:tearDown()
	self.testIADS = SkynetIADS:create()
	self.testIADS:addEarlyWarningRadarsByPrefix('ew')
	lu.assertEquals(#self.testIADS:getEarlyWarningRadars(), 0)
end	

function TestSkynetIADS:testEvaluateContacts1EWAnd1SAMSiteWithContactInRange()
	local iads = SkynetIADS:create()
	local ewRadar = iads:addEarlyWarningRadar('EW-west23')
	
	function ewRadar:getDetectedTargets()
		return {IADSContactFactory('test-in-firing-range-of-sa-2')}
	end
	
	local samSite = iads:addSAMSite('SAM-SA-2')
	
	
	function samSite:getDetectedTargets()
		return {}
	end
	
	samSite:goDark()
	lu.assertEquals(samSite:isInRadarDetectionRangeOf(ewRadar), true)
	iads:activate()
	iads:evaluateContacts()
	lu.assertEquals(#iads:getContacts(), 1)
	lu.assertEquals(samSite:isActive(), true)
	
	-- we remove the target to test if the sam site will no go dark, was added for the performance optimised code
	function ewRadar:getDetectedTargets()
		return {}
	end
	iads:evaluateContacts()
	lu.assertEquals(samSite:isActive(), false)
	
end

function TestSkynetIADS:testEarlyWarningRadarHasWorkingPowerSourceByDefault()
	local ewRadar = self.testIADS:getEarlyWarningRadarByUnitName('EW-west')
	lu.assertEquals(ewRadar:hasWorkingPowerSource(), true)
end

function TestSkynetIADS:testPowerSourceConnectedToMultipleAbstractRadarElementSitesIsDestroyedAutonomousStateIsOnlyRebuiltOnce()

	local iads = SkynetIADS:create()

	ewWest2PowerSource = StaticObject.getByName('west Power Source')
	local ewRadar = iads:addEarlyWarningRadar('EW-west'):addPowerSource(ewWest2PowerSource)
	
	local samSite = iads:addSAMSite('test-samsite-with-unit-as-power-source')
	
	lu.assertEquals(samSite:getAutonomousState(), false)
	
	local samSite2 = iads:addSAMSite('SAM-SA-15')
	samSite2:addPowerSource(ewWest2PowerSource)
	samSite2:goLive()
	
	local updateCalls = 0

	function iads:enforceRebuildAutonomousStateOfSAMSites()
		SkynetIADS.enforceRebuildAutonomousStateOfSAMSites(self)
		updateCalls = updateCalls + 1
	end
	
	lu.assertEquals(ewRadar:hasWorkingPowerSource(), true)
	trigger.action.explosion(ewWest2PowerSource:getPosition().p, 100)
	lu.assertEquals(ewRadar:hasWorkingPowerSource(), false)
	lu.assertEquals(ewRadar:isActive(), false)
	
	lu.assertEquals(samSite:getAutonomousState(), true)
	lu.assertEquals(samSite2:isActive(), false)
	
	-- we ensure the autonomous state is only rebuilt once when a power source connected to mulitple EW or SAM sites is destroyed
	lu.assertEquals(updateCalls, 1)
	
	
end

function TestSkynetIADS:testEarlyWarningRadarAndSAMSiteLooseConnectionNodeAndAutonomousStateIsOnlyRebuiltOnce()

	local iads = SkynetIADS:create()

	ewWestConnectionNode = StaticObject.getByName('west Connection Node Destroy')
	local ewRadar = iads:addEarlyWarningRadar('EW-west'):addConnectionNode(ewWestConnectionNode)
	
	local samSite = iads:addSAMSite('test-samsite-with-unit-as-power-source')
	samSite:addConnectionNode(ewWestConnectionNode)
	lu.assertEquals(samSite:getAutonomousState(), false)
	
	local updateCalls = 0

	function iads:enforceRebuildAutonomousStateOfSAMSites()
		SkynetIADS.enforceRebuildAutonomousStateOfSAMSites(self)
		updateCalls = updateCalls + 1
	end
	
	trigger.action.explosion(ewWestConnectionNode:getPosition().p, 100)
	
	lu.assertEquals(ewRadar:hasActiveConnectionNode(), false)
	lu.assertEquals(samSite:hasActiveConnectionNode(), false)
	lu.assertEquals(ewRadar:isActive(), false)
	
	lu.assertEquals(samSite:getAutonomousState(), true)
	
	-- we ensure the autonomous state is only rebuilt once when a connection node used by mulitple EW or SAM sites is destroyed
	lu.assertEquals(updateCalls, 1)
	
end

function TestSkynetIADS:testAWACSHasMovedAndThereforeRebuildAutonomousStatesOfSAMSites()

	local iads = SkynetIADS:create()
	local awacs = iads:addEarlyWarningRadar('EW-AWACS-A-50')

	local updateCalls = 0
	function iads:enforceRebuildAutonomousStateOfSAMSites()
		SkynetIADS.enforceRebuildAutonomousStateOfSAMSites(self)
		updateCalls = updateCalls + 1
	end
	
	lu.assertEquals(awacs:getDistanceTraveledSinceLastUpdate(), 0)
	lu.assertEquals(getmetatable(awacs), SkynetIADSAWACSRadar)
	lu.assertEquals(awacs:getMaxAllowedMovementForAutonomousUpdateInNM(), 11)
	lu.assertEquals(awacs:isUpdateOfAutonomousStateOfSAMSitesRequired(), false)
	
	iads:evaluateContacts()
	lu.assertEquals(updateCalls, 0)
	
	--test distance calculation by giving the awacs a different position:
	local firstPos = Unit.getByName('EW-AWACS-KJ-2000'):getPosition().p
	awacs.lastUpdatePosition = firstPos
	lu.assertEquals(awacs:getDistanceTraveledSinceLastUpdate(), 763)
	lu.assertEquals(awacs:isUpdateOfAutonomousStateOfSAMSitesRequired(), true)
	
	iads:evaluateContacts()
	lu.assertEquals(updateCalls, 1)
	
end


function TestSkynetIADS:testSAMSiteLoosesPower()
	local powerSource = StaticObject.getByName('SA-6 Power')
	local samSite = self.testIADS:getSAMSiteByGroupName('SAM-SA-6'):addPowerSource(powerSource)
	lu.assertEquals(#self.testIADS:getUsableSAMSites(), self.numSAMSites)
	lu.assertEquals(samSite:isActive(), false)
	samSite:goLive()
	lu.assertEquals(samSite:isActive(), true)
	trigger.action.explosion(powerSource:getPosition().p, 100)
	lu.assertEquals(#self.testIADS:getUsableSAMSites(), self.numSAMSites-1)
	lu.assertEquals(samSite:isActive(), false)
end

function TestSkynetIADS:testSAMSiteSA6LostConnectionNodeAutonomusStateDCSAI()
	local sa6ConnectionNode = StaticObject.getByName('SA-6 Connection Node')
	self.testIADS:getSAMSiteByGroupName('SAM-SA-6'):addConnectionNode(sa6ConnectionNode)
	lu.assertEquals(#self.testIADS:getSAMSites(), self.numSAMSites)
	lu.assertEquals(#self.testIADS:getUsableSAMSites(), self.numSAMSites)
	trigger.action.explosion(sa6ConnectionNode:getPosition().p, 100)
	lu.assertEquals(#self.testIADS:getUsableSAMSites(), self.numSAMSites-1)

	lu.assertEquals(#self.testIADS:getUsableSAMSites(), self.numSAMSites-1)
	lu.assertEquals(#self.testIADS:getSAMSites(), self.numSAMSites)
	local samSite = self.testIADS:getSAMSiteByGroupName('SAM-SA-6')
	lu.assertEquals(samSite:isActive(), true)

	lu.assertEquals(samSite:getAutonomousState(), true)
	lu.assertEquals(samSite:isActive(), true)
end

function TestSkynetIADS:testSAMSiteSA62ConnectionNodeLostAutonomusStateDark()
	local sa6ConnectionNode2 = StaticObject.getByName('SA-6-2 Connection Node')
	local samSite = self.testIADS:getSAMSiteByGroupName('SAM-SA-6-2')
	lu.assertEquals(samSite:isActive(), false)
	self.testIADS:getSAMSiteByGroupName('SAM-SA-6-2'):addConnectionNode(sa6ConnectionNode2):setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
	lu.assertEquals(samSite:hasActiveConnectionNode(), true)
	trigger.action.explosion(sa6ConnectionNode2:getPosition().p, 100)
	lu.assertEquals(samSite:hasActiveConnectionNode(), false)
	lu.assertEquals(#samSite:getRadars(), 1)
	lu.assertEquals(samSite:isActive(), false)
end

function TestSkynetIADS:testOneCommandCenterIsDestroyed()
	local powerStation1 = StaticObject.getByName("Command Center Power")
	local commandCenter1 = StaticObject.getByName("Command Center")	
	lu.assertEquals(#self.testIADS:getCommandCenters(), 0)
	self.testIADS:addCommandCenter(commandCenter1):addPowerSource(powerStation1)
	lu.assertEquals(#self.testIADS:getCommandCenters(), 1)
	lu.assertEquals(self.testIADS:isCommandCenterUsable(), true)
	trigger.action.explosion(commandCenter1:getPosition().p, 10000)
	lu.assertEquals(#self.testIADS:getCommandCenters(), 1)
	lu.assertEquals(self.testIADS:isCommandCenterUsable(), false)
end

function TestSkynetIADS:testSetSamSitesToAutonomous()
	local samSiteDark = self.testIADS:getSAMSiteByGroupName('SAM-SA-6')
	local samSiteActive = self.testIADS:getSAMSiteByGroupName('SAM-SA-6-2')
	lu.assertEquals(samSiteDark:isActive(), false)
	lu.assertEquals(samSiteActive:isActive(), false)
	self.testIADS:getSAMSiteByGroupName('SAM-SA-6'):setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
	self.testIADS:getSAMSiteByGroupName('SAM-SA-6-2'):setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DCS_AI)
	self.testIADS:setSAMSitesToAutonomousMode()
	lu.assertEquals(samSiteDark:isActive(), false)
	lu.assertEquals(samSiteActive:isActive(), true)
	samSiteActive:goDark()
	--dont call an update of the IADS in this test, its just to test setSamSitesToAutonomousMode()
end

function TestSkynetIADS:testSetOptionsForSAMSiteType()
	local powerSource = StaticObject.getByName('SA-11-power-source')
	local connectionNode = StaticObject.getByName('SA-11-connection-node')
	lu.assertEquals(#self.testIADS:getSAMSitesByNatoName('SA-6'), 2)
	--lu.assertIs(getmetatable(self.testIADS:getSAMSitesByNatoName('SA-6')), SkynetIADSTableForwarder)
	local samSites = self.testIADS:getSAMSitesByNatoName('SA-6'):setActAsEW(true):addPowerSource(powerSource):addConnectionNode(connectionNode):setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE):setGoLiveRangeInPercent(90):setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
	lu.assertEquals(#samSites, 2)
	for i = 1, #samSites do
		local samSite = samSites[i]
		lu.assertEquals(samSite:getActAsEW(), true)
		lu.assertEquals(samSite:getEngagementZone(), SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
		lu.assertEquals(samSite:getGoLiveRangeInPercent(), 90)
		lu.assertEquals(samSite:getAutonomousBehaviour(), SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
		lu.assertIs(samSite:getConnectionNodes()[1], connectionNode)
		lu.assertIs(samSite:getPowerSources()[1], powerSource)
	end
end

function TestSkynetIADS:testSetOptionsForAllAddedSamSitesByPrefix()
	self:tearDown()
	self.testIADS = SkynetIADS:create()
	local samSites = self.testIADS:addSAMSitesByPrefix('SAM'):setActAsEW(true):addPowerSource(powerSource):addConnectionNode(connectionNode):setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE):setGoLiveRangeInPercent(90):setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
	lu.assertEquals(#samSites, self.numSAMSites)
	for i = 1, #samSites do
		local samSite = samSites[i]
		lu.assertEquals(samSite:getActAsEW(), true)
		lu.assertEquals(samSite:getEngagementZone(), SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
		lu.assertEquals(samSite:getGoLiveRangeInPercent(), 90)
		lu.assertEquals(samSite:getAutonomousBehaviour(), SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
		lu.assertIs(samSite:getConnectionNodes()[1], connectionNode)
		lu.assertIs(samSite:getPowerSources()[1], powerSource)
	end
end

function TestSkynetIADS:testSetOptionsForAllAddedSAMSites()
	local samSites = self.testIADS:getSAMSites():setActAsEW(true):addPowerSource(powerSource):addConnectionNode(connectionNode):setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE):setGoLiveRangeInPercent(90):setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
	lu.assertEquals(#samSites, self.numSAMSites)
	for i = 1, #samSites do
		local samSite = samSites[i]
		lu.assertEquals(samSite:getActAsEW(), true)
		lu.assertEquals(samSite:getEngagementZone(), SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
		lu.assertEquals(samSite:getGoLiveRangeInPercent(), 90)
		lu.assertEquals(samSite:getAutonomousBehaviour(), SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
		lu.assertIs(samSite:getConnectionNodes()[1], connectionNode)
		lu.assertIs(samSite:getPowerSources()[1], powerSource)
	end
end

function TestSkynetIADS:testSetOptionsForAllAddedEWSitesByPrefix()
	self:tearDown()
	self.testIADS = SkynetIADS:create()
	local ewSites = self.testIADS:addEarlyWarningRadarsByPrefix('EW'):addPowerSource(powerSource):addConnectionNode(connectionNode)
	lu.assertEquals(#ewSites, self.numEWSites)
	for i = 1, #ewSites do
		local ewSite = ewSites[i]
		lu.assertIs(ewSite:getConnectionNodes()[1], connectionNode)
		lu.assertIs(ewSite:getPowerSources()[1], powerSource)
	end
	
end

function TestSkynetIADS:testSetOptionsForAllAddedEWSites()
	local ewSites = self.testIADS:getEarlyWarningRadars()
	lu.assertEquals(#ewSites, self.numEWSites)
	for i = 1, #ewSites do
		local ewSite = ewSites[i]
		lu.assertIs(ewSite:getConnectionNodes()[1], connectionNode)
		lu.assertIs(ewSite:getPowerSources()[1], powerSource)
	end
end


function TestSkynetIADS:testOneCommandCenterLoosesPower()
	local commandCenter2Power = StaticObject.getByName("Command Center2 Power")
	local commandCenter2 = StaticObject.getByName("Command Center2")
	lu.assertEquals(#self.testIADS:getCommandCenters(), 0)
	lu.assertEquals(self.testIADS:isCommandCenterUsable(), true)
	local comCenter = self.testIADS:addCommandCenter(commandCenter2):addPowerSource(commandCenter2Power)
	lu.assertEquals(#comCenter:getPowerSources(), 1)
	lu.assertEquals(#self.testIADS:getCommandCenters(), 1)
	lu.assertEquals(self.testIADS:isCommandCenterUsable(), true)
	trigger.action.explosion(commandCenter2Power:getPosition().p, 10000)
	lu.assertEquals(#self.testIADS:getCommandCenters(), 1)
	lu.assertEquals(self.testIADS:isCommandCenterUsable(), false)
end

function TestSkynetIADS:testMergeContacts()
	lu.assertEquals(#self.testIADS:getContacts(), 0)
	self.testIADS:mergeContact(IADSContactFactory('Harrier Pilot'))
	lu.assertEquals(#self.testIADS:getContacts(), 1)
	
	self.testIADS:mergeContact(IADSContactFactory('Harrier Pilot'))
	lu.assertEquals(#self.testIADS:getContacts(), 1)
	
	self.testIADS:mergeContact(IADSContactFactory('test-in-firing-range-of-sa-2'))
	lu.assertEquals(#self.testIADS:getContacts(), 2)
	
end

function TestSkynetIADS:testCleanAgedTargets()
	local iads = SkynetIADS:create()
	
	target1 = IADSContactFactory('test-in-firing-range-of-sa-2')
	function target1:getAge()
		return iads.maxTargetAge + 1
	end
	
	target2 = IADSContactFactory('test-distance-calculation')
	function target2:getAge()
		return 1
	end
	
	iads.contacts[1] = target1
	iads.contacts[2] = target2
	lu.assertEquals(#iads:getContacts(), 2)
	iads:cleanAgedTargets()
	lu.assertEquals(#iads:getContacts(), 1)
end

function TestSkynetIADS:testOnlyLoadGroupsWithPrefixForSAMSiteNotOtherUnitsOrStaticObjectsWithSamePrefix()
	self:tearDown()
	self.testIADS = SkynetIADS:create()
	local calledPrint = false
	function self.testIADS:printOutput(str, isWarning)
		calledPrint = true
	end
	self.testIADS:addSAMSitesByPrefix('prefixtest')
	lu.assertEquals(#self.testIADS:getSAMSites(), 1)
	lu.assertEquals(calledPrint, false)
end

function TestSkynetIADS:testOnlyLoadGroupsWithPrefixForSAMSiteNotOtherUnitsOrStaticObjectsWithSamePrefix2()
	self:tearDown()
	self.testIADS = SkynetIADS:create()
	local calledPrint = false
	function self.testIADS:printOutput(str, isWarning)
		calledPrint = true
	end
	--happened when the string.find method was not set to plain special characters messed up the regex pattern
	self.testIADS:addSAMSitesByPrefix('IADS-EW')
	lu.assertEquals(#self.testIADS:getSAMSites(), 1)
	lu.assertEquals(calledPrint, false)
end

function TestSkynetIADS:testOnlyLoadUnitsWithPrefixForEWSiteNotStaticObjectssWithSamePrefix()
	self:tearDown()
	self.testIADS = SkynetIADS:create()
	local calledPrint = false
	function self.testIADS:printOutput(str, isWarning)
		calledPrint = true
	end
	self.testIADS:addEarlyWarningRadarsByPrefix('prefixewtest')
	lu.assertEquals(#self.testIADS:getEarlyWarningRadars(), 1)
	lu.assertEquals(calledPrint, false)
end

function TestSkynetIADS:testDontPassShipsGroundUnitsAndStructuresToSAMSites()
	
	-- make sure we don't get any targets in the test mission
	local ewRadars = self.testIADS:getEarlyWarningRadars()
	for i = 1, #ewRadars do
		local ewRadar = ewRadars[i]
		function ewRadar:getDetectedTargets()
			return {}
		end
	end
	
	
	local samSites = self.testIADS:getSAMSites()
	for i = 1, #samSites do
		local samSite = samSites[i]
		function samSite:getDetectedTargets()
			return {}
		end
	end
	

	self.testIADS:evaluateContacts()
	-- verifies we have a clean test setup
	lu.assertEquals(#self.testIADS.contacts, 0)
	

	
	-- ground units should not be passed to the SAM	
	local mockContactGroundUnit = {}
	function mockContactGroundUnit:getDesc()
		return {category = Unit.Category.GROUND_UNIT}
	end
	function mockContactGroundUnit:getAge()
		return 0
	end
	
	
	table.insert(self.testIADS.contacts, mockContactGroundUnit)
	
	local correlatedCalled = false
	function self.testIADS:correlateWithSAMSites(contact)
		correlatedCalled = true
	end
	
	self.testIADS:evaluateContacts()
	lu.assertEquals(correlatedCalled, false)
	lu.assertEquals(#self.testIADS.contacts, 1)
	
	
	
	self.testIADS.contacts = {}
	
	-- ships should not be passed to the SAM	
	local mockContactShip = {}
	function mockContactShip:getDesc()
		return {category = Unit.Category.SHIP}
	end
	function mockContactShip:getAge()
		return 0
	end
	
	table.insert(self.testIADS.contacts, mockContactShip)
	
	correlatedCalled = false
	function self.testIADS:correlateWithSAMSites(contact)
		correlatedCalled = true
	end
	self.testIADS:evaluateContacts()
	lu.assertEquals(correlatedCalled, false)
	lu.assertEquals(#self.testIADS.contacts, 1)
	
	self.testIADS.contacts = {}
	
	-- aircraft should be passed to the SAM	
	local mockContactAirplane = {}
	function mockContactAirplane:getDesc()
		return {category = Unit.Category.AIRPLANE}
	end
	function mockContactAirplane:getAge()
		return 0
	end
	
	table.insert(self.testIADS.contacts, mockContactAirplane)
	
	correlatedCalled = false
	function self.testIADS:correlateWithSAMSites(contact)
	--	correlatedCalled = true
	end
	self.testIADS:evaluateContacts()
	--TODO: FIX TEST
	--lu.assertEquals(correlatedCalled, true)
	lu.assertEquals(#self.testIADS.contacts, 1)
	self.testIADS.contacts = {}

end

--TODO:Finish Unit Test
function TestSkynetIADS:testAddMooseSetGroup()

	local mockMooseSetGroup = {}
	local mockMooseConnector = {}
	local setGroupCalled = false
	
	function mockMooseConnector:addMooseSetGroup(group)
		setGroupCalled = true
		lu.assertEquals(mockMooseSetGroup, group)
	end
	
	function self.testIADS:getMooseConnector()
		return mockMooseConnector
	end
	
	self.testIADS:addMooseSetGroup(mockMooseSetGroup)
	lu.assertEquals(setGroupCalled, true)
end

-- this test ensures all the required calls to update the iads coverage are called
-- its fully mocked the single functions are unit tested in other test cases
function TestSkynetIADS:testUpdateIADSCoverage()

	local coveredAreaCalled = false
	function self.testIADS:buildSAMSitesInCoveredArea()
		coveredAreaCalled = true
	end
	
	local enforceBuildAutonomous = false
	function self.testIADS:enforceRebuildAutonomousStateOfSAMSites()
		enforceBuildAutonomous = true
	end
	
	local mockMooseConnector = {}
	local updateCalled = false
	function mockMooseConnector:update()
		updateCalled = true
	end
	function self.testIADS:getMooseConnector()
		return mockMooseConnector
	end
	
	self.testIADS:updateIADSCoverage()
	
	lu.assertEquals(coveredAreaCalled, true)
	lu.assertEquals(enforceBuildAutonomous, true)
	lu.assertEquals(updateCalled, true)
end

function TestSkynetIADS:testWillSAMSitesWithNoCoverageGoAutonomous()
	self:tearDown()

	self.testIADS = SkynetIADS:create()
	
	local autonomousSAM = self.testIADS:addSAMSite('test-SAM-SA-2-test')
	local nonAutonomousSAM = self.testIADS:addSAMSite('SAM-SA-6')
	local ewSAM = self.testIADS:addSAMSite('SAM-SA-10'):setActAsEW(true)
	local sa15 = self.testIADS:addSAMSite('SAM-SA-15-1')
	
	self.testIADS:addEarlyWarningRadarsByPrefix('EW')
	
	self.testIADS:updateIADSCoverage()
	
	lu.assertEquals(autonomousSAM:getAutonomousState(), true)
	lu.assertEquals(nonAutonomousSAM:getAutonomousState(), false)
	lu.assertEquals(sa15:getAutonomousState(), false)
	lu.assertEquals(ewSAM:getAutonomousState(), false)
end

function TestSkynetIADS:testSAMSiteLoosesConnectionThenAddANewOneAgain()
	self:tearDown()
	self.testIADS = SkynetIADS:create()
	local connectionNode = StaticObject.getByName('SA-6 Connection Node-autonomous-test')
	local nonAutonomousSAM = self.testIADS:addSAMSite('SAM-SA-6'):addConnectionNode(connectionNode)
	self.testIADS:addEarlyWarningRadarsByPrefix('EW')
	
	self.testIADS:updateIADSCoverage()
	
	lu.assertEquals(nonAutonomousSAM:getAutonomousState(), false)
	trigger.action.explosion(connectionNode:getPosition().p, 500)
	lu.assertEquals(nonAutonomousSAM:getAutonomousState(), true)
	
	local connectionNodeReAdd = StaticObject.getByName('SA-6 Connection Node-autonomous-test-readd')
	nonAutonomousSAM:addConnectionNode(connectionNodeReAdd)
	lu.assertEquals(nonAutonomousSAM:getAutonomousState(), false)
	
end

function TestSkynetIADS:testBuildSAMSitesInCoveredArea()
	local iads = SkynetIADS:create()
	
	local mockSAM = {}
	local samCalled = false
	function mockSAM:updateSAMSitesInCoveredArea()
		samCalled = true
	end
	
	function iads:getUsableSAMSites()
		return {mockSAM}
	end
	
	local mockEW = {}
	local ewCalled = false
	function mockEW:updateSAMSitesInCoveredArea()
		ewCalled = true
	end
	
	function iads:getUsableEarlyWarningRadars()
		return {mockEW}
	end
	
	iads:buildSAMSitesInCoveredArea()
	
	lu.assertEquals(samCalled, true)
	lu.assertEquals(ewCalled, true)
	
end

function TestSkynetIADS:testGetSAMSitesByPrefix()
	self:setUp();
	local samSites = self.testIADS:getSAMSitesByPrefix('SAM-SA-15')
	lu.assertEquals(#samSites, 3)
end

function TestSkynetIADS:testSetMaxAgeOfCachedTargets()
	local iads = SkynetIADS:create()
	
	-- test default value
	lu.assertEquals(iads.contactUpdateInterval, 5)
	
	iads:setUpdateInterval(10)
	lu.assertEquals(iads.contactUpdateInterval, 10)
	
	lu.assertEquals(iads:getCachedTargetsMaxAge(), 10)
	
	local ewRadar = iads:addEarlyWarningRadar('EW-west')
	local samSite = iads:addSAMSite('SAM-SA-15-1')
	
	lu.assertEquals(ewRadar.cachedTargetsMaxAge, 10)
	lu.assertEquals(samSite.cachedTargetsMaxAge, 10)
	
end

function TestSkynetIADS:testAddSingleEWRadarAndSAMSiteWillTriggerAutonomousStateUpdate()
	local iads = SkynetIADS:create()
	local numTimesCalledUpdate = 0
	
	function iads:updateIADSCoverage()
		numTimesCalledUpdate = numTimesCalledUpdate + 1
	end
	
	local ewRadar = iads:addEarlyWarningRadar('EW-west')
	lu.assertEquals(numTimesCalledUpdate, 0)
	
	local samSite = iads:addSAMSite('SAM-SA-6-2')
	lu.assertEquals(numTimesCalledUpdate, 0)
	
	--activate IADS, now the function must be called:
	iads:activate()
	lu.assertEquals(numTimesCalledUpdate, 1)
	
	local ewRadar = iads:addEarlyWarningRadar('EW-west')
	lu.assertEquals(numTimesCalledUpdate, 2)
	
	local samSite = iads:addSAMSite('SAM-SA-6-2')
	lu.assertEquals(numTimesCalledUpdate, 3)
	
end

function TestSkynetIADS:testSetupSAMSites()
	local numCalls = 0
	local numHARMCalls = 0
	local sams = self.testIADS:getSAMSites()
	for i = 1, #sams do
		local sam = sams[i]
		function sam:goLive()
			numCalls = numCalls + 1
		end
		function sam:stopScanningForHARMs()
				numHARMCalls = numHARMCalls + 1
		end
	end

	lu.assertEquals(self.testIADS.samSetupMistTaskID, nil)
	lu.assertEquals(self.testIADS.samSetupTime, 60)
	self.testIADS:setupSAMSitesAndThenActivate(10)
	lu.assertEquals(numCalls, #self.testIADS:getSAMSites())
	lu.assertEquals(numHARMCalls, #self.testIADS:getSAMSites())
	lu.assertNotEquals(self.testIADS.samSetupMistTaskID, nil)
	lu.assertEquals(self.testIADS.samSetupTime, 10)
end

function TestSkynetIADS:testSetupSAMSiteWithPointDefence()
	local iads = SkynetIADS:create()
	local sa15 = iads:addSAMSite('SAM-SA-15-1')
	iads:addSAMSite('SAM-SA-10'):addPointDefence(sa15)
	iads:setupSAMSitesAndThenActivate()
	lu.assertEquals(iads:getSAMSiteByGroupName('SAM-SA-10'):isActive(), true)
	lu.assertEquals(iads:getSAMSiteByGroupName('SAM-SA-15-1'):isActive(), true)
	
end

function TestSkynetIADS:testPostSetupCall()
	local numHARMCalls = 0
	local sams = self.testIADS:getSAMSites()
	for i = 1, #sams do
		local sam = sams[i]
		function sam:scanForHarms()
				numHARMCalls = numHARMCalls + 1
		end
	end
	local activateCalled = false
	function self.testIADS:activate()
		activateCalled = true
	end
	self.testIADS:postSetupSAMSites()
	lu.assertEquals(numHARMCalls, #self.testIADS:getSAMSites())
	lu.assertEquals(activateCalled, true)
end

end
