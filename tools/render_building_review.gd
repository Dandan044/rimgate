extends SceneTree

# Isolated building art review, not gameplay and not a production art swap.
const PawnArt = preload("res://scripts/ui/pawn_art.gd")
const State = preload("res://scripts/sim/state.gd")
const Weapon = preload("res://scripts/sim/weapon_pose.gd")
const OUT := "res://docs/art_review/building_style_v1/"
const CASES := [
	[Vector2i(1,1)],
	[Vector2i(0,1),Vector2i(1,1),Vector2i(2,1)],
	[Vector2i(1,0),Vector2i(1,1),Vector2i(1,2)],
	[Vector2i(1,0),Vector2i(1,1),Vector2i(2,1)],
	[Vector2i(0,1),Vector2i(1,1),Vector2i(2,1),Vector2i(1,2)],
	[Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(2,1),Vector2i(1,2)]
]
const LABELS := ["单格","横向连续","纵向连续","转角","T形交汇","十字交汇"]
const CLEAN_ALPHA := """
shader_type canvas_item;
varying vec4 drawing_tint;
void vertex() { drawing_tint=COLOR; }
void fragment() {
 vec4 sample_color=texture(TEXTURE,UV);
 // Discard unintended faint generation haze in the view, preserving originals.
 float alpha=smoothstep(0.40,0.80,sample_color.a);
 COLOR=vec4(sample_color.rgb,alpha)*drawing_tint;
}
"""

const SANDBAG_SHADER := """
shader_type canvas_item;
uniform sampler2D fabric_tex : source_color, filter_linear;
uniform vec4 fabric_color : source_color = vec4(0.76,0.69,0.48,1.0);
uniform vec2 centers[64];
uniform vec4 spans[96];
uniform int adj[64];
uniform int center_count=1;
uniform int span_count=0;
uniform vec2 domain_origin=vec2(-0.18,-0.24);
uniform vec2 domain_size=vec2(3.36,3.55);
uniform float pixel_width=0.012;
float hash11(float p) {return fract(sin(p*127.1+311.7)*43758.5453);}
float rounded_box(vec2 p,vec2 center,vec2 half_size,float radius) {
 vec2 d=abs(p-center)-half_size+radius;
 return length(max(d,vec2(0)))+min(max(d.x,d.y),0.0)-radius;
}
float smooth_union(float a,float b,float k) {
 float h=max(k-abs(a-b),0.0)/k;return min(a,b)-h*h*k*0.25;
}
float field(vec2 p) {
 float distance=100.0;
 for(int i=0;i<64;i++) {
  if(i>=center_count) break;
  distance=smooth_union(distance,rounded_box(p,centers[i],vec2(.36),.15),.07);
 }
 for(int i=0;i<96;i++) {
  if(i>=span_count) break;
  vec2 a=spans[i].xy,b=spans[i].zw;
  distance=smooth_union(distance,rounded_box(p,(a+b)*.5,abs(a-b)*.5+vec2(.36),.15),.08);
 }
 // Slight irregularity belongs to the entire pile contour, not cell borders.
 distance+=sin(p.x*17.0+p.y*7.0)*sin(p.y*19.0-p.x*3.0)*.016;
 return distance;
}
void fragment() {
 vec2 p=domain_origin+UV*domain_size;
 float d=field(p);
 float side_d=field(p-vec2(0,.14));
 float shadow_d=field(p-vec2(.025,.20));
 float top_alpha=1.0-smoothstep(-pixel_width,pixel_width,d);
 float side_alpha=1.0-smoothstep(-pixel_width,pixel_width,side_d);
 float shadow_alpha=(1.0-smoothstep(-.02,.07,shadow_d))*.24;
 vec2 q=p;
 for(int i=0;i<64;i++) {
  if(i>=center_count) break;
  if(all(lessThan(abs(p-centers[i]),vec2(.51)))) {
   // Straight vertical runs lay their bags along that run. Junctions use
   // one center arrangement, never overlaid crossing straight sections.
   if((adj[i]&10)==0 && (adj[i]&5)!=0) q=vec2(p.y,-p.x);
  }
 }
 float row_i=floor((q.y+sin(q.x*5.3)*.016)/.23);
 float stagger=mod(row_i,2.0)*.15+(hash11(row_i)-.5)*.13;
 float bag_width=.30+(hash11(row_i+43.0)-.5)*.045;
 vec2 bag_uv=vec2(fract((q.x+stagger+sin(q.y*6.1)*.018)/bag_width),fract((q.y+sin(q.x*5.3)*.016)/.23));
 vec2 ridge=abs(bag_uv-.5)*2.0;
 float seam=max(smoothstep(.91,.99,ridge.x),smoothstep(.91,.99,ridge.y));
 float puff=1.0-.12*(pow(ridge.x,3.0)+pow(ridge.y,3.0))+.035*(1.0-ridge.x)*(1.0-ridge.y);
 float bag_id=floor((q.x+stagger)/bag_width)+row_i*91.0;
 vec2 grain_uv=fract(p*1.73+vec2(.137,.291));
 // Sample only cloth interior; source sack outline/ropes are not repeated.
 vec3 cloth=texture(fabric_tex,vec2(.24,.28)+grain_uv*vec2(.50,.38)).rgb;
 float grain=(dot(cloth,vec3(.299,.587,.114))-.55)*.58;
 vec3 base=fabric_color.rgb*(1.0+grain+(hash11(bag_id)-.5)*.06);
 vec2 grad=vec2(field(p+vec2(.007,0))-field(p-vec2(.007,0)),field(p+vec2(0,.007))-field(p-vec2(0,.007)));
 vec2 normal=normalize(grad+vec2(.000001));
 float rim=smoothstep(-.19,-.015,d);
 float light=.97+rim*dot(normal,normalize(vec2(-.55,-.83)))*.19;
 vec3 top=base*light*puff*(1.0-seam*.24);
 // The south-facing lower courses supply a readable stacked front face.
 float courses=.94-.10*smoothstep(.70,.97,abs(fract(p.y/.095)-.5)*2.0);
 vec3 side=base*.72*courses*(1.0-seam*.12);
 float outline=1.0-smoothstep(-.035,-.005,d);
 top=mix(top,base*.48,outline*.65);
 vec3 color=vec3(.12,.15,.10);
 color=mix(color,side,side_alpha);
 color=mix(color,top,top_alpha);
 COLOR=vec4(color,max(max(top_alpha,side_alpha),shadow_alpha));
}
"""

