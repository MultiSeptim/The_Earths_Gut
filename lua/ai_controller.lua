if not wml_actions then wml_actions = {} end

-- We need one of these in every file that uses one of these, apparently:
local _ = wesnoth.textdomain("wesnoth-The_Earths_Gut")

------------------------------------------------------------------------------------------------------------------------

local function calc_position_danger(side, x, y)
	local location_set = wesnoth.require "lua/location_set.lua"
	local adjacent = location_set.create()
	for u, v in helper.adjacent_tiles(x, y) do
		adjacent:insert(u, v)
	end

	local reach_units = {}
	for i, u in ipairs(wesnoth.units.find_on_map({ { "filter_side", { { "enemy_of", { side = side }} }} })) do
		local ucfg = u.__cfg
		local reachable = location_set.of_pairs(wesnoth.find_reach(u, { ignore_units = false, ignore_teleport = false, additional_turns = 0, viewing_side = 0 }))
		--if u.x == 6 then
			--reachable_pairs = reachable:to_pairs()
			--for i, loc in ipairs(reachable_pairs) do
				--wml_actions.label({ text = "*", x = loc[1], y = loc[2] })
			--end
		--end
		reachable:inter(adjacent)
		if reachable:size() > 0 then
			local reach_unit = { unit = u, level = ucfg.level}
			local function mark_as_reachable(x, y)
				--local data = adjacent:get(x, y)
				--data[u] = ucfg.level
				--adjacent:insert(x, y, data)
				table.insert(reach_unit, { x, y })
			end
			reachable:iter(mark_as_reachable)
			table.insert(reach_units, reach_unit)
		end
	end
	--wml_actions.message({ speaker = "narrator", message = tostring(reach_units[1].unit)})
	--dbms(reach_units)
	local function compare(u1, u2)
		if u1.level == u2.level then
			return #u1> #u2
		end
		return u1.level < u2.level
	end
	table.sort(reach_units, compare)
	--dbms(reach_units)
	--for i, loc in ipairs(wesnoth.map.find({})) do wml_actions.label({ x = loc[1], y = loc[2], text = "" }) end
	--for i, loc in ipairs(reach_units[1]) do wml_actions.label({ x = loc[1], y = loc[2], text = "*" }) end
	
	local function calc_danger(adjacent)
		local danger = 0
		local function do_it(x, y, data)
			if type(data) ~= "table" then danger = danger + 0.0
			elseif data.level < 1 then danger = danger + 0.5
			elseif data.level < 2 then danger = danger + 1.0
			elseif data.level < 3 then danger = danger + 1.5
			else danger = danger + 2
			end
		end
		adjacent:iter(do_it)
		return danger
	end
	
	local function distribute_units(reach_units, adjacent, toplevel)
		local function remove_used_up_hexes_and_units_accordingly_to_hexes(reach_units, hex)
			local i = #reach_units
			while true do
				if i < 1 then break end
				local u = reach_units[i]
				for j, v in ipairs(u) do
					if v[1] == hex[1] and v[2] == hex[2] then
						table.remove(u, j)
					end
				end
				if #u == 0 then 
					--dbms(reach_units[i], "removing")
					table.remove(reach_units, i)
				end
				i = i - 1
			end
		end
		while true do
			--if toplevel then dbms(adjacent) end
			if #reach_units < 1 then return adjacent end
			local u = reach_units[#reach_units]
			--if toplevel then dbms("processing: " .. u.unit.name) end
			assert(#u >= 1)
			local hex
			if #u == 1 then
				hex = u[1]
			else
				--dbms(u)
				--dbms("entering multi-hex case")
				local best_danger = 0
				local best_hex
				for i, loc in ipairs(u) do
					--local adjacent_saved = adjacent
					local adjacent = helper.deep_copy(adjacent)
					--assert(helper.equals(adjacent, adjacent_saved))
					--local reach_units_saved = reach_units
					local reach_units = helper.deep_copy(reach_units)
					--assert(helper.equals(reach_units_saved, reach_units))
					local reach_unit = reach_units[#reach_units]
					reach_unit = { unit = reach_unit.unit, level = reach_unit.level, loc }
					--dbms(reach_unit)
					reach_units[#reach_units] = reach_unit
					assert(#reach_units[#reach_units] == 1)
					--dbms("checking case " .. tostring(i) .. " for " .. dbms(u, true, false, true, false, true))
					--dbms(dbms(reach_units, true, "reach_units", true, false, true))
					adjacent = distribute_units(reach_units, adjacent)
					local danger = calc_danger(adjacent)
					--dbms(adjacent, true, "resulting adjacent")
					--dbms(danger, true, "resulting danger")
					if danger > best_danger then
						best_danger = danger
						best_hex = loc
					end
				end
				hex = best_hex
				--dbms(adjacent, true, "chosen adjacent")
				--dbms(reach_units)
			end
			--dbms(adjacent)
			local previous = adjacent:get(hex[1], hex[2])
			--if toplevel then dbms(previous) end
			if type(previous) == "table" then
				assert(previous.level >= u.level)
				table.remove(reach_units)
				--if toplevel then dbms("discarding: " .. previous.unit.name) end
			else
				--dbms("inserting:" .. u.unit.name)
				adjacent:insert(hex[1], hex[2], u)
				table.remove(reach_units)
				--dbms(reach_units)
				remove_used_up_hexes_and_units_accordingly_to_hexes(reach_units, hex)
			end
		end
		return adjacent
	end
	adjacent = distribute_units(reach_units, adjacent, true)
	--for i, loc in ipairs(wesnoth.map.find({})) do wml_actions.label({ x = loc[1], y = loc[2], text = "" }) end
	--local function put_unit_names(x, y, data)
		--if type(data) ~= "table" then return end
		--wml_actions.label({ x = x, y = y, text = data.unit.name })
	--end
	--dbms(adjacent)
	--adjacent:iter(put_unit_names)
	local danger = calc_danger(adjacent)
	--dbms(danger)
	return danger
end

function wml_actions.ai_controller_new_force_to_heal_wounded_units(cfg)
	local side = wesnoth.current.side

	local function move_wounded_unit_to(u, loc)
		local path = wesnoth.find_path(u, loc[1], loc[2], { ignore_teleport = true, viewing_side = 0 })
		--wml_actions.message({ speaker = "narrator", message = string.format("found path: %s", dbms(path, false, "path", true, false, true)) })
		if #path == 0 then
			helper.warning("no path found to force " .. u.name .. " to heal")
			return
		end
		assert(#path >= 2)
		local dest_length = wml.variables["LUA_destinations.length"]
		wesnoth.set_variable(string.format("LUA_destinations[%u].x", dest_length), loc[1])
		wesnoth.set_variable(string.format("LUA_destinations[%u].y", dest_length), loc[2])
		for i, loc in ipairs(path) do
			if i == 1 then
			else
				--wml_actions.message({ speaker = "narrator", message = string.format("checking loc: (%u, %u)", loc[1], loc[2]) })
				local cost = wesnoth.unit_movement_cost(u, wesnoth.get_terrain(loc[1], loc[2]))
				local new_moves = u.moves - cost
				--wml_actions.message({ speaker = "narrator", message = string.format("new moves: %i", new_moves) })
				if new_moves >= 0 then
					--wml_actions.message({ speaker = "narrator", message = string.format("move step: (%u, %u)", loc[1], loc[2]) })
					u.moves = new_moves
					wml_actions.move_unit({ id = u.id, to_x = loc[1], to_y = loc[2],
						check_passability = false, fire_event = false })
				else
					u.moves = 0
					--wml_actions.message({ speaker = "narrator", message = string.format("%s stopped on the way to heal before (%u, %u))", u.name, loc[1], loc[2]) })
					break
				end
				if i == #path then
					u.moves = 0
					u.role = "force_heal_heals_side" .. tostring(side)
					wml_actions.capture_village({ side = u.side, x = u.x, y = u.y })
					--wml_actions.message({ speaker = "narrator", message = string.format("%s heals now at (%u, %u)", u.name, loc[1], loc[2]) })
				end
			end
		end
	end

	local function handle_healing_units()
		local units = wesnoth.units.find_on_map({ role = "force_heal_heals_side" .. tostring(side) })
		for i, u in ipairs(units) do
			if u.hitpoints == u.max_hitpoints then
				u.role = ""
				--wml_actions.message({ speaker = "narrator", message = string.format("%s has finished healing at (%u, %u))", u.name, u.x, u.y) })
			else
				u.moves = 0
				u.attacks_left = 0
				--wml_actions.message({ speaker = "narrator", message = string.format("%s continues to heal at (%u, %u))", u.name, u.x, u.y) })
			end
		end
	end
	local function free_unneccessarily_occupied_villages()
		local units = wesnoth.units.find_on_map({ side = side, { "filter_location", { terrain = "*^V*" }}, formula = "max_hitpoints = hitpoints" })
		for i, u in ipairs(units) do
			for x, y in helper.adjacent_tiles(u.x, u.y, false) do
				if not wesnoth.get_unit(x, y) then
					wml_actions.move_unit({ id = u.id, to_x = x, to_y = y })
					break
				end
			end
		end
	end
	free_unneccessarily_occupied_villages()
	handle_healing_units()

	local filter = helper.shallow_literal(helper.get_child(cfg, "filter"))
	local forbidden_sides = cfg.forbidden_sides
	filter.formula = "max_hitpoints > hitpoints"
	table.insert(filter, { "not", { role = "force_heal_heals_side" .. tostring(side) }})
	local wounded_units = wesnoth.units.find_on_map(filter)

	for i, u in ipairs(wounded_units) do
		assert(u.side == side)
		--wml_actions.message({ speaker = "narrator", message = string.format("found unit to heal: %s", u.name) })
		local filter =
		{
			x_source = u.x,
			y_source = u.y,
			{ "not",
				{
					{ "filter", {} }
				}
			},
			{ "not",
				{ find_in = "LUA_destinations" }
			},
			x = cfg.x,
			y = cfg.y,
			--{ "filter_owner", { side = side }}
			{ "and",
				{
					{ "filter_owner", { { "not", {}} }},
					{ "or",
						{
							{ "filter_owner",
								{
									{ "not", { side = forbidden_sides }}
								}
							}
						}
					}
				}
			}
		}
		--dbms(filter)
		if not wesnoth.get_terrain_info(wesnoth.get_terrain(u.x, u.y)).village then
			local function calc_heal_loc()
				local heal_loc = wml_actions.nearest_hex(filter, true, true)
				if not heal_loc then return end
				local danger = calc_position_danger(u.side, heal_loc[1], heal_loc[2])
				if danger <= 1 then return heal_loc end
				local dest_length = wml.variables["LUA_destinations.length"]
				wesnoth.set_variable(string.format("LUA_destinations[%u].x", dest_length), heal_loc[1])
				wesnoth.set_variable(string.format("LUA_destinations[%u].y", dest_length), heal_loc[2])
				return calc_heal_loc()
			end
			local heal_loc = calc_heal_loc()
			u.attacks_left = 0 --in any case, especially if trapped
			if heal_loc then
				--wml_actions.message({ speaker = "narrator", message = string.format("found heal location: (%u,%u)", heal_loc[1], heal_loc[2]) })
				move_wounded_unit_to(u, heal_loc)
			else
				helper.warning("no location found to force " .. u.name .. " to heal")
			end
		end
	end
	wesnoth.set_variable("LUA_destinations")
end

function wml_actions.ai_controller_place_reserved_labels(cfg)
	local locs = wesnoth.map.find({ x = cfg.x, y = cfg.y })
	local color = wesnoth.sides[cfg.side].color
	local color_number = tonumber(color)
	if color_number then color = color_number end
	local rgb = helper.get_child(wml.variables["team_colors"], "color_range", color).rgb
	color = string.sub(rgb, 1, 6)
	local text = string.format(tostring(_"<span color='#%s'>reserved</span>"), color)
	for i, loc in ipairs(locs) do
		wml_actions.label({ x = loc[1], y = loc[2], text = text })
	end
end
----------------------------------------------------------------------------------------------------------
