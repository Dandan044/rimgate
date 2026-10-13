extends SceneTree

# Offline, native Godot component registration/baking. Original AI originals
# and approved review images remain untouched. No wardrobe combinations bake.
const OUT := "res://assets/art/v3/"
const PawnArt=preload("res://scripts/ui/pawn_art.gd")
const State=preload("res://scripts/sim/state.gd")
const CLEAN := "shader_type canvas_item; varying vec4 tint; void vertex(){tint=COLOR;} void fragment(){vec4 c=texture(TEXTURE,UV); COLOR=vec4(c.rgb,smoothstep(.40,.80,c.a))*tint;}"
const GROUND_SHADER := """
shader_type canvas_item;
uniform sampler2D grass_tex : source_color, filter_linear;
uniform sampler2D dirt_tex : source_color, filter_linear;
uniform sampler2D gravel_tex : source_color, filter_linear;
uniform sampler2D concrete_tex : source_color, filter_linear;
uniform sampler2D metal_tex : source_color, filter_linear;
float hash21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise21(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);}
vec4 tile(sampler2D tex,vec2 p){vec2 uv=fract(p/7.5),shifted=fract(uv+.5);vec2 w=sin(uv*3.14159265);w*=w;return mix(mix(texture(tex,shifted),texture(tex,vec2(uv.x,shifted.y)),w.x),mix(texture(tex,vec2(shifted.x,uv.y)),texture(tex,uv),w.x),w.y);}
float box(vec2 p,vec2 center,vec2 extent){vec2 d=abs(p-center)-extent;return length(max(d,vec2(0)))+min(max(d.x,d.y),0.0);}
float area(vec2 p,vec2 center,vec2 extent,float n,float edge){return 1.0-smoothstep(-edge,edge,box(p,center,extent)+n*.35);}
void fragment(){
 vec2 p=UV*vec2(64,48);float n=noise21(p*3.4)-.5;
 float dirt=max(max(area(p,vec2(13.5,10),vec2(4.5,10),n,.55),area(p,vec2(47.5,10),vec2(4.5,10),n,.55)),area(p,vec2(7.5,21.5),vec2(7.5,3.5),n,.55));
 vec4 col=mix(tile(grass_tex,p),tile(dirt_tex,p),dirt);
 float gravel=area(p,vec2(34,35.5),vec2(12.7,10.5),n,.55);col=mix(col,tile(gravel_tex,p),gravel*.8);
 float concrete=area(p,vec2(34,35.5),vec2(11,8.5),0.0,.05);col=mix(col,tile(concrete_tex,p),concrete);
 float metal=area(p,vec2(32,38),vec2(2.1,2.1),0.0,.03);col=mix(col,tile(metal_tex,p),metal);
 vec2 joint=abs(fract(p/2.0)-.5);float seam=max(smoothstep(.491,.5,joint.x),smoothstep(.491,.5,joint.y));col.rgb*=1.0-seam*concrete*.075;
 COLOR=vec4(col.rgb,1.0);
}
"""

