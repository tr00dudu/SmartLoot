SmartLoot = {};

SmartLoot.Version = "1.3-wotlk";

SmartLoot.Roll = {
	Pass = 0;
	Need = 1;
	Greed = 2;
	Disenchant = 3;
};

SmartLoot_Options = nil;
SmartLoot_Autoroll = {};
SmartLoot.LootFrames = nil;
SmartLoot.Queue = {};
SmartLoot.RollVotes = {}; -- [itemKey] = { need={}, greed={}, disenchant={}, pass={} }
SmartLoot.RollChat = {
	buffers = {};
	patterns = nil;
	filterRegistered = false;
};

local WEAPON_EQUIP_SLOTS = {
	["INVTYPE_WEAPON"] = true;
	["INVTYPE_2HWEAPON"] = true;
	["INVTYPE_WEAPONMAINHAND"] = true;
	["INVTYPE_WEAPONOFFHAND"] = true;
	["INVTYPE_RANGED"] = true;
	["INVTYPE_RANGEDRIGHT"] = true;
	["INVTYPE_THROWN"] = true;
};

SmartLoot.Res = {
	MinmapTooltip1 = "SmartLoot";
	MinmapTooltip2 = "Left click to open options";
	MinmapTooltip3 = "Right click and drag to move this button";
	ShowAnchor = {
		Label = "Show anchor";
		Tooltip = "";
	};
	HideDefaultFrames = {
		Label = "Hide default loot frames";
		Tooltip = "Whether to hide default blizzard group loot UI. Unchecking this will show any active loot frames. Can be used for debugging.";
	};
	AutoLoot = {
		Label = "Auto roll";
		Tooltip = "Automatically roll using defined auto-roll rules.";
	};
	AutoConfirmAll = {
		Label = "Autoconfirm all rolls";
		Tooltip = "Automatically confirm BoP prompts when you roll manually. Auto-rolls always confirm.";
	};
	AutoUncommonWeapons = {
		Label = "Uncommon weapons";
		Tooltip = "Auto-roll on green (Uncommon) weapons when no per-item rule matches.";
	};
	AutoUncommonGear = {
		Label = "Uncommon gear";
		Tooltip = "Auto-roll on green (Uncommon) equippable non-weapons when no per-item rule matches.";
	};
	FilterChatRollSpam = {
		Label = "Filter chat roll spam";
		Tooltip = "Hide Blizzard group-loot chat lines (chose / rolled / passed / all passed). Won lines are left visible.";
	};
	IncludeRollSummary = {
		Label = "Include roll summary in chat";
		Tooltip = "After a roll resolves, print a compact yellow summary of the top rolls. Requires Filter chat roll spam.";
	};
	ShowSelectedRolls = {
		Label = "Show selected rolls";
		Tooltip = "Show a count beside Need/Greed/DE/Pass of how many players picked each option. Hover a count to see who.";
	};
	LootFrameCount = {
		Label = "Loot frame count";
		Tooltip = "Number of loot frames that can be visible at a time.";
	};
	LootGrowUp = {
		Label = "Grow loot frames upward";
		Tooltip = "If checked, loot frames stack above the anchor (first item just above, next ones higher). If unchecked, they stack below.";
	};
	TestLoot = {
		Label = "Show test loot";
		Tooltip = "Displays a fake loot item for each loot frame. This option is not saved. Rolling on this loot doesn't work, use this checkbox again to delete it.";
	};
	ShowMinimapButton = {
		Label = "Show minimap button";
		Tooltip = "Right-click and drag the minimap button to move it.";
	};
};

function SmartLoot.OnLoad(self)
	SLASH_SLOOT1 = "/sloot";

	SlashCmdList["SLOOT"] = function(msg)
		SmartLoot.ToggleOptions();
	end

	self:RegisterEvent("CONFIRM_LOOT_ROLL");
	self:RegisterEvent("CONFIRM_DISENCHANT_ROLL");
	self:RegisterEvent("START_LOOT_ROLL");
	self:RegisterEvent("ADDON_LOADED");
	self:RegisterEvent("CANCEL_LOOT_ROLL");
end

function SmartLoot.OnEvent(self, event, ...)
	local arg1, arg2 = ...
	local rollId = arg1;
	local timeout = arg2;

	if(event == "START_LOOT_ROLL") then
		if(SmartLoot_Options.HideDefaultFrames) then
			SmartLoot.ToggleDefaultFrames(false);
		end

		local texture, name, count, quality, bindOnPickup, canNeed, canGreed, canDis = GetLootRollItemInfo(rollId);
		local link = GetLootRollItemLink(rollId);

		if(SmartLoot_Options.AutoLoot) then
			local desired = SmartLoot.GetDesiredRoll(name, link, quality, canNeed, canGreed, canDis);
			if(desired ~= nil) then
				SmartLoot.MarkAutoConfirm(rollId);
				RollOnLoot(rollId, desired);
				return;
			end
		end

		SmartLoot.QueueLoot(rollId, timeout, texture, name, quality, canNeed, canGreed, canDis, link);

	elseif(event == "CANCEL_LOOT_ROLL") then
		SmartLoot.ClearAutoConfirm(rollId);
		SmartLoot.ClearLoot(rollId);

	elseif(event == "CONFIRM_LOOT_ROLL" or event == "CONFIRM_DISENCHANT_ROLL") then
		if(SmartLoot.ShouldAutoConfirm(rollId)) then
			ConfirmLootRoll(arg1, arg2);
			StaticPopup_Hide("CONFIRM_LOOT_ROLL", rollId);
			StaticPopup_Hide("CONFIRM_DISENCHANT_ROLL", rollId);
		end

	elseif(event == "ADDON_LOADED" and arg1 == "SmartLoot") then
		self:UnregisterEvent("ADDON_LOADED");
		SmartLoot.EnsureOptions();
		SmartLoot.Initialize();
	end
