-- hud_util.lua
-- Helper for the `hud` section of heart_config.lua: reads button/label
-- definitions and draws nfp backgrounds on the monitor.
-- Screens keep working without a background or without a hud section.
--
-- UNIFORM CONFIG COLORS (used by every element):
--   textColor - foreground color of the text/label
--   bgColor   - background color behind the text / button fill

local MonitorUtil = require("screens/monitor_util")
local heartConfig = require("heart_config")

local HudUtil = {}

local HUD = (heartConfig and heartConfig.hud) or {}

local function section(sectionId)
  return HUD[sectionId] or {}
end

local imageCache = {}

--- Combined color of the create_edit section (text bg default).
local function createEditBg()
  local ce = section("create_edit")
  if ce.bgColor ~= nil then return HudUtil.color(ce.bgColor) end
  return nil
end

--- Background color used for page/list text over the create_edit HUD.
--- Controlled by hud.create_edit.bgColor (nil -> drawn as-is).
--- Kept for backward compatibility.
--- @return number|nil
function HudUtil.createEditTextBg()
  return createEditBg()
end

--- Work area of the create_edit background: the rectangle where generated
--- list/page text is allowed to draw on top of the image.
--- Controlled by hud.create_edit.area { x, y, w, h, textColor, bgColor }.
--- Defaults reproduce the legacy layout (x=2, y=3, w = monW-4, h = monH-5).
--- @param mon table monitor
--- @return table { x, y, w, h, textColor, bgColor }
function HudUtil.getArea(mon)
  local w, h = mon.getSize()
  local ce = section("create_edit")
  local a = (type(ce.area) == "table") and ce.area or {}
  local area = {
    x = a.x or 2,
    y = a.y or 3,
    w = a.w or (w - 4),
    h = a.h or (h - 5),
    textColor = HudUtil.color(a.textColor or "white"),
    bgColor = (a.bgColor ~= nil) and HudUtil.color(a.bgColor) or createEditBg() or nil,
  }
  if area.x < 1 then area.x = 1 end
  if area.y < 1 then area.y = 1 end
  if area.w < 1 then area.w = 1 end
  if area.h < 1 then area.h = 1 end
  return area
end

