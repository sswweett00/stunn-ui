// 3B viewport manipülatörleri (Translate / Rotate / Scale). Motor tiplerini bilmez:
// yalnızca ham işaretçiler ([3]f32 konum/ölçek, [4]f32 kuaterniyon x,y,z,w) ve matrisler alır.
// Fare seçimi ekran uzayı mesafesiyle, sürükleme matematiği vmath ışınlarıyla yapılır.
package gizmo

import "core:math"
import vmath "vmath:src"
import stunn "../src"

Gizmo_Mode :: enum { Translate, Rotate, Scale }

// origin: gizmo'nun çizildiği dünya konumu. axes: eksen takımının yönelimi (Translate/Rotate için
// birim kuaterniyon = dünya, Scale için nesne yönelimi). İşaretçiler kullanılmayan modda nil olabilir.
Gizmo_Target :: struct {
	origin:   [3]f32,
	axes:     [4]f32,
	position: ^[3]f32, // Translate: dünya konumu
	rotation: ^[4]f32, // Rotate: dünya yönelimi (x, y, z, w)
	scale:    ^[3]f32, // Scale
}

// hot / active: 0 = yok, 1..3 = X, Y, Z.
Gizmo_State :: struct {
	hot, active:  int,
	start_origin: vmath.Vec3,
	start_pos:    vmath.Vec3,
	start_scale:  vmath.Vec3,
	start_rot:    vmath.Quat,
	start_t:      f32,
	start_angle:  f32,
}

Gizmo_Result :: struct {
	changed:  bool,
	hot:      bool, // fare bir tutamağın üstünde: host seçimi (picking) yapmamalı
	dragging: bool,
}

GIZMO_PICK_PX :: 10
GIZMO_RING_SEGS :: 48

gizmo_cancel :: proc(st: ^Gizmo_State) { st^ = {} }

@(private = "package")
to_screen :: proc(r: stunn.Rect, vp: vmath.Mat4, p: vmath.Vec3) -> (s: stunn.Vec2, ok: bool) {
	c := vp * vmath.Vec4{p.x, p.y, p.z, 1}
	if c.w < 1e-3 { return {}, false }
	nx, ny := c.x / c.w, c.y / c.w
	sz := stunn.rect_size(r)
	return {r.min.x + (nx * 0.5 + 0.5) * sz.x, r.min.y + (1 - (ny * 0.5 + 0.5)) * sz.y}, true
}

@(private = "file")
dist_point_segment :: proc(p, a, b: stunn.Vec2) -> f32 {
	ab := b - a
	t := clamp(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / max(ab.x * ab.x + ab.y * ab.y, 1e-6), 0, 1)
	q := a + ab * t
	d := p - q
	return math.sqrt(d.x * d.x + d.y * d.y)
}

@(private = "package")
ring_point :: proc(origin, a: vmath.Vec3, s: f32, i: int) -> vmath.Vec3 {
	u, _ := vmath.orthonormal_basis(a)
	v := vmath.cross(a, u)
	th := f32(i) / GIZMO_RING_SEGS * math.TAU
	return origin + (u * math.cos(th) + v * math.sin(th)) * s
}

@(private = "file")
ring_angle :: proc(origin, a, hit: vmath.Vec3) -> f32 {
	u, _ := vmath.orthonormal_basis(a)
	v := vmath.cross(a, u)
	w := hit - origin
	return math.atan2(vmath.dot(w, v), vmath.dot(w, u))
}

// Halka üzerindeki sürükleme açısı.
//
// Normal durumda pick ışını halkanın DÜZLEMİyle kesiştirilir: imlecin halka üzerindeki
// noktası birebir izlenir. Ancak halka düzlemine kenarından bakıldığında (kamera tam olarak
// halka düzlemi içinde, ör. Y halkası + pitch = 0) ışın düzleme paraleldir; düzlem kesişimi
// yoktur ve ray_plane "ışılabı" döndürür — halka hiç yakalanamaz. Bu durumda ışının halka
// EKSENİNE en yakın noktası kullanılır; yön hâlâ tanımlı olduğu için açı elde edilir.
// Yalnızca ışın eksene paralelse (kamera halkanın üstünden bakıyor) açı belirsizdir.
@(private = "file")
ring_drag_angle :: proc(origin, a: vmath.Vec3, r: vmath.Ray) -> (angle: f32, ok: bool) {
	if hit, t := vmath.ray_plane(r, vmath.plane_from_point_normal(origin, a)); hit {
		return ring_angle(origin, a, vmath.ray_at(r, t)), true
	}
	hit_ok, t_ray, _ := vmath.ray_line_closest(r, origin, a)
	if !hit_ok {
		return 0, false
	}
	return ring_angle(origin, a, vmath.ray_at(r, t_ray)), true
}