end

function SmartLoot.EnsureOptions()
	if(not SmartLoot_Options) then
		SmartLoot_Options = {};
	end

	local set = function(option, value)
		if(SmartLoot_Options[option] == nil) then
			SmartLoot_Options[option] = value;
		end
	end;

	set("ShowAnchor", true);
	set("HideDefaultFrames", true);
	set("AutoLoot", true);
	set("AutoConfirmAll", false);
	SmartLoot_Options.AutoConfirm = nil; -- removed; auto-rolls always confirm
	set("LootFrameCount", 4);
	set("LootGrowUp", true);
	set("MinimapButtonPosition", 281);
	set("ShowMinimapButton", true);
	set("FilterChatRollSpam", false);
	set("IncludeRollSummary", false);
	set("ShowSelectedRolls", false);

	SmartLoot.MigrateGenericRollOption("AutoUncommonWeapons");
	SmartLoot.MigrateGenericRollOption("AutoUncommonGear");
end

-- Convert legacy off/de/pass strings (or leave numeric rolls). Default Off = nil.
function SmartLoot.MigrateGenericRollOption(key)
	local v = SmartLoot_Options[key];
	if(v == nil or v == false or v == "off") then
		SmartLoot_Options[key] = nil;
	elseif(v == "de") then
		SmartLoot_Options[key] = SmartLoot.Roll.Disenchant;
	elseif(v == "pass") then
		SmartLoot_Options[key] = SmartLoot.Roll.Pass;
	elseif(v == "need") then
		SmartLoot_Options[key] = SmartLoot.Roll.Need;
	elseif(v == "greed") then
		SmartLoot_Options[key] = SmartLoot.Roll.Greed;
	elseif(type(v) ~= "number") then
		SmartLoot_Options[key] = nil;
	end
end

function SmartLoot.ResolveRollType(desiredRoll, canNeed, canGreed, canDis)
	if(desiredRoll == SmartLoot.Roll.Disenchant) then
		if(canDis) then
			return SmartLoot.Roll.Disenchant;
		end
		if(canGreed) then
			return SmartLoot.Roll.Greed;
		end
		return SmartLoot.Roll.Pass;
	end
	if(desiredRoll == SmartLoot.Roll.Need and not canNeed) then
		return nil;
	end
	if(desiredRoll == SmartLoot.Roll.Greed and not canGreed) then
		return nil;
	end
	return desiredRoll;
end

function SmartLoot.IsWeaponItem(itemType, equipSlot)
	if(itemType == "Weapon") then
		return true;
	end
	return equipSlot and WEAPON_EQUIP_SLOTS[equipSlot] or false;
end

function SmartLoot.GetItemClassInfo(link)
	if(not link) then
		return nil;
	end
	local name, _, quality, _, _, itemType, _, _, equipSlot = GetItemInfo(link);
	if(not name) then
		return nil;
	end
	return {
		name = name;
		quality = quality;
		itemType = itemType;
		equipSlot = equipSlot or "";
		isWeapon = SmartLoot.IsWeaponItem(itemType, equipSlot);
		isEquippable = (equipSlot ~= nil and equipSlot ~= "");
	};
end

function SmartLoot.CategoryChoiceToRoll(choice)
	if(type(choice) == "number") then
		return choice;
	end
	return nil;
end

function SmartLoot.GetCategoryDesiredRoll(link, quality, canNeed, canGreed, canDis)
	local info = SmartLoot.GetItemClassInfo(link);
	if(not info or info.quality ~= 2) then
		return nil;
	end

	local choice = nil;
	if(info.isWeapon) then
		choice = SmartLoot_Options.AutoUncommonWeapons;
	elseif(info.isEquippable) then
		choice = SmartLoot_Options.AutoUncommonGear;
	end

	local desired = SmartLoot.CategoryChoiceToRoll(choice);
	if(desired == nil) then
		return nil;
	end
	return SmartLoot.ResolveRollType(desired, canNeed, canGreed, canDis);
end

function SmartLoot.GetDesiredRoll(name, link, quality, canNeed, canGreed, canDis)
	local named = SmartLoot_Autoroll[name];
	if(named) then
		return SmartLoot.ResolveRollType(named.roll, canNeed, canGreed, canDis);
	end
	return SmartLoot.GetCategoryDesiredRoll(link, quality, canNeed, canGreed, canDis);