class Connections extends Node2D:
	var bags: Array[Texture2D] = []
	var wall: Texture2D
	var kind := "sandbag"
	var only_mask:=0
	var only_variant:=0
	var placements: Array[Dictionary] = []
	var material_clean: ShaderMaterial
	func _ready() -> void:
		texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		var shader:=Shader.new();shader.code=CLEAN
		material_clean=ShaderMaterial.new();material_clean.shader=shader;material=material_clean
		if kind=="sandbag": assemble()
	func has_direction(mask: int, point: Vector2) -> bool:
		# Compact isolated pile. Arms extend to the exact cell edge and are
		# clipped by the atlas cell; connection data never merges hit points.
		if absf(point.x-.5)<=.27 and absf(point.y-.5)<=.27: return true
		if (mask&1)!=0 and absf(point.x-.5)<=.27 and point.y<=.5: return true
		if (mask&2)!=0 and absf(point.y-.5)<=.27 and point.x>=.5: return true
		if (mask&4)!=0 and absf(point.x-.5)<=.27 and point.y>=.5: return true
		if (mask&8)!=0 and absf(point.y-.5)<=.27 and point.x<=.5: return true
		return false
	func assemble() -> void:
		for variant in [only_variant]:
			for mask in [only_mask]:
				var origin:=Vector2.ZERO
				for row in range(-1,6):
					for col in range(-1,5):
						var p:=Vector2(col/3.0+(.1666667 if posmod(row,2)==1 else 0),row*.25)
						var vertical: bool=(mask&10)==0 and (mask&5)!=0
						if vertical:p=Vector2(p.y,p.x)
						if not has_direction(mask,p): continue
						# A common grid phase keeps neighboring cells sewn together.
						# Shape selection changes the interior only, never the edges.
						var edge: bool=p.x<.16 or p.x>.84 or p.y<.16 or p.y>.84
						var seed_value:=absi(row*137+col*79+(0 if edge else variant*29))
						placements.append({"origin":origin,"point":p,"vertical":vertical,"variant":seed_value%bags.size(),"tone":.98+float(seed_value%5)*.009,"size":Vector2(.42,.30)})
	func _draw() -> void:
		if kind=="wall":
			for variant in [only_variant]:
				for mask in [only_mask]: draw_wall(mask,variant)
			return
		for lower in [true,false]:
			for item in placements:
				var p: Vector2=item.origin+Vector2(item.point)*128.0+Vector2(0,7 if lower else -2)
				var size: Vector2=Vector2(item.size)*128.0
				if bool(item.vertical): size=Vector2(size.y,size.x)
				# Bags may change their long axis, but contact shadows and the
				# relighting glaze are always world-space upper-left lit.
				if not lower:
					draw_set_transform(p+Vector2(2,4),0,size*Vector2(.45,.32));draw_circle(Vector2.ZERO,1,Color("25231938"))
				draw_set_transform(p,PI*.5 if bool(item.vertical) else 0.0)
				var texture_size: Vector2=Vector2(item.size)*128.0
				var color:=Color(.68,.65,.54) if lower else Color.WHITE*float(item.tone);color.a=1
				draw_texture_rect(bags[int(item.variant)],Rect2(-texture_size*.5,texture_size),false,color)
				draw_set_transform(Vector2.ZERO)
				if not lower:
					# The same world-space highlight/shadow remains after a turn.
					draw_line(p+Vector2(-size.x*.34,-size.y*.29),p+Vector2(size.x*.20,-size.y*.29),Color("f3e6b51e"),1.2,true)
	func draw_wall(mask: int,variant: int) -> void:
		var origin:=Vector2.ZERO
		# The cap is visually raised; a 32px front and 7px east face make this
		# read as a standing concrete wall, without changing its grid footprint.
		var regions: Array[Rect2]=[Rect2(22,10,84,72)]
		if (mask&1)!=0:regions.append(Rect2(22,0,84,16))
		if (mask&2)!=0:regions.append(Rect2(100,10,28,72))
		if (mask&4)!=0:regions.append(Rect2(22,76,84,52))
		if (mask&8)!=0:regions.append(Rect2(0,10,28,72))
		var boundaries: Array[Dictionary]=[]
		var step:=2.0
		for y in range(64):
			for x in range(64):
				var p:=Vector2(x+.5,y+.5)*step
				var occupied:=false
				for r in regions:
					if r.has_point(p):occupied=true;break
				if not occupied:continue
				for delta in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
					var next: Vector2=p+delta*step;var other:=false
					for r in regions:
						if r.has_point(next):other=true;break
					if other or next.x<0 or next.x>=128 or next.y<0 or next.y>=128:continue
					var edge: Vector2=origin+p+delta*step*.5
					var axis:=Vector2(-delta.y,delta.x)*step*.5
					boundaries.append({"a":edge-axis,"b":edge+axis,"direction":delta})
		for r in regions:draw_rect(Rect2(r.position+Vector2(7,36),r.size),Color("25312650"))
		for edge in boundaries:
			var delta: Vector2=edge.direction
			if delta not in [Vector2.RIGHT,Vector2.DOWN]:continue
			var lift:=Vector2(7,32) if delta==Vector2.RIGHT else Vector2(0,32)
			var side:=Color("606351") if delta==Vector2.RIGHT else Color("82816c")
			draw_colored_polygon(PackedVector2Array([edge.a,edge.b,Vector2(edge.b)+lift,Vector2(edge.a)+lift]),side)
			draw_line(Vector2(edge.a)+lift,Vector2(edge.b)+lift,Color("414a3b"),2,true)
		for r in regions:
			var uv:=PackedVector2Array([r.position/128.0,r.position/128.0+Vector2(r.size.x/128.0,0),r.end/128.0,r.position/128.0+Vector2(0,r.size.y/128.0)])
			draw_polygon(PackedVector2Array([r.position,r.position+Vector2(r.size.x,0),r.end,r.position+Vector2(0,r.size.y)]),PackedColorArray([Color.WHITE]),uv,wall)
		for edge in boundaries:
			var delta: Vector2=edge.direction
			draw_line(edge.a,edge.b,Color("535b49"),2.5,true)
			var bevel:=Color("f0e5c8b0") if delta in [Vector2.UP,Vector2.LEFT] else Color("9e9e8290")
			draw_line(Vector2(edge.a)-delta*2.7,Vector2(edge.b)-delta*2.7,bevel,3.0,true)
		if (mask&4)==0:
			# An anchored reinforcing strap crosses the vertical front face.
			draw_rect(Rect2(52,82,24,31),Color("6b775c"))
			draw_line(Vector2(53,84),Vector2(53,111),Color("a3ad8a"),1.6,true)
			for point in [Vector2(59,89),Vector2(69,105)]:
				draw_circle(point,3.0,Color("3e4938"));draw_circle(point-Vector2(.5,.7),1.8,Color("bdc2a0"))
		# Three intentionally different, restrained wear patterns. They live
		# within the cap, never changing the edge silhouette/connection seam.
		var cracks: Array[PackedVector2Array]=[
			PackedVector2Array([Vector2(35,24),Vector2(42,30),Vector2(39,37),Vector2(46,41)]),
			PackedVector2Array([Vector2(81,21),Vector2(73,34),Vector2(78,42),Vector2(70,52),Vector2(73,60)]),
			PackedVector2Array([Vector2(37,62),Vector2(49,57),Vector2(55,44),Vector2(67,40),Vector2(77,28)])]
		draw_polyline(cracks[variant],Color("6b6e59a0"),2.0,true)
		var offset:=Vector2(1,-1)
		var lip:=PackedVector2Array()
		for point in cracks[variant]:lip.append(point+offset)
		draw_polyline(lip,Color("e8dfc35a"),1.1,true)
		for i in range(3):
			var point:=Vector2(37+posmod(i*23+variant*13,57),22+posmod(i*17+variant*11,45))
			draw_circle(point,1.6+float((i+variant)%2)*.6,Color("7c7e665b"))

