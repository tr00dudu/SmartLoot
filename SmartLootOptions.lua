function SmartLoot.PopulateOptionsUI()
	local setCheckbox = function(option, frame)
		frame = frame or getglobal("SmartLoot_OptionsFrame_"..option);
		frame:SetChecked(SmartLoot_Options[option]);
	end;

	setCheckbox("ShowAnchor");
	setCheckbox("UseSmartLootFrames");
	setCheckbox("AutoLoot", SmartLoot_OptionsFrame_AutoRollPanel_AutoLoot);
	setCheckbox("AutoConfirmAll");
	setCheckbox("ShowMinimapButton");
	setCheckbox("FilterChatRollSpam");
	setCheckbox("IncludeRollSummary");
	setCheckbox("ShowSelectedRolls");
	setCheckbox("LootGrowUp");

	SmartLoot_OptionsFrame_LootFrameCount_CountText:SetText(SmartLoot_Options.LootFrameCount);

	SmartLoot.UpdateRollSummaryCheckboxState();
	SmartLoot.UpdateSmartLootFramesOptionsState();
	SmartLoot.UpdateGenericRollUI();
	SmartLoot.RefreshAutorollList();
	SmartLoot.UpdateAutoLootUIState();
end

function SmartLoot.UpdateSmartLootFramesOptionsState()
	local enabled = not not SmartLoot_Options.UseSmartLootFrames;
	local function setEnabled(frame)
		if(not frame) then
			return;
		end
		if(enabled) then
			frame:Enable();
		else
			frame:Disable();
		end
	end

	setEnabled(SmartLoot_OptionsFrame_ShowSelectedRolls);
	setEnabled(SmartLoot_OptionsFrame_ShowAnchor);
	setEnabled(SmartLoot_OptionsFrame_LootGrowUp);
	setEnabled(SmartLoot_OptionsFrame_TestLoot);
	setEnabled(SmartLoot_OptionsFrame_LootFrameCount_Dec);
	setEnabled(SmartLoot_OptionsFrame_LootFrameCount_Inc);
end

function SmartLoot.UpdateAutoLootUIState()
	local panel = SmartLoot_OptionsFrame_AutoRollPanel;
	if(not panel) then
		return;
	end

	local enabled = not not SmartLoot_Options.AutoLoot;
	local alpha = enabled and 1 or 0.45;
	local prefix = panel:GetName();

	local function setEnabled(btn, on)
		if(not btn) then
			return;
		end
		if(on) then
			btn:Enable();
		else
			btn:Disable();
		end
	end

	local function setRowRadios(row, on)
		if(not row) then
			return;
		end
		local name = row:GetName();
		setEnabled(getglobal(name.."_Need"), on);
		setEnabled(getglobal(name.."_Greed"), on);
		setEnabled(getglobal(name.."_Disenchant"), on);
		setEnabled(getglobal(name.."_Pass"), on);
	end

	local weapons = getglobal(prefix.."_Weapons");
	local gear = getglobal(prefix.."_Gear");
	local list = getglobal(prefix.."_AutorollList");
	weapons:SetAlpha(alpha);
	gear:SetAlpha(alpha);
	list:SetAlpha(alpha);

	getglobal(prefix.."_ColNeed"):SetAlpha(alpha);
	getglobal(prefix.."_ColGreed"):SetAlpha(alpha);
	getglobal(prefix.."_ColDE"):SetAlpha(alpha);
	getglobal(prefix.."_ColPass"):SetAlpha(alpha);

	local perItem = getglobal(prefix.."_PerItemTitle");
	perItem:SetAlpha(alpha);
	perItem:SetFontObject(enabled and GameFontHighlight or GameFontDisable);

	setRowRadios(weapons, enabled);
	setRowRadios(gear, enabled);

	for i = 1, SmartLoot.AutorollList and SmartLoot.AutorollList.PageSize or 10 do
		local row = getglobal(list:GetName().."_Item"..i);
		setRowRadios(row, enabled);
		setEnabled(getglobal(list:GetName().."_Item"..i.."_X"), enabled);
	end

	local scroll = getglobal(list:GetName().."_ScrollBar");
	if(scroll) then
		scroll:EnableMouse(enabled);
	end
