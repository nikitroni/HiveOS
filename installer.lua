-- installer.lua
-- HiveOS role installer for CC:Tweaked.
-- Usage: wget run https://raw.githubusercontent.com/nikitroni/HiveOS/main/installer.lua

local repoOwner = "nikitroni"
local repoName = "HiveOS"
local userAgent = "CC-Tweaked-Installer"
local roles = { "BeeOS", "LabOS", "HeartOS", "PocketOS" }
local branch = "main"

local function httpGet(url)
  local ok, response, reason = pcall(http.get, {
    url = url,
    headers = { ["User-Agent"] = userAgent },
  })
  if not ok then return nil, tostring(response) end
  if not response then return nil, tostring(reason) end
  local readOk, body = pcall(response.readAll)
  local closeOk, closeError = pcall(response.close)
  if not readOk then return nil, tostring(body) end
  if not closeOk then return nil, tostring(closeError) end
  return body
end

local function chooseRole()
  print("Select role to install:")
  for i, role in ipairs(roles) do
    print(i .. ". " .. role)
  end
  write("Choose role (number): ")
  local n = tonumber(read())
  if not n or not roles[n] then return nil end
  return roles[n]
end

local function fetchTree(branch)
  local apiRoot = "https://api.github.com/repos/" .. repoOwner .. "/" .. repoName
  local commitBody, commitReason = httpGet(apiRoot .. "/commits/" .. branch)
  if not commitBody then return nil, commitReason end
  local commitOk, commit = pcall(textutils.unserializeJSON, commitBody)
  if not commitOk or type(commit) ~= "table" or type(commit.sha) ~= "string"
      or not commit.sha:match("^%x+$")
      or type(commit.commit) ~= "table" or type(commit.commit.tree) ~= "table"
      or type(commit.commit.tree.sha) ~= "string"
      or not commit.commit.tree.sha:match("^%x+$") then
    return nil, "Invalid branch revision"
  end
  local revision = commit.sha
  local url = apiRoot .. "/git/trees/" .. commit.commit.tree.sha .. "?recursive=1"
  local body, reason = httpGet(url)
  if not body then return nil, reason end
  local ok, data = pcall(textutils.unserializeJSON, body)
  if not ok or type(data) ~= "table" or type(data.tree) ~= "table" then
    return nil, "Invalid repository tree"
  end
  if data.truncated then return nil, "Repository tree was truncated" end
  return data.tree, revision
end

local function downloadRole(role, branch)
  local tree, revision = fetchTree(branch)
  if not tree then
    print("FAIL: could not fetch " .. branch .. " repository tree: " .. tostring(revision))
    return false
  end
  local prefix = role .. "/"
  local okCount, failCount = 0, 0
  for _, entry in ipairs(tree) do
    if entry.type == "blob" and type(entry.path) == "string" and entry.path:sub(1, #prefix) == prefix then
      local rel = entry.path:sub(#prefix + 1)
      local dir = fs.getDir(rel)
      local prepared = dir == "" or fs.exists(dir)
      if not prepared then
        prepared = pcall(fs.makeDir, dir) and fs.exists(dir)
      end
      if not prepared then
        print("FAIL: cannot create directory for " .. rel)
        failCount = failCount + 1
      else
        local url = "https://raw.githubusercontent.com/" .. repoOwner .. "/" ..
            repoName .. "/" .. revision .. "/" .. entry.path
        local body, reason = httpGet(url)
        if body == nil then
          print("FAIL: " .. rel .. " (" .. tostring(reason) .. ")")
          failCount = failCount + 1
        else
          local file, openError = fs.open(rel, "w")
          if not file then
            print("FAIL: " .. rel .. " (" .. tostring(openError) .. ")")
            failCount = failCount + 1
          else
            local writeOk, writeError = pcall(file.write, body)
            local closeOk, closeError = pcall(file.close)
            if writeOk and closeOk then
              print("OK: " .. rel)
              okCount = okCount + 1
            else
              print("FAIL: " .. rel .. " (" .. tostring(writeOk and closeError or writeError) .. ")")
              failCount = failCount + 1
            end
          end
        end
      end
    end
  end
  print("Downloaded: " .. okCount .. ", failed: " .. failCount)
  if okCount == 0 or failCount > 0 then
    print("Installation incomplete. Fix the failures before rebooting.")
    return false
  end
  print("Done. Run 'reboot' to start.")
  return true
end

local role = chooseRole()
if not role then
  print("Invalid choice.")
else
  downloadRole(role, branch)
end
