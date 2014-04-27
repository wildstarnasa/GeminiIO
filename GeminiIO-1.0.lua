local MAJOR, MINOR = "Gemini:IO-1.0", 1
local APkg = Apollo.GetPackage(MAJOR)
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade is needed
end
local Lib = APkg and APkg.tPackage or {}

local Queue
local glog = nil

local UPDATE_INTERVAL = 0.4			-- In seconds
local TOKEN = "GeminiIO"
local DELIMITER = ":::"
local STRING_BUFFER_SIZE = 8000		-- Message characters to write to clipboard in each batch

function Lib:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 
    return o
end

function Lib:OnLoad()
	Queue = Apollo.GetPackage("Drafto:Lib:Queue-1.2").tPackage
	local XmlDocument = Apollo.GetPackage("Drafto:Lib:XmlDocument-1.0").tPackage
	glog = glog or Apollo.GetPackage("Gemini:Logging-1.2").tPackage:GetLogger({
		level = Apollo.GetPackage("Gemini:Logging-1.2").tPackage.FATAL,
		pattern = "%d %n %c %l - %m",
		appender = "GeminiConsole"
	})

	self.messageQueue = Queue.new()
	
	self.tOpenPaths = {}
	
	-- Create new Forms document
	local tDoc = XmlDocument.NewForm()
	-- Create the base ClipboardForm
	local tForm = tDoc:NewFormNode("ClipboardForm", {
		AnchorPoints = {0,0,0,0},
		AnchorOffsets = {197,106,935,316},
		Visible = false,
	})
	-- Add it to the XML Document
	tDoc:GetRoot():AddChild(tForm)
	-- Create the hidden editboxes that will store text
	local tClipboardHidden = tDoc:NewControlNode("ClipboardHidden", "EditBox", {
		AnchorPoints = {0,0,1,1},
		AnchorOffsets = {4,4,-4,-4},
		Visible = false,
		MultiLine = true,
	})
	tForm:AddChild(tClipboardHidden)
	local tClipboardHistory = tDoc:NewControlNode("ClipboardHistory", "EditBox", {
		AnchorPoints = {0,0,1,1},
		AnchorOffsets = {10,129,371,158},
		Visible = false,
		MultiLine = true,
		DT_WORDBREAK = true,
	})
	tForm:AddChild(tClipboardHistory)

	-- Instantiate the ClipboardForm
	self.wndMain = tDoc:LoadForm("ClipboardForm", nil, self)
	self.wndMain:Show(false, false)
	self.wndClipboardHidden = self.wndMain:FindChild("ClipboardHidden")
	self.wndClipboardHistory = self.wndMain:FindChild("ClipboardHistory")
	
	Apollo.RegisterTimerHandler("GeminiIO_ClipboardMessageQueueTimer", "OnClipboardMessageQueueTimer", self)
	Apollo.CreateTimer("GeminiIO_ClipboardMessageQueueTimer", UPDATE_INTERVAL, true)

	local strMessage = TOKEN .. DELIMITER .. "Init"
	self:QueueMessage(strMessage)

	glog:info("Loaded GeminiIO")
end

function Lib:OnDependencyError(strDep, strError)
	-- No Logging is not ideal, but not fatal
	if strDep == "Gemini:Logging-1.2" then
		glog = { info = function() end }
		return true
	end
	Print("GeminiIO couldn't load " .. strDep .. ". Fatal error: " .. strError)
	return false
end
------------------------------------------------------------

function Lib:OnClipboardMessageQueueTimer()
	if Queue.Size(self.messageQueue) > 0 then
		local strMessage = Queue.PopRight(self.messageQueue)
		self.wndClipboardHidden:SetText(strMessage)
		self.wndClipboardHidden:CopyTextToClipboard()
	end
end

function Lib:QueueMessage(strMessage)
	Queue.PushLeft(self.messageQueue, strMessage)
end

------------------------------------------------------------

function Lib:BuildFileStreamWriter(strPath)
	local tGeminiIO = self
	local strFilePath = strPath
	local tLogger = {
		GetPath = function() return strFilePath end,
		Write = function(tObj, ...)
					strText = string.format(unpack(arg))
					tGeminiIO:WriteToFile(strFilePath, strText)
				end,
		Close = function(tObj)
					tGeminiIO:CloseFile(strFilePath)
					for k,v in pairs(tObj) do
						tObj[k] = nil
					end
				end,
	}

	return tLogger
end

------------------------------------------------------------

function Lib:OpenFile(strPath, bAppend)
	glog:info("Opening file: " .. strPath)
	self.tOpenPaths[strPath] = self:BuildFileStreamWriter(strPath)
	
	local strMessageType
	if bAppend then
		strMessageType = "OpenFileAppend"
	else
		strMessageType = "OpenFile"
	end
	
	local strMessage = TOKEN .. DELIMITER .. strMessageType .. DELIMITER .. strPath
	self:QueueMessage(strMessage)

	return self.tOpenPaths[strPath]
end

function Lib:CloseFile(strPath)
	glog:info("Closing file: " .. strPath)
	
	local strMessage = TOKEN .. DELIMITER .. "CloseFile" .. DELIMITER .. strPath
	self:QueueMessage(strMessage)
	
	self.tOpenPaths[strPath] = nil
end

function Lib:WriteToFile(strPath, strText)
	if strPath == nil then return end
	glog:info("Writing to file: " .. strPath)
	
	local tTextParts = {}
	
	if #strText > STRING_BUFFER_SIZE then
		local nCursor = 1
		while nCursor < #strText do
			local nCursorNext = nCursor + STRING_BUFFER_SIZE
			if nCursorNext > #strText then
				nCursorNext = #strText
			end
			local strMessageText = string.sub(strText, nCursor, nCursorNext - 1)
			nCursor = nCursorNext
			table.insert(tTextParts,strMessageText)
		end
	else
		table.insert(tTextParts, strText)
	end
	
	for i,strPart in ipairs(tTextParts) do
		local strMessage = TOKEN .. DELIMITER .. "WriteToFile" .. DELIMITER ..  strPath .. DELIMITER .. strPart
		self:QueueMessage(strMessage)
	end
end

function Lib:IsFileOpen(strPath)
	return self.tOpenPaths[strPath] ~= nil
end

function Lib:GetOpenFiles()
	local tPaths = {}
	for k,v in pairs(self.tOpenPaths) do
		if v ~= nil then
			table.insert(tPaths, k)
		end
	end
	return tPaths
end

Apollo.RegisterPackage(Lib, MAJOR, MINOR, {"Gemini:Logging-1.2", "Drafto:Lib:Queue-1.2", "Drafto:Lib:XmlDocument-1.0"})