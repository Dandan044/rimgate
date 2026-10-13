extends RefCounted

# Presentation-only modular paper doll. No lookup contains a complete friendly
# identity/outfit combination and no drawing routine consumes simulation RNG.
const CELL := 256.0
const ROOT := "res://assets/art/v3/"
const HAIR_ROWS: Array[int] = [0,1,2,3,6,7]
const RIGS := [
    {"size":Vector2(24,37),"widths":[.89,.94,.83,.86,.91],"socket":Vector2(0,-44)},
    {"size":Vector2(29,39),"widths":[1.04,1.04,.92,.96,.93],"socket":Vector2(0,-46)},
    {"size":Vector2(28,35),"widths":[.96,1.0,1.08,1.08,.93],"socket":Vector2(0,-42)}
]
var heads: Texture2D
var helmets: Texture2D
var long_hair: Texture2D
var faces: Texture2D
var hair_front: Texture2D
var hair_back: Texture2D
var features: Dictionary = {}
var enemy_outfits: Dictionary = {}
var observed_directions: Dictionary = {}
var observed_postures: Dictionary = {}
var bodies: Dictionary = {}
var garments: Dictionary = {}
var visual_loadouts: Dictionary = {}
var head_history: Dictionary = {}
var ready := false

func setup() -> void:
    var old_root := "res://assets/art/pawns_ai/"
    if not ResourceLoader.exists(old_root+"body_base.png"):return
    heads=load(old_root+"heads.png")
    helmets=load(old_root+"helmets.png")
    long_hair=load(old_root+"long_hair.png")
    bodies.base=load(old_root+"body_base.png")
    for kind in ["uniform_top","uniform_legs","vest_light","vest_standard","vest_heavy"]:garments[kind]=load(old_root+kind+".png")
    if ResourceLoader.exists(ROOT+"faces.svg"):
        faces=load(ROOT+"faces.svg");hair_front=load(ROOT+"hair_front.png");hair_back=load(ROOT+"hair_back.png")
        for expression in ["natural","blink","aim","hurt","panic","closed"]:features[expression]=load(ROOT+"features_"+expression+".svg")
        for kind in ["trooper","flanker","heavy"]:
            var path: String=ROOT+"enemy_"+kind
            enemy_outfits[kind]=load(path+".png" if ResourceLoader.exists(path+".png") else path+".svg")
    ready=faces!=null and hair_front!=null and hair_back!=null

func profile(unit: Dictionary) -> Dictionary:
    var id: int=absi(int(unit.id))
    var default_hair: int=[0,4,1,5,2,3][(id-1)%6] if id>0 else 1
    var default_features: int=[0,3,1,4,2,5][(id-1)%6] if id>0 else 1
    var gear: String="heavy" if String(unit.kind)=="heavy" else ("standard" if int(unit.team)==0 else "light")
    var appearance := {"face":id%3,"features":default_features,"hair":default_hair,"body":(id-1)%3,"gear":gear,"top":"uniform_top","legs":"uniform_legs","vest":"vest_"+gear,"helmet":unit.kind=="heavy" or (int(unit.team)==0 and id in [1,2,5]),"head":HAIR_ROWS[default_hair]}
    appearance.merge(unit.get("appearance_profile",{}),true)
    var overrides: Dictionary=visual_loadouts.get(id,{})
    if overrides.has("head"):
        var old_head: int=clampi(int(overrides.head),0,8)
        appearance.hair=HAIR_ROWS.find(old_head)
        if int(appearance.hair)<0:appearance.hair=3
        appearance.features=old_head%6;appearance.face=old_head%3
    appearance.merge(overrides,true)
    for key in ["face","features","hair","body"]:appearance[key]=posmod(int(appearance[key]),3 if key in ["face","body"] else 6)
    return appearance

func expression_for(unit: Dictionary, clock: float, down: bool=false, hurt: bool=false) -> String:
    if down:return "closed"
    if hurt or bool(unit.get("art_hurt",false)):return "hurt"
    if bool(unit.get("cower",false)) or int(unit.get("pressure_level",0))>=3 or String(unit.get("job",""))=="rout":return "panic"
    if String(unit.get("weapon_state",""))=="aiming":return "aim"
    # Deterministic, individual non-synchronous blinks. Paused display clock
    # freezes this phase, rather than blinking while the entire world is frozen.
    var phase: float=fposmod(clock+float(int(unit.id)*31%71)*.071,3.9+float(int(unit.id)%3)*.43)
    return "blink" if phase<.12 else "natural"

func direction_for(facing: float) -> int:
    var a:=wrapf(facing,-PI,PI)
    if a>=PI/4 and a<3*PI/4:return 0
    if a>=-3*PI/4 and a<-PI/4:return 2
    return 3 if absf(a)>=3*PI/4 else 1

