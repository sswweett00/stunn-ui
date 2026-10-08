// stunn_ui OpenGL 4.6 Core backend + GLFW girdi köprüsü. Çekirdek (../src) GL'den habersizdir.
// Host, GL fonksiyonlarını önceden yüklemiş olmalıdır (gl.load_up_to).
package stunn_gl

import "core:fmt"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import stunn "../src"

VERT_SRC :: `#version 460 core
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_col;
uniform mat4 u_proj;
out vec2 v_uv;
out vec4 v_col;
void main() {
	v_uv = a_uv;
	v_col = a_col;
	gl_Position = u_proj * vec4(a_pos, 1.0);
}`

FRAG_SRC :: `#version 460 core
in vec2 v_uv;
in vec4 v_col;
uniform sampler2D u_tex;
uniform int u_is_atlas;
out vec4 o_color;
void main() {
	vec4 t = texture(u_tex, v_uv);
	o_color = (u_is_atlas != 0) ? vec4(v_col.rgb, v_col.a * t.r) : v_col * t;
}`

Renderer :: struct {
	program:             u32,
	vao, vbo, ebo:       u32,
	atlas_tex:           u32,
	loc_proj, loc_tex, loc_is_atlas: i32,
	vbo_bytes, ebo_bytes: int,
}

init :: proc(r: ^Renderer, ctx: ^stunn.Context) -> bool {
	prog, ok := gl.load_shaders_source(VERT_SRC, FRAG_SRC)
	if !ok {
		fmt.eprintln("stunn_gl: shader derlenemedi")
		return false
	}
	r.program = prog
	r.loc_proj     = gl.GetUniformLocation(prog, "u_proj")
	r.loc_tex      = gl.GetUniformLocation(prog, "u_tex")
	r.loc_is_atlas = gl.GetUniformLocation(prog, "u_is_atlas")

	gl.GenVertexArrays(1, &r.vao)
	gl.GenBuffers(1, &r.vbo)
	gl.GenBuffers(1, &r.ebo)
	gl.BindVertexArray(r.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, r.ebo)
	stride := i32(size_of(stunn.Draw_Vertex))
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, stride, uintptr(offset_of(stunn.Draw_Vertex, pos)))
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, stride, uintptr(offset_of(stunn.Draw_Vertex, uv)))
	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(2, 4, gl.FLOAT, false, stride, uintptr(offset_of(stunn.Draw_Vertex, col)))
	gl.BindVertexArray(0)

	gl.GenTextures(1, &r.atlas_tex)
	gl.BindTexture(gl.TEXTURE_2D, r.atlas_tex)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.R8, stunn.ATLAS_W, stunn.ATLAS_H, 0, gl.RED, gl.UNSIGNED_BYTE, &ctx.atlas[0])
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	return true
}

destroy :: proc(r: ^Renderer) {
	gl.DeleteProgram(r.program)
	gl.DeleteVertexArrays(1, &r.vao)
	gl.DeleteBuffers(1, &r.vbo)
	gl.DeleteBuffers(1, &r.ebo)
	gl.DeleteTextures(1, &r.atlas_tex)
}

// display: UI mantıksal boyutu; fb_w/fb_h: gerçek framebuffer piksel boyutu (HiDPI için).
render :: proc(r: ^Renderer, ctx: ^stunn.Context, fb_w, fb_h: i32) {
	b := &ctx.draw
	if b.cmds.count == 0 { return }

	gl.Viewport(0, 0, fb_w, fb_h)
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Enable(gl.SCISSOR_TEST)

	vbytes := b.vertices.count * size_of(stunn.Draw_Vertex)
	ibytes := b.indices.count * size_of(u32)
	gl.BindVertexArray(r.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	if vbytes > r.vbo_bytes {
		r.vbo_bytes = vbytes * 2
		gl.BufferData(gl.ARRAY_BUFFER, r.vbo_bytes, nil, gl.STREAM_DRAW)
	}
	gl.BufferSubData(gl.ARRAY_BUFFER, 0, vbytes, stunn.draw_vertex_data(b))
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, r.ebo)
	if ibytes > r.ebo_bytes {
		r.ebo_bytes = ibytes * 2
		gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, r.ebo_bytes, nil, gl.STREAM_DRAW)
	}
	gl.BufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, ibytes, stunn.draw_index_data(b))

	gl.UseProgram(r.program)
	w, h := ctx.display.x, ctx.display.y
	proj := matrix[4, 4]f32{
		2 / w, 0,      0, -1,
		0,     -2 / h, 0, 1,
		0,     0,      1, 0,
		0,     0,      0, 1,
	}
	gl.UniformMatrix4fv(r.loc_proj, 1, false, &proj[0, 0])
	gl.Uniform1i(r.loc_tex, 0)
	gl.ActiveTexture(gl.TEXTURE0)

	sx := f32(fb_w) / w
	sy := f32(fb_h) / h
	for ci in 0 ..< b.cmds.count {
		c := &b.cmds.data[ci]
		if c.idx_count == 0 { continue }
		x0 := i32(c.clip.min.x * sx)
		y1 := i32(c.clip.max.y * sy)
		cw := i32(c.clip.max.x * sx) - x0
		ch := y1 - i32(c.clip.min.y * sy)
		if cw <= 0 || ch <= 0 { continue }
		gl.Scissor(x0, fb_h - y1, cw, ch)
		if c.texture == 0 {
			gl.BindTexture(gl.TEXTURE_2D, r.atlas_tex)
			gl.Uniform1i(r.loc_is_atlas, 1)
		} else {
			gl.BindTexture(gl.TEXTURE_2D, u32(c.texture))
			gl.Uniform1i(r.loc_is_atlas, 0)
		}
		gl.DrawElements(gl.TRIANGLES, i32(c.idx_count), gl.UNSIGNED_INT, rawptr(uintptr(c.idx_offset) * size_of(u32)))
	}
	gl.Disable(gl.SCISSOR_TEST)
	gl.Disable(gl.BLEND)
	gl.BindVertexArray(0)
}

// ---------------------------------------------------------------- GLFW girdi köprüsü
@(private)
scroll_accum: stunn.Vec2

install_scroll_callback :: proc(window: glfw.WindowHandle) {
	glfw.SetScrollCallback(window, proc "c" (_: glfw.WindowHandle, x, y: f64) {
		scroll_accum += {f32(x), f32(y)}
	})
}

feed_input :: proc(ctx: ^stunn.Context, window: glfw.WindowHandle) {
	x, y := glfw.GetCursorPos(window)
	stunn.input_mouse_pos(ctx, {f32(x), f32(y)})
	stunn.input_mouse_button(ctx, 0, glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS)
	stunn.input_mouse_button(ctx, 1, glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS)
	stunn.input_mouse_button(ctx, 2, glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_MIDDLE) == glfw.PRESS)
	stunn.input_scroll(ctx, scroll_accum)
	scroll_accum = {}
	shift := glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS || glfw.GetKey(window, glfw.KEY_RIGHT_SHIFT) == glfw.PRESS
	ctrl  := glfw.GetKey(window, glfw.KEY_LEFT_CONTROL) == glfw.PRESS || glfw.GetKey(window, glfw.KEY_RIGHT_CONTROL) == glfw.PRESS
	stunn.input_modifiers(ctx, shift, ctrl)
}

