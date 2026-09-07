class_name CrawlerReach
extends RefCounted

## Seated Reach ranks: extra beam and projectile range, plus Far Cast.


static func range_mul(rank: int) -> float:
	return CrawlerRules.reach_range_mul(rank)


static func far_cast_meters(rank: int) -> float:
	return CrawlerRules.far_cast_meters(rank)


static func far_cast(stats: Dictionary) -> float:
	return maxf(float(stats.get("far_cast", 0.0)), 0.0)


static func shift(from: Vector3, along: Vector3, stats: Dictionary) -> Vector3:
	var span := far_cast(stats)
	if span <= 0.001 or not from.is_finite():
		return from
	if along.length_squared() < 0.000001:
		return from
	return from + along.normalized() * span


static func shift_pair(left: Vector3, right: Vector3, along: Vector3,
		stats: Dictionary) -> Array[Vector3]:
	return [shift(left, along, stats), shift(right, along, stats)]
