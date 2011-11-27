-- EPOE Server Code

require ( "hook" )

local G=_G
local umsg=umsg
local ValidEntity=ValidEntity
local RecipientFilter=RecipientFilter
local error=error
local pairs=pairs
local hook=hook
local table=table
local pcall=pcall
local concommand=concommand
local tostring=tostring
local timer=timer
local len=string.len
local setmetatable=setmetatable
local util=util

-- inform the client of the version
CreateConVar( "epoe_version", "2.1", FCVAR_NOTIFY )

module( "epoe" )

-- Constants 
local recover_time = 2 -- 0.1 = agressive. 2 = safer. 

-- Store global old print functions. Original ones.
G._Msg=G._Msg or G.Msg
G._MsgC=G._MsgC or G.MsgC or G.Msg
G._MsgN=G._MsgN or G.MsgN
G._print=G._print or G.print

-- Store local real messages, real ones
RealMsg=G.Msg
RealMsgC=VERSION > 129 and G.MsgC or function(col,...) 
	RealMsg(...)
end
RealMsgN=G.MsgN
RealPrint=G.print


-- Hack
local function ErrorNoHalt(...)
	G.timer.Simple(0.01,G.ErrorNoHalt,...)
end



------------------ SUBS SYSTEM ------------------

	-- Subscribed people
	Sub = {
		-- player = true
	}
	-- Garbage collect whenever you want...
	setmetatable(Sub,{__mode="k"})
	
	HasNoSubs=true

	function AddSub(pl)
		if (pl and pl.IsValid and pl:IsValid()) and pl:IsPlayer() then
			HasNoSubs=false
			Sub[pl]=true
			umsg.Start(Tag,pl)	umsg.Char(IS_EPOE)	umsg.String("_S") --[[_S=Subscribe]]	umsg.End()
		end
	end

	function DelSub(pl)
		Sub[pl]=nil
		CalculateSubs()
		umsg.Start(Tag,pl)	umsg.Char(IS_EPOE)	umsg.String("_US") --[[_US=Unsubscribe]]	umsg.End()
	end

	function CalculateSubs()
		for k,v in pairs(Sub) do
			HasNoSubs=false
			return
		end
		
		HasNoSubs=true
		
		DisableTick()
	end

	-- Could probably remove this.
	function OnEntityRemoved(pl)
		if !(pl and pl.IsValid and pl:IsValid()) then return end
		if 	pl:IsPlayer() then
			DelSub(pl)
		end
	end
	hook.Add('EntityRemoved',TagHuman,OnEntityRemoved)

	-- Override for admin mods :o
	function CanSubscribe(pl,unsubscribe)
		--RealPrint( tostring(pl)..(unsubscribe and "unsubscribed from" or "subscribed to").." EPOE" )
		return pl:IsAdmin("epoe")
	end

	function OnSubCmd(pl,_,argz)
		if not (pl and pl.IsValid and pl:IsValid()) then return end -- Consoles can't subscribe. Sorry :(
		
		local wantsub=util.tobool(argz[1] or "0")
		
		if wantsub then
			if CanSubscribe(pl) then
				AddSub(pl)
			else
				-- uhoh
				umsg.Start(Tag,pl)	umsg.Char(IS_EPOE)	umsg.String("_NA") --[[_NA=Not admin]]	umsg.End()
			end
		else
			DelSub(pl)
			CanSubscribe(pl,true)
		end
		
	end
	concommand.Add(Tag,OnSubCmd)

	function GetSubscribers()
		return Sub
	end
	

RF=RecipientFilter()
local RF=RF

-- Refresh pretty much everything for us
function Refresh()
	--RealMsgN(InEPOE and "IN EPOE","Refresh")
	RF:RemoveAllPlayers()
	CalculateSubs()
	if HasNoSubs then return end
	for pl,_ in pairs(Sub) do
		if (pl and pl.IsValid and pl:IsValid()) and CheckSub(pl) then
			RF:AddPlayer(pl)
		end
	end
end

-- Override and return false to prevent player from receiving more updates.
-- Added for dynamic demote from EPOE. Can get spammed so should be lightweight to call.
function CheckSub()
	return true
end

-------------------------------------------------



-- Prevent local errors from screwing our system
InEPOE=true
	
-- Holds the messages that are to be sent to clients
Messages=FIFO() -- shared.lua
local Messages=Messages

-- Flood Protection
function Recover()
	EnableTick()
	Messages:clear() -- We were in flood protection mode. Don't continue doing it...
	
	InEPOE = false
	
	local payload={ flag=IS_EPOE,
	msg="Queue reset! (Over "..tostring(MaxQueue or "unknown").." messages pushed triggering safeguards)" }
	Messages:push(payload)
	
end


local TickEnabled=false
function EnableTick()
	if TickEnabled then return end
	TickEnabled = true
	hook.Add('Tick',TagHuman,OnTick)
end
local EnableTick=EnableTick

function DisableTick()
	--RealMsgN(InEPOE and "IN EPOE",TickEnabled,"DisableTick")
	if not TickEnabled then return end
	TickEnabled = false
	hook.Remove('Tick',TagHuman)
end
local DisableTick=DisableTick

