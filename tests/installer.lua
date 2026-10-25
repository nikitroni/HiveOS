local originalLoadfile = loadfile

local function runInstall(failSecond)
  local inputs = { "4", "upgrade" }
  local urls = {}
  local writes = {}
  local output = {}
  local env = setmetatable({
    print = function(message) output[#output + 1] = tostring(message) end,
    write = function() end,
    read = function() return table.remove(inputs, 1) end,
    http = {
      get = function(request)
        local url = request.url
        urls[#urls + 1] = url
        local body
        if url:find("/commits/upgrade", 1, true) then
          body = "commit"
        elseif url:find("/git/trees/bbbb", 1, true) then
          body = "tree"
        elseif url:find("/PocketOS/startup.lua", 1, true) then
          body = "startup bytes"
        elseif url:find("/PocketOS/pocket_main.lua", 1, true) and not failSecond then
          body = "program bytes"
        end
        if not body then return nil, "Simulated HTTP error" end
        return {
          readAll = function() return body end,
          close = function() end,
        }
      end,
    },
    textutils = {
      unserializeJSON = function(body)
        if body == "commit" then
          return { sha = "aaaa", commit = { tree = { sha = "bbbb" } } }
        end
        if body == "tree" then
          return {
            truncated = false,
            tree = {
              { type = "blob", path = "PocketOS/startup.lua" },
              { type = "blob", path = "PocketOS/pocket_main.lua" },
              { type = "blob", path = "BeeOS/startup.lua" },
            },
          }
        end
      end,
    },
    fs = {
      getDir = function() return "" end,
      open = function(path)
        return {
          write = function(body) writes[path] = body end,
          close = function() end,
        }
      end,
    },
  }, { __index = _G })
  assert(originalLoadfile("HiveOS/installer.lua", "t", env))()
  return urls, writes, table.concat(output, "\n")
end

local urls, writes, output = runInstall(false)
assert(urls[1]:find("/commits/upgrade", 1, true), "Upgrade branch not selected")
assert(urls[2]:find("/git/trees/bbbb", 1, true), "Tree SHA not used for API lookup")
assert(urls[3]:find("/aaaa/PocketOS/startup.lua", 1, true), "Files not pinned to commit")
assert(writes["startup.lua"] == "startup bytes")
assert(writes["pocket_main.lua"] == "program bytes")
assert(not writes["BeeOS/startup.lua"], "Another role was downloaded")
assert(output:find("Done. Run 'reboot'", 1, true), "Complete installation not reported")

local _, _, failedOutput = runInstall(true)
assert(failedOutput:find("Installation incomplete", 1, true), "Partial install not reported")
assert(not failedOutput:find("Done. Run 'reboot'", 1, true), "Partial install was reported ready")

print("Pocket installer tests passed")
