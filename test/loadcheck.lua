-- syntax check only: compiles the built file without running it
local f, err = loadfile(arg[1])
if not f then print("SYNTAX ERROR: " .. tostring(err)) os.exit(1) end
print("syntax ok")