func _region(column: int,row: int) -> Rect2:return Rect2(Vector2(column,row)*CELL,Vector2.ONE*CELL)

func draw_pawn(canvas: CanvasItem,unit: Dictionary,point: Vector2,facing: float,posture: int,down: bool,clock: float,tint: Color,dip: float=0.0,before_head: Callable=Callable()) -> void:
    var direction:=direction_for(facing)
    observed_directions[direction]=true
    var cower: bool=bool(unit.get("cower",false)) and not down
    observed_postures[4 if down else (3 if cower else posture)]=true
    if int(unit.team)==1 and not enemy_outfits.is_empty():
        _draw_enemy(canvas,unit,point,direction,posture,down,cower,tint,before_head,clock)
        return
    var appearance:=profile(unit)
    var rig: Dictionary=RIGS[int(appearance.body)]
    var moving: bool=Vector2(unit.velocity).length_squared()>.01 and not down and not cower
    var stride: float=sin(clock*(10.0 if posture==0 else 6.0)+int(unit.id)) if moving else 0.0
    var bob: float=absf(stride)*(1.2 if posture==0 else .55)
    var body_size: Vector2=Vector2(rig.size)
    if posture==1:body_size.y-=6
    var head_size:=Vector2(34,34)
    var body_rect: Rect2
    var head_center: Vector2
    var source_pose:=posture
    if posture<2:
        body_rect=Rect2(point+Vector2(-body_size.x*.5,-body_size.y+dip-bob),body_size)
        head_center=point+Vector2(stride*.25,-body_size.y-7+dip-bob)
        if int(appearance.hair)==0 and long_hair!=null:
            canvas.draw_texture_rect(long_hair,Rect2(head_center+Vector2(-15,-12),Vector2(30,42 if posture==0 else 34)),false,tint)
    elif cower:
        body_size=Vector2(34,24)
        body_rect=Rect2(point+Vector2(-17,-15),body_size)
        head_center=point+Vector2(-3,-14)
        head_size=Vector2(27,27)
        source_pose=1
    else:
        body_size=Vector2(54,28) if direction in [1,3] else Vector2(29,52)
        body_rect=Rect2(point-body_size*.5,body_size)
        var offset: Vector2=[Vector2(0,20),Vector2(20,0),Vector2(0,-20),Vector2(-20,0)][direction]
        head_center=point+offset;head_size=Vector2(28,28)
    # Only the presentation position eases. Actual posture/collision state is
    # authored by simulation; the transition never keeps a former hit volume.
    var key:=int(unit.id)
    var pose_key:=4 if down else (3 if cower else posture)
    var history: Dictionary=head_history.get(key,{"pose":pose_key,"from":head_center-point,"at":clock})
    if int(history.pose)!=pose_key:
        history={"pose":pose_key,"from":Vector2(history.get("last",head_center-point)),"at":clock};head_history[key]=history
    if not down and float(unit.get("posture_timer",0))>0:
        var t:=smoothstep(0.0,.35,clock-float(history.at))
        head_center=point+Vector2(history.from).lerp(head_center-point,t)
    history.last=head_center-point;head_history[key]=history
    var face_dir: int=direction if posture<2 or cower else (0 if down else 2)
    var head_rect:=Rect2(head_center-head_size*.5,head_size)
    if hair_back!=null:canvas.draw_texture_rect_region(hair_back,head_rect,_region(face_dir,int(appearance.hair)),tint)
    _draw_body(canvas,appearance,body_rect,direction,source_pose,tint,moving,stride)
    if before_head.is_valid() and not cower:before_head.call()
    if face_dir!=2:
        canvas.draw_texture_rect_region(faces,head_rect,_region(face_dir,int(appearance.face)),tint)
        var expression:=expression_for(unit,clock,down,tint.r>tint.g*1.25)
        canvas.draw_texture_rect_region(features[expression],head_rect,_region(face_dir,int(appearance.features)),tint)
        if hair_front!=null:canvas.draw_texture_rect_region(hair_front,head_rect,_region(face_dir,int(appearance.hair)),tint)
    else:
        canvas.draw_texture_rect_region(hair_back,head_rect,_region(2,int(appearance.hair)),tint)
    if helmets!=null and bool(appearance.helmet):
        # Helmet clips cap hair, leaving side locks/back hair in their own layers.
        canvas.draw_texture_rect_region(helmets,Rect2(head_center+Vector2(-head_size.x*.53,-head_size.y*.56),head_size*Vector2(1.06,.97)),_region(face_dir,1 if appearance.gear=="heavy" else 0),tint)

