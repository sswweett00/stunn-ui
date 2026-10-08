// stunn için safeguardsiz yazılım rasterizer backend (OpenGL gerektirmez).
// Draw_Command_Buffer komutlarını ham 32-bit framebuffer'a işler:
// barycentric enterpolasyon (renk + uv), atlas kapsama maskesi, source-over.
// Ana bilgisayar Framebuffer struct'ını doldurur (piksel biçimi maskeleriyle).
package stunn_sw

import stunn "../src"

// 32-bit lineer hedef: piksel düzeni ana bilgisayarın maskelerinden gelir.
Framebuffer :: struct {
	pixels:  [^]u32,
	width:   int,
	height:  int,
	stride:  int, // satır başına piksel
	mask_r:  u32,
	mask_g:  u32,
	mask_b:  u32,
	shift_r: u32,
	shift_g: u32,
	shift_b: u32,
}

Color :: [4]u8 // R, G, B, A

mask_shift :: proc "contextless" (m: u32) -> u32 {
	m := m
	if m == 0 { return 0 }
	s: u32 = 0
	for m & 1 == 0 {
		m >>= 1
		s += 1
	}
	return s
}

pixel_at :: proc "contextless" (fb: ^Framebuffer, x, y: int) -> ^u32 {
	return &fb.pixels[uintptr(y * fb.stride + x)]
}

// Source-over alpha birleştirme (bayt düzeni maskelerden okunur).
blend_pixel :: proc "contextless" (fb: ^Framebuffer, x, y: int, c: Color) {
	if x < 0 || y < 0 || x >= fb.width || y >= fb.height { return }
	a := f32(c[3]) / 255.0
	if a <= 0.0 { return }
	px := pixel_at(fb, x, y)
	cur := px^
	cr := u8((cur >> fb.shift_r) & (fb.mask_r >> fb.shift_r))
	cg := u8((cur >> fb.shift_g) & (fb.mask_g >> fb.shift_g))
	cb := u8((cur >> fb.shift_b) & (fb.mask_b >> fb.shift_b))
	nr := u8(f32(cr) + (f32(c[0]) - f32(cr)) * a)
	ng := u8(f32(cg) + (f32(c[1]) - f32(cg)) * a)
	nb := u8(f32(cb) + (f32(c[2]) - f32(cb)) * a)
	px^ = (u32(nr) << fb.shift_r & fb.mask_r) | (u32(ng) << fb.shift_g & fb.mask_g) | (u32(nb) << fb.shift_b & fb.mask_b)
}

// Atlas örneği: en yakın texel (R8 kapsama maskesi 0/255).
@(private)
atlas_sample :: proc "contextless" (atlas: ^[stunn.ATLAS_W * stunn.ATLAS_H]u8, u, v: f32) -> f32 {
	ax := int(u * stunn.ATLAS_W)
	ay := int(v * stunn.ATLAS_H)
	if ax < 0 { ax = 0 } else if ax >= stunn.ATLAS_W { ax = stunn.ATLAS_W - 1 }
	if ay < 0 { ay = 0 } else if ay >= stunn.ATLAS_H { ay = stunn.ATLAS_H - 1 }
	return f32(atlas[ay * stunn.ATLAS_W + ax]) / 255.0
}

@(private)
f32_to_u8 :: proc "contextless" (v: f32) -> u8 {
	if v <= 0.0 { return 0 }
	if v >= 1.0 { return 255 }
	return u8(v * 255.0)
}

// Kenar fonksiyonu: (b-a) x (p-a) (z-bileşeni).
@(private)
edge :: proc "contextless" (a, b, p: stunn.Vec2) -> f32 {
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
}

