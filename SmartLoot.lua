SmartLoot = {};

SmartLoot.Version = "1.3";

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

-- roll buttons in the order they appear on a loot frame; suffix matches the
-- $parent_<suffix> / $parent_<suffix>Advanced widgets in SmartLoot_RollTemplate
SmartLoot.RollButtons = {
	{ suffix = "Need"; label = "Need"; roll = SmartLoot.Roll.Need };
	{ suffix = "Greed"; label = "Greed"; roll = SmartLoot.Roll.Greed };
	{ suffix = "Disenchant"; label = "Disenchant"; roll = SmartLoot.Roll.Disenchant };
	{ suffix = "Pass"; label = "Pass"; roll = SmartLoot.Roll.Pass };
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
		Tooltip = "Wether to hide default blizzard group loot UI. Unchecking this will show any active loot frames. Can be used for debugging.";
	};
	AutoLoot = {
		Label = "Autoloot";
		Tooltip = "Automatically roll on loot using defined loot rules.";
	};
	AutoConfirm = {
		Label = "Autoconfirm rolls";
		Tooltip = "Automatically confim rolling on BoP items and disenchanting.";
	};
	LootFrameCount = {
		Label = "Loot frame count";
		Tooltip = "Number of loot frames that can be visible at a time.";
	};
	TestLoot = {
		Label = "Show test loot";
		Tooltip = "Displays a fake loot item for each loot frame. This option is not saved. Rolling on this loot doesn't work, use this checkbox again to delete it.";
	};
	ShowMinimapButton = {
		Label = "Show minimap button";
		Tooltip = "";
	};
	MinimapButtonPosition = "Minimap button position";
}

function SmartLoot.OnLoad(self)

	SLASH_SLOOT1 = "/sloot";

	SlashCmdList["SLOOT"] = function(msg)
		SmartLoot.ToggleOptions();
	end

	-- registered from lua rather than xml so the handler gets the event
	-- arguments passed as parameters instead of via the removed arg1 globals
	self:SetScript("OnEvent", SmartLoot.OnEvent);

	self:RegisterEvent("CONFIRM_LOOT_ROLL");
	self:RegisterEvent("CONFIRM_DISENCHANT_ROLL");
	self:RegisterEvent("START_LOOT_ROLL");
	self:RegisterEvent("ADDON_LOADED");
	self:RegisterEvent("CANCEL_LOOT_ROLL");
end

function SmartLoot.OnEvent(self, event, arg1, arg2)
	if(event == "START_LOOT_ROLL") then
		if(SmartLoot_Options.HideDefaultFrames) then
			SmartLoot.ToggleDefaultFrames(false);
		end

		local rollId = arg1;
		local timeout = arg2;

		local loot = SmartLoot.GetLootInfo(rollId, timeout);
		local autoroll = SmartLoot_Autoroll[loot.name];

		-- an autoroll rule for a roll the server won't accept (need on an item
		-- of the wrong armour type, disenchant without the skill, ...) would be
		-- silently dropped, so fall back to showing the frame
		if(SmartLoot_Options.AutoLoot and autoroll and loot.can[autoroll.roll]) then
			RollOnLoot(rollId, autoroll.roll);
		else
			SmartLoot.QueueLoot(loot);
		end
	elseif(event == "CANCEL_LOOT_ROLL") then
		-- fires after rolling or passing on an item
		SmartLoot.ClearLoot(arg1);
	elseif(event == "CONFIRM_LOOT_ROLL" or event == "CONFIRM_DISENCHANT_ROLL") then
		if(SmartLoot_Options.AutoConfirm) then
			ConfirmLootRoll(arg1, arg2);
			StaticPopup_Hide("CONFIRM_LOOT_ROLL", arg1);
		end
	elseif(event == "ADDON_LOADED" and arg1 == "SmartLoot") then
		SmartLoot.EnsureOptions();
		SmartLoot.Initialize();
	end
end

-- LOOT_ROLL_INELIGIBLE_REASON<n> explains why a roll type is unavailable;
-- reason 5 (disenchant) takes the required skill level as a format argument
function SmartLoot.IneligibleReason(reason, deSkillRequired)
	if(not reason or reason == 0) then
		return nil;
	end

	local text = getglobal("LOOT_ROLL_INELIGIBLE_REASON"..reason);

	if(not text) then
		return nil;
	end

	-- some reason strings take the required skill level as a format argument,
	-- the rest are plain text
	if(string.find(text, "%%[ds]")) then
		return string.format(text, deSkillRequired or 0);
	end

	return text;
end

-- ITEM_QUALITY_COLORS doesn't necessarily have an entry for every quality the
-- client has a name for, so never index it directly
function SmartLoot.QualityColor(quality)
	return ITEM_QUALITY_COLORS[quality or 1]
		or ITEM_QUALITY_COLORS[1]
		or { r = 1; g = 1; b = 1; hex = "|cffffffff" };
