extends SceneTree
## Writes the prototype textures used by TrenchBroom maps to res://textures/ (PNG, so
## TrenchBroom can show them too): flat colours with a 1 m grid, and copies FuncGodot's
## special clip/skip/origin textures next to them. All textures are 512 px and the maps use
## a UV scale of 0.125, so one texture covers 2 m (32 units = 1 m; see
## tools/make_map_resources.gd, default_uv_scale).
## Run: godot --headless --path . -s res://tools/make_textures.gd, then godot --headless --path . --import

const SIZE := 512
const GRID := 256  # 1 m
## Texture name -> colour (the greybox palette of the old test arena).
const COLORS := {
	"ground": Color(0.2275, 0.2275, 0.2275),
	"wall": Color(0.2667, 0.2667, 0.3098),
	"blue": Color(0.3333, 0.3333, 0.4784),
	"green": Color(0.3098, 0.4157, 0.3098),
	"yellow": Color(0.4157, 0.4157, 0.3098),
	"red": Color(0.4157, 0.3098, 0.3098),
}
const SPECIAL := ["clip", "skip", "origin"]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://textures/prototype")
	for texture_name: String in COLORS:
		var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var base: Color = COLORS[texture_name]
		image.fill(base)
		var line := base.darkened(0.3)
		for x in SIZE:
			for y in SIZE:
				if x % GRID < 4 or y % GRID < 4:
					image.set_pixel(x, y, line)
		image.save_png("res://textures/prototype/%s.png" % texture_name)
	for special: String in SPECIAL:
		DirAccess.copy_absolute("res://addons/func_godot/textures/%s.png" % special, "res://textures/%s.png" % special)
	quit()
