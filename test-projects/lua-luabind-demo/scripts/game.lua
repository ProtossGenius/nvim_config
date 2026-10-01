-- Game logic script interacting with C++ bound functions
local function battle_turn()
  local dmg = calculate_damage(1, 100)
  local player = {}
  player:heal(50)
  player:teleport(10.5, 20.0)
  set_speed(1.5)
  return dmg
end
return {
  battle_turn = battle_turn,
}
