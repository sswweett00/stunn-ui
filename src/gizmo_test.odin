package stunn

import "core:math"
import "core:mem"
import "core:testing"
import vmath "vmath:src"

@(private = "file")
setup :: proc() -> (view, proj: vmath.Mat4, rect: Rect) {
	view = vmath.mat4_look_at({0, 0, 10}, {}, vmath.VEC3_UP)
	proj = vmath.mat4_perspective(vmath.radians(60), 1, 0.1, 100)
	rect = {{0, 0}, {800, 800}}
	return
}

@(private = "file")
vpstate :: proc(rect: Rect, mouse: Vec2, pressed: bool) -> Viewport_State {
	return {rect = rect, size = rect_size(rect), hovered = true, mouse_pos = mouse - rect.min, pressed = {pressed, false, false}, down = {true, false, false}}
}

@(test)
test_translate_gizmo_drag :: proc(t: ^testing.T) {
	ctx := new(Context)
	defer free(ctx)
	init(ctx)
	defer destroy(ctx)
	view, proj, rect := setup()
	pos := [3]f32{0, 0, 0}
	tg := Gizmo_Target{origin = pos, axes = {0, 0, 0, 1}, position = &pos}

	begin_frame(ctx, {800, 800}, 0.016)
	ctx.input.mouse_down[0] = true
	r := gizmo(ctx, .Translate, vpstate(rect, {455, 400}, true), view, proj, tg)
	testing.expect(t, r.hot && r.dragging && ctx.gizmo.active == 1, "X ekseni yakalandı")
	end_frame(ctx)

	begin_frame(ctx, {800, 800}, 0.016)
	r = gizmo(ctx, .Translate, vpstate(rect, {535, 400}, false), view, proj, tg)
	testing.expect(t, r.changed, "sürükleme değişiklik üretti")
	testing.expect(t, abs(pos.x - 1.1547) < 0.01 && abs(pos.y) < 1e-3 && abs(pos.z) < 1e-3, "yalnızca X ekseninde ~1.155 hareket")
	end_frame(ctx)

	begin_frame(ctx, {800, 800}, 0.016)
	ctx.input.mouse_down[0] = false
	_ = gizmo(ctx, .Translate, vpstate(rect, {535, 400}, false), view, proj, tg)
	testing.expect(t, ctx.gizmo.active == 0, "bırakınca sürükleme biter")
}

@(test)
test_scale_and_rotate_gizmo :: proc(t: ^testing.T) {
	ctx := new(Context)
	defer free(ctx)
	init(ctx)
	defer destroy(ctx)
	view, proj, rect := setup()

	// Scale: eksen üzerinde başlangıç noktasının 2 katına sürükle -> çarpan ~2
	scale := [3]f32{1, 1, 1}
	tg := Gizmo_Target{origin = {}, axes = {0, 0, 0, 1}, scale = &scale}
	begin_frame(ctx, {800, 800}, 0.016)
	ctx.input.mouse_down[0] = true
	_ = gizmo(ctx, .Scale, vpstate(rect, {455, 400}, true), view, proj, tg)
	end_frame(ctx)
	begin_frame(ctx, {800, 800}, 0.016)
	// 455 px -> t0; 510 px hedef: dünya x = (110/400)*10/1.732 ≈ 1.5877 ; başlangıç 55 px -> 0.7939 => çarpan 2
	_ = gizmo(ctx, .Scale, vpstate(rect, {510, 400}, false), view, proj, tg)
	testing.expect(t, abs(scale.x - 2) < 0.05 && scale.y == 1 && scale.z == 1, "X ölçeği ~2")
	end_frame(ctx)
	gizmo_cancel(ctx)

	// Rotate: Y halkası; halka noktasından döndür, yönelim değişmeli ve birim kalmalı.
	// Editörün gerçek kamera açısına yakın eğimli bir görünüm kullanılır: halka düzlemi
	// kameraya paralel olmadığı için imleç halka üzerindeki noktayı birebir izler
	// (k=0 -> k=6, halkada 6/48 tur = 45° dönmelidir).
	rot := [4]f32{0, 0, 0, 1}
	tr := Gizmo_Target{origin = {}, axes = {0, 0, 0, 1}, rotation = &rot}
	rot_view := vmath.mat4_look_at({0, math.sin(f32(0.5)), math.cos(f32(0.5))} * 10, {}, vmath.VEC3_UP)
	// Y halkası (XZ düzlemi) ekranda yassı elips; ring_point(k=0) noktasını bul ve fare oraya koy
	vpm := proj * rot_view
	s := (vpm * vmath.Vec4{0, 0, 0, 1}).w * 0.16
	p0 := ring_point({}, {0, 1, 0}, s, 0)
	p1 := ring_point({}, {0, 1, 0}, s, 6)
	sp0, _ := to_screen(rect, vpm, p0)
	sp1, _ := to_screen(rect, vpm, p1)
	begin_frame(ctx, {800, 800}, 0.016)
	ctx.input.mouse_down[0] = true
	r := gizmo(ctx, .Rotate, vpstate(rect, sp0, true), rot_view, proj, tr)
	testing.expect(t, r.dragging && ctx.gizmo.active == 2, "Y halkası yakalandı")
	end_frame(ctx)
	begin_frame(ctx, {800, 800}, 0.016)
	r = gizmo(ctx, .Rotate, vpstate(rect, sp1, false), rot_view, proj, tr)
	l := rot[0] * rot[0] + rot[1] * rot[1] + rot[2] * rot[2] + rot[3] * rot[3]
	// 45° = halkada 6/48 tam tur -> quat bileşeni sin(22.5°) = 0.3827
	testing.expect(t, r.changed && abs(l - 1) < 1e-4 && abs(rot[1] - 0.38268) < 1e-3 && abs(rot[0]) < 1e-4 && abs(rot[2]) < 1e-4, "Y ekseni etrafında 45° dönüş")
	end_frame(ctx)
}