end

function SmartLoot.MarkAutoConfirm(rollId)
	SmartLoot.PendingAutoConfirm = SmartLoot.PendingAutoConfirm or {};
	SmartLoot.PendingAutoConfirm[rollId] = true;
end

function SmartLoot.ClearAutoConfirm(rollId)
	if(SmartLoot.PendingAutoConfirm) then
		SmartLoot.PendingAutoConfirm[rollId] = nil;
	end
end

function SmartLoot.ShouldAutoConfirm(rollId)
	-- Auto-rolls always confirm; the option covers manual Need/Greed/DE clicks.
	if(SmartLoot.PendingAutoConfirm and SmartLoot.PendingAutoConfirm[rollId]) then
		SmartLoot.PendingAutoConfirm[rollId] = nil;
		return true;
	end
	return not not SmartLoot_Options.AutoConfirmAll;
end

function SmartLoot.SetAnchorDisplay()
	if(SmartLoot_Options.ShowAnchor) then
		SmartLoot_LootFrame_Anchor:Show();
	else
		SmartLoot_LootFrame_Anchor:Hide();
	end
end

function SmartLoot.ToggleDefaultFrames(show)
	local toggle;

	if(show) then
		toggle = function(frame)
			local rollId = frame.rollID;
			if(rollId ~= nil and GetLootRollTimeLeft(rollId) > 0) then
				frame:Show();
			end
		end
	else
		toggle = function(frame)
			frame:Hide();
		end
	end

	for id = 1, 4, 1 do
		local defaultLootFrame = getglobal("GroupLootFrame"..id);
		toggle(defaultLootFrame);
	end
end

function SmartLoot.SetRollButtonState(button, enabled)
	if(not button) then
		return;
	end
	if(enabled) then
		button:Enable();
	else
		button:Disable();
	end
end

-- Roll frame width: XML default is sized for vote counts visible.
SmartLoot.RollFrameWidthWithVotes = 350;
SmartLoot.VoteColumnWidth = 14; -- each Need/Greed/DE/Pass count column
SmartLoot.VoteColumnGap = 1; -- space between count and button

function SmartLoot.GetRollFrameWidth()
	local w = SmartLoot.RollFrameWidthWithVotes;
	if(not SmartLoot_Options or not SmartLoot_Options.ShowSelectedRolls) then
		w = w - 4 * (SmartLoot.VoteColumnWidth + SmartLoot.VoteColumnGap);
	end
	return w;
end

function SmartLoot.ApplyRollFrameLayout(frame)
	if(not frame) then
		return;
	end
	local show = not not (SmartLoot_Options and SmartLoot_Options.ShowSelectedRolls);
	local w = SmartLoot.GetRollFrameWidth();
	local infoW = w - 45;
	local name = frame:GetName();

	frame:SetWidth(w);
	getglobal(name.."_Timeout"):SetWidth(w);
	getglobal(name.."_Info"):SetWidth(infoW);
	getglobal(name.."_Info_ItemName"):SetWidth(infoW);

	local needVotes = getglobal(name.."_NeedVotes");
	local greedVotes = getglobal(name.."_GreedVotes");
	local deVotes = getglobal(name.."_DisenchantVotes");
	local passVotes = getglobal(name.."_PassVotes");
	local need = getglobal(name.."_Need");
	local greed = getglobal(name.."_Greed");
	local de = getglobal(name.."_Disenchant");
	local pass = getglobal(name.."_Pass");
	local icon = getglobal(name.."_Icon");
	local needAdv = getglobal(name.."_NeedAdvanced");
	local greedAdv = getglobal(name.."_GreedAdvanced");
	local deAdv = getglobal(name.."_DisenchantAdvanced");

	local function setVoteVisible(vote, visible)
		vote:SetWidth(SmartLoot.VoteColumnWidth);
		if(visible) then
			vote:Show();
			vote:EnableMouse(true);
		else
			vote:Hide();
			vote:EnableMouse(false);
		end
	end

	setVoteVisible(needVotes, show);
	setVoteVisible(greedVotes, show);
	setVoteVisible(deVotes, show);
	setVoteVisible(passVotes, show);

	-- Re-anchor the chain so buttons actually shift (hidden frames still take space if left in-chain).
	-- Avoid ClearAllPoints on UIPanelButtons — it can wipe their label FontStrings in 3.3.5.
	if(show) then
		needVotes:ClearAllPoints();
		needVotes:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 4, 2);
		need:SetPoint("BOTTOMLEFT", needVotes, "BOTTOMRIGHT", SmartLoot.VoteColumnGap, 0);

		greedVotes:ClearAllPoints();
		greedVotes:SetPoint("BOTTOMLEFT", needAdv, "BOTTOMRIGHT", 2, 2);
		greed:SetPoint("BOTTOMLEFT", greedVotes, "BOTTOMRIGHT", SmartLoot.VoteColumnGap, 0);

		deVotes:ClearAllPoints();
		deVotes:SetPoint("BOTTOMLEFT", greedAdv, "BOTTOMRIGHT", 2, 2);
		de:SetPoint("BOTTOMLEFT", deVotes, "BOTTOMRIGHT", SmartLoot.VoteColumnGap, 0);

		passVotes:ClearAllPoints();
		passVotes:SetPoint("BOTTOMLEFT", deAdv, "BOTTOMRIGHT", 2, 2);
		pass:SetPoint("BOTTOMLEFT", passVotes, "BOTTOMRIGHT", SmartLoot.VoteColumnGap, 0);
	else
		need:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 5, 2);
		greed:SetPoint("BOTTOMLEFT", needAdv, "BOTTOMRIGHT", 2, 2);
		de:SetPoint("BOTTOMLEFT", greedAdv, "BOTTOMRIGHT", 2, 2);
		pass:SetPoint("BOTTOMLEFT", deAdv, "BOTTOMRIGHT", 2, 2);
	end

	-- Restore labels in case a prior ClearAllPoints blanked them
	need:SetText("Need");
	greed:SetText("Greed");
	de:SetText("DE");
	pass:SetText("Pass");