--- Draw the wizard page title on the create_edit background.
--- Position/colors come from hud.create_edit.title { x, y, textColor, bgColor }.
--- x = nil centers, y = nil uses 2, colors default yellow / create_edit.bgColor.
--- @param mon table monitor
--- @param text string
function HudUtil.createEditTitle(mon, text)
  local ce = section("create_edit")
  local t = (type(ce.title) == "table") and ce.title or {}
  local w, h = mon.getSize()
  local x = t.x or math.floor((w - #text) / 2) + 1
  if x < 1 then x = 1 end
  local y = t.y or 2
  local bg = (t.bgColor ~= nil) and HudUtil.color(t.bgColor) or createEditBg() or nil
  MonitorUtil.drawText(mon, x, y, text, HudUtil.color(t.textColor or "yellow"), bg)
end

--- Get a whole `hud` section as a table (empty table if missing).
--- @param sectionId string
--- @return table
function HudUtil.get(sectionId)
  return HUD[sectionId] or {}
end

--- Find a button definition by id inside a section.
--- Supports the `buttons` array, flat buttons (section[btnId]) and
--- `columns[i].start` (Start buttons, action defaults to the column id).
--- @return table|nil raw config button { id, x, y, w, h, label, action, textColor, bgColor }
function HudUtil.getButton(sectionId, btnId)
  local s = section(sectionId)
  for _, b in ipairs(s.buttons or {}) do
    if b.id == btnId then
      return b
    end
  end
  local flat = s[btnId]
  if type(flat) == "table" and (flat.x ~= nil or flat.label ~= nil) then
    return flat
  end
  for _, col in ipairs(s.columns or {}) do
    if col.id == btnId and type(col.start) == "table" then
      return col.start
    end
  end
  return nil
end

--- Resolve a color name/string/number to a colors.* value.
--- @param name string|number|nil
--- @return number
function HudUtil.color(name)
  if name == nil then return colors.gray end
  if type(name) == "number" then return name end
  return colors[name] or colors.gray
end

--- Resolve an optional color (nil stays nil so callers can use a default).
--- @param name string|number|nil
--- @return number|nil
local function optColor(name)
  if name == nil then return nil end
  return HudUtil.color(name)
end

--- Build a MonitorUtil button (with height) from a config definition.
--- x = nil centers horizontally, y = nil uses the bottom row (h - 1).
--- Button fields: id, label, x, y, w, h, bgColor (button fill),
--- textColor (label color, default white).
--- @return table|nil ready-to-draw button
function HudUtil.createButton(mon, sectionId, btnId)
  local spec = HudUtil.getButton(sectionId, btnId)
  if not spec then return nil end
  local w, h = mon.getSize()
  local width = spec.w or #(spec.label or "")
  local x = spec.x or math.floor((w - width) / 2) + 1
  if x < 1 then x = 1 end
  local y = spec.y or (h - 1)
  local btn = MonitorUtil.createButton(x, y, width, spec.label or "",
    spec.action or btnId, HudUtil.color(spec.bgColor), spec.h or 1)
  btn.id = spec.id or btnId
  if spec.textColor then
    btn.textColor = HudUtil.color(spec.textColor)
  end
  return btn
end

--- Draw a named label (title/hint) from config.
--- Label fields: text, x, y, textColor, bgColor. x = nil centers, y = nil uses h - 1.
function HudUtil.drawLabel(mon, sectionId, name)
  local lb = section(sectionId)[name]
  if type(lb) ~= "table" then return end
  local text = lb.text or ""
  local w, h = mon.getSize()
  local x = lb.x or math.floor((w - #text) / 2) + 1
  if x < 1 then x = 1 end
  local y = lb.y or (h - 1)
  MonitorUtil.drawText(mon, x, y, text, HudUtil.color(lb.textColor), optColor(lb.bgColor))
end

--- Draw one column (title + description lines) from `hud.<sectionId>.columns`.
--- Text fields: title/desc = { x, y, text, textColor, bgColor }.
--- The Start button itself is drawn separately via HudUtil.createButton.
--- @param mon table monitor
--- @param sectionId string
--- @param col table column spec
function HudUtil.drawColumn(mon, sectionId, col)
  local title = col.title
  if type(title) == "table" then
    MonitorUtil.drawText(mon, title.x, title.y, "[" .. (title.text or "") .. "]",
      HudUtil.color(title.textColor or col.textColor), optColor(title.bgColor))
  end
  local desc = col.desc
  if type(desc) == "table" then
    local dy = desc.y
    local descColor = (desc.textColor and HudUtil.color(desc.textColor)) or MonitorUtil.COLORS.text
    local bg = optColor(desc.bgColor)
    for line in tostring(desc.text or ""):gmatch("[^\n]+") do
      MonitorUtil.drawText(mon, desc.x, dy, line, descColor, bg)
      dy = dy + 1
    end
  end
end

--- Draw the nfp background of a section with `path`.
--- Returns true on success, false otherwise (screen still works without it).
--- @return boolean
function HudUtil.drawBackground(mon, sectionId)
  local path = section(sectionId).path
  if not path or #path == 0 then return false end
  local img = imageCache[path]
  if img == nil then
    local ok, loaded = pcall(paintutils.loadImage, path)
    if not ok or not loaded then
      imageCache[path] = false
      return false
    end
    img = loaded
    imageCache[path] = img
  elseif img == false then
    return false
  end
  local oldTerm = term.redirect(mon)
  pcall(paintutils.drawImage, img, 1, 1)
  term.redirect(oldTerm)
  return true
end

--- Build a single footer button from `create_edit` config or a default.
--- @param name string "back" | "prev" | "next"
--- @param default table fallback spec { x, y, w, label, action, bgColor, textColor }
--- @return table MonitorUtil button
local function buildFooterButton(mon, name, default)
  local spec = section("create_edit")[name]
  if type(spec) ~= "table" then spec = default end
  local w, h = mon.getSize()
  local width = spec.w or #(spec.label or "")
  local x = spec.x or default.x
  local y = spec.y or default.y or (h - 1)
  local btn = MonitorUtil.createButton(x, y, width, spec.label or "",
    spec.action or "", HudUtil.color(spec.bgColor or default.bgColor), spec.h or 1)
  if spec.textColor or default.textColor then
    btn.textColor = HudUtil.color(spec.textColor or default.textColor)
  end
  return btn
end

--- Resolve the paginated footer (back/prev/next + page text) for the
--- `create_edit` background. Falls back to the legacy layout
--- (2 / w-19 / w-11 on the bottom row) when config is missing.
--- @param mon table monitor
--- @param pageIndex number current page number (1-based)
--- @param totalPages number
--- @return table footer { back, prev, next, pageText, pageX, pageY, pageColor, pageBg }
function HudUtil.getFooter(mon, pageIndex, totalPages)
  local w, h = mon.getSize()
  local footer = {}

  footer.back = buildFooterButton(mon, "back",
    { x = 2, y = h - 1, w = 9, label = " [Back]", action = "back", bgColor = "red", textColor = "white" })
  footer.prev = buildFooterButton(mon, "prev",
    { x = w - 19, y = h - 1, w = 7, label = " [<Prev]", action = "prev", bgColor = "blue", textColor = "white" })
  footer.next = buildFooterButton(mon, "next",
    { x = w - 11, y = h - 1, w = 7, label = " [Next>]", action = "next", bgColor = "blue", textColor = "white" })

  local page = section("create_edit").page or {}
  local pageText = "Page " .. tostring(pageIndex) .. "/" .. tostring(totalPages)
  local pageX
  if page.x then
    pageX = page.x
  else
    pageX = math.floor((w - #pageText) / 2) + 1
    if pageX < 1 then pageX = 1 end
    if pageX + #pageText >= footer.prev.x then
      pageX = footer.prev.x - #pageText - 2
    end
    if pageX < 12 then pageX = 12 end
  end
  footer.pageText = pageText
  footer.pageX = pageX
  -- page.y is the base row; optional page.line adds an offset so the page
  -- indicator can sit on a lower row of the footer block (line 2 = y + 1).
  footer.pageY = (page.y or (h - 1)) + ((page.line or 1) - 1)
  footer.pageColor = HudUtil.color(page.textColor or "cyan")
  footer.pageBg = optColor(page.bgColor)

  return footer
end

return HudUtil