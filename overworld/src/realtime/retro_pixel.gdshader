shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 pixel_resolution = vec2(320.0, 180.0);


void fragment() {
	vec2 pixel_uv = (floor(SCREEN_UV * pixel_resolution) + vec2(0.5)) / pixel_resolution;
	COLOR = textureLod(screen_texture, pixel_uv, 0.0);
}
