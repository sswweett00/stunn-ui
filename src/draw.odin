// Draw_Command_Buffer: anlık-mod çağrıları GPU'ya gitmez, buraya birikir (batching).
package stunn

Draw_Vertex :: struct {
	pos: [3]f32, // x, y, z
	uv:  [2]f32, // u, v
	col: [4]f32, // r, g, b, a
}

Draw_Cmd :: struct {
	clip:       Rect,
	texture:    Texture_ID,
	idx_offset: u32,
	idx_count:  u32,
}

Draw_Command_Buffer :: struct {
	vertices:   ABuf(Draw_Vertex),
	indices:    ABuf(u32),
	cmds:       ABuf(Draw_Cmd),
	clip_stack: ABuf(Rect),
}

// Kapasiteler başlangıçta arenadan ayrılır; kare başına yalnızca sayaç
// sıfırlanır (yeniden tahsis yok).
draw_init :: proc "contextless" (b: ^Draw_Command_Buffer, vert_cap, idx_cap, cmd_cap: int) {
	abuf_init(&b.vertices, vert_cap)
	abuf_init(&b.indices, idx_cap)
	abuf_init(&b.cmds, cmd_cap)
	abuf_init(&b.clip_stack, 64)
}

draw_reset :: proc "contextless" (b: ^Draw_Command_Buffer, full: Rect) {
	abuf_clear(&b.vertices)
	abuf_clear(&b.indices)
	abuf_clear(&b.cmds)
	abuf_clear(&b.clip_stack)
	abuf_push(&b.clip_stack, full)
}

draw_clip_current :: #force_inline proc "contextless" (b: ^Draw_Command_Buffer) -> Rect {
	return abuf_last(&b.clip_stack)
}

draw_push_clip :: proc "contextless" (b: ^Draw_Command_Buffer, r: Rect) {
	abuf_push(&b.clip_stack, rect_intersect(draw_clip_current(b), r))
}

draw_pop_clip :: proc "contextless" (b: ^Draw_Command_Buffer) {
	if b.clip_stack.count > 1 { abuf_pop(&b.clip_stack) }
}

// Backend'ler için ham veri erişimi (nil-güvenli).
draw_vertex_data :: proc "contextless" (b: ^Draw_Command_Buffer) -> rawptr {
	if b.vertices.count <= 0 { return nil }
	return rawptr(b.vertices.data)
}

draw_index_data :: proc "contextless" (b: ^Draw_Command_Buffer) -> rawptr {
	if b.indices.count <= 0 { return nil }
	return rawptr(b.indices.data)
}

draw_quad_uv :: proc "contextless" (b: ^Draw_Command_Buffer, r: Rect, uv0, uv1: Vec2, col: Color, tex: Texture_ID) {
	clip := draw_clip_current(b)
	n := b.cmds.count
	if n == 0 || b.cmds.data[n - 1].texture != tex || b.cmds.data[n - 1].clip != clip {
		abuf_push(&b.cmds, Draw_Cmd{clip = clip, texture = tex, idx_offset = u32(b.indices.count)})
		n += 1
	}
	base := u32(b.vertices.count)
	abuf_push(&b.vertices, Draw_Vertex{{r.min.x, r.min.y, 0}, {uv0.x, uv0.y}, col})
	abuf_push(&b.vertices, Draw_Vertex{{r.max.x, r.min.y, 0}, {uv1.x, uv0.y}, col})
	abuf_push(&b.vertices, Draw_Vertex{{r.max.x, r.max.y, 0}, {uv1.x, uv1.y}, col})
	abuf_push(&b.vertices, Draw_Vertex{{r.min.x, r.max.y, 0}, {uv0.x, uv1.y}, col})
	abuf_push(&b.indices, base)
	abuf_push(&b.indices, base + 1)
	abuf_push(&b.indices, base + 2)
	abuf_push(&b.indices, base)
	abuf_push(&b.indices, base + 2)
	abuf_push(&b.indices, base + 3)
	b.cmds.data[n - 1].idx_count += 6
}

// Keyfi dörtgen (döndürülmüş çizgiler vb.). Köşeler saat yönünde/tersinde verilebilir.
draw_quad_points :: proc "contextless" (b: ^Draw_Command_Buffer, p: [4]Vec2, uv: Vec2, col: Color, tex: Texture_ID) {
	clip := draw_clip_current(b)
	n := b.cmds.count
	if n == 0 || b.cmds.data[n - 1].texture != tex || b.cmds.data[n - 1].clip != clip {
		abuf_push(&b.cmds, Draw_Cmd{clip = clip, texture = tex, idx_offset = u32(b.indices.count)})
		n += 1
	}
	base := u32(b.vertices.count)
	for i in 0 ..< 4 {
		abuf_push(&b.vertices, Draw_Vertex{{p[i].x, p[i].y, 0}, {uv.x, uv.y}, col})
	}
	abuf_push(&b.indices, base)
	abuf_push(&b.indices, base + 1)
	abuf_push(&b.indices, base + 2)
	abuf_push(&b.indices, base)
	abuf_push(&b.indices, base + 2)
	abuf_push(&b.indices, base + 3)
	b.cmds.data[n - 1].idx_count += 6
}
