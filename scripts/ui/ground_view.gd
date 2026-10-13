extends Node2D

const GRID := 64.0
const EnvironmentArt = preload("res://scripts/ui/environment_art.gd")
var world
var props: Texture2D
var font: Font
var ground: Texture2D
var grass: Texture2D=preload("res://assets/art/vector/grass_01.svg")
var chunks: Array[Rect2] = []
var art = EnvironmentArt.new()

func _ready() -> void:
    art.setup()
    if ResourceLoader.exists("res://assets/art/v3/ground_map.png"):ground=load("res://assets/art/v3/ground_map.png")
    # Offline-composited A materials are split into retained static draw chunks.
    # No per-frame noise, tile loops, shader work or simulation RNG is involved.
    for y in range(4):
        for x in range(4):chunks.append(Rect2(x*1024,y*768,1024,768))
    queue_redraw()

func _draw() -> void:
    if ground==null:
        draw_rect(Rect2(0,0,4096,3072),Color("7b8568"))
        return
    for chunk in chunks:draw_texture_rect_region(ground,chunk,chunk)
    var med:=Rect2(38*GRID,39*GRID,6*GRID,4*GRID)
    draw_rect(med,Color("8f9f8552"))
    draw_rect(med.grow(-6),Color("c7ceb280"),false,2)
    for point in world.medical_slots:art.draw_prop(self,"medical_bed",Rect2(Vector2(point)*GRID-Vector2(30,24),Vector2(60,48)))
    draw_string(font,Vector2(38*GRID+10,39*GRID+28),"战地救护",HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("f4f0da"))
    draw_string(font,Vector2(24*GRID,28*GRID),"弹药补给",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("656d59"))
    # Sparse world-space grass details are decoration, not navigation changes.
    for i in range(32):
        var point:=Vector2(160+posmod(i*787,3780),120+posmod(i*463,2800))
        if Rect2(21*GRID,25*GRID,27*GRID,22*GRID).has_point(point):continue
        draw_texture_rect(grass,Rect2(point-Vector2(22,30),Vector2(44,44)),false,Color(1,1,1,.42))
    draw_rect(Rect2(1,1,4094,3070),Color("555e49"),false,5)