end

function SmartLoot.UpdateRollSummaryCheckboxState()
	local cb = SmartLoot_OptionsFrame_IncludeRollSummary;
	if(not cb) then
		return;
	end
	if(SmartLoot_Options.FilterChatRollSpam) then
		cb:Enable();
	else
		cb:Disable();
	end
end

function SmartLoot.SetRollRadios(frame, roll)
	getglobal(frame:GetName().."_Need"):SetChecked(roll == SmartLoot.Roll.Need);
	getglobal(frame:GetName().."_Greed"):SetChecked(roll == SmartLoot.Roll.Greed);
	getglobal(frame:GetName().."_Disenchant"):SetChecked(roll == SmartLoot.Roll.Disenchant);
	getglobal(frame:GetName().."_Pass"):SetChecked(roll == SmartLoot.Roll.Pass);
end

function SmartLoot.UpdateGenericRollUI()
	SmartLoot.SetRollRadios(SmartLoot_OptionsFrame_AutoRollPanel_Weapons, SmartLoot_Options.AutoUncommonWeapons);
	SmartLoot.SetRollRadios(SmartLoot_OptionsFrame_AutoRollPanel_Gear, SmartLoot_Options.AutoUncommonGear);
end

function SmartLoot.SetGenericRoll(optionKey, roll)
	local current = SmartLoot_Options[optionKey];
	-- Clicking the already-selected radio clears it (Off)
	if(current == roll) then
		SmartLoot_Options[optionKey] = nil;
	else
		SmartLoot_Options[optionKey] = roll;
	end
	SmartLoot.UpdateGenericRollUI();
end

function SmartLoot.UpdateAutorollListScrollBar()
	FauxScrollFrame_Update(SmartLoot_OptionsFrame_AutoRollPanel_AutorollList_ScrollBar, SmartLoot.AutorollList.TotalCount, SmartLoot.AutorollList.PageSize, 20);
	SmartLoot.AutorollList.Offset = FauxScrollFrame_GetOffset(SmartLoot_OptionsFrame_AutoRollPanel_AutorollList_ScrollBar);
	SmartLoot.RenderAutorollList();
end

function SmartLoot.OnOptionsHide()
	if(SmartLoot.AutorollList) then
		SmartLoot.AutorollList.DataSource = nil;
	end
end

function SmartLoot.RefreshAutorollList()
	if(not SmartLoot_OptionsFrame_AutoRollPanel_AutorollList) then
		return;
	end
	SmartLoot.AutorollList = SmartLoot.AutorollList or {};
	SmartLoot.AutorollList.Offset = SmartLoot.AutorollList.Offset or 0;
	SmartLoot.AutorollList.PageSize = 10;
	SmartLoot.AutorollList.DataSource = nil;
	SmartLoot.RenderAutorollList();
end

