-- @version alpha-1.0
-- @location /
--
-- authors: smarrtie, mizly
-------------------------TYPES-------------------------




--- @class LibData
--- @field name string
--- @field md5 string
--- @field loc string | nil
--- @field ver string | nil
--- @field matchName boolean | nil
--- @field matchSum boolean | nil
local LibData = {}
LibData.__index = LibData

function LibData.new(name, md5, loc, ver)
    local self = setmetatable({}, LibData)
    self.name = name
    self.md5 = md5
    self.loc = loc or "/libs/"
    self.ver = ver or "unknown"
    return self
end



--------------------------LIBS--------------------------
local files = require("files")
local md5 = require("md5")
local smarrtieUtils = require("smarrtieUtils")
local downloadFile = require("downloadFile")
------------------------CONSTANTS-----------------------
local modDir = files.getInstanceDir() .. "/config/hypixelcry/scripts"
local dataDir = modDir.."/data/"
local libData = dataDir.."packages.json"

local remoteRepo = "https://raw.githubusercontent.com/lmoboy/hypixel-cry-libs/main"
-------------------------VALUES-------------------------
local runningThreads = {}
local libManager = {}
libManager.error = "loading..."
libManager.remoteLibs = {}
libManager.localLibs = {}
------------------------HELPERS-------------------------

local function unpack_utf(t) --YES this was stolen from stackoverflow
  local bytearr = {}
  for _, v in ipairs(t) do
    local utf8byte = v < 0 and (0xff + v + 1) or v
    table.insert(bytearr, string.char(utf8byte))
  end
  return table.concat(bytearr)
end

local function killThreads() -- kinda useless since thread detach is handled within the mod but this might help with low fps if md5 is too heavy in some cases
    for _, id in pairs(runningThreads) do
        if threads.isAlive(id) then
            threads.interruptThread(id)
        end
    end
end

function libManager.saveLibData()
    local succ = files.writeFile(libData, json.stringify({ libs = libManager.localLibs }))
    if succ then libManager.readLibData() end
end

function libManager.readLibData()
    local data = files.readFile(libData)
    if not data then libManager.getLocalLibs() return end
    local parsed = json.parse(data)
    if not parsed then libManager.getLocalLibs() return end
    local existingLibs = {}
    local needsSave = false

    for _, lib in ipairs(parsed.libs) do
        local loc = (lib.loc or "/libs/"):gsub("%s+", "")
        local fullPath = modDir .. loc .. lib.name
        if files.readFile(fullPath) then
            table.insert(existingLibs, lib)
        else
            needsSave = true
        end
    end

    libManager.localLibs = existingLibs
    if needsSave then
        libManager.saveLibData()
    end
end

function libManager.getLocalLibs() -- this will get repurposed for forceful file integrity check
    for _, libs in pairs(files.getDirectories(modDir)) do
        local formatted = modDir.."/"..libs
        for _, file in pairs(files.getFiles(formatted)) do
            local formFile = formatted.."/"..file
            if string.match(formFile, ".lua") then
                local threadId = threads.startThread(function()
                    local sumhex = md5.sumhexa(files.readFile(formFile))
                    table.insert(libManager.localLibs, LibData.new(file, sumhex, "/"..libs.."/", nil))
                end)
                table.insert(runningThreads, threadId)
            end
        end
    end
end

function libManager.updateLibSum(libData) --probably best to call on callback when new/updated file downloads to keep track at runtime
    threads.startThread(function ()
        local loc = (libData.loc or "/libs/"):gsub("%s+", "")
        local filePath = modDir .. loc .. libData.name
        local fileContent = files.readFile(filePath)

        if not fileContent then
            print("Error: Could not read file " .. libData.name)
            return
        end

        local sumhex = md5.sumhexa(fileContent)

        local found = false
        for i, lib in ipairs(libManager.localLibs) do
            if lib.name == libData.name then
                libManager.localLibs[i] = LibData.new(libData.name, sumhex, loc, libData.ver)
                libManager.saveLibData()
                found = true
                break
            end
        end

        if not found then
            table.insert(libManager.localLibs, LibData.new(libData.name, sumhex, loc, libData.ver))
            libManager.saveLibData()
        end
    end)
end

--- @return boolean success did the fetch complete
function libManager.fetchRemoteLibs()
    local response = http.get_async_callback(
        remoteRepo .. "/registry.json",
        function(resp, err)
            if err then
                libManager.error = err
                return false
            else
                libManager.error = ""
                local parsed = json.parse(unpack_utf(resp))
                for _, remoteLib in pairs(parsed.libs) do
                    table.insert(libManager.remoteLibs, LibData.new(remoteLib.name, remoteLib.md5, remoteLib.location, remoteLib.ver, nil, nil))
                end
                return true
            end
        end)
    if not response then
        libManager.error = "something went wrong while fetching libraries"
        return false
    end
    return false