class BagTopLayer extends Node2D:
	var cells: Array=[]
	var textures: Array[Texture2D]=[]
	var extent:=Vector2(188,200)
	var domain_start:=Vector2(-.18,-.24)
	var domain_extent:=Vector2(3.36,3.55)
	var placements: Array[Dictionary]=[]

	func _ready() -> void:
		texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		var shader:=Shader.new(); shader.code=CLEAN_ALPHA
		var alpha_material:=ShaderMaterial.new();alpha_material.shader=shader
		material=alpha_material
		assemble()

	func rounded_box(point: Vector2, center: Vector2, half_size: Vector2) -> float:
		var d: Vector2=(point-center).abs()-half_size+Vector2.ONE*.08
		return d.max(Vector2.ZERO).length()+minf(maxf(d.x,d.y),0)-.08

	func covered_direction(point: Vector2, vertical: bool) -> bool:
		for cell in cells:
			var center:=Vector2(cell)+Vector2.ONE*.5
			var horizontal_neighbors: bool=cells.has(cell+Vector2i.LEFT) or cells.has(cell+Vector2i.RIGHT)
			var vertical_neighbors: bool=cells.has(cell+Vector2i.UP) or cells.has(cell+Vector2i.DOWN)
			# Each branch lays its bags along that branch. A junction owns one
			# horizontal center patch; vertical courses meet its edge, not another
			# full stack underneath. Isolated stacks retain the horizontal layout.
			var has_center: bool=vertical_neighbors if vertical else horizontal_neighbors or not vertical_neighbors
			var half_size:=Vector2(.26,.21) if vertical else Vector2(.21,.26)
			if has_center and rounded_box(point,center,half_size)<=0: return true
			var delta:=Vector2i.DOWN if vertical else Vector2i.RIGHT
			if not cells.has(cell+delta): continue
			var other:=Vector2(cell+delta)+Vector2.ONE*.5
			if rounded_box(point,(center+other)*.5,(other-center).abs()*.5+half_size)<=0: return true
		return false

	func assemble() -> void:
		placements.clear()
		var low:=Vector2.INF;var high:=Vector2(-INF,-INF)
		for cell in cells:
			low=low.min(Vector2(cell));high=high.max(Vector2(cell)+Vector2.ONE)
		for vertical in [false,true]:
			var local_low:=Vector2(low.y,low.x) if vertical else low
			var local_high:=Vector2(high.y,high.x) if vertical else high
			for row in range(floori(local_low.y/.20)-1,ceili(local_high.y/.20)+1):
				for col in range(floori(local_low.x/.30)-2,ceili(local_high.x/.30)+2):
					var rng:=RandomNumberGenerator.new();rng.seed=absi(row*73856093+col*19349663+7919)
					var local:=Vector2(col*.30+(.15 if posmod(row,2)==1 else 0)+.09,row*.20+.10)
					local+=Vector2(rng.randf_range(-.025,.025),rng.randf_range(-.018,.018))
					var point:=Vector2(local.y,local.x) if vertical else local
					if not covered_direction(point,vertical): continue
					if vertical and covered_direction(point,false): continue
					placements.append({"point":point,"size":Vector2(rng.randf_range(.40,.45),rng.randf_range(.27,.31)),"rotation":(PI*.5 if vertical else 0.0)+rng.randf_range(-.09,.09),"variant":rng.randi_range(0,textures.size()-1),"height":rng.randf_range(.018,.055),"tone":rng.randf_range(.96,1.035)})
		placements.sort_custom(func(a,b):return a.point.y<b.point.y)
		queue_redraw()

	func draw_bag(item: Dictionary, lower: bool) -> void:
		var scale:=extent/domain_extent
		var point: Vector2=item.point+Vector2(0,.075 if lower else -float(item.height))
		var size: Vector2=Vector2(item.size)*scale*(1.025 if lower else 1.0)
		var pixel: Vector2=(point-domain_start)*scale
		if not lower:
			draw_set_transform(pixel+Vector2(1.1,2.0),float(item.rotation),size*Vector2(.45,.35))
			draw_circle(Vector2.ZERO,1,Color("30281735"))
		draw_set_transform(pixel,float(item.rotation))
		var tint:=Color(.73,.69,.60) if lower else Color.WHITE*float(item.tone)
		tint.a=1.0
		draw_texture_rect(textures[int(item.variant)],Rect2(-size*.5,size),false,tint)
		draw_set_transform(Vector2.ZERO)

	func _draw() -> void:
		for item in placements: draw_bag(item,true)
		for item in placements: draw_bag(item,false)

