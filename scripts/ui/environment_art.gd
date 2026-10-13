extends RefCounted

const ROOT := "res://assets/art/v3/"
const GRID := 64.0
const DIRECTIONS := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
var textures: Dictionary = {}
var occupied: Dictionary = {}
var cell_masks: Dictionary = {}
var building_cells: Dictionary = {}
var last_updated_cells: Array[Vector2i] = []
var ready := false

func setup() -> void:
	for name in ["sandbag_connections","wall_connections","core_body"]:
		if ResourceLoader.exists(ROOT+name+".png"):textures[name]=load(ROOT+name+".png")
	for name in ["mg_base","mg_gun","mortar_base","mortar_gun","rifle","ammo_box","medical_bed","core_damage"]:
		if ResourceLoader.exists(ROOT+name+".png"):textures[name]=load(ROOT+name+".png")
		elif ResourceLoader.exists(ROOT+name+".svg"):textures[name]=load(ROOT+name+".svg")
	ready=textures.size()==11

func rebuild(world) -> void:
	occupied.clear();cell_masks.clear();building_cells.clear();last_updated_cells.clear()
	for building in world.buildings:
		if building.kind not in ["sandbag","wall"] or bool(building.destroyed):continue
		var list: Array[Vector2i]=[]
		for y in range(building.rect.position.y,building.rect.end.y):
			for x in range(building.rect.position.x,building.rect.end.x):
				var cell:=Vector2i(x,y);list.append(cell);occupied[cell]={"kind":String(building.kind),"id":int(building.id)}
		building_cells[int(building.id)]=list
	for cell in occupied:_refresh_cell(cell)

func _refresh_cell(cell: Vector2i) -> void:
	if not occupied.has(cell):cell_masks.erase(cell);return
	var mask:=0
	for i in range(4):
		var neighbor: Vector2i=cell+DIRECTIONS[i]
		if occupied.has(neighbor) and occupied[neighbor].kind==occupied[cell].kind:mask|=1<<i
	cell_masks[cell]=mask

func destroyed(world,entity_id: int) -> void:
	# Removing one real building only invalidates its own cells and four
	# neighbors. Draw caches never merge collision geometry or durability.
	last_updated_cells.clear()
	var candidates: Dictionary={}
	for cell in building_cells.get(entity_id,[]):
		occupied.erase(cell);candidates[cell]=true
		for delta in DIRECTIONS:candidates[cell+delta]=true
	building_cells.erase(entity_id)
	for cell in candidates:_refresh_cell(cell);last_updated_cells.append(cell)

func mask_at(cell: Vector2i) -> int:return int(cell_masks.get(cell,0))

func variant_at(cell: Vector2i) -> int:return posmod(cell.x*73+cell.y*131,3)

func draw_connections(canvas: CanvasItem,building: Dictionary) -> void:
	var texture: Texture2D=textures[String(building.kind)+"_connections"]
	for y in range(building.rect.position.y,building.rect.end.y):
		for x in range(building.rect.position.x,building.rect.end.x):
			var cell:=Vector2i(x,y);var mask:=mask_at(cell);var variant:=variant_at(cell)
			var source:=Rect2(Vector2(mask%4,int(mask/4)+variant*4)*128,Vector2(128,128))
			canvas.draw_texture_rect_region(texture,Rect2(Vector2(cell)*GRID,Vector2.ONE*GRID),source)

func draw_prop(canvas: CanvasItem,name: String,destination: Rect2,tint: Color=Color.WHITE) -> void:
	if textures.has(name):canvas.draw_texture_rect(textures[name],destination,false,tint)

func draw_core(canvas: CanvasItem,building: Dictionary,rect: Rect2,clock: float) -> void:
	draw_prop(canvas,"core_body",rect.grow(5),Color("9b9c86") if building.destroyed else Color.WHITE)
	if building.destroyed or float(building.hp)<float(building.max_hp)*.65:
		draw_prop(canvas,"core_damage",rect.grow(-5),Color(1,1,1,1.0 if building.destroyed else .6))
	if not building.destroyed:
		var pulse:=.55+.45*sin(clock*1.8)
		var center:=rect.get_center()+Vector2(-1,-1)
		canvas.draw_circle(center,rect.size.x*.055,Color(.35,.97,.90,.23+pulse*.15))
		canvas.draw_arc(center,rect.size.x*.12,0,TAU,48,Color(.34,.97,.88,.22+pulse*.22),2,true)