// st: çağıranın sahip olduğu kalıcı durum (eskiden Context içindeydi;
// bare-metal uyumu için dışarı taşındı).
gizmo :: proc(ctx: ^stunn.Context, st: ^Gizmo_State, mode: Gizmo_Mode, vp: stunn.Viewport_State, view, proj: vmath.Mat4, tg: Gizmo_Target) -> Gizmo_Result {
	res: Gizmo_Result
	if vp.size.x < 2 || vp.size.y < 2 { return res }

	view_proj := proj * view
	aq := vmath.quat_normalize(vmath.Quat{tg.axes[0], tg.axes[1], tg.axes[2], tg.axes[3]})
	basis := [3]vmath.Vec3{
		vmath.quat_rotate(aq, vmath.VEC3_RIGHT), vmath.quat_rotate(aq, vmath.VEC3_UP), vmath.quat_rotate(aq, {0, 0, 1}),
	}
	origin := vmath.Vec3(tg.origin)
	if st.active != 0 { origin = st.start_origin }

	clip := view_proj * vmath.Vec4{origin.x, origin.y, origin.z, 1}
	if clip.w < 0.05 { return res }
	s := clip.w * 0.16 // sabit ekran boyutu için derinlikle ölçeklenen dünya uzunluğu

	mouse := vp.rect.min + vp.mouse_pos
	inv, inv_ok := vmath.mat4_inverse(view_proj)
	if !inv_ok { return res }
	ray := vmath.ray_from_screen(inv, vp.mouse_pos.x, vp.mouse_pos.y, vp.size.x, vp.size.y)

	// ---- hover (sürükleme yokken)
	if st.active == 0 {
		st.hot = 0
		if vp.hovered {
			best: f32 = GIZMO_PICK_PX
			for i in 0 ..< 3 {
				d: f32 = max(f32)
				if mode == .Rotate {
					for k in 0 ..< GIZMO_RING_SEGS {
						p0, ok0 := to_screen(vp.rect, view_proj, ring_point(origin, basis[i], s, k))
						p1, ok1 := to_screen(vp.rect, view_proj, ring_point(origin, basis[i], s, k + 1))
						if ok0 && ok1 { d = min(d, dist_point_segment(mouse, p0, p1)) }
					}
				} else {
					p0, ok0 := to_screen(vp.rect, view_proj, origin)
					p1, ok1 := to_screen(vp.rect, view_proj, origin + basis[i] * s)
					if ok0 && ok1 { d = dist_point_segment(mouse, p0, p1) }
				}
				if d < best { best = d; st.hot = i + 1 }
			}
		}
	}

	// ---- sürükleme başlangıcı
	if st.active == 0 && st.hot != 0 && vp.pressed[0] {
		a := basis[st.hot - 1]
		started := true
		st.start_origin = origin
		if tg.position != nil { st.start_pos = vmath.Vec3(tg.position^) }
		if tg.scale != nil { st.start_scale = vmath.Vec3(tg.scale^) }
		if tg.rotation != nil { st.start_rot = vmath.quat_normalize(vmath.Quat{tg.rotation[0], tg.rotation[1], tg.rotation[2], tg.rotation[3]}) }
		switch mode {
		case .Translate, .Scale:
			ok, _, tl := vmath.ray_line_closest(ray, origin, a)
			if ok { st.start_t = tl } else { started = false }
		case .Rotate:
			if ang, ok := ring_drag_angle(origin, a, ray); ok { st.start_angle = ang } else { started = false }
		}
		if started { st.active = st.hot }
	}

	// ---- sürükleme
	if st.active != 0 {
		if !ctx.input.mouse_down[0] {
			st.active = 0
		} else {
			idx := st.active - 1
			a := basis[idx]
			switch mode {
			case .Translate:
				if ok, _, tl := vmath.ray_line_closest(ray, st.start_origin, a); ok && tg.position != nil {
					tg.position^ = st.start_pos + a * (tl - st.start_t)
					res.changed = true
				}
			case .Scale:
				if ok, _, tl := vmath.ray_line_closest(ray, st.start_origin, a); ok && tg.scale != nil && abs(st.start_t) > 1e-3 {
					f := clamp(tl / st.start_t, 0.01, 100)
					ns := st.start_scale
					ns[idx] = st.start_scale[idx] * f
					tg.scale^ = ns
					res.changed = true
				}
			case .Rotate:
				if cur, ok := ring_drag_angle(st.start_origin, a, ray); ok && tg.rotation != nil {
					ang := cur - st.start_angle
					q := vmath.quat_mul(vmath.quat_axis_angle(a, ang), st.start_rot)
					tg.rotation^ = {q.x, q.y, q.z, q.w}
					res.changed = true
				}
			}
		}
	}
	res.hot = st.hot != 0 || st.active != 0
	res.dragging = st.active != 0

	// ---- çizim
	stunn.draw_push_clip(&ctx.draw, vp.rect)
	base_cols := [3]stunn.Color{{0.92, 0.25, 0.25, 1}, {0.35, 0.85, 0.3, 1}, {0.3, 0.5, 1, 1}}
	hl := stunn.Color{1, 0.9, 0.2, 1}
	for i in 0 ..< 3 {
		col := hl if (st.hot == i + 1 && st.active == 0) || st.active == i + 1 else base_cols[i]
		if mode == .Rotate {
			for k in 0 ..< GIZMO_RING_SEGS {
				p0, ok0 := to_screen(vp.rect, view_proj, ring_point(origin, basis[i], s, k))
				p1, ok1 := to_screen(vp.rect, view_proj, ring_point(origin, basis[i], s, k + 1))
				if ok0 && ok1 { stunn.draw_line(ctx, p0, p1, 3, col) }
			}
		} else {
			p0, ok0 := to_screen(vp.rect, view_proj, origin)
			p1, ok1 := to_screen(vp.rect, view_proj, origin + basis[i] * s)
			if ok0 && ok1 {
				stunn.draw_line(ctx, p0, p1, 3, col)
				h: f32 = 5 if mode == .Translate else 6
				stunn.draw_rect(ctx, {p1 - {h, h}, p1 + {h, h}}, col)
			}
		}
	}
	if c, ok := to_screen(vp.rect, view_proj, origin); ok {
		stunn.draw_rect(ctx, {c - {3, 3}, c + {3, 3}}, {1, 1, 1, 1})
	}
	stunn.draw_pop_clip(&ctx.draw)
	return res
}