end

function SmartLoot.GetLootInfo(rollId, timeout)
	local texture, name, count, quality, bindOnPickup, canNeed, canGreed, canDisenchant,
		reasonNeed, reasonGreed, reasonDisenchant, deSkillRequired = GetLootRollItemInfo(rollId);

	local loot = {
		rollId = rollId;
		timeout = timeout;
		texture = texture;
		-- START_LOOT_ROLL occasionally fires before the item is cached
		name = name or ("Item "..rollId);
		quality = quality or 1;
		can = {};
		reason = {};
	};

	if(canNeed == nil and canGreed == nil and canDisenchant == nil) then
		-- client doesn't report eligibility, assume everything is allowed
		canNeed, canGreed, canDisenchant = true, true, false;
	end

	loot.can[SmartLoot.Roll.Need] = (canNeed and true) or false;
	loot.can[SmartLoot.Roll.Greed] = (canGreed and true) or false;
	loot.can[SmartLoot.Roll.Disenchant] = (canDisenchant and true) or false;
	loot.can[SmartLoot.Roll.Pass] = true;

	loot.reason[SmartLoot.Roll.Need] = SmartLoot.IneligibleReason(reasonNeed);
	loot.reason[SmartLoot.Roll.Greed] = SmartLoot.IneligibleReason(reasonGreed);
	loot.reason[SmartLoot.Roll.Disenchant] = SmartLoot.IneligibleReason(reasonDisenchant, deSkillRequired);

	return loot;
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
	set("AutoConfirm", true);
	set("LootFrameCount", 4);
	set("MinimapButtonPosition", 281);
	set("ShowMinimapButton", true);
end

function SmartLoot.SetAnchorDisplay()
	if(SmartLoot_Options.ShowAnchor) then
		SmartLoot_LootFrame:Show();
	else
		SmartLoot_LootFrame:Hide();
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

	for id = 1, (NUM_GROUP_LOOT_FRAMES or 4), 1 do
		local defaultLootFrame = getglobal("GroupLootFrame"..id);

		if(defaultLootFrame) then
			toggle(defaultLootFrame);
		end
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
			frame:SetPoint("TOP", SmartLoot_LootFrame, "BOTTOM", 0, (id - 1) * -40 - (id - 1) * 2)
			frame.loot = nil;

			for i, button in ipairs(SmartLoot.RollButtons) do
				local dropDown = CreateFrame("Frame", frameName.."_Advanced"..button.suffix.."DropDown", frame);

				-- the dropdown initializer is invoked as dropDown:initialize(level, menuList)
				dropDown.initialize = function(dd, level)
					SmartLoot.InitializeRollDropDown(dd, button.roll, button.label);
				end
			end
		end

		SmartLoot.LootFrames[id] = frame;

	end

	-- frames created by a previously higher LootFrameCount are no longer part of
	-- the queue rotation and would otherwise stay on screen forever
	local orphan = SmartLoot_Options.LootFrameCount + 1;
	while(getglobal("SmartLoot_Loot"..orphan)) do
		local frame = getglobal("SmartLoot_Loot"..orphan);
		frame:Hide();
		frame.loot = nil;
		orphan = orphan + 1;
	end
end

function SmartLoot.InitializeRollDropDown(dropDown, roll, rollName)
	local lootFrame = dropDown:GetParent();

	if(not lootFrame.loot) then
		return;
	end

	SmartLoot.AddAutoLootButton(roll, rollName, lootFrame.loot);
end

function SmartLoot.AddAutoLootButton(roll, rollName, loot)
	local color = SmartLoot.QualityColor(loot.quality);
	UIDropDownMenu_AddButton({
		text = "Always "..rollName.." on "..color.hex.."["..loot.name.."]|r";
		func = SmartLoot.AddAutoLoot;
		arg1 = { loot = loot; roll = roll };
		notCheckable = true;
		justifyH = "CENTER";
	});
end

function SmartLoot.AddAutoLoot(self, arg1)
	local roll = arg1.roll;
	local loot = arg1.loot;

	SmartLoot_Autoroll[loot.name] = {
		quality = loot.quality;
		roll = roll;
	};

	local tmp = {};

	for i, l in ipairs(SmartLoot.Queue) do
		if(l.name == loot.name and l.can[roll]) then
			table.insert(tmp, l.rollId);
		end
	end

	for i, id in ipairs(tmp) do
		RollOnLoot(id, roll);
	end
end

