extends SceneTree

# Standalone material review board. Uses existing pawn/weapon/prop art, but is
# not a gameplay screenshot and never writes to battle state or production art.
const PawnArt = preload("res://scripts/ui/pawn_art.gd")
const State = preload("res://scripts/sim/state.gd")
const Weapon = preload("res://scripts/sim/weapon_pose.gd")
const OUT := "res://docs/art_review/terrain_style_v1/"
const GROUND_SHADER := """
shader_type canvas_item;
uniform sampler2D grass_tex : source_color, filter_linear;
uniform sampler2D dirt_tex : source_color, filter_linear;
uniform sampler2D gravel_tex : source_color, filter_linear;
uniform sampler2D concrete_tex : source_color, filter_linear;
uniform sampler2D metal_tex : source_color, filter_linear;
uniform float edge_softness = 0.25;
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise21(vec2 p) {
 vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
vec4 tile(sampler2D tex,vec2 p) {
 // Four phase samples fade to zero before their own source edge wraps.
 // Avoid mirror symmetry, while keeping original generated pixels intact.
 vec2 uv=fract(p/7.5), shifted=fract(uv+0.5);
 vec2 w=sin(uv*3.14159265); w*=w;
 vec4 a=texture(tex,shifted);
 vec4 b=texture(tex,vec2(uv.x,shifted.y));
 vec4 c=texture(tex,vec2(shifted.x,uv.y));
 vec4 d=texture(tex,uv);
 return mix(mix(a,b,w.x),mix(c,d,w.x),w.y);
}
float box_sdf(vec2 p,vec2 center,vec2 extent) {
 vec2 d=abs(p-center)-extent;
 return length(max(d,vec2(0)))+min(max(d.x,d.y),0.0);
}
void fragment() {
 vec2 p=UV*vec2(24.0,12.0);
 float n=noise21(p*4.0)-0.5;
 float path_y=8.0+sin(p.x*0.44)*0.5;
 float width=0.91+sin(p.x*0.75)*0.16;
 float dirt=1.0-smoothstep(width-edge_softness,width+edge_softness,abs(p.y-path_y)+n*0.32);
 vec4 col=mix(tile(grass_tex,p),tile(dirt_tex,p),dirt);
 float gravel=1.0-smoothstep(-edge_softness,edge_softness,box_sdf(p,vec2(17.3,7.2),vec2(5.65,3.75))+n*0.4);
 col=mix(col,tile(gravel_tex,p),gravel);
 float concrete=step(13.0,p.x)*step(p.x,22.0)*step(4.0,p.y)*step(p.y,10.0);
 col=mix(col,tile(concrete_tex,p),concrete);
 float metal=step(17.0,p.x)*step(p.x,21.0)*step(5.0,p.y)*step(p.y,8.0);
 col=mix(col,tile(metal_tex,p),metal);
 COLOR=vec4(col.rgb,1.0);
}
"""