// Regresyon: kamera tam olarak halka düzlemi içindeyken (pitch = 0, Y halkası kenardan görünür)
// pick ışını halkanın düzlemine paraleldir. Önceden düzlem kesişimi "ışılabı" döndürüyor ve
// halka hiç yakalanamıyordu (active kalıcı olarak 0, dönüş imkânsız).
@(test)
test_rotate_gizmo_edge_on_ring :: proc(t: ^testing.T) {
	ctx := new(Context)
	defer free(ctx)
	init(ctx)
	defer destroy(ctx)
	view, proj, rect := setup()

	rot := [4]f32{0, 0, 0, 1}
	tr := Gizmo_Target{origin = {}, axes = {0, 0, 0, 1}, rotation = &rot}
	vpm := proj * view
	s := (vpm * vmath.Vec4{0, 0, 0, 1}).w * 0.16
	sp0, _ := to_screen(rect, vpm, ring_point({}, {0, 1, 0}, s, 0))
	sp1, _ := to_screen(rect, vpm, ring_point({}, {0, 1, 0}, s, 6))

	begin_frame(ctx, {800, 800}, 0.016)
	ctx.input.mouse_down[0] = true
	r := gizmo(ctx, .Rotate, vpstate(rect, sp0, true), view, proj, tr)
	testing.expect(t, r.dragging && ctx.gizmo.active == 2, "kenardan görünen Y halkası yakalanıyor")
	end_frame(ctx)
	begin_frame(ctx, {800, 800}, 0.016)
	r = gizmo(ctx, .Rotate, vpstate(rect, sp1, false), view, proj, tr)
	l := rot[0] * rot[0] + rot[1] * rot[1] + rot[2] * rot[2] + rot[3] * rot[3]
	testing.expect(t, r.changed && abs(l - 1) < 1e-4, "kenardan görünürken de dönüş birim kuaterniyon üretiyor")
	end_frame(ctx)
}

@(test)
test_gizmo_zero_allocation :: proc(t: ^testing.T) {
	ctx := new(Context)
	defer free(ctx)
	init(ctx)
	defer destroy(ctx)
	view, proj, rect := setup()
	pos := [3]f32{}
	tg := Gizmo_Target{axes = {0, 0, 0, 1}, position = &pos}
	context.allocator = mem.panic_allocator()
	context.temp_allocator = mem.panic_allocator()
	for _ in 0 ..< 200 {
		begin_frame(ctx, {800, 800}, 0.016)
		_ = gizmo(ctx, .Translate, vpstate(rect, {455, 400}, false), view, proj, tg)
		end_frame(ctx)
	}
	testing.expect(t, true, "gizmo kare başına tahsisat yapmaz")
}
