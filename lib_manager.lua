-- @version alpha-1.0
-- @location /libs/
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

function LibData.new(name, md5, loc, ver, matchName, matchSum)
    local self = setmetatable({}, LibData)
    self.name = name
    self.md5 = md5
    self.loc = loc or nil
    self.ver = ver or nil
    self.matchName = matchName or nil
    self.matchSum = matchSum or nil
    return self
end



--------------------------LIBS--------------------------
local files = require("files")
local md5 = require("md5")
local smarrtieUtils = require("smarrtieUtils")
local downloadFile = require("downloadFile")
------------------------CONSTANTS-----------------------
local libDir = files.getInstanceDir() .. "/config/hypixelcry/scripts/libs/"
local dataDir = files.getInstanceDir() .. "/config/hypixelcry/scripts/data/"
local libData = files.getInstanceDir() .. "/config/hypixelcry/scripts/data/packages.json"
local libs = files.getFiles(libDir)
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

local function killThreads()
    for _, id in pairs(runningThreads) do
        if threads.isAlive(id) then
            threads.interruptThread(id)
        end
    end
end

function libManager.getLocalLibs()
    local localFiles = files.getFiles(libDir)
    for _, file in pairs(localFiles) do
        threads.startThread(function ()
            local sumhex = md5.sumhexa(files.readFile(libDir..file))
            table.insert(libManager.localLibs, LibData.new(file, sumhex, nil, nil))
        end)
    end
end

function libManager.fetchRemoteLibs()
    local response = http.get_async_callback(
        "https://raw.githubusercontent.com/lmoboy/hypixel-cry-libs/refs/heads/main/registry.json",
        function(resp, err)
            if err then
                libManager.error = err
                return false
            else
                libManager.error = ""
                local parsed = json.parse(unpack_utf(resp))
                libManager.remoteLibs = parsed.libs -- array
                for _, remoteLib in pairs(parsed.libs) do
                    table.insert(libManager.remoteLibs, LibData.new(remoteLib.name, remoteLib.md5, remoteLib.loc, remoteLib.ver))
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

libManager.getLocalLibs()
-------------------------IMGUI-------------------------

player.addToast("[Lib Manager]", "Loaded successfully", 1)

registerImGuiRenderEvent(function()
    if imgui.begin("Lib Manager") then
        if imgui.button("Fetch remote libraries") then
            local succ = libManager.fetchRemoteLibs()
            if not succ then
                imgui.bulletText(libManager.error)
            end
        end
        if #libManager.remoteLibs > 0 then
            for i, lib in pairs(libManager.remoteLibs) do
                imgui.text(lib.name)
                imgui.sameLine(0, 0)
                imgui.text(" - ")
                imgui.sameLine(0, 0)
                imgui.text(lib.ver)
            end
        end
        imgui.beginTabBar("tab bar")
        imgui.beginTabItem("tab item")
        
        imgui.endTabItem()
        imgui.endTabBar()
    end
    imgui.endBegin()
end)




-------------------------HOOKS--------------------------

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