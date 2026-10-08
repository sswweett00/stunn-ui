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
	vertices:   [dynamic]Draw_Vertex,
	indices:    [dynamic]u32,
	cmds:       [dynamic]Draw_Cmd,
	clip_stack: [dynamic]Rect,
}

// Kapasiteler başlangıçta ayrılır; kare başına yalnızca clear() yapılır (yeniden tahsis yok).
draw_init :: proc(b: ^Draw_Command_Buffer, vert_cap := 1 << 16, idx_cap := 1 << 17, cmd_cap := 512, allocator := context.allocator) {
	b.vertices   = make([dynamic]Draw_Vertex, 0, vert_cap, allocator)
	b.indices    = make([dynamic]u32, 0, idx_cap, allocator)
	b.cmds       = make([dynamic]Draw_Cmd, 0, cmd_cap, allocator)
	b.clip_stack = make([dynamic]Rect, 0, 64, allocator)
}

draw_destroy :: proc(b: ^Draw_Command_Buffer) {
	delete(b.vertices); delete(b.indices); delete(b.cmds); delete(b.clip_stack)
}

draw_reset :: proc(b: ^Draw_Command_Buffer, full: Rect) {
	clear(&b.vertices); clear(&b.indices); clear(&b.cmds); clear(&b.clip_stack)
	append(&b.clip_stack, full)
}

draw_clip_current :: #force_inline proc(b: ^Draw_Command_Buffer) -> Rect { return b.clip_stack[len(b.clip_stack) - 1] }

draw_push_clip :: proc(b: ^Draw_Command_Buffer, r: Rect) {
	append(&b.clip_stack, rect_intersect(draw_clip_current(b), r))
}

draw_pop_clip :: proc(b: ^Draw_Command_Buffer) {
	if len(b.clip_stack) > 1 { pop(&b.clip_stack) }
}

draw_quad_uv :: proc(b: ^Draw_Command_Buffer, r: Rect, uv0, uv1: Vec2, col: Color, tex: Texture_ID) {
	clip := draw_clip_current(b)
	n := len(b.cmds)
	if n == 0 || b.cmds[n - 1].texture != tex || b.cmds[n - 1].clip != clip {
		append(&b.cmds, Draw_Cmd{clip = clip, texture = tex, idx_offset = u32(len(b.indices))})
		n += 1
	}
	base := u32(len(b.vertices))
	append(&b.vertices,
		Draw_Vertex{{r.min.x, r.min.y, 0}, {uv0.x, uv0.y}, col},
		Draw_Vertex{{r.max.x, r.min.y, 0}, {uv1.x, uv0.y}, col},
		Draw_Vertex{{r.max.x, r.max.y, 0}, {uv1.x, uv1.y}, col},
		Draw_Vertex{{r.min.x, r.max.y, 0}, {uv0.x, uv1.y}, col},
	)
	append(&b.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	b.cmds[n - 1].idx_count += 6
}

// Keyfi dörtgen (döndürülmüş çizgiler, gizmo vb.). Köşeler saat yönünde/tersinde verilebilir.
draw_quad_points :: proc(b: ^Draw_Command_Buffer, p: [4]Vec2, uv: Vec2, col: Color, tex: Texture_ID) {
	clip := draw_clip_current(b)
	n := len(b.cmds)
	if n == 0 || b.cmds[n - 1].texture != tex || b.cmds[n - 1].clip != clip {
		append(&b.cmds, Draw_Cmd{clip = clip, texture = tex, idx_offset = u32(len(b.indices))})
		n += 1
	}
	base := u32(len(b.vertices))
	for i in 0 ..< 4 {
		append(&b.vertices, Draw_Vertex{{p[i].x, p[i].y, 0}, {uv.x, uv.y}, col})
	}
	append(&b.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	b.cmds[n - 1].idx_count += 6
}