class HairBake extends Node2D:
	var original: Texture2D
	var front:=true
	const ROWS: Array[int]=[0,1,2,3,6,7]
	const HAIR_SHADER:="""
shader_type canvas_item;
uniform bool front_layer=true;
varying vec2 local_uv;
varying float direction;
void vertex(){local_uv=VERTEX/256.0;direction=mod(floor(local_uv.x),4.0);}
void fragment(){
 vec4 c=texture(TEXTURE,UV);
 vec2 p=fract(local_uv);
 float dir=floor(local_uv.x);
 float skin=step(.83,c.r)*step(.55,c.g)*step(.36,c.b)*step(c.g*1.11,c.r)*step(c.b*1.10,c.g);
 float keep=1.0;
 if(dir<.5){keep=(p.y<.56||p.x<.25||p.x>.75)?1.0:0.0;}
 else if(dir<1.5){keep=(p.y<.52||p.x<.43)?1.0:0.0;}
 else if(dir<2.5){keep=1.0;}
 else {keep=(p.y<.52||p.x>.57)?1.0:0.0;}
 if(front_layer){keep*=dir>1.5&&dir<2.5?0.0:1.0;}
 else {keep*=dir>1.5&&dir<2.5?1.0:((p.y>.52)?1.0:0.0);}
 COLOR=vec4(c.rgb,smoothstep(.40,.80,c.a)*keep*(1.0-skin));
}
"""
	func _ready() -> void:
		texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		var shader:=Shader.new();shader.code=HAIR_SHADER
		var mat:=ShaderMaterial.new();mat.shader=shader;mat.set_shader_parameter("front_layer",front);material=mat
	func _draw() -> void:
		for row in range(6):
			for direction in range(4):draw_texture_rect_region(original,Rect2(direction*256,row*256,256,256),Rect2(direction*256,ROWS[row]*256,256,256))

