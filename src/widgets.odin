package stunn

import "core:math"

label :: proc "contextless" (ctx: ^Context, text: string) {
	h := text_height(ctx)
	r := layout_next(ctx, {text_width(ctx, text), h})
	draw_text(ctx, r.min, text, ctx.style.text)
}

separator :: proc "contextless" (ctx: ^Context) {
	r := layout_next(ctx, {0, 2})
	draw_rect(ctx, r, ctx.style.border)
}

// Tahsisatsız "%.Nf" biçimleyici (tprint yerine; freestanding uyumu).
// Dönen dilim statik tampondadır — kare içinde hemen kullanılmalıdır.
@(private)
fmt_scratch: [32]u8

@(private)
pow10_i :: proc "contextless" (n: int) -> int {
	p := 1
	for _ in 0 ..< n { p *= 10 }
	return p
}

fmt_float :: proc "contextless" (fmt_str: string, v: f32) -> string {
	dec := 2
	for i in 0 ..< len(fmt_str) {
		if fmt_str[i] == '.' && i + 1 < len(fmt_str) && fmt_str[i + 1] >= '0' && fmt_str[i + 1] <= '9' {
			dec = int(fmt_str[i + 1] - '0')
		}
	}
	if dec < 0 { dec = 0 }
	if dec > 6 { dec = 6 }
	neg := v < 0
	a := v
	if neg { a = -a }
	ip := int(a)
	mult := pow10_i(dec)
	fp := int((a - f32(ip)) * f32(mult) + 0.5)
	if fp >= mult { ip += 1; fp -= mult }
	// Tersten yaz, sonra çevir.
	tmp: [32]u8
	n := 0
	if dec > 0 {
		d := fp
		for _ in 0 ..< dec {
			tmp[n] = u8('0' + d % 10)
			d /= 10
			n += 1
		}
		tmp[n] = '.'
		n += 1
	}
	q := ip
	if q == 0 {
		tmp[n] = '0'
		n += 1
	} else {
		for q > 0 {
			tmp[n] = u8('0' + q % 10)
			q /= 10
			n += 1
		}
	}
	if neg {
		tmp[n] = '-'
		n += 1
	}
	for i in 0 ..< n {
		fmt_scratch[i] = tmp[n - 1 - i]
	}
	return string(fmt_scratch[:n])
}

@(private)
widget_h :: proc "contextless" (ctx: ^Context) -> f32 { return text_height(ctx) + 8 }

button :: proc "contextless" (ctx: ^Context, text: string, width: f32 = 0) -> bool {
	id := get_id(ctx, text)
	r := layout_next(ctx, {width, widget_h(ctx)})
	hovered, held, pressed := item_behavior(ctx, id, r)
	s := &ctx.style
	draw_rect(ctx, r, s.widget_active if held else (s.widget_hot if hovered else s.widget_bg))
	t := label_text(text)
	draw_text(ctx, {r.min.x + (rect_size(r).x - text_width(ctx, t)) * 0.5, r.min.y + 4}, t, s.text)
	return pressed
}

// Seçilebilir satır (hiyerarşi listeleri vb.).
selectable :: proc "contextless" (ctx: ^Context, text: string, selected: bool) -> bool {
	id := get_id(ctx, text)
	r := layout_next(ctx, {0, text_height(ctx) + 4})
	hovered, held, pressed := item_behavior(ctx, id, r)
	s := &ctx.style
	if selected { draw_rect(ctx, r, s.widget_active) } else if hovered || held { draw_rect(ctx, r, s.widget_hot) }
	draw_text(ctx, {r.min.x + 4, r.min.y + 2}, label_text(text), s.text)
	return pressed
}

checkbox :: proc "contextless" (ctx: ^Context, text: string, value: ^bool) -> bool {
	id := get_id(ctx, text)
	box := text_height(ctx)
	t := label_text(text)
	r := layout_next(ctx, {box + 6 + text_width(ctx, t), widget_h(ctx)})
	hovered, _, pressed := item_behavior(ctx, id, r)
	if pressed { value^ = !value^ }
	s := &ctx.style
	b := Rect{{r.min.x, r.min.y + 4}, {r.min.x + box, r.min.y + 4 + box}}
	draw_rect(ctx, b, s.widget_hot if hovered else s.widget_bg)
	if value^ { draw_rect(ctx, rect_shrink(b, 3), s.accent) }
	draw_text(ctx, {b.max.x + 6, r.min.y + 4}, t, s.text)
	return pressed
}

// Tek bir sürükle-değiştir alanı (ortak çekirdek). log_scale: üstel hız (pozitif değerler için).
@(private)
drag_float_field :: proc "contextless" (ctx: ^Context, id: ID, r: Rect, v: ^f32, speed, vmin, vmax: f32, log_scale: bool, fmt_str: string) -> bool {
	hovered, held, _ := item_behavior(ctx, id, r)
	changed := false
	if held && ctx.input.mouse_delta.x != 0 {
		mult: f32 = 1
		if ctx.input.shift { mult = 0.1 } else if ctx.input.ctrl { mult = 10 }
		dx := ctx.input.mouse_delta.x * speed * mult
		if log_scale {
			base := max(abs(v^), 1e-4)
			v^ = math.sign(v^ if v^ != 0 else 1) * base * math.exp(dx)
		} else {
			v^ += dx
		}
		if vmax > vmin { v^ = clamp(v^, vmin, vmax) }
		changed = true
	}
	s := &ctx.style
	draw_rect(ctx, r, s.widget_active if held else (s.widget_hot if hovered else s.widget_bg))
	txt := fmt_float(fmt_str, v^)
	draw_text(ctx, {r.min.x + (rect_size(r).x - text_width(ctx, txt)) * 0.5, r.min.y + 4}, txt, s.text)
	return changed
}