class ArtLayer extends Node2D:
	var pieces: Array[Texture2D] = []
	var index := 0
	var art = PawnArt.new()
	var props: Texture2D
	var board
	var focus_mode := false
	var sandbag_views: Array[Node2D] = []
	var sandbag_shader: Shader
	var lumpy_bags: Array[Texture2D]=[]

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var shader := Shader.new(); shader.code=CLEAN_ALPHA
		var alpha_material := ShaderMaterial.new(); alpha_material.shader=shader
		material=alpha_material
		sandbag_shader=Shader.new(); sandbag_shader.code=SANDBAG_SHADER
		art.setup(); props=load("res://assets/art/vector/props_atlas.svg")
		var registration: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"sandbags-lumpy-registration.json"))
		var raw:=Image.load_from_file(OUT+String(registration.source))
		for box in registration.parts: lumpy_bags.append(ImageTexture.create_from_image(raw.get_region(Rect2i(box[0],box[1],box[2],box[3]))))

	func fitted(texture: Texture2D, area: Rect2, max_ratio: float = 1.0) -> void:
		var size: Vector2 = texture.get_size()
		var factor: float = minf(area.size.x/size.x,area.size.y/size.y)*max_ratio
		size*=factor
		draw_texture_rect(texture,Rect2(area.get_center()-size*.5,size),false)

	func bag(point: Vector2, cell: float, angle: float=0.0) -> void:
		draw_set_transform(point,angle)
		draw_texture_rect(pieces[4],Rect2(-Vector2(.365,.25)*cell*.5,Vector2(.365,.25)*cell),false)
		draw_set_transform(Vector2.ZERO)

	func rebuild_sandbags() -> void:
		for view in sandbag_views: view.queue_free()
		sandbag_views.clear()
		for i in range(6):
			make_sandbag_view(CASES[i],Rect2(Vector2(96+i*248,590)-Vector2(10,14),Vector2(188,200)),Vector2(-10.0/56.0,-14.0/56.0),Vector2(188.0/56.0,200.0/56.0),1.0/56.0)
		make_sandbag_view(CASES[0],Rect2(106,155,272,244),Vector2(.82,.78),Vector2(1.36,1.22),1.0/200.0)

	func make_sandbag_view(cells: Array, rect: Rect2, domain_start: Vector2, domain_extent: Vector2, pixel: float) -> void:
		var view:=BagTopLayer.new();view.position=rect.position;view.extent=rect.size
		view.domain_start=domain_start;view.domain_extent=domain_extent;view.cells=cells;view.textures=lumpy_bags
		add_child(view);sandbag_views.append(view)

	func sandbags(cells: Array, origin: Vector2, cell: float) -> void:
		# Each shared edge is bridged once, then the center stack covers the join.
		# T/cross centers are one stack, not crossing duplicated straight sprites.
		for c in cells:
			var center: Vector2 = origin+(Vector2(c)+Vector2.ONE*.5)*cell
			if cells.has(c+Vector2i.RIGHT):
				for offset in [-.24,0,.24]: bag(center+Vector2(.5,offset)*cell,cell)
			if cells.has(c+Vector2i.DOWN):
				for offset in [-.24,0,.24]: bag(center+Vector2(offset,.5)*cell,cell,PI*.5)
		for c in cells:
			var center: Vector2 = origin+(Vector2(c)+Vector2.ONE*.5)*cell
			var vertical: bool = (cells.has(c+Vector2i.UP) or cells.has(c+Vector2i.DOWN)) and not (cells.has(c+Vector2i.LEFT) or cells.has(c+Vector2i.RIGHT))
			for x in [-.17,.17]:
				for y in [-.24,0,.24]:
					bag(center+(Vector2(-y,x) if vertical else Vector2(x,y))*cell,cell,PI*.5 if vertical else 0.0)

	func wall_rect(rect: Rect2) -> void:
		var vertices := PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)])
		var uvs := PackedVector2Array()
		for point in vertices: uvs.append(point/150.0)
		draw_polygon(vertices,PackedColorArray([Color.WHITE]),uvs,pieces[5])

	func walls(cells: Array, origin: Vector2, cell: float) -> void:
		var rectangles: Array[Rect2] = []
		var pixels: Dictionary = {}
		# 10 subcells define a union footprint, only exterior edges are outlined.
		for c in cells:
			var regions: Array[Rect2i] = [Rect2i(2,2,6,6)]
			if cells.has(c+Vector2i.UP): regions.append(Rect2i(2,0,6,3))
			if cells.has(c+Vector2i.RIGHT): regions.append(Rect2i(7,2,3,6))
			if cells.has(c+Vector2i.DOWN): regions.append(Rect2i(2,7,6,3))
			if cells.has(c+Vector2i.LEFT): regions.append(Rect2i(0,2,3,6))
			for region in regions:
				rectangles.append(Rect2(origin+(Vector2(c)+Vector2(region.position)/10.0)*cell,Vector2(region.size)*cell/10.0))
				for x in range(region.position.x,region.end.x):
					for y in range(region.position.y,region.end.y): pixels[c*10+Vector2i(x,y)]=true
		var height := cell*.17
		var side: Color = [Color("6b7064"),Color("465359"),Color("827d63")][index]
		for rect in rectangles:
			draw_rect(Rect2(rect.position+Vector2(0,height+2),rect.size),Color("26362b2a"))
			draw_rect(Rect2(rect.position+Vector2(0,height),rect.size),side)
		for rect in rectangles: wall_rect(rect)
		for p in pixels:
			var point: Vector2 = origin+Vector2(p)*cell/10.0
			var step := cell/10.0
			var edges := []
			if not pixels.has(p+Vector2i.UP): edges.append([point,point+Vector2(step,0),true])
			if not pixels.has(p+Vector2i.RIGHT): edges.append([point+Vector2(step,0),point+Vector2.ONE*step,false])
			if not pixels.has(p+Vector2i.DOWN): edges.append([point+Vector2(0,step),point+Vector2.ONE*step,false])
			if not pixels.has(p+Vector2i.LEFT): edges.append([point,point+Vector2(0,step),true])
			for edge in edges:
				draw_line(edge[0]+Vector2(0,height),edge[1]+Vector2(0,height),Color("354339"),1.6,true)
				draw_line(edge[0],edge[1],Color("354339"),2.0,true)
				if edge[2]: draw_line(edge[0]+Vector2(1,1),edge[1]+Vector2(1,1),Color("ede2beaa"),1,true)
		# Simple reinforcement along exposed front faces, without internal caps.
		for c in cells:
			if cells.has(c+Vector2i.DOWN): continue
			var point: Vector2 = origin+(Vector2(c)+Vector2(.5,.8))*cell
			draw_rect(Rect2(point+Vector2(-cell*.08,1),Vector2(cell*.16,height-2)),[Color("63705a"),Color("667b86"),Color("8c8058")][index])

	func rifle(point: Vector2,angle: float,factor: float) -> void:
		var pose: Dictionary=Weapon.rifle(Vector2.ZERO,angle,0)
		draw_set_transform(point+Vector2(pose.anchor)*64*factor,angle,Vector2.ONE*factor)
		var atlas_side: float=props.get_width()/4.0
		draw_texture_rect_region(props,pose.sprite_rect,Rect2(Vector2(2,2)*atlas_side,Vector2.ONE*atlas_side))
		draw_set_transform(point,0,Vector2.ONE*factor)

	func _draw() -> void:
		if pieces.size()!=6: return
		if focus_mode:
			for rect in [Rect2(1260,218,92,133),Rect2(1260,465,92,133)]: fitted(pieces[2],rect)
			var point:=Vector2(888,390)
			var unit: Dictionary=State.unit(4,0,Vector2.ZERO)
			draw_set_transform(point)
			art.draw_pawn(self,unit,Vector2.ZERO,0.0,0,false,0,Color.WHITE,0,rifle.bind(point,0.0,1.0))
			draw_set_transform(Vector2.ZERO)
			return
		# Enlarged shape/material cards; actual gameplay footprints remain undecided.
		for i in range(1,4): fitted(pieces[i],Rect2(92+i*372,158,300,236),0.96)
		for i in range(6):
			var origin := Vector2(96+i*248,590)
			walls(CASES[i],origin+Vector2(0,364),56)
		for i in range(3):
			var point := Vector2(1372+i*62,99)
			var unit: Dictionary=State.unit(i+3,0,Vector2.ZERO)
			draw_set_transform(point,0,Vector2.ONE*.65)
			art.draw_pawn(self,unit,Vector2.ZERO,PI*.5,0,false,0,Color.WHITE,0,rifle.bind(point,PI*.5,.65))
			draw_set_transform(Vector2.ZERO)