func _draw_body(canvas: CanvasItem,appearance: Dictionary,body: Rect2,direction: int,posture: int,tint: Color,moving: bool,stride: float) -> void:
    var source:=_region(direction,posture)
    # White T/shorts are the canonical minimum outfit. An opaque pants layer
    # owns its leg silhouette, so bare knees cannot protrude through trousers.
    var base: Texture2D=bodies.base
    if garments.has(String(appearance.legs)):
        var keep:=Rect2(0,0,1,.45)
        if posture==2:keep=[Rect2(0,.45,1,.55),Rect2(.45,0,.55,1),Rect2(0,0,1,.55),Rect2(0,0,.55,1)][direction]
        _rigged(canvas,base,Rect2(body.position+body.size*keep.position,body.size*keep.size),Rect2(source.position+source.size*keep.position,source.size*keep.size),tint,int(appearance.body),keep.position.y,keep.size.y)
    else:_rigged(canvas,base,body,source,tint,int(appearance.body))
    var torso:=Rect2(body.position,Vector2(body.size.x,body.size.y*.56))
    var legs:=Rect2(body.position+Vector2(0,body.size.y*.45),Vector2(body.size.x,body.size.y*.55))
    if posture==2:
        match direction:
            0:torso=Rect2(body.position+Vector2(0,body.size.y*.44),Vector2(body.size.x,body.size.y*.56));legs=Rect2(body.position,Vector2(body.size.x,body.size.y*.55))
            1:torso=Rect2(body.position+Vector2(body.size.x*.44,0),Vector2(body.size.x*.56,body.size.y));legs=Rect2(body.position,Vector2(body.size.x*.55,body.size.y))
            3:torso=Rect2(body.position,Vector2(body.size.x*.56,body.size.y));legs=Rect2(body.position+Vector2(body.size.x*.45,0),Vector2(body.size.x*.55,body.size.y))
    for data in [["legs",legs,.45,.55],["top",torso,0.0,.56],["vest",torso.grow_individual(.7,0,.7,.4),0.0,.56]]:
        var kind:=String(appearance[String(data[0])])
        if not garments.has(kind):continue
        var rect: Rect2=data[1]
        if moving and posture==0 and String(data[0])=="legs":rect.position.y+=absf(stride)*.35
        _rigged(canvas,garments[kind],rect,source,tint,int(appearance.body),float(data[2]),float(data[3]))

func _rig_width(rig: int,y: float) -> float:
    var values: Array=RIGS[rig].widths
    var p:=clampf(y,0,1)*4;var i:=mini(3,floori(p))
    return lerpf(float(values[i]),float(values[i+1]),p-i)

func _rigged(canvas: CanvasItem,texture: Texture2D,rect: Rect2,source: Rect2,tint: Color,rig: int,y_from: float=0,y_range: float=1) -> void:
    # A five-anchor shoulder/waist/hip/leg rig changes the contour locally.
    # Garments share these anchors; this is not a uniform x-scale body variant.
    var tex_size:=texture.get_size()
    for strip in range(4):
        var a:=float(strip)/4;var b:=float(strip+1)/4
        var wa:=rect.size.x*_rig_width(rig,y_from+a*y_range)*.5;var wb:=rect.size.x*_rig_width(rig,y_from+b*y_range)*.5
        var center:=rect.position.x+rect.size.x*.5
        var points:=PackedVector2Array([Vector2(center-wa,rect.position.y+rect.size.y*a),Vector2(center+wa,rect.position.y+rect.size.y*a),Vector2(center+wb,rect.position.y+rect.size.y*b),Vector2(center-wb,rect.position.y+rect.size.y*b)])
        var uv:=PackedVector2Array([source.position/tex_size+Vector2(0,source.size.y*a)/tex_size,(source.position+Vector2(source.size.x,source.size.y*a))/tex_size,(source.position+Vector2(source.size.x,source.size.y*b))/tex_size,(source.position+Vector2(0,source.size.y*b))/tex_size])
        canvas.draw_polygon(points,PackedColorArray([tint]),uv,texture)

func _draw_enemy(canvas: CanvasItem,unit: Dictionary,point: Vector2,direction: int,posture: int,down: bool,cower: bool,tint: Color,weapon_layer: Callable,clock: float) -> void:
    var kind:=String(unit.kind)
    if not enemy_outfits.has(kind):kind="trooper"
    var pose:=4 if down else (3 if cower else posture)
    var moving: bool=Vector2(unit.velocity).length_squared()>.01 and not down and not cower
    var bob:=absf(sin(clock*9+int(unit.id)))*.8 if moving else 0.0
    var rect:=Rect2(point+Vector2(-34,-61-bob),Vector2(68,68))
    if pose>=2:rect.position=point-Vector2(34,34)
    var source_cell: float=enemy_outfits[kind].get_width()/4.0
    canvas.draw_texture_rect_region(enemy_outfits[kind],rect,Rect2(direction*source_cell,pose*source_cell,source_cell,source_cell),tint)
    if weapon_layer.is_valid() and not cower:weapon_layer.call()
