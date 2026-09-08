class_name CrawlerCastleGarrison
extends Node3D

## Preseeded goblin pads inside Stormwatch. Harvest runs when the castle
## is seated so the horde can wake every home at once when a player
## gets close.

const GROUP := &"crawler_castle_garrison"
const HOMES := preload("res://game/crawler/crawler_interior_homes.gd")

var homes: PackedVector3Array = PackedVector3Array()
var _site: Node3D
var _host: Node3D


func _ready() -> void:
	name = "CastleGarrison"
	add_to_group(GROUP)


static func attach(site: Node3D, host: Node3D) -> CrawlerCastleGarrison:
	var garrison := CrawlerCastleGarrison.new()
	if host != null:
		host.add_child(garrison)
	elif site != null:
		site.add_child(garrison)
	garrison.bind(site, host)
	garrison.harvest()
	return garrison


func bind(site: Node3D, host: Node3D = null) -> void:
	_site = site
	_host = host
	if _host == null and site != null:
		var model := site.get_node_or_null("Model") as Node3D
		_host = model if model != null else site


func harvest() -> int:
	var root := _host
	if root == null:
		root = get_parent() as Node3D
	homes = HOMES.harvest(root, CrawlerRules.GOBLIN_GARRISON, 2.2)
	return homes.size()


func home_count() -> int:
	return homes.size()


func home_at(index: int) -> Vector3:
	if index < 0 or index >= homes.size():
		return Vector3.INF
	return homes[index]


static func find_for(site: Node) -> CrawlerCastleGarrison:
	if site == null:
		return null
	var held := site.find_child("CastleGarrison", true, false) \
			as CrawlerCastleGarrison
	if held != null:
		return held
	if not site.is_inside_tree():
		return null
	for node_variant: Variant in site.get_tree().get_nodes_in_group(GROUP):
		var garrison := node_variant as CrawlerCastleGarrison
		if garrison == null:
			continue
		if garrison._site == site or site.is_ancestor_of(garrison):
			return garrison
	return null


static func homes_for(site: Node) -> PackedVector3Array:
	var garrison := find_for(site)
	if garrison == null:
		return PackedVector3Array()
	if garrison.homes.is_empty():
		garrison.harvest()
	return garrison.homes