function HitMaxQueue()

	if Messages:len() > MaxQueue then
		
		DisableTick()
		Messages:clear()
		
		InEPOE=true
		timer.Simple(recover_time,Recover)
		
		return true
	
	end
	
end

------------------
-- Overrides
------------------
	function OnMsg(...)	
		if InEPOE or HasNoSubs then RealMsg(...) else
			InEPOE = true	
				
				if HitMaxQueue() then return end
				
				EnableTick()
				
				local data={...}
				local err,str=pcall(ToString,data) -- just to be sure
				
				if str then
					PushPayload( IS_MSG , str )
				end
				
				RealMsg(...)
			
			InEPOE=false
		end
	end

	-- TODO: Add Colors..
	function OnMsgC(color,...)	
		if InEPOE or HasNoSubs then RealMsgC(color,...) else
			InEPOE = true	
				
				if HitMaxQueue() then return end
				
				EnableTick()
				
				local data={...}
				local err,str=pcall(ToString,data) -- just to be sure
				
				if str then
					local colbytes = ColorToStr(color)
					PushPayload( IS_MSGC , colbytes..str )
				end
				
				RealMsgC(color,...)
			
			InEPOE=false
		end
	end	

	function OnMsgN(...)
		if InEPOE or HasNoSubs then RealMsgN(...) else
			InEPOE = true	
				
				if HitMaxQueue() then return end
				
				EnableTick()
			
				local data={...}
				local err,str=pcall(ToString,data)
				if str then
					PushPayload( IS_MSGN , str )
				end
			
				RealMsgN(...)
			
			InEPOE=false
		end
	end

	function OnPrint(...)
		if InEPOE or HasNoSubs then RealPrint(...) else
			InEPOE = true	
					
				if HitMaxQueue() then return end

				EnableTick()
			
				local data={...}
				local err,str=pcall(ToString,data)
				if str then
					PushPayload( IS_PRINT , str )
				end
			
				RealPrint(...)
			
			InEPOE=false
		end
	end

	function OnLuaError(str)
		if InEPOE or HasNoSubs then return end
		
		InEPOE = true
			
			if HitMaxQueue() then return end
			
			EnableTick()

			PushPayload( IS_ERROR , tostring(str) )
		
		InEPOE=false
	end
	
------------------
	

local function DivideStr(str,pos)
	local cur,remaining = str:sub(1,pos),str:sub(pos,#str-pos)
	return cur,remaining
end

local function DoPush(payload)
	local last = Messages:peek()
	if payload.flag==last.flag and payload.msg==last.msg then
		if payload.flag!=IS_SEQ then
			payload={
				flag=IS_REPEAT,
				msg=""
				}
		end
	end
	Messages:push(payload)
end

-- Make sure our message is less than 200 bytes to make it sendable.
-- If it isn't divide it to parts
function PushPayload(flags,s)
	local str=""
	local remaining=s
	for i=0,512 do -- Should be long enough for anything. We get hit by other limitations if more..
		str,remaining=DivideStr(remaining,190) -- Max 200 bytes. Hmm...
		if len(remaining)==0 then
			DoPush{
				flag=flags, -- Byte
				msg=str -- arbitrary
			}			
			return
		else
			DoPush{
				flag=flags|IS_SEQ,
				msg=str
			}		
		end
		
	end
	
	-- safeguard --
	
	EnableTick()
	Messages:clear()
	InEPOE=false			
	Messages:push{flag=IS_EPOE,msg="Cancelling messages, too many iterations."}
	
end

------------------
-- Transmit one from the queue
-- Return: true if queue is empty
------------------
function OnBeingTransmit()

	local payload=Messages:pop()
	if payload==nil then return true end
	umsg.Start(Tag,RF)
		umsg.Char(payload.flag or 0)
		umsg.String(payload.msg or "EPOE ERROR")
	umsg.End()
	
end


------------------
-- What makes you tick!
------------------
function OnTick()
	if InEPOE then return end
	--RealMsgN(InEPOE and "IN EPOE","OnTick")
	InEPOE = true
		
		Refresh()
		if HasNoSubs then 
			Messages:clear() 
		elseif !HitMaxQueue() and Messages:len()>0 then 
		
			for i=1,UMSGS_IN_TICK do 
				
				if OnBeingTransmit() then -- No more in queue
					DisableTick()
					break
				end
				
			end
		
		end
	
	InEPOE=false
end

-- Initialize EPOE
function Initialize()
	InEPOE=true
	
		G.require	"enginespew"
		
		G.print	"EPOE hooks added"
		G.Msg   =	OnMsg
		G.MsgC   =	OnMsgC
		G.MsgN  =	OnMsgN
		G.print =	OnPrint
		

		local inhook = false -- Prevent deadloop. Should not happen type.
		hook.Add("EngineSpew", TagHuman, function(spewType, msg, group, level) 
			if inhook then return end
			inhook = true
			
			if spewType == 1 --[[ = SPEW_WARNING]] then -- TODO: Add possibility for full console output.
				OnLuaError( msg ) 
			end
			inhook = false
		end )
		
	
	InEPOE=false
end

-- TODO: Initialize earlier to hook even module prints
Initialize()