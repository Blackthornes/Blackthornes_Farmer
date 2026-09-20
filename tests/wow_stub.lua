--[[--------------------------------------------------------------------------
  Just enough of the WoW client to load the addon outside the game.

  Widgets are recording stubs: any method that is not defined here returns the
  widget itself, so chains of layout calls are harmless, while SetText,
  Show/Hide and SetScript keep their values so tests can inspect them.
----------------------------------------------------------------------------]]

-- table.getn is gone in modern Lua but is how 1.12 code counts arrays.
if not table.getn then
	table.getn = function(t) return #t end
end

local M = { chat = {} }

local Widget = {}
Widget.__index = function(widget, key)
	local noop = function() return widget end
	rawset(widget, key, noop)
	return noop
end

local function NewWidget(name)
	local w = setmetatable({ _name = name, _scripts = {} }, Widget)
	w.SetText = function(self, text) self._text = text end
	w.GetText = function(self) return self._text or "" end
	w.Show = function(self) self._shown = true end
	w.Hide = function(self) self._shown = false end
	w.IsShown = function(self) return self._shown == true end
	w.SetScript = function(self, event, fn) self._scripts[event] = fn end
	w.GetScript = function(self, event) return self._scripts[event] end
	w.CreateFontString = function() return NewWidget() end
	w.GetPoint = function() return "CENTER", nil, "CENTER", 0, 40 end
	return w
end

M.NewWidget = NewWidget

function M.Install()
	UIParent = NewWidget("UIParent")

	CreateFrame = function(_, name, _, _)
		local w = NewWidget(name)
		if name then _G[name] = w end
		return w
	end

	DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, msg) table.insert(M.chat, msg) end,
	}

	SlashCmdList = {}

	return M
end

return M