class Board extends Node2D:
	var art = PawnArt.new()
	var font: Font
	var props: Texture2D
	var textures: Array[Texture2D] = []
	var style_index := 0
	var map_rect := Rect2(64,112,1472,736)
	var cell := 1472.0 / 24.0
	var ground: ColorRect
	var names := ["A · 柔和手绘", "B · 清爽战术插画", "C · 旧工业质感"]
	var notes := ["暖灰地板、柔和草泥过渡，地面保持安静。", "清晰的色块与冷灰地板，强调区域辨识。", "更丰富的颗粒、裂纹与磨损，强调材质触感。"]

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
		props = load("res://assets/art/vector/props_atlas.svg")
		art.setup()
		ground = ColorRect.new()
		ground.position = map_rect.position; ground.size = map_rect.size
		ground.z_index = -1
		var shader := Shader.new(); shader.code = GROUND_SHADER
		var material := ShaderMaterial.new(); material.shader = shader
		ground.material = material
		add_child(ground)

	func use_style(index: int) -> void:
		style_index = index
		textures.clear()
		var raw := Image.load_from_file(OUT + "source/" + ["a","b","c"][index] + "-materials.png")
		for column in range(5):
			var x0 := roundi(raw.get_width() * column / 5.0)
			var x1 := roundi(raw.get_width() * (column + 1) / 5.0)
			var side := mini(x1 - x0, raw.get_height())
			var region := raw.get_region(Rect2i(x0, (raw.get_height()-side)/2, side, side))
			textures.append(ImageTexture.create_from_image(region))
		var material: ShaderMaterial = ground.material
		for i in range(5): material.set_shader_parameter(["grass_tex","dirt_tex","gravel_tex","concrete_tex","metal_tex"][i], textures[i])
		material.set_shader_parameter("edge_softness", [0.32,0.16,0.26][index])
		queue_redraw()

	func text(at: Vector2, words: String, size: int, color: Color = Color("31443e")) -> void:
		draw_string(font,at,words,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

	func pos(x: float,y: float) -> Vector2:
		return map_rect.position + Vector2(x,y)*cell

	func prop(index: int,rect: Rect2) -> void:
		var side := props.get_width()/4.0
		draw_texture_rect_region(props,rect,Rect2(Vector2(index%4,index/4)*side,Vector2.ONE*side))

	func rifle(point: Vector2,angle: float,posture: int,factor: float) -> void:
		var pose: Dictionary = Weapon.rifle(Vector2.ZERO,angle,posture)
		draw_set_transform(point+Vector2(pose.anchor)*64*factor,angle,Vector2.ONE*factor)
		prop(10,pose.sprite_rect)
		draw_set_transform(point,0,Vector2.ONE*factor)

	func _draw() -> void:
		if textures.is_empty(): return
		text(Vector2(64,53),names[style_index],33)
		text(Vector2(64,85),notes[style_index],20,Color("68776b"))
		text(Vector2(1110,47),"RIMGATE / 地表与地板审稿",20)
		text(Vector2(1110,77),"相同布局 · 现有小人与沙袋 · 非实机截图",16,Color("68776b"))
		# Floor joints are graphic overlays, not terrain elevation.
		var joint := Color("5f665f"); joint.a = [0.22,0.30,0.38][style_index]
		for x in range(13,23): draw_line(pos(x,4),pos(x,10),joint,1.4,true)
		for y in range(4,11): draw_line(pos(13,y),pos(22,y),joint,1.4,true)
		draw_rect(Rect2(pos(13,4),Vector2(9,6)*cell),Color("57665c66"),false,1.6)
		# Steel plates stay directional. Narrow seams and small fasteners.
		for x in range(17,22): draw_line(pos(x,5),pos(x,8),Color("263b42a0"),2,true)
		for y in range(5,9): draw_line(pos(17,y),pos(21,y),Color("263b42a0"),2,true)
		for x in range(17,21):
			for y in range(5,8):
				for corner in [Vector2(.1,.1),Vector2(.9,.1),Vector2(.1,.9),Vector2(.9,.9)]:
					var p := pos(x+corner.x,y+corner.y)
					draw_circle(p,1.5,Color("a4b1a26b"))
		# Same sparse detail placements in each board; density varies by style.
		var rng := RandomNumberGenerator.new(); rng.seed = 2941
		for i in range([4,1,12][style_index]):
			var p := pos(rng.randf_range(13.3,21.7),rng.randf_range(8.2,9.7))
			draw_polyline(PackedVector2Array([p,p+Vector2(5,4),p+Vector2(9,1),p+Vector2(13,8)]),Color("565d573d"),0.9,true)
		# Render original props and current layered pawns at the same game scale.
		var scale_to_map := cell/64.0
		draw_set_transform(map_rect.position,0,Vector2.ONE*scale_to_map)
		for x in range(13,22): prop(0,Rect2(Vector2(x,4)*64,Vector2(64,64)))
		for y in range(5,7):
			prop(0,Rect2(Vector2(13,y)*64,Vector2(64,64)))
			prop(0,Rect2(Vector2(21,y)*64,Vector2(64,64)))
		prop(2,Rect2(Vector2(20,9)*64,Vector2(64,64)))
		prop(12,Rect2(Vector2(14.2,9)*64,Vector2(52,42)))
		# Fixed MG references use the unchanged real station components.
		var station_point := Vector2(16.5,5.5)*64
		prop(6,Rect2(station_point-Vector2(36,36),Vector2(72,72)))
		var station_pose := Weapon.station(station_point/64,-PI*.6,"mg")
		draw_set_transform(map_rect.position+Vector2(station_pose.anchor)*cell,-PI*.6,Vector2.ONE*scale_to_map)
		prop(7,station_pose.sprite_rect)
		draw_set_transform(Vector2.ZERO)
		var placements := [[1,Vector2(14.5,5.7),-PI*.5,0],[2,Vector2(18.5,5.7),-PI*.5,1],[3,Vector2(15.5,8.5),0.2,0],[4,Vector2(8.5,7.0),-0.1,0],[5,Vector2(5.5,9.8),PI*.5,0],[6,Vector2(19.0,7.0),PI*.75,0]]
		for item in placements:
			var unit: Dictionary = State.unit(int(item[0]),0,item[1])
			var point: Vector2 = pos(item[1].x,item[1].y)
			var angle: float = item[2]; var posture: int = item[3]
			draw_set_transform(point+Vector2(0,3),0,Vector2(18,7)*scale_to_map)
			draw_circle(Vector2.ZERO,1,Color("15241b35"))
			draw_set_transform(Vector2.ZERO)
			# Pawn draw uses pixel positions, so only this preview transform scales it.
			draw_set_transform(point,0,Vector2.ONE*scale_to_map)
			art.draw_pawn(self,unit,Vector2.ZERO,angle,posture,false,0,Color.WHITE,0,rifle.bind(point,angle,posture,scale_to_map))
			draw_set_transform(Vector2.ZERO)
		draw_rect(map_rect,Color("b2b7a6"),false,1)
		var labels := ["草地","泥土","碎石","混凝土地板","金属地板"]
		for i in range(5):
			var swatch := Rect2(64+i*296,916,264,156)
			text(Vector2(swatch.position.x,900),labels[i],20)
			draw_texture_rect(textures[i],swatch,false)
			if i>=3:
				for j in range(1,4): draw_line(swatch.position+Vector2(j*66,0),swatch.position+Vector2(j*66,156),Color("33443d55"),1,true)
				for j in range(1,3): draw_line(swatch.position+Vector2(0,j*52),swatch.position+Vector2(264,j*52),Color("33443d55"),1,true)
			draw_rect(swatch,Color("8f9d8a"),false,1)
		text(Vector2(64,1120),"审阅重点：材质风格、色彩、细节密度、地表衔接；不改变地形、建筑或战斗规则。",19,Color("647469"))
		text(Vector2(64,1150),"本轮为AI材质底稿＋Godot拼接样板。原稿保留；重复接缝与更多边缘变体待选定方向后完善。",16,Color("7b8577"))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	RenderingServer.set_default_clear_color(Color("eeeae1"))
	# Render to an explicit viewport, independent of desktop window height.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600,1180)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var board := Board.new(); viewport.add_child(board)
	await process_frame
	var manifest := {"purpose":"Static terrain/floor art review; not gameplay screenshot or implemented demo change", "generator":"builtin image_gen material originals; Godot scene composition", "sources":[], "production_assets_modified":false, "same_layout_and_pawns":true}
	for index in range(3):
		board.use_style(index)
		await process_frame
		await RenderingServer.frame_post_draw
		var filename: String = ["a-soft-painted.png","b-clear-tactical.png","c-weathered-industrial.png"][index]
		var shot := viewport.get_texture().get_image()
		var result := shot.save_png(OUT+filename)
		if result != OK: quit(2); return
		shot.get_region(Rect2i(830,350,650,400)).save_png(OUT+filename.get_basename()+"-detail.png")
		manifest.sources.append({"style":["a","b","c"][index],"source":"source/"+["a","b","c"][index]+"-materials.png","board":filename,"size":[shot.get_width(),shot.get_height()]})
		print("TERRAIN_REVIEW_SAVED ",ProjectSettings.globalize_path(OUT+filename))
	var file := FileAccess.open(OUT+"manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"))
	board.queue_free()
	await process_frame
	quit(0)