end

function SmartLoot.ApplyAllRollFrameLayouts()
	if(not SmartLoot.LootFrames) then
		return;
	end
	for _, frame in ipairs(SmartLoot.LootFrames) do
		SmartLoot.ApplyRollFrameLayout(frame);
	end
end

function SmartLoot.PositionLootFrame(frame, id)
	frame:ClearAllPoints();
	local spacing = (id - 1) * 42;
	if(SmartLoot_Options.LootGrowUp) then
		frame:SetPoint("BOTTOM", SmartLoot_LootFrame_Anchor, "TOP", 0, spacing);
	else
		frame:SetPoint("TOP", SmartLoot_LootFrame_Anchor, "BOTTOM", 0, -spacing);
	end
end

function SmartLoot.CreateLootFrames()
	SmartLoot.LootFrames = {};

	for id = 1, SmartLoot_Options.LootFrameCount, 1 do
		local frameName = "SmartLoot_Loot"..id;
		local frame = getglobal(frameName);

		if(not frame) then
			frame = CreateFrame("Frame", frameName, UIParent, "SmartLoot_RollTemplate");
			frame:Hide();
			frame.loot = nil;

			local needDropDown = CreateFrame("Frame", frameName.."_AdvancedNeedDropDown", frame);
			needDropDown.initialize = SmartLoot.InitializeNeedDropDown;

			local greedDropDown = CreateFrame("Frame", frameName.."_AdvancedGreedDropDown", frame);
			greedDropDown.initialize = SmartLoot.InitializeGreedDropDown;

			local deDropDown = CreateFrame("Frame", frameName.."_AdvancedDisenchantDropDown", frame);
			deDropDown.initialize = SmartLoot.InitializeDisenchantDropDown;

			local passDropDown = CreateFrame("Frame", frameName.."_AdvancedPassDropDown", frame);
			passDropDown.initialize = SmartLoot.InitializePassDropDown;
		end

		SmartLoot.PositionLootFrame(frame, id);
		SmartLoot.ApplyRollFrameLayout(frame);
		SmartLoot.LootFrames[id] = frame;
	end
end

function SmartLoot.InitializeNeedDropDown(self)
	local lootFrame = self:GetParent();
	SmartLoot.AddAutoLootButton(SmartLoot.Roll.Need, "Need", lootFrame.loot);
end

function SmartLoot.InitializeGreedDropDown(self)
	local lootFrame = self:GetParent();
	SmartLoot.AddAutoLootButton(SmartLoot.Roll.Greed, "Greed", lootFrame.loot);
end

function SmartLoot.InitializeDisenchantDropDown(self)
	local lootFrame = self:GetParent();
	SmartLoot.AddAutoLootButton(SmartLoot.Roll.Disenchant, "Disenchant", lootFrame.loot);
end

function SmartLoot.InitializePassDropDown(self)
	local lootFrame = self:GetParent();
	SmartLoot.AddAutoLootButton(SmartLoot.Roll.Pass, "Pass", lootFrame.loot);
end

function SmartLoot.AddAutoLootButton(rollType, rollName, loot)
	local color = ITEM_QUALITY_COLORS[loot.quality];
	UIDropDownMenu_AddButton({
		text = "Always "..rollName.." on "..color.hex.."["..loot.name.."]|r";
		func = SmartLoot.AddAutoLoot;
		arg1 = { loot = loot; roll = rollType };
		notCheckable = true;
		justifyH = "CENTER";
	});
end

function SmartLoot.AddAutoLoot(self)
	local roll = self.arg1.roll;
	local loot = self.arg1.loot;

	SmartLoot_Autoroll[loot.name] = {
		quality = loot.quality;
		roll = roll;
	};

	local tmp = {};
	for i, l in ipairs(SmartLoot.Queue) do
		if(l.name == loot.name) then
			table.insert(tmp, l);
		end
	end

	for i, l in ipairs(tmp) do
		local resolved = SmartLoot.ResolveRollType(roll, l.canNeed, l.canGreed, l.canDis);
		if(resolved ~= nil) then
			SmartLoot.MarkAutoConfirm(l.rollId);
			RollOnLoot(l.rollId, resolved);
		end
	end

	if(SmartLoot.RefreshAutorollList) then
		SmartLoot.RefreshAutorollList();
	end