// Tek üçgeni kırpılmış kutuya rasterler.
@(private)
raster_tri :: proc "contextless" (
	fb: ^Framebuffer,
	atlas: ^[stunn.ATLAS_W * stunn.ATLAS_H]u8,
	v0, v1, v2: stunn.Draw_Vertex,
	cx0, cy0, cx1, cy1: int,
) {
	area := edge(v0.pos.xy, v1.pos.xy, v2.pos.xy)
	if area == 0.0 { return }
	inv := 1.0 / area

	x0 := int(v0.pos.x)
	if v1.pos.x < f32(x0) { x0 = int(v1.pos.x) }
	if v2.pos.x < f32(x0) { x0 = int(v2.pos.x) }
	y0 := int(v0.pos.y)
	if v1.pos.y < f32(y0) { y0 = int(v1.pos.y) }
	if v2.pos.y < f32(y0) { y0 = int(v2.pos.y) }
	x1 := int(v0.pos.x) + 1
	if int(v1.pos.x) + 1 > x1 { x1 = int(v1.pos.x) + 1 }
	if int(v2.pos.x) + 1 > x1 { x1 = int(v2.pos.x) + 1 }
	y1 := int(v0.pos.y) + 1
	if int(v1.pos.y) + 1 > y1 { y1 = int(v1.pos.y) + 1 }
	if int(v2.pos.y) + 1 > y1 { y1 = int(v2.pos.y) + 1 }

	if x0 < cx0 { x0 = cx0 }
	if y0 < cy0 { y0 = cy0 }
	if x1 > cx1 { x1 = cx1 }
	if y1 > cy1 { y1 = cy1 }
	if x0 >= x1 || y0 >= y1 { return }

	p0 := v0.pos.xy
	p1 := v1.pos.xy
	p2 := v2.pos.xy
	for py := y0; py < y1; py += 1 {
		for px := x0; px < x1; px += 1 {
			p := stunn.Vec2{f32(px) + 0.5, f32(py) + 0.5}
			w0 := edge(p1, p2, p) * inv
			w1 := edge(p2, p0, p) * inv
			w2 := edge(p0, p1, p) * inv
			// Her iki sarım yönünü de kabul et.
			if area > 0.0 {
				if w0 < 0.0 || w1 < 0.0 || w2 < 0.0 { continue }
			} else {
				if w0 > 0.0 || w1 > 0.0 || w2 > 0.0 { continue }
			}
			col := w0 * v0.col + w1 * v1.col + w2 * v2.col
			if col.w <= 0.0 { continue }
			uv := w0 * v0.uv + w1 * v1.uv + w2 * v2.uv
			mask := atlas_sample(atlas, uv.x, uv.y)
			a := col.w * mask
			if a <= 0.0 { continue }
			src := Color{f32_to_u8(col.x), f32_to_u8(col.y), f32_to_u8(col.z), f32_to_u8(a)}
			blend_pixel(fb, px, py, src)
		}
	}
}

// Komut tamponunun tamamını hedefe işler.
render :: proc "contextless" (
	fb: ^Framebuffer,
	b: ^stunn.Draw_Command_Buffer,
	atlas: ^[stunn.ATLAS_W * stunn.ATLAS_H]u8,
) {
	if fb.pixels == nil || fb.width <= 0 || fb.height <= 0 { return }
	nv := b.vertices.count
	for ci in 0 ..< b.cmds.count {
		cmd := &b.cmds.data[ci]
		cx0 := clamp(int(cmd.clip.min.x), 0, fb.width)
		cy0 := clamp(int(cmd.clip.min.y), 0, fb.height)
		cx1 := clamp(int(cmd.clip.max.x), 0, fb.width)
		cy1 := clamp(int(cmd.clip.max.y), 0, fb.height)
		if cx0 >= cx1 || cy0 >= cy1 { continue }
		n := int(cmd.idx_count)
		base := int(cmd.idx_offset)
		for t := 0; t + 2 < n; t += 3 {
			i0 := int(b.indices.data[base + t + 0])
			i1 := int(b.indices.data[base + t + 1])
			i2 := int(b.indices.data[base + t + 2])
			if i0 < 0 || i1 < 0 || i2 < 0 { continue }
			if i0 >= nv || i1 >= nv || i2 >= nv { continue }
			raster_tri(fb, atlas, b.vertices.data[i0], b.vertices.data[i1], b.vertices.data[i2], cx0, cy0, cx1, cy1)
		}
	}
}