class EnemyBake extends Node2D:
	var art=PawnArt.new()
	var kind:="trooper"
	var mask_texture: Texture2D
	func _ready() -> void:
		art.setup();mask_texture=load(OUT+"enemy_mask.svg")
		texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		var shader:=Shader.new();shader.code=CLEAN
		var mat:=ShaderMaterial.new();mat.shader=shader;material=mat
	func _draw() -> void:
		for pose in range(5):
			for direction in range(4):
				var point:=Vector2(32,62) if pose<2 else Vector2(32,32)
				var unit:=State.unit(1,0,Vector2.ZERO)
				var body:=1 if kind=="heavy" else (0 if kind=="flanker" else 2)
				var gear:="heavy" if kind=="heavy" else ("light" if kind=="flanker" else "standard")
				art.visual_loadouts[1]={"face":1,"features":3,"hair":5,"body":body,"top":"uniform_top","legs":"uniform_legs","vest":"vest_"+gear,"gear":gear,"helmet":true}
				unit.cower=pose==3
				var posture:=mini(2,pose)
				var facing: float=[PI*.5,0.0,-PI*.5,PI][direction]
				var tint:=Color(.94,.87,.77) if kind=="trooper" else Color(.77,.89,.90) if kind=="flanker" else Color(.88,.91,.85)
				var origin:=Vector2(direction,pose)*128.0
				draw_set_transform(origin,0,Vector2.ONE*2.0)
				art.draw_pawn(self,unit,point,facing,posture,pose==4,1.2,tint)
				var head_size:=Vector2(34,34)
				var head_center: Vector2
				if pose<2:
					var height:=float(PawnArt.RIGS[body].size.y)-(6 if pose==1 else 0)
					head_center=point+Vector2(0,-height-7)
				elif pose==3:head_center=point+Vector2(-3,-14);head_size=Vector2(27,27)
				else:head_center=point+[Vector2(0,20),Vector2(20,0),Vector2(0,-20),Vector2(-20,0)][direction];head_size=Vector2(28,28)
				var head_direction:=direction if pose<2 or pose==3 else (0 if pose==4 else 2)
				if head_direction!=2:
					draw_texture_rect_region(mask_texture,Rect2(head_center-head_size*.5,head_size),Rect2(head_direction*256,0,256,256),tint)
				# Helmet is always the top layer of this fixed whole-enemy asset.
				draw_texture_rect_region(art.helmets,Rect2(head_center+Vector2(-head_size.x*.53,-head_size.y*.56),head_size*Vector2(1.06,.97)),Rect2(head_direction*256,(1 if kind=="heavy" else 0)*256,256,256),tint)
				draw_set_transform(Vector2.ZERO)

class MachineGunPart extends Node2D:
	var raw: Texture2D
	var gun:=false
	func _ready() -> void:
		texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		var shader:=Shader.new()
		shader.code="""
shader_type canvas_item;
uniform bool gun_part=false;
varying vec2 location;
void vertex(){location=VERTEX;}
void fragment(){
 vec4 c=texture(TEXTURE,UV);float keep=1.0;
 if(gun_part){float neutral=1.0-smoothstep(.04,.13,max(c.r,max(c.g,c.b))-min(c.r,min(c.g,c.b)));keep=neutral;}
 else {if(location.x>54.0&&location.x<94.0&&location.y<88.0)keep=0.0;}
 COLOR=vec4(c.rgb,smoothstep(.40,.80,c.a)*keep);
}
"""
		var mat:=ShaderMaterial.new();mat.shader=shader;mat.set_shader_parameter("gun_part",gun);material=mat
	func _draw() -> void:
		if gun:
			draw_set_transform(Vector2(7,16),PI*.5)
			draw_texture_rect_region(raw,Rect2(-6.5,-54,13,54),Rect2(1206,18,85,379))
			draw_set_transform(Vector2.ZERO)
			draw_line(Vector2(59,16),Vector2(61,16),Color("343a33"),2,true)
		else:
			draw_texture_rect_region(raw,Rect2(0,0,128,128),Rect2(1067,190,307,292))

class MachineGunPivot extends Node2D:
	var raw: Texture2D
	func _draw() -> void:
		draw_texture_rect_region(raw,Rect2(48,0,50,94),Rect2(408,515,90,95))
		draw_circle(Vector2(68,62),31,Color("3e4b39"))
		draw_circle(Vector2(68,62),26,Color("899276"))
		draw_circle(Vector2(68,62),23,Color("5b684fc8"))
		draw_arc(Vector2(68,62),25,PI*.9,PI*1.8,32,Color("bec2a0"),1.6,true)
		draw_arc(Vector2(68,62),27,0,PI*.75,32,Color("303d2f"),2.5,true)