end

function SmartLoot.Initialize()
	tinsert(UISpecialFrames, "SmartLoot_OptionsFrame");
	SmartLoot.SetAnchorDisplay();
	SmartLoot.UpdateMinimapButtonPosition();
	SmartLoot.CreateLootFrames();
	SmartLoot.UpdateChatFilter();
	SmartLoot.Print("loaded. v"..SmartLoot.Version.." Use /sloot or minimap button to open options.");
end

function SmartLoot.QueueLoot(rollId, timeout, texture, name, quality, canNeed, canGreed, canDis, link)
	local itemKey = SmartLoot.ItemKeyFromText(link) or name;
	table.insert(SmartLoot.Queue, {
		rollId = rollId;
		timeout = timeout;
		texture = texture;
		name = name;
		quality = quality;
		canNeed = canNeed and true or false;
		canGreed = canGreed and true or false;
		canDis = canDis and true or false;
		link = link;
		itemKey = itemKey;
		r = false;
	});

	SmartLoot.EnsureRollVotes(itemKey);
	SmartLoot.ProcessQueue();
end

function SmartLoot.ProcessQueue()
	local i = 1;
	for j, frame in ipairs(SmartLoot.LootFrames) do
		local loot = SmartLoot.Queue[i];
		if(loot) then
			SmartLoot.PopulateLootFrame(frame, loot);
		else
			frame:Hide();
			frame.loot = nil;
		end
		i = i + 1;
	end
end

function SmartLoot.PopulateLootFrame(frame, loot)
	frame.loot = loot;

	local frameName = frame:GetName();
	local icon = getglobal(frameName.."_Icon_Image");
	local itemName = getglobal(frameName.."_Info_ItemName");
	local timeoutBar = getglobal(frameName.."_Timeout");

	timeoutBar:SetMinMaxValues(0, loot.timeout);
	timeoutBar:SetValue(loot.timeout);
	icon:SetTexture(loot.texture);
	itemName:SetText(loot.name);

	local color = ITEM_QUALITY_COLORS[loot.quality];
	itemName:SetTextColor(color.r, color.g, color.b, 1);

	-- Test loot: enable all buttons
	local canNeed = loot.canNeed;
	local canGreed = loot.canGreed;
	local canDis = loot.canDis;
	if(loot.rollId == -1) then
		canNeed = true;
		canGreed = true;
		canDis = true;
	end

	SmartLoot.SetRollButtonState(getglobal(frameName.."_Need"), canNeed);
	SmartLoot.SetRollButtonState(getglobal(frameName.."_NeedAdvanced"), canNeed);
	SmartLoot.SetRollButtonState(getglobal(frameName.."_Greed"), canGreed);
	SmartLoot.SetRollButtonState(getglobal(frameName.."_GreedAdvanced"), canGreed);
	SmartLoot.SetRollButtonState(getglobal(frameName.."_Disenchant"), canDis);
	SmartLoot.SetRollButtonState(getglobal(frameName.."_DisenchantAdvanced"), canDis);
	SmartLoot.SetRollButtonState(getglobal(frameName.."_Pass"), true);
	SmartLoot.SetRollButtonState(getglobal(frameName.."_PassAdvanced"), true);

	SmartLoot.UpdateFrameVoteCounts(frame);
	SmartLoot.ApplyRollFrameLayout(frame);
	frame:Show();
end

function SmartLoot.EnsureRollVotes(itemKey)
	if(not itemKey) then
		return nil;
	end
	local votes = SmartLoot.RollVotes[itemKey];
	if(not votes) then
		votes = { need = {}; greed = {}; disenchant = {}; pass = {} };
		SmartLoot.RollVotes[itemKey] = votes;
	end
	return votes;
end

function SmartLoot.ClearRollVotes(itemKey)
	if(itemKey) then
		SmartLoot.RollVotes[itemKey] = nil;
	end
end

function SmartLoot.RecordRollChoice(itemKey, choice, who)
	if(not itemKey or not choice or not who or who == "") then
		return;
	end
	local votes = SmartLoot.EnsureRollVotes(itemKey);
	-- One selection per player
	for _, list in pairs(votes) do
		for i = #list, 1, -1 do
			if(list[i] == who) then
				table.remove(list, i);
			end
		end
	end
	table.insert(votes[choice], who);
	SmartLoot.RefreshVoteCountsForItem(itemKey);
end

function SmartLoot.RefreshVoteCountsForItem(itemKey)
	if(not SmartLoot.LootFrames) then
		return;
	end
	for _, frame in ipairs(SmartLoot.LootFrames) do
		if(frame.loot and frame.loot.itemKey == itemKey) then
			SmartLoot.UpdateFrameVoteCounts(frame);
		end
	end
end