class Board extends Node2D:
	var art_layer: ArtLayer
	var index := 0
	var floor_textures: Array[Texture2D] = []
	var font: Font
	var names := ["方案 1 · 野战军用","方案 2 · 模块化工业","方案 3 · 遗迹科技"]
	var notes := ["米色帆布、暖灰混凝土、橄榄绿钢件；偏实用野战工事。","帆布沙袋、钢板包覆、铆接装甲；偏模块化工业设施。","浅色帆布、暖白外壳、旧铜结构；偏遗迹科技与野战改装。"]

	func _ready() -> void:
		texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		font=load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
		var raw:=Image.load_from_file("res://docs/art_review/terrain_style_v1/source/a-materials.png")
		for i in range(5):
			var x:=roundi(raw.get_width()*i/5.0)
			var side:=roundi(raw.get_width()/5.0)
			floor_textures.append(ImageTexture.create_from_image(raw.get_region(Rect2i(x,(raw.get_height()-side)/2,side,side))))
		art_layer=ArtLayer.new(); art_layer.board=self; art_layer.z_index=1
		add_child(art_layer)

	func use_style(style: int, registration: Dictionary) -> void:
		index=style; art_layer.index=style
		var key: String=["a","b","c"][style]
		var raw:=Image.load_from_file(OUT+String(registration[key].source))
		art_layer.pieces.clear()
		for piece in registration[key].pieces:
			var box: Array=piece.rect
			if piece.name=="wall_material":
				var inset:=int(mini(int(box[2]),int(box[3]))*.25)
				box=[int(box[0])+inset,int(box[1])+inset,int(box[2])-inset*2,int(box[3])-inset*2]
			art_layer.pieces.append(ImageTexture.create_from_image(raw.get_region(Rect2i(box[0],box[1],box[2],box[3]))))
		art_layer.rebuild_sandbags()
		queue_redraw(); art_layer.queue_redraw()

	func text(at: Vector2, words: String,size: int,color: Color=Color("31443d")) -> void:
		draw_string(font,at,words,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

	func _draw() -> void:
		if floor_textures.is_empty(): return
		text(Vector2(64,51),names[index],32)
		text(Vector2(64,84),notes[index],20,Color("68786d"))
		text(Vector2(1100,40),"RIMGATE / 建筑风格审稿",20)
		text(Vector2(1130,82),"现有小人参照 →",16,Color("68786d"))
		var titles := ["沙袋","墙体","炮塔／机枪工事","远古AI核心"]
		for i in range(4):
			text(Vector2(64+i*372,122),titles[i],23)
			var card:=Rect2(64+i*372,136,356,280)
			draw_texture_rect(floor_textures[[0,3,3,4][i]],card,false,Color(1,1,1,.64))
			draw_rect(card,Color("a9b2a2"),false,1)
		text(Vector2(64,450),"上排为造型放大图；下排使用统一格子比例检查连接。背景沿用已选 A 版地表。",18,Color("68786d"))
		text(Vector2(64,496),"沙袋连接 · 同类四方向邻接",25)
		text(Vector2(920,496),"圆润端头、连续堤体、错缝与堆叠厚度；格子用于定位。",17,Color("68786d"))
		text(Vector2(64,860),"墙体连接 · 连续顶面与外缘",25)
		text(Vector2(940,860),"共享边不画端盖；转角、T形和十字按邻接重建。",17,Color("68786d"))
		for row in range(2):
			for i in range(6):
				var panel:=Rect2(64+i*248,528+row*364,232,278)
				draw_texture_rect(floor_textures[0 if row==0 else 3],panel,false,Color(1,1,1,.62))
				draw_rect(panel,Color("a9b2a2"),false,1)
				text(panel.position+Vector2(15,30),LABELS[i],21)
				var origin:=Vector2(96+i*248,590+row*364)
				for grid in range(4):
					draw_line(origin+Vector2(grid*56,0),origin+Vector2(grid*56,168),Color("35483a28"),1,true)
					draw_line(origin+Vector2(0,grid*56),origin+Vector2(168,grid*56),Color("35483a28"),1,true)
		text(Vector2(64,1218),"连接区是按相邻格拼接的审稿原型，接头细节可随风格继续深化；未替换 Demo 资源。",18,Color("657469"))
		text(Vector2(64,1250),"核心与炮塔当前仅审造型；正式接入时再拆分枪身、底座、动画与损毁状态。",17,Color("788477"))

class FocusBoard extends Node2D:
	var art_layer: ArtLayer
	var font: Font
	var reference: Texture2D
	var grass: Texture2D
	var dirt: Texture2D

	func _ready() -> void:
		font=load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
		reference=ImageTexture.create_from_image(Image.load_from_file(OUT+"reference-sandbags.png"))
		var raw:=Image.load_from_file("res://docs/art_review/terrain_style_v1/source/a-materials.png")
		var side:=roundi(raw.get_width()/5.0)
		grass=ImageTexture.create_from_image(raw.get_region(Rect2i(0,0,side,side)))
		dirt=ImageTexture.create_from_image(raw.get_region(Rect2i(side,0,side,side)))
		art_layer=ArtLayer.new(); art_layer.z_index=1; art_layer.focus_mode=true
		add_child(art_layer)

	func prepare(registration: Dictionary) -> void:
		var raw:=Image.load_from_file(OUT+String(registration.a.source))
		for piece in registration.a.pieces:
			var box: Array=piece.rect
			art_layer.pieces.append(ImageTexture.create_from_image(raw.get_region(Rect2i(box[0],box[1],box[2],box[3]))))
		var fort: Array=[]
		for x in range(7): fort.append(Vector2i(x,1)); fort.append(Vector2i(x,5))
		for y in range(2,5): fort.append(Vector2i(6,y))
		for x in [1,3,5]: fort.append(Vector2i(x,0)); fort.append(Vector2i(x,6))
		art_layer.make_sandbag_view(fort,Rect2(700,146,474,486),Vector2(-.2,-.2),Vector2(7.4,7.6),1.0/64.0)
		for i in range(6):
			art_layer.make_sandbag_view(CASES[i],Rect2(80+i*248,774,200,212),Vector2(-.18,-.24),Vector2(3.36,3.55),1.0/60.0)
		queue_redraw(); art_layer.queue_redraw()

	func text(at: Vector2,words: String,size: int,color: Color=Color("31443d")) -> void:
		draw_string(font,at,words,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

	func _draw() -> void:
		if reference==null: return
		text(Vector2(64,51),"沙袋修订 · 纵向排布与交汇",31)
		text(Vector2(64,85),"横向与纵向沿各自堤线错缝堆放；交汇处共用一组中心沙袋，保留独立鼓包与遮挡。",19,Color("68786d"))
		text(Vector2(64,131),"你的参考",22)
		var scale:=minf(314.0/reference.get_width(),468.0/reference.get_height())
		draw_texture_rect(reference,Rect2(Vector2(64,150),reference.get_size()*scale),false)
		text(Vector2(488,131),"修订后的连接样板 / A版地表",22)
		draw_texture_rect(grass,Rect2(480,146,1056,492),false,Color(1,1,1,.85))
		draw_texture_rect(dirt,Rect2(725,267,330,227),false,Color(1,1,1,.80))
		text(Vector2(64,700),"端头、转角和交汇处",25)
		for i in range(6):
			var panel:=Rect2(64+i*248,726,232,278)
			draw_texture_rect(grass,panel,false,Color(1,1,1,.65))
			text(panel.position+Vector2(14,28),LABELS[i],20)
		text(Vector2(64,1042),"沙袋形体与连接审稿原型，未替换游戏素材。重点检查纵向宽度、转角与交汇处的摆袋方式。",17,Color("68786d"))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	RenderingServer.set_default_clear_color(Color("eeeae1"))
	var viewport:=SubViewport.new(); viewport.size=Vector2i(1600,1280)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var board:=Board.new(); viewport.add_child(board)
	await process_frame
	var registration: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"registration.json"))
	var outputs: Array=[]
	for style in range(3):
		board.use_style(style,registration)
		await process_frame
		await RenderingServer.frame_post_draw
		var filename: String=["1-field-military.png","2-modular-industrial.png","3-ancient-technology.png"][style]
		var shot:=viewport.get_texture().get_image()
		if shot.save_png(OUT+filename)!=OK: quit(2); return
		outputs.append(filename)
		print("BUILDING_REVIEW_SAVED ",ProjectSettings.globalize_path(OUT+filename))
	board.hide()
	viewport.size=Vector2i(1600,1080)
	var focus:=FocusBoard.new(); viewport.add_child(focus)
	await process_frame
	focus.prepare(registration)
	await process_frame; await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT+"sandbag-refinement-v4.png")
	outputs.append("sandbag-refinement-v4.png")
	var manifest: Dictionary={"generator":"builtin image_gen source assets; native Godot registration/composition","purpose":"Building style and same-type adjacency art review; not gameplay","selected_ground":"terrain_style_v1 A","outputs":outputs,"production_assets_modified":false,"review_status":"awaiting user selection; horizontal sandbags received positive feedback, vertical layout revised","same_layout":true,"connection_cases":LABELS,"neighbor_directions":["north","east","south","west"],"adjacency_prototype":"independent varied bag sprites in overlapping upper/lower courses; horizontal and vertical branches use directional staggered layouts with one junction center; wall union footprint with external-only outline","user_reference":"reference-sandbags.png, style reference only; not extracted as game art","source_atlases_unchanged":true,"weapon_core_animation_layers":"pending selected style; upper concept sprites are static whole shapes","prompts":"prompts.json","sandbag_prompt":"sandbags-lumpy-prompt.txt","sandbag_source":"source/sandbags-lumpy-v3.png"}
	var file:=FileAccess.open(OUT+"manifest.json",FileAccess.WRITE); file.store_string(JSON.stringify(manifest,"\t"))
	board.queue_free(); focus.queue_free(); await process_frame
	quit(0)