end

function libManager.download(libData)
    local loc = (libData.loc or "/libs/"):gsub("%s+", "")
    -- All files in the repo are in the 'src' directory, regardless of local 'loc'
    local url = remoteRepo .. "/src/" .. libData.name
    local path = modDir .. loc .. libData.name
    
    -- player.addMessage("Downloading " .. libData.name .. "...")
    downloadFile.download(url, path, function(success, msg)
        if success then
            player.addToast("[Lib Manager]", "Downloaded " .. libData.name, 100)
            libManager.updateLibSum(libData)
        else
            player.addMessage("§cFailed to download " .. libData.name .. ": " .. msg)
        end
    end)
end

function libManager.libButton(libData)
    local uid = "##" .. libData.name 

    for _, lib in pairs(libManager.localLibs) do
        if (lib.name == libData.name) and (lib.md5 == libData.md5) then
            imgui.text("Latest")
            return
        end

        if (lib.md5 == libData.md5) then
            if imgui.button("Sum matches, rename?" .. uid) then
                player.addMessage("rename file : " .. libData.name)
                -- clearly to each button we need to add a method
            end
            return
        end

        if (lib.name == libData.name) then
            if imgui.button("Update!" .. uid) then
                libManager.download(libData)
            end
            return
        end
    end

    if imgui.button("Download" .. uid) then
        libManager.download(libData)
    end
end

libManager.readLibData()
libManager.fetchRemoteLibs()
-------------------------IMGUI-------------------------
player.addToast("[Lib Manager]", "Loaded successfully", 100)

local values={}
values.search = ""

registerImGuiRenderEvent(function()
    if imgui.begin("Lib Manager") then
        if imgui.beginTabBar("##tabBar") then
            if imgui.beginTabItem("Remote") then
                local c, v = imgui.inputText("Search for libs...", values.search)
                if c then values.search = v end
                if #libManager.remoteLibs > 0 then
                    for i, lib in pairs(libManager.remoteLibs) do
                        if string.find(lib.name, values.search) then
                            imgui.text(lib.name)
                            imgui.sameLine(0, 0)
                            imgui.text(" - ")
                            imgui.sameLine(0, 0)
                            imgui.text(lib.ver)
                            libManager.libButton(lib)
                            imgui.separator()
                        end
                    end
                end
                imgui.endTabItem()
            end
            if imgui.beginTabItem("Local") then
                if #libManager.localLibs > 0 then
                    for i, lib in pairs(libManager.localLibs) do
                        imgui.text(lib.name)
                        imgui.sameLine(0, 0)
                        imgui.text(" - ")
                        imgui.sameLine(0, 0)
                        imgui.text(lib.ver or "NULL")
                    end
                end
                imgui.endTabItem()
            end
            if imgui.beginTabItem("Dev")then
                imgui.bulletText("This tab is only for developers and debugging purposes")
                imgui.text("Playing around with the settings and functions here can\ncause some minor inconveniences")
                imgui.endTabItem()
            end
        end
        imgui.endTabBar()
    end
    imgui.endBegin()
end)




-------------------------HOOKS--------------------------
local timeout = 0
local attempts = 0
registerClientTick(function ()
    if #libManager.remoteLibs == 0 then
        timeout = timeout + 1
        if timeout >= 600 then
            attempts = attempts + 1
            timeout = 0
            player.addMessage("Failed to fetch, attempt: "..attempts)
            -- libManager.fetchRemoteLibs()
        end
        if attempts >= 3 then
            player.sendCommand("/lua load lib_manager")
        end
    end
end)


registerClientTickPre(function()
    if smarrtieUtils.getFPS() <= 10 then
        if #runningThreads > 0 then
            killThreads()
        end
        libManager.error = "LOW FPS WARNING"
    else
        if libManager.error == "LOW FPS WARNING" then
            libManager.error = ""
        end
    end
end)

register2DRenderer(function(ctx)
    local scale = ctx.getWindowScale()
    local width = scale.width -- Number
    local height = scale.height -- Number
    local wigth = ctx.getTextWidth(libManager.error)
    local error = {
    	x = width/2-wigth/2, y = height/2, scale = 0.75,
    	text = "§7"..libManager.error,
    	red = 0, green = 0, blue = 0
    }
    ctx.renderText(error)
end)
