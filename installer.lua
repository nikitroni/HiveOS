-- installer.lua
-- HiveOS role installer for CC:Tweaked.
-- Usage: wget run https://raw.githubusercontent.com/nikitroni/HiveOS/main/installer.lua

local REPO_OWNER = "nikitroni"
local REPO_NAME = "HiveOS"
local BRANCH = "main"
local USER_AGENT = "CC-Tweaked-Installer"
local ROLES = { "BeeOS", "LabOS", "HeartOS" }

local function httpGet(url)
  local res = http.get({ url = url, headers = { ["User-Agent"] = USER_AGENT } })
  if not res then return nil end
  local body = res.readAll()
  res.close()
  return body
end

local function chooseRole()
  print("Select role to install:")
  for i, role in ipairs(ROLES) do
    print(i .. ". " .. role)
  end
  write("Choose role (number): ")
  local n = tonumber(read())
  if not n or not ROLES[n] then return nil end
  return ROLES[n]
end

local function fetchTree()
  local url = "https://api.github.com/repos/" .. REPO_OWNER .. "/" .. REPO_NAME ..
      "/git/trees/" .. BRANCH .. "?recursive=1"
  local body = httpGet(url)
  if not body then return nil end
  local ok, data = pcall(textutils.unserializeJSON, body)
  if not ok or type(data) ~= "table" or type(data.tree) ~= "table" then return nil end
  return data.tree
end

local function downloadRole(role)
  local tree = fetchTree()
  if not tree then
    print("FAIL: could not fetch repository tree.")
    return
  end
  local prefix = role .. "/"
  local okCount, failCount = 0, 0
  for _, entry in ipairs(tree) do
    if entry.type == "blob" and type(entry.path) == "string" and entry.path:sub(1, #prefix) == prefix then
      local rel = entry.path:sub(#prefix + 1)
      local dir = fs.getDir(rel)
      if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
      end
      local url = "https://raw.githubusercontent.com/" .. REPO_OWNER .. "/" ..
          REPO_NAME .. "/" .. BRANCH .. "/" .. entry.path
      local body = httpGet(url)
      if body then
        local f = fs.open(rel, "w")
        f.write(body)
        f.close()
        print("OK: " .. rel)
        okCount = okCount + 1
      else
        print("FAIL: " .. rel)
        failCount = failCount + 1
      end
    end
  end
  print("Downloaded: " .. okCount .. ", failed: " .. failCount)
  print("Done. Run 'reboot' to start.")
end

local role = chooseRole()
if not role then
  print("Invalid choice.")
else
  downloadRole(role)
end