func _initialize() -> void: call_deferred("run")

func raw_texture(path: String, region: Rect2i=Rect2i()) -> Texture2D:
	var raw:=Image.load_from_file(path)
	if region.size.x>0: raw=raw.get_region(region)
	return ImageTexture.create_from_image(raw)

func capture(view: SubViewport,node: Node2D,path: String,size: Vector2i) -> void:
	view.size=size;view.add_child(node)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image();image.save_png(path)
	node.queue_free();await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var view:=SubViewport.new();view.transparent_bg=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var registration: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/art_review/building_style_v1/sandbags-lumpy-registration.json"))
	var bags: Array[Texture2D]=[]
	for box in registration.parts:bags.append(raw_texture("res://docs/art_review/building_style_v1/"+String(registration.source),Rect2i(box[0],box[1],box[2],box[3])))
	var wall:=raw_texture("res://docs/art_review/building_style_v1/source/a-buildings.png",Rect2i(1187,679,138,138))
	for kind in ["sandbag","wall"]:
		var atlas:=Node2D.new()
		for variant in range(3):
			for mask in range(16):
				var clip:=Control.new();clip.position=Vector2(mask%4,mask/4+variant*4)*128.0;clip.size=Vector2(128,128);clip.clip_contents=true;atlas.add_child(clip)
				var node:=Connections.new();node.bags=bags;node.wall=wall;node.kind=kind;node.only_mask=mask;node.only_variant=variant;clip.add_child(node)
		await capture(view,atlas,OUT+kind+"_connections.png",Vector2i(512,1536))
	var original:=raw_texture("res://assets/art/pawns_ai/heads.png")
	for front in [false,true]:
		var node:=HairBake.new();node.original=original;node.front=front
		await capture(view,node,OUT+("hair_front.png" if front else "hair_back.png"),Vector2i(1024,1536))
	# Keep cropped originals as independent pieces; all compositing is native.
	for part in [{"name":"core_body","rect":Rect2i(76,498,457,478)},{"name":"mg_source","rect":Rect2i(1067,17,307,465)}]:
		var image:=Image.load_from_file("res://docs/art_review/building_style_v1/source/a-buildings.png").get_region(part.rect)
		image.save_png(OUT+String(part.name)+".png")
	# Approved A: five source material squares, source remains in docs for provenance.
	var ground:=Image.load_from_file("res://docs/art_review/terrain_style_v1/source/a-materials.png")
	for col in range(5):
		var x0:=roundi(ground.get_width()*col/5.0);var x1:=roundi(ground.get_width()*(col+1)/5.0)
		var side:=mini(x1-x0,ground.get_height())
		ground.get_region(Rect2i(x0,(ground.get_height()-side)/2,side,side)).save_png(OUT+"ground_"+["grass","dirt","gravel","concrete","metal"][col]+".png")
	var ground_node:=Node2D.new();var painted:=ColorRect.new();painted.size=Vector2(4096,3072)
	var shader:=Shader.new();shader.code=GROUND_SHADER
	var ground_material:=ShaderMaterial.new();ground_material.shader=shader
	for name in ["grass","dirt","gravel","concrete","metal"]:ground_material.set_shader_parameter(name+"_tex",raw_texture(OUT+"ground_"+name+".png"))
	painted.material=ground_material;ground_node.add_child(painted)
	await capture(view,ground_node,OUT+"ground_map.png",Vector2i(4096,3072))
	for kind in ["trooper","flanker","heavy"]:
		var enemy:=EnemyBake.new();enemy.kind=kind
		await capture(view,enemy,OUT+"enemy_"+kind+".png",Vector2i(512,640))
	var approved_turret:=raw_texture("res://docs/art_review/building_style_v1/source/a-buildings.png")
	for gun in [false,true]:
		var assembly:=Node2D.new()
		if not gun:
			var pivot:=MachineGunPivot.new();pivot.raw=approved_turret;assembly.add_child(pivot)
		var part:=MachineGunPart.new();part.gun=gun;part.raw=approved_turret;assembly.add_child(part)
		await capture(view,assembly,OUT+("mg_gun.png" if gun else "mg_base.png"),Vector2i(64,32) if gun else Vector2i(128,128))
	print("V3_ART_BAKED: 16 neighbor masks x 3 variants x 2 buildings; 6 independent front/back hair x 4 views; approved A materials")
	quit()