function SmartLoot.RenderAutorollList()
	if(not SmartLoot.AutorollList) then
		SmartLoot.AutorollList = { Offset = 0; PageSize = 10 };
	end

	if(SmartLoot.AutorollList.DataSource == nil) then
		SmartLoot.AutorollList.TotalCount, SmartLoot.AutorollList.DataSource = SmartLoot.GetAutorollListData();
	end

	local list = SmartLoot_OptionsFrame_AutoRollPanel_AutorollList;
	local empty = getglobal(list:GetName().."_Empty");
	local info = getglobal(list:GetName().."_Info");
	local total = SmartLoot.AutorollList.TotalCount or 0;

	if(total == 0) then
		empty:SetText("No remembered items.\nUse Always Need/Greed/DE/Pass on a loot frame.");
		empty:Show();
		info:SetText("0 items");
	else
		empty:Hide();
		info:SetText(total.." item"..(total == 1 and "" or "s"));
	end

	local hide = false;
	local displayedCount = 0;

	for i = 1, SmartLoot.AutorollList.PageSize, 1 do
		local frame = getglobal(list:GetName().."_Item"..i);
		if(hide) then
			frame:Hide();
			frame.itemName = nil;
		else
			local index = i + (SmartLoot.AutorollList.Offset or 0);
			local row = SmartLoot.AutorollList.DataSource[index];
			if(not row) then
				hide = true;
				frame:Hide();
				frame.itemName = nil;
			else
				local color = ITEM_QUALITY_COLORS[row.quality] or ITEM_QUALITY_COLORS[1];
				local text = getglobal(frame:GetName().."_Text");
				frame.itemName = row.name;
				frame.index = index;
				text:SetText(row.name);
				text:SetTextColor(color.r, color.g, color.b);
				SmartLoot.SetRollRadios(frame, row.roll);
				frame:Show();
				displayedCount = displayedCount + 1;
			end
		end
	end

	FauxScrollFrame_Update(SmartLoot_OptionsFrame_AutoRollPanel_AutorollList_ScrollBar, total, SmartLoot.AutorollList.PageSize, 20);
	SmartLoot.UpdateAutoLootUIState();
end

function SmartLoot.AutorollListRemove(self)
	if(not self.itemName) then
		return;
	end
	SmartLoot_Autoroll[self.itemName] = nil;
	SmartLoot.AutorollList.DataSource = nil;
	SmartLoot.RenderAutorollList();
end

function SmartLoot.SetAutoroll(self, roll)
	if(not self.itemName or not SmartLoot_Autoroll[self.itemName]) then
		return;
	end
	SmartLoot_Autoroll[self.itemName].roll = roll;
	if(SmartLoot.AutorollList.DataSource and self.index) then
		SmartLoot.AutorollList.DataSource[self.index].roll = roll;
	end
	SmartLoot.RenderAutorollList();
end

function SmartLoot.SetOption(option, value)
	if(value == nil) then
		value = false;
	end
	SmartLoot_Options[option] = value;

	if(option == "ShowAnchor") then
		SmartLoot.SetAnchorDisplay();
	elseif(option == "LootFrameCount") then
		SmartLoot_OptionsFrame_LootFrameCount_CountText:SetText(SmartLoot_Options.LootFrameCount);
		SmartLoot.CreateLootFrames();
	elseif(option == "LootGrowUp") then
		SmartLoot.CreateLootFrames();
		SmartLoot.ProcessQueue();
	elseif(option == "UseSmartLootFrames") then
		SmartLoot.UpdateSmartLootFramesOptionsState();
	elseif(option == "ShowMinimapButton" or option == "MinimapButtonPosition") then
		SmartLoot.UpdateMinimapButtonPosition();
	elseif(option == "FilterChatRollSpam") then
		SmartLoot.UpdateChatFilter();
		SmartLoot.UpdateRollSummaryCheckboxState();
	elseif(option == "AutoLoot") then
		SmartLoot.UpdateAutoLootUIState();
	elseif(option == "ShowSelectedRolls") then
		SmartLoot.ApplyAllRollFrameLayouts();
	end
end

function SmartLoot.GetAutorollListData()
	local result = {};
	local count = 0;
	for name, info in sorted(SmartLoot_Autoroll) do
		table.insert(result, { name = name, quality = info.quality, roll = info.roll });
		count = count + 1;
	end
	return count, result;
end

function sorted(t, f)
	local a = {};
	for n in pairs(t) do table.insert(a, n); end
	table.sort(a, f);
	local i = 0;
	local iter = function ()
		i = i + 1;
		if a[i] == nil then return nil;
		else return a[i], t[a[i]];
		end
	end
	return iter;
end