function SmartLoot.UpdateFrameVoteCounts(frame)
	if(not frame) then
		return;
	end
	local votes = (frame.loot and frame.loot.itemKey and SmartLoot.RollVotes[frame.loot.itemKey])
		or { need = {}; greed = {}; disenchant = {}; pass = {} };
	local name = frame:GetName();
	getglobal(name.."_NeedVotes_Text"):SetText(tostring(#votes.need));
	getglobal(name.."_GreedVotes_Text"):SetText(tostring(#votes.greed));
	getglobal(name.."_DisenchantVotes_Text"):SetText(tostring(#votes.disenchant));
	getglobal(name.."_PassVotes_Text"):SetText(tostring(#votes.pass));
end

function SmartLoot.OnVoteCountEnter(voteFrame)
	local lootFrame = voteFrame:GetParent();
	local choice = voteFrame.choice;
	if(not lootFrame or not choice) then
		return;
	end
	local votes = (lootFrame.loot and lootFrame.loot.itemKey and SmartLoot.RollVotes[lootFrame.loot.itemKey]);
	local list = votes and votes[choice] or {};
	local titles = {
		need = "Need";
		greed = "Greed";
		disenchant = "Disenchant";
		pass = "Pass";
	};

	GameTooltip:SetOwner(voteFrame, "ANCHOR_TOP");
	GameTooltip:ClearLines();
	GameTooltip:AddLine(titles[choice] or choice, 1, 1, 1);
	if(#list == 0) then
		GameTooltip:AddLine("Nobody yet", 0.5, 0.5, 0.5);
	else
		for i = 1, #list do
			GameTooltip:AddLine(list[i], 1, 0.82, 0);
		end
	end
	GameTooltip:Show();
end

function SmartLoot.ClearLoot(rollId)
	rollId = tonumber(rollId) or rollId;
	local clearedKey = nil;
	for i, loot in ipairs(SmartLoot.Queue) do
		if(tonumber(loot.rollId) == rollId or loot.rollId == rollId) then
			clearedKey = loot.itemKey;
			table.remove(SmartLoot.Queue, i);
			break;
		end
	end

	-- Drop vote data once no queued rolls remain for this item
	if(clearedKey) then
		local stillActive = false;
		for _, loot in ipairs(SmartLoot.Queue) do
			if(loot.itemKey == clearedKey) then
				stillActive = true;
				break;
			end
		end
		if(not stillActive) then
			SmartLoot.ClearRollVotes(clearedKey);
		end
	end

	SmartLoot.ProcessQueue();
	StaticPopup_Hide("CONFIRM_LOOT_ROLL", rollId);
	StaticPopup_Hide("CONFIRM_DISENCHANT_ROLL", rollId);
end

function SmartLoot.OnTimeoutBarUpdate(self)
	if(not self.loot) then
		return;
	end

	local rollId = self.loot.rollId;
	-- Fake test loot has no server roll id
	if(rollId == -1) then
		return;
	end

	local remaining = GetLootRollTimeLeft(rollId);
	-- Like XLootGroup's timeout path: roll is gone when time is nil/<=0 (CANCEL may not always fire).
	-- Huge values are a known dead-roll sentinel on some clients.
	if(not remaining or remaining <= 0 or remaining > 1000000000) then
		SmartLoot.ClearLoot(rollId);
		return;
	end

	local timeoutBar = getglobal(self:GetName().."_Timeout");
	timeoutBar:SetValue(remaining);
end

function SmartLoot.RollNeed(self)
	RollOnLoot(self.loot.rollId, SmartLoot.Roll.Need);
end

function SmartLoot.RollGreed(self)
	RollOnLoot(self.loot.rollId, SmartLoot.Roll.Greed);
end

function SmartLoot.RollDisenchant(self)
	RollOnLoot(self.loot.rollId, SmartLoot.Roll.Disenchant);
end

function SmartLoot.Pass(self)
	RollOnLoot(self.loot.rollId, SmartLoot.Roll.Pass);
end

function SmartLoot.OnIconEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -(self:GetWidth()), 0);
	GameTooltip:SetLootRollItem(self.loot.rollId);
	GameTooltip:Show();
end

function SmartLoot.OnIconLeave(self)
	GameTooltip:Hide();
end

function SmartLoot.ToggleTestLoot(show)
	if(show) then
		for i = 1, SmartLoot_Options.LootFrameCount, 1 do
			SmartLoot.QueueLoot(-1, 60000, "Interface\\Icons\\INV_Helmet_51", "Crimson Felt Hat", 3, true, true, true, nil);
		end
	else
		for i, loot in ipairs(SmartLoot.Queue) do
			if(loot.rollId == -1) then
				SmartLoot.Queue[i] = nil;
			end
		end
		SmartLoot.ProcessQueue();
	end
end

function SmartLoot.ToggleOptions()
	local f = SmartLoot_OptionsFrame;
	if(f:IsVisible()) then
		f:Hide();
	else
		f:Show();
	end
end

function SmartLoot.Print(text)
	if(text == nil) then
		text = "-nil-";
	end
	DEFAULT_CHAT_FRAME:AddMessage("SmartLoot: "..(text));
end

------------------------------------------------------------
-- Chat roll spam filter + summary
------------------------------------------------------------

local function EscapePattern(text)
	-- Escape Lua pattern magic except '%' (handled as format tokens below)
	return (string.gsub(text, "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"));
end

-- Convert a Blizzard format string (%s / %d) into a Lua pattern with captures.
local function FormatToLuaPattern(fmt)
	if(not fmt) then
		return nil;
	end
	local pattern = EscapePattern(fmt);
	pattern = string.gsub(pattern, "%%s", "(.+)");
	pattern = string.gsub(pattern, "%%d", "(%%d+)");
	pattern = string.gsub(pattern, "%%%%", "%%");
	return "^"..pattern.."$";
end

function SmartLoot.BuildChatPatterns()
	local patterns = {};

	local function add(fmt, kind, captureMap)
		local pat = FormatToLuaPattern(fmt);
		if(pat) then
			table.insert(patterns, { pattern = pat; kind = kind; map = captureMap });
		end
	end

	-- Selection / pass: track votes on the roll frame; optionally suppress in chat
	add(LOOT_ROLL_NEED, "choice", { who = 1; item = 2; choice = "need" });
	add(LOOT_ROLL_GREED, "choice", { who = 1; item = 2; choice = "greed" });
	if(LOOT_ROLL_DISENCHANT) then
		add(LOOT_ROLL_DISENCHANT, "choice", { who = 1; item = 2; choice = "disenchant" });
	end
	add(LOOT_ROLL_NEED_SELF, "choice", { item = 1; choice = "need"; self = true });
	add(LOOT_ROLL_GREED_SELF, "choice", { item = 1; choice = "greed"; self = true });
	if(LOOT_ROLL_DISENCHANT_SELF) then
		add(LOOT_ROLL_DISENCHANT_SELF, "choice", { item = 1; choice = "disenchant"; self = true });
	end
	add(LOOT_ROLL_PASSED, "choice", { who = 1; item = 2; choice = "pass" });
	add(LOOT_ROLL_PASSED_SELF, "choice", { item = 1; choice = "pass"; self = true });
	add(LOOT_ROLL_PASSED_AUTO, "choice", { who = 1; item = 2; choice = "pass" });
	if(LOOT_ROLL_PASSED_AUTO_FEMALE) then
		add(LOOT_ROLL_PASSED_AUTO_FEMALE, "choice", { who = 1; item = 2; choice = "pass" });
	end
	if(LOOT_ROLL_PASSED_SELF_AUTO) then
		add(LOOT_ROLL_PASSED_SELF_AUTO, "choice", { item = 1; choice = "pass"; self = true });
	end

	-- Rolled: typically "Need Roll - %d for %s by %s" => roll, item, who
	add(LOOT_ROLL_ROLLED_NEED, "rolled", { roll = 1; item = 2; who = 3; tier = "need" });
	add(LOOT_ROLL_ROLLED_GREED, "rolled", { roll = 1; item = 2; who = 3; tier = "greedde" });
	if(LOOT_ROLL_ROLLED_DE) then
		add(LOOT_ROLL_ROLLED_DE, "rolled", { roll = 1; item = 2; who = 3; tier = "greedde"; isDE = true });
	end

	-- Resolve: WON lines are never suppressed (see HandleRollChatMessage); still matched for summary
	add(LOOT_ROLL_WON, "won", { who = 1; item = 2 });
	if(LOOT_ROLL_YOU_WON) then
		add(LOOT_ROLL_YOU_WON, "won", { item = 1 });
	end
	add(LOOT_ROLL_ALL_PASSED, "allpassed", { item = 1 });

	SmartLoot.RollChat.patterns = patterns;
end

function SmartLoot.ItemKeyFromText(itemText)
	if(not itemText) then
		return nil;
	end
	local link = string.match(itemText, "|H(item:[^|]+)|h");
	if(link) then
		return link;
	end
	local name = string.match(itemText, "%[(.-)%]");
	return name or itemText;
end

local function DisplayItemFromText(itemText)
	if(not itemText) then
		return "item";
	end
	local colored = string.match(itemText, "|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r");
	if(colored) then
		return colored;
	end
	local bracket = string.match(itemText, "%[[^%]]+%]");
	return bracket or itemText;
end

function SmartLoot.EnsureRollBuffer(itemKey, itemDisplay)
	local buf = SmartLoot.RollChat.buffers[itemKey];
	if(not buf) then
		buf = { need = {}; greedde = {}; hadGreed = false; hadDE = false; itemDisplay = itemDisplay };
		SmartLoot.RollChat.buffers[itemKey] = buf;
	elseif(itemDisplay and not buf.itemDisplay) then
		buf.itemDisplay = itemDisplay;
	end
	return buf;
end

function SmartLoot.EmitRollSummary(itemKey)
	local buf = SmartLoot.RollChat.buffers[itemKey];
	SmartLoot.RollChat.buffers[itemKey] = nil;
	if(not buf) then
		return;
	end

	local itemDisplay = buf.itemDisplay or itemKey;
	local list;
	local prefix;

	if(buf.need and #buf.need > 0) then
		list = buf.need;
		prefix = "Need rolls";
	elseif(buf.greedde and #buf.greedde > 0) then
		list = buf.greedde;
		if(buf.hadDE and buf.hadGreed) then
			prefix = "DE/Greed rolls";
		elseif(buf.hadDE) then
			prefix = "DE rolls";
		else
			prefix = "Greed rolls";
		end
	else
		DEFAULT_CHAT_FRAME:AddMessage("All passed on "..itemDisplay, 1.0, 1.0, 0.0);
		return;
	end

	table.sort(list, function(a, b)
		return a.roll > b.roll;
	end);
	local parts = {};
	local top = math.min(3, #list);
	for i = 1, top do
		table.insert(parts, list[i].name.." ("..list[i].roll..")");
	end
	local line = prefix.." for "..itemDisplay..": "..table.concat(parts, ", ");
	if(#list > 3) then
		line = line..", +"..(#list - 3);
	end

	DEFAULT_CHAT_FRAME:AddMessage(line, 1.0, 1.0, 0.0);
end

-- Returns true if this is a suppressible roll-spam line (chose / rolled / passed / all-passed).
function SmartLoot.HandleRollChatMessage(msg)
	if(not SmartLoot.RollChat.patterns) then
		SmartLoot.BuildChatPatterns();
	end

	for i, entry in ipairs(SmartLoot.RollChat.patterns) do
		local a1, a2, a3, a4 = string.match(msg, entry.pattern);
		if(a1) then
			local caps = { a1, a2, a3, a4 };

			if(entry.kind == "choice" and entry.map) then
				local who = entry.map.self and UnitName("player") or caps[entry.map.who];
				local itemText = caps[entry.map.item];
				local key = SmartLoot.ItemKeyFromText(itemText);
				-- Prefer matching an active loot frame by item name if link keys differ slightly
				if(key) then
					local matched = false;
					if(SmartLoot.Queue) then
						for _, loot in ipairs(SmartLoot.Queue) do
							if(loot.itemKey == key or loot.name == key or (itemText and string.find(itemText, loot.name, 1, true))) then
								SmartLoot.RecordRollChoice(loot.itemKey, entry.map.choice, who);
								matched = true;
								break;
							end
						end
					end
					if(not matched) then
						SmartLoot.RecordRollChoice(key, entry.map.choice, who);
					end
				end
			elseif(entry.kind == "rolled" and entry.map and SmartLoot_Options.IncludeRollSummary) then
				local who = caps[entry.map.who];
				local roll = tonumber(caps[entry.map.roll]);
				local itemText = caps[entry.map.item];
				local key = SmartLoot.ItemKeyFromText(itemText);
				if(key and who and roll) then
					local buf = SmartLoot.EnsureRollBuffer(key, DisplayItemFromText(itemText));
					table.insert(buf[entry.map.tier], { name = who; roll = roll });
					if(entry.map.tier == "greedde") then
						if(entry.map.isDE) then
							buf.hadDE = true;
						else
							buf.hadGreed = true;
						end
					end
				end
			elseif(entry.kind == "won" and entry.map) then
				local itemText = caps[entry.map.item];
				local key = SmartLoot.ItemKeyFromText(itemText);
				if(key and SmartLoot_Options.IncludeRollSummary) then
					SmartLoot.EnsureRollBuffer(key, DisplayItemFromText(itemText));
					SmartLoot.EmitRollSummary(key);
				elseif(key) then
					SmartLoot.RollChat.buffers[key] = nil;
				end
				SmartLoot.ClearRollVotes(key);
				-- Always leave Blizzard WON lines visible
				return false;
			elseif(entry.kind == "allpassed" and entry.map) then
				local itemText = caps[entry.map.item];
				local key = SmartLoot.ItemKeyFromText(itemText);
				if(key and SmartLoot_Options.IncludeRollSummary) then
					SmartLoot.EnsureRollBuffer(key, DisplayItemFromText(itemText));
					SmartLoot.EmitRollSummary(key);
				elseif(key) then
					SmartLoot.RollChat.buffers[key] = nil;
				end
				SmartLoot.ClearRollVotes(key);
			end

			-- Suppress chose / rolled / passed / all-passed only when filter is on
			return true;
		end
	end
	return false;
end

function SmartLoot.ChatLootFilter(self, event, msg, ...)
	local isRollLine = SmartLoot.HandleRollChatMessage(msg);
	if(isRollLine and SmartLoot_Options and SmartLoot_Options.FilterChatRollSpam) then
		return true;
	end
	return false;
end

function SmartLoot.UpdateChatFilter()
	if(not ChatFrame_AddMessageEventFilter) then
		return;
	end
	-- Always registered so vote counts update even when chat filter is off
	if(not SmartLoot.RollChat.filterRegistered) then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_LOOT", SmartLoot.ChatLootFilter);
		SmartLoot.RollChat.filterRegistered = true;
	end
end