drag_float :: proc "contextless" (ctx: ^Context, text: string, v: ^f32, speed: f32 = 0.01, vmin: f32 = 0, vmax: f32 = 0, log_scale := false, fmt_str := "%.3f") -> bool {
	id := get_id(ctx, text)
	r := layout_next(ctx, {0, widget_h(ctx)})
	lw := rect_size(r).x * 0.38
	t := label_text(text)
	draw_text(ctx, {r.min.x, r.min.y + 4}, t, ctx.style.text)
	return drag_float_field(ctx, id, {{r.min.x + lw, r.min.y}, r.max}, v, speed, vmin, vmax, log_scale, fmt_str)
}

// ^[3]f32 üzerinde çalışır (Transform, renk, vb.); motor tiplerini bilmez.
drag_float3 :: proc "contextless" (ctx: ^Context, text: string, v: ^[3]f32, speed: f32 = 0.01, vmin: f32 = 0, vmax: f32 = 0) -> bool {
	id := get_id(ctx, text)
	r := layout_next(ctx, {0, widget_h(ctx)})
	lw := rect_size(r).x * 0.30
	t := label_text(text)
	draw_text(ctx, {r.min.x, r.min.y + 4}, t, ctx.style.text)
	fw := (rect_size(r).x - lw) / 3
	changed := false
	axis_col := [3]Color{{0.9, 0.3, 0.3, 1}, {0.4, 0.85, 0.4, 1}, {0.4, 0.55, 1, 1}}
	abuf_push(&ctx.id_stack, id)
	for i in 0 ..< 3 {
		fr := Rect{{r.min.x + lw + fw * f32(i), r.min.y}, {r.min.x + lw + fw * f32(i + 1) - 2, r.max.y}}
		fid := ID(u32(id) * 16777619 ~ u32(i + 1))
		if drag_float_field(ctx, fid, fr, &v[i], speed, vmin, vmax, false, "%.2f") { changed = true }
		draw_rect(ctx, {fr.min, {fr.min.x + 2, fr.max.y}}, axis_col[i])
	}
	pop_id(ctx)
	return changed
}

slider_float :: proc "contextless" (ctx: ^Context, text: string, v: ^f32, vmin, vmax: f32) -> bool {
	id := get_id(ctx, text)
	r := layout_next(ctx, {0, widget_h(ctx)})
	lw := rect_size(r).x * 0.38
	t := label_text(text)
	draw_text(ctx, {r.min.x, r.min.y + 4}, t, ctx.style.text)
	fr := Rect{{r.min.x + lw, r.min.y}, r.max}
	hovered, held, _ := item_behavior(ctx, id, fr)
	changed := false
	w := max(rect_size(fr).x, 1)
	if held {
		nv := vmin + saturate01((ctx.input.mouse_pos.x - fr.min.x) / w) * (vmax - vmin)
		if nv != v^ { v^ = nv; changed = true }
	}
	s := &ctx.style
	draw_rect(ctx, fr, s.widget_hot if hovered else s.widget_bg)
	frac := saturate01((v^ - vmin) / (vmax - vmin))
	draw_rect(ctx, {fr.min, {fr.min.x + w * frac, fr.max.y}}, s.accent if held else s.widget_active)
	txt := fmt_float("%.2f", v^)
	draw_text(ctx, {fr.min.x + (w - text_width(ctx, txt)) * 0.5, fr.min.y + 4}, txt, s.text)
	return changed
}

@(private)
saturate01 :: #force_inline proc "contextless" (x: f32) -> f32 { return clamp(x, 0, 1) }

// 3B viewport widget'ı: host'un ürettiği dokuyu (saf ID) gösterir. Fare/etkileşim bilgisini döner.
Viewport_State :: struct {
	rect:      Rect,
	size:      Vec2,  // piksel cinsinden gerçek boyut (host render hedefini buna göre boyutlandırır)
	hovered:   bool,
	mouse_pos: Vec2,  // viewport sol-üstüne göre
	pressed:   [3]bool,
	down:      [3]bool,
	scroll:    Vec2,
}

// size {0,0}: panelde kalan alanın tamamı. Doku GL konvansiyonunda (alt-sol orijin) olduğundan v ters çevrilir.
viewport :: proc "contextless" (ctx: ^Context, tex: Texture_ID, size := Vec2{0, 0}) -> Viewport_State {
	r := layout_next(ctx, size)
	vs := Viewport_State{rect = r, size = rect_size(r)}
	visible := rect_intersect(r, draw_clip_current(&ctx.draw))
	vs.hovered = rect_contains(visible, ctx.input.mouse_pos) && ctx.active == 0
	vs.mouse_pos = ctx.input.mouse_pos - r.min
	if vs.hovered {
		for i in 0 ..< 3 { vs.pressed[i] = mouse_pressed(ctx, i) }
		vs.scroll = ctx.input.scroll
	}
	for i in 0 ..< 3 { vs.down[i] = ctx.input.mouse_down[i] }
	draw_image(ctx, r, tex, {0, 1}, {1, 0})
	return vs
}
