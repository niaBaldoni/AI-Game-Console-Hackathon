extends Object
class_name MeadowWorld

const SIZE := Vector2(2400.0, 1350.0)
const ROAD_X := 1080.0
const ROAD_Y := 565.0
const ROAD_WIDTH := 74.0

const ICELAND := {
    "name": "ICELAND",
    "rect": Rect2(0.0, 0.0, 1080.0, 565.0),
    "fill": Color("#8ec8dc"),
    "dot": Color("#e7f7ff"),
    "label": Color("#f4fbff"),
}
const FIRELAND := {
    "name": "FIRELAND",
    "rect": Rect2(1154.0, 0.0, 1246.0, 565.0),
    "fill": Color("#d37a4a"),
    "dot": Color("#f3c07a"),
    "label": Color("#fff1c7"),
}
const PURPLELAND := {
    "name": "PURPLELAND",
    "rect": Rect2(0.0, 641.0, 1080.0, 709.0),
    "fill": Color("#7a5aa8"),
    "dot": Color("#c9a6e6"),
    "label": Color("#f0e1ff"),
}
const GRASSLAND := {
    "name": "GRASSLAND",
    "rect": Rect2(1154.0, 641.0, 1246.0, 709.0),
    "fill": Color("#6ea85a"),
    "dot": Color("#74b761"),
    "label": Color("#e7ffd8"),
}


static func regions() -> Array[Dictionary]:
    return [ICELAND, FIRELAND, PURPLELAND, GRASSLAND]
