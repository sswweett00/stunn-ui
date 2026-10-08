// stunn_ui tek başına demo: motor/volt bağımlılığı yok. Yalnızca stunn + vendor:glfw + vendor:OpenGL.
package main

import "core:fmt"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import stunn "../src"
import stunn_gl "../backend_gl"

main :: proc() {
	if !glfw.Init() { fmt.eprintln("glfw init başarısız"); return }
	defer glfw.Terminate()
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 6)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	window := glfw.CreateWindow(1280, 720, "Stunn UI - standalone demo", nil, nil)
	if window == nil { fmt.eprintln("pencere açılamadı (OpenGL 4.6 gerekli)"); return }
	defer glfw.DestroyWindow(window)
	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(1)
	gl.load_up_to(4, 6, glfw.gl_set_proc_address)

	ctx: stunn.Context
	stunn.init(&ctx)
	defer stunn.destroy(&ctx)
	rend: stunn_gl.Renderer
	if !stunn_gl.init(&rend, &ctx) { return }
	defer stunn_gl.destroy(&rend)
	stunn_gl.install_scroll_callback(window)

	// Viewport widget'ı için 64x64 dama dokusu (host'un ürettiği saf GL doku ID'si).
	checker: [64 * 64 * 4]u8
	for y in 0 ..< 64 {
		for x in 0 ..< 64 {
			v := u8(230) if ((x / 8) + (y / 8)) % 2 == 0 else u8(60)
			i := (y * 64 + x) * 4
			checker[i], checker[i + 1], checker[i + 2], checker[i + 3] = v, v / 2 + 60, 255 - v, 255
		}
	}
	tex: u32
	gl.GenTextures(1, &tex)
	gl.BindTexture(gl.TEXTURE_2D, tex)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 64, 64, 0, gl.RGBA, gl.UNSIGNED_BYTE, &checker[0])
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

	position := [3]f32{1, 2, 3}
	scale    := [3]f32{1, 1, 1}
	exposure: f32 = 1
	intensity: f32 = 10
	show_grid := true
	clicks := 0
	last := glfw.GetTime()

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
		now := glfw.GetTime()
		dt := f32(now - last)
		last = now

		ww, wh := glfw.GetWindowSize(window)
		fw, fh := glfw.GetFramebufferSize(window)
		stunn_gl.feed_input(&ctx, window)
		stunn.begin_frame(&ctx, {f32(ww), f32(wh)}, dt)

		if stunn.begin_window(&ctx, "Inspector", {{20, 20}, {380, 360}}) {
			stunn.labelf(&ctx, "Frame: %.2f ms", dt * 1000)
			stunn.separator(&ctx)
			stunn.drag_float3(&ctx, "Position", &position, 0.05)
			stunn.drag_float3(&ctx, "Scale", &scale, 0.01, 0.01, 100)
			stunn.drag_float(&ctx, "Exposure", &exposure, 0.01, 0.01, 16)
			stunn.drag_float(&ctx, "Intensity (log)", &intensity, 0.01, 0, 0, true)
			stunn.slider_float(&ctx, "Slider", &exposure, 0.01, 16)
			stunn.checkbox(&ctx, "Show grid", &show_grid)
			if stunn.button(&ctx, "Click me") { clicks += 1 }
			stunn.same_line(&ctx)
			stunn.labelf(&ctx, "%d", clicks)
			stunn.end_window(&ctx)
		}
		if stunn.begin_window(&ctx, "Viewport", {{420, 20}, {500, 400}}) {
			vp := stunn.viewport(&ctx, stunn.Texture_ID(tex))
			_ = vp
			stunn.end_window(&ctx)
		}
		stunn.end_frame(&ctx)

		gl.ClearColor(0.05, 0.05, 0.06, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		stunn_gl.render(&rend, &ctx, fw, fh)
		glfw.SwapBuffers(window)
		free_all(context.temp_allocator)
	}
}