function SmartLoot.Initialize()

	tinsert(UISpecialFrames, "SmartLoot_OptionsFrame"); -- enables closing the options frame by pressing Esc

	SmartLoot.SetAnchorDisplay();
	SmartLoot.UpdateMinimapButtonPosition();
	SmartLoot.CreateLootFrames();
	SmartLoot.Print("loaded. v"..SmartLoot.Version.." by Necroskillz. Use /sloot or minimap button to open options.");

end

function SmartLoot.QueueLoot(loot)
	table.insert(SmartLoot.Queue, loot);

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

	local color = SmartLoot.QualityColor(loot.quality);
	itemName:SetTextColor(color.r, color.g, color.b, 1);

	for i, button in ipairs(SmartLoot.RollButtons) do
		local rollButton = getglobal(frameName.."_"..button.suffix);
		local advancedButton = getglobal(frameName.."_"..button.suffix.."Advanced");
		local reason = loot.reason[button.roll];

		rollButton.reason = reason;
		advancedButton.reason = reason;

		if(loot.can[button.roll]) then
			rollButton:Enable();
			advancedButton:Enable();
		else
			rollButton:Disable();
			advancedButton:Disable();
		end
	end

	frame:Show();
end

function SmartLoot.ClearLoot(rollId)
	for i, loot in ipairs(SmartLoot.Queue) do
		if(loot.rollId == rollId) then
			table.remove(SmartLoot.Queue, i);
			break;
		end
	end

	SmartLoot.ProcessQueue();
	StaticPopup_Hide("CONFIRM_LOOT_ROLL", rollId);
end

function SmartLoot.OnTimeoutBarUpdate(self)
	local loot = self.loot;

	-- test loot has no real roll to query
	if(not loot or loot.rollId < 0) then
		return;
	end

	local timeoutBar = getglobal(self:GetName().."_Timeout");
	local remaining = GetLootRollTimeLeft(loot.rollId);

	if(remaining > 0) then
		timeoutBar:SetValue(remaining);
	end
end

function SmartLoot.DoRoll(self, roll)
	if(not self.loot or self.loot.rollId < 0) then
		return;
	end

	RollOnLoot(self.loot.rollId, roll);
end

function SmartLoot.ToggleRollDropDown(button, suffix)
	local frame = button:GetParent();
	local frameName = frame:GetName();

	ToggleDropDownMenu(nil, nil, getglobal(frameName.."_Advanced"..suffix.."DropDown"), frameName.."_"..suffix, -45, 5);
end

function SmartLoot.OnIconEnter(self)
	local frame = self:GetParent();
	local loot = frame.loot;

	if(not loot) then
		return;
	end

	-- test loot has no roll for the server to describe, it carries a borrowed
	-- item link instead
	if(loot.rollId < 0 and not loot.link) then
		return;
	end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -(self:GetWidth()), 0);

	if(loot.rollId < 0) then
		GameTooltip:SetHyperlink(loot.link);
	else
		GameTooltip:SetLootRollItem(loot.rollId);
	end

	GameTooltip:Show();
end

function SmartLoot.OnIconLeave(self)
	GameTooltip:Hide();
end

function SmartLoot.OnRollButtonEnter(self)
	if(not self.reason) then
		return;
	end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(self.reason, nil, nil, nil, nil, true);
	GameTooltip:Show();
end

-- test loot borrows something the player is wearing: a real link means a real
-- tooltip (and working shift-compare), and an equipped item is always cached
function SmartLoot.GetTestLootItem()
	local slots = { "HeadSlot", "ChestSlot", "MainHandSlot", "LegsSlot", "HandsSlot" };

	for i, slot in ipairs(slots) do
		local link = GetInventoryItemLink("player", GetInventorySlotInfo(slot));

		if(link) then
			local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link);

			if(name) then
				return link, name, quality, texture;
			end
		end
	end

	-- naked character, fall back to a made up item with no tooltip
	return nil, "Crimson Felt Hat", 3, "Interface\\Icons\\INV_Helmet_51";
end

function SmartLoot.ToggleTestLoot(show)
	if(show) then
		local link, name, quality, texture = SmartLoot.GetTestLootItem();

		for i = 1, SmartLoot_Options.LootFrameCount, 1 do
			local loot = {
				rollId = -1;
				timeout = 60000;
				link = link;
				texture = texture;
				name = name;
				quality = quality;
				can = {};
				reason = {};
			};

			loot.can[SmartLoot.Roll.Need] = true;
			loot.can[SmartLoot.Roll.Greed] = true;
			loot.can[SmartLoot.Roll.Disenchant] = true;
			loot.can[SmartLoot.Roll.Pass] = true;

			SmartLoot.QueueLoot(loot);
		end
	else
		-- iterate backwards, removing by ascending index shifts the later ones
		for i = #SmartLoot.Queue, 1, -1 do
			if(SmartLoot.Queue[i].rollId == -1) then
				table.remove(SmartLoot.Queue, i);
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
