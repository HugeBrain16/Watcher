local M = {}
package.path = package.path .. ";./bin/lua/watcher/modules/?.lua"

local pollnet = require("pollnet")
M._pollnet = pollnet

M.username = "Anonymous"
M.channel = "general"
M.server = "irc.kbfail.net:6667"

M.tips_duration = 10000
M.message_duration = 5000

M.logged_in = false
M.is_connected = false
M.update_interval = 100
M.last_update = 0

-- prevent callback being fired multiple times due to fast update rate
M.on_connecting_called = false
M.on_connected_called = false
M.on_illegal_name_called = false
M.on_name_already_in_use_called = false

-- callbacks
M.on_connecting = nil
M.on_connected = nil
M.on_illegal_name = nil
M.on_name_already_in_use = nil
M.on_message_receive = nil

function M.reset_states()
	M.is_connected = false
	M.logged_in = false
	M.on_connected_called = false
	M.on_connecting_called = false
	M.on_illegal_name_called = false
	M.on_name_already_in_use_called = false
end

function M.parse_message(line)
	local prefix, command, params, trailing
	line = line:match("^%s*(.*)$")

  	if line:sub(1, 1) == ":" then
    	prefix, line = line:match("^:([^%s]+)%s+(.*)$")
  	end

  	local space_pos = line:find(" ")
  	if space_pos then
    	command = line:sub(1, space_pos - 1)
    	line = line:sub(space_pos + 1)
  	else
    	command = line
    	line = ""
  	end

  	local trailing_pos = line:find(":")
  	if trailing_pos then
    	params = line:sub(1, trailing_pos - 2)
    	trailing = line:sub(trailing_pos + 1)
  	else
		params = line
	end
	
	return prefix, command, params, trailing
end

function M.send(msg)
	if M.irc:status() == "open" then
		M.irc:send(msg .. "\r\n")
	end
end

function M.init()
	M.irc = pollnet.Socket()
	M.irc:open_tcp(M.server)
	M.last_update = os.clock() * 1000
end

function M.update()
	if not M.irc then return end

	local now = os.clock() * 1000
	if (now - M.last_update) < M.update_interval then return end
	M.last_update = now

	local ok, msg = M.irc:poll()
	if msg then 
  	    local prefix, command, params, trailing = M.parse_message(msg)

        if command == "PING" then
            M.irc:send("PONG :" .. trailing .. "\r\n")
			printf("[Watcher] Got ping: %s", trailing)
		elseif (command == "001" or command == "376") and not M.logged_in then
            M.irc:send("JOIN " .. "#stalker_anomaly_" .. M.channel .. "\r\n")
            M.logged_in = true
			if M.on_connected and not M.on_connected_called then
				M.on_connected()
				M.on_connected_called = true
				M.is_connected = true
			end
		elseif command == "432" and not M.logged_in then
			if M.on_illegal_name then
				M.on_illegal_name()
				M.on_illegal_name_called = true
			end
        elseif command == "433" then
			if M.on_name_already_in_use then
				M.on_name_already_in_use()
				M.on_name_already_in_use_called = true
			end
		else
			if M.on_message_receive then
				M.on_message_receive(msg)
			end
		end 
	end

	if M.irc:status() == "opening" then
		M.irc:send("NICK " .. M.username .. "\r\n")
		M.irc:send("USER " .. M.username .. " 0 * :" .. M.username .. "\r\n")
		if M.on_connecting and not M.on_connecting_called then
			M.on_connecting()
			M.on_connecting_called = true
		end
	end
end

return M
