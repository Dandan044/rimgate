extends SceneTree

const PawnArt=preload("res://scripts/ui/pawn_art.gd")
const EnvironmentArt=preload("res://scripts/ui/environment_art.gd")
const State=preload("res://scripts/sim/state.gd")
const Pose=preload("res://scripts/sim/weapon_pose.gd")
const World=preload("res://scripts/sim/world.gd")
const OUT:="res://docs/art_review/v3_runtime/"

class Sheet extends Node2D:
	var art=PawnArt.new()
	var environment=EnvironmentArt.new()
	var font: Font
	var clock:=1.2
	var mode:=0
	func _ready() -> void:
		art.setup();environment.setup();font=load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	func rifle(at: Vector2,angle: float,posture: int,scale: float) -> void:
		var pose:=Pose.rifle(Vector2.ZERO,angle,posture)
		draw_set_transform(at+Vector2(pose.anchor)*64*scale,angle,Vector2.ONE*scale)
		environment.draw_prop(self,"rifle",pose.sprite_rect)
		draw_set_transform(at,0,Vector2.ONE*scale)
	func _draw() -> void:
		draw_rect(Rect2(0,0,1800,1250),Color("d9d8c7"))
		draw_string(font,Vector2(42,48),"V3 · 独立四特征 / 装备层 / 四向姿态 / 建筑连接",HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("36493f"))
		var labels:=["白T恤与短裤","独立上衣 / 裤装","独立防弹衣 / 头盔","四向","蹲伏","卧倒","蜷缩","倒地"]
		for row in range(8):
			draw_string(font,Vector2(42,112+row*137),labels[row],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("48584a"))
			for col in range(6):
				var unit:=State.unit(col+1,0,Vector2.ZERO)
				unit.appearance_profile={"face":col%3,"features":col,"hair":col,"body":col%3}
				var override:={"helmet":false,"top":"","legs":"","vest":""}
				if row==1:override.top="uniform_top";override.legs="uniform_legs"
				if row>=2:override={"helmet":col%2==0,"top":"uniform_top","legs":"uniform_legs","vest":"vest_"+["light","standard","heavy"][col%3],"gear":["light","standard","heavy"][col%3]}
				art.visual_loadouts[col+1]=override
				var facing: float=PI*.5 if row<3 else [PI*.5,0,-PI*.5,PI,0,PI*.5][col]
				var posture:=1 if row==4 else (2 if row>=5 else 0)
				unit.posture=posture;unit.cower=row==6
				unit.weapon_state="aiming" if col==2 else "idle";unit.art_hurt=col==3
				unit.pressure_level=3 if row==6 else 0
				var at:=Vector2(290+col*235,186+row*137)
				draw_set_transform(at,0,Vector2.ONE*1.75)
				art.draw_pawn(self,unit,Vector2.ZERO,facing,posture,row==7,clock,Color.WHITE,0,rifle.bind(at,facing,posture,1.75) if row>=2 and row not in [6,7] else Callable())
				draw_set_transform(Vector2.ZERO)

class ConnectionsSheet extends Node2D:
	var environment=EnvironmentArt.new()
	var kind:="sandbag"
	var font: Font
	func _ready() -> void:environment.setup();font=load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,1080),Color("d9d8c7"))
		draw_string(font,Vector2(35,48),"V3 · "+("沙袋" if kind=="sandbag" else "墙体")+" · 北东南西16邻接 × 3变体",HORIZONTAL_ALIGNMENT_LEFT,-1,27,Color("36493f"))
		var texture: Texture2D=environment.textures[kind+"_connections"]
		for mask in range(16):
			var base:=Vector2(38+mask%4*390,85+int(mask/4)*241)
			draw_rect(Rect2(base,Vector2(365,215)),Color("c4c5b1"),false,1)
			draw_string(font,base+Vector2(12,26),"邻接 %02d"%mask,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("48584a"))
			for variant in range(3):
				var center:=base+Vector2(60+variant*115,124)
				var source:=Rect2(Vector2(mask%4,int(mask/4)+variant*4)*128,Vector2(128,128))
				draw_texture_rect_region(texture,Rect2(center-Vector2(42,42),Vector2(84,84)),source)
				draw_string(font,center+Vector2(-24,73),"变体%d"%(variant+1),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("65715b"))

class EnemiesSheet extends Node2D:
	var art=PawnArt.new()
	var environment=EnvironmentArt.new()
	var font: Font
	func _ready() -> void:art.setup();environment.setup();font=load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	func _draw() -> void:
		draw_rect(Rect2(0,0,1400,1100),Color("d9d8c7"))
		draw_string(font,Vector2(42,48),"V3 · 固定敌种外观 / 独立武器 / 保留姿态",HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("36493f"))
		for col in range(3):
			var kind: String=["trooper","flanker","heavy"][col]
			draw_string(font,Vector2(270+col*410,95),["普通步兵","侧翼轻装","重型装甲"][col],HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("48584a"))
			for pose in range(5):
				var unit:=State.unit(100+col,1,Vector2.ZERO,kind)
				unit.cower=pose==3
				var at:=Vector2(330+col*410,230+pose*175)
				draw_set_transform(at,0,Vector2.ONE*2.2)
				art.draw_pawn(self,unit,Vector2.ZERO,PI*.5,mini(2,pose),pose==4,1.2,Color.WHITE)
				draw_set_transform(Vector2.ZERO)
		for pose in range(5):draw_string(font,Vector2(42,210+pose*175),["站立","蹲伏","卧倒","蜷缩","倒地"][pose],HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("48584a"))

func _initialize() -> void:call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var view:=SubViewport.new();view.size=Vector2i(1800,1250);view.transparent_bg=false;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var sheet:=Sheet.new();view.add_child(sheet)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(OUT+"paperdoll-poses.png")
	sheet.queue_free();await process_frame
	view.size=Vector2i(1600,1080)
	for kind in ["sandbag","wall"]:
		var connections:=ConnectionsSheet.new();connections.kind=kind;view.add_child(connections)
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		view.get_texture().get_image().save_png(OUT+kind+"-16-masks.png")
		connections.queue_free();await process_frame
	view.size=Vector2i(1400,1100)
	var enemies:=EnemiesSheet.new();view.add_child(enemies)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(OUT+"enemy-poses.png")
	print("V3_PAPERDOLL_REVIEW_CAPTURED")
	quit()


