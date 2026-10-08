package stunn

// NOT (freestanding uyarlaması): orijinal `core:fmt` + `core:math` yerine
// yalnızca `core:math` (sqrt) kullanılır. `tprint`/`labelf` çıkarıldı —
// sayılar köprüdeki arena-tahsisatsız biçimleyicilerle yazılır. `gizmo`
// alanı yoktur (3B editör parçası gömülmedi).

import "core:math"

// ---------------------------------------------------------------- Girdi
Input :: struct {
	mouse_pos:       Vec2,
	mouse_delta:     Vec2,
	scroll:          Vec2,
	mouse_down:      [3]bool, // 0 sol, 1 sağ, 2 orta
	mouse_down_prev: [3]bool,
	shift, ctrl:     bool,
	mouse_pos_last:  Vec2,
}

input_mouse_pos    :: proc "contextless" (ctx: ^Context, p: Vec2)            { ctx.input.mouse_pos = p }
input_mouse_button :: proc "contextless" (ctx: ^Context, b: int, down: bool) { if b >= 0 && b < 3 { ctx.input.mouse_down[b] = down } }
input_scroll       :: proc "contextless" (ctx: ^Context, s: Vec2)            { ctx.input.scroll = s }
input_modifiers    :: proc "contextless" (ctx: ^Context, shift, ctrl: bool)  { ctx.input.shift = shift; ctx.input.ctrl = ctrl }

mouse_down     :: #force_inline proc "contextless" (ctx: ^Context, b: int) -> bool { return ctx.input.mouse_down[b] }
mouse_pressed  :: #force_inline proc "contextless" (ctx: ^Context, b: int) -> bool { return ctx.input.mouse_down[b] && !ctx.input.mouse_down_prev[b] }
mouse_released :: #force_inline proc "contextless" (ctx: ^Context, b: int) -> bool { return !ctx.input.mouse_down[b] && ctx.input.mouse_down_prev[b] }

// ---------------------------------------------------------------- Storage (ID tabanlı kalıcı önbellek)
// Sabit boyutlu açık adresli hash tablosu: pencere konumu/boyutu vb. kalıcı durum. Tahsisat yok.
STORAGE_CAP :: 2048

Storage_Entry :: struct {
	key:   ID,
	value: [4]f32,
}

Storage :: struct {
	entries: [STORAGE_CAP]Storage_Entry,
	count:   int,
}

storage_find :: proc "contextless" (s: ^Storage, key: ID) -> ^Storage_Entry {
	i := int(u32(key)) & (STORAGE_CAP - 1)
	for _ in 0 ..< STORAGE_CAP {
		e := &s.entries[i]
		if e.key == key || e.key == 0 { return e }
		i = (i + 1) & (STORAGE_CAP - 1)
	}
	return nil
}

storage_get :: proc "contextless" (s: ^Storage, key: ID, default: [4]f32) -> [4]f32 {
	if e := storage_find(s, key); e != nil && e.key == key { return e.value }
	return default
}

storage_set :: proc "contextless" (s: ^Storage, key: ID, v: [4]f32) {
	e := storage_find(s, key)
	if e == nil { return }
	if e.key == 0 { e.key = key; s.count += 1 }
	e.value = v
}

// ---------------------------------------------------------------- Stil
Theme :: enum {
	Dark,
	Light,
}

Style :: struct {
	font_scale:    f32,
	padding:       f32,
	spacing:       f32,
	title_h_extra: f32,
	window_bg:     Color,
	title_bg:      Color,
	title_text:    Color,
	text:          Color,
	widget_bg:     Color,
	widget_hot:    Color,
	widget_active: Color,
	accent:        Color,
	border:        Color,
}

style_dark :: proc "contextless" () -> Style {
	return {
		font_scale = 2, padding = 6, spacing = 4, title_h_extra = 6,
		window_bg     = {0.11, 0.115, 0.13, 0.97},
		title_bg      = {0.17, 0.18, 0.22, 1},
		title_text    = {0.92, 0.94, 1, 1},
		text          = {0.86, 0.88, 0.92, 1},
		widget_bg     = {0.20, 0.21, 0.25, 1},
		widget_hot    = {0.27, 0.29, 0.35, 1},
		widget_active = {0.33, 0.45, 0.75, 1},
		accent        = {0.36, 0.55, 0.95, 1},
		border        = {0.05, 0.05, 0.06, 1},
	}
}

style_light :: proc "contextless" () -> Style {
	return {
		font_scale = 2, padding = 6, spacing = 4, title_h_extra = 6,
		window_bg     = {0.94, 0.94, 0.96, 0.98},
		title_bg      = {0.86, 0.87, 0.90, 1},
		title_text    = {0.12, 0.13, 0.16, 1},
		text          = {0.18, 0.19, 0.22, 1},
		widget_bg     = {0.88, 0.89, 0.92, 1},
		widget_hot    = {0.78, 0.82, 0.92, 1},
		widget_active = {0.45, 0.58, 0.88, 1},
		accent        = {0.28, 0.48, 0.90, 1},
		border        = {0.70, 0.71, 0.74, 1},
	}
}

style_for_theme :: proc "contextless" (t: Theme) -> Style {
	switch t {
	case .Light: return style_light()
	case .Dark:  return style_dark()
	}
	return style_dark()
}

style_default :: proc "contextless" () -> Style { return style_dark() }

set_theme :: proc "contextless" (ctx: ^Context, t: Theme) {
	ctx.style = style_for_theme(t)
}

// ---------------------------------------------------------------- Bağlam
Panel :: struct {
	id:            ID,
	rect:          Rect,
	content_min:   Vec2,
	content_max_x: f32,
	cursor:        Vec2,
	line_start_y:  f32,
	line_h:        f32,
	continuing:    bool,
	last_rect:     Rect,
}

MAX_PANELS :: 16

Context :: struct {
	input:   Input,
	style:   Style,
	draw:    Draw_Command_Buffer,
	storage: Storage,
	atlas:   [ATLAS_W * ATLAS_H]u8,

	id_stack: ABuf(ID),
	hot, active: ID,
	display: Vec2,
	dt:      f32,
	frame:   u64,

	panels:      [MAX_PANELS]Panel,
	panel_count: int,

	// Host için: UI fareyi tüketiyor mu? (pencere üstünde veya bir widget aktif)
	want_capture_mouse: bool,
}

init :: proc "contextless" (ctx: ^Context) {
	ctx.style = style_default()
	draw_init(&ctx.draw, 1 << 16, 1 << 17, 512)
	abuf_init(&ctx.id_stack, 64)
	font_build_atlas(&ctx.atlas)
}

begin_frame :: proc "contextless" (ctx: ^Context, display: Vec2, dt: f32) {
	ctx.display = display
	ctx.dt = dt
	ctx.frame += 1
	ctx.input.mouse_delta = ctx.input.mouse_pos - ctx.input.mouse_pos_last
	abuf_clear(&ctx.id_stack)
	ctx.panel_count = 0
	ctx.hot = 0
	ctx.want_capture_mouse = ctx.active != 0
	draw_reset(&ctx.draw, Rect{{0, 0}, display})
	// Sol tık bırakıldıysa ve hâlâ active varsa temizle (item_behavior kaçırsa güvenlik ağı)
	if !ctx.input.mouse_down[0] && ctx.active != 0 {
		ctx.active = 0
	}
}

end_frame :: proc "contextless" (ctx: ^Context) {
	ctx.input.mouse_down_prev = ctx.input.mouse_down
	ctx.input.mouse_pos_last = ctx.input.mouse_pos
	ctx.input.scroll = {}
}

// ---------------------------------------------------------------- ID stack
current_id :: proc "contextless" (ctx: ^Context) -> ID {
	if ctx.id_stack.count > 0 { return ctx.id_stack.data[ctx.id_stack.count - 1] }
	return 0
}
get_id :: proc "contextless" (ctx: ^Context, s: string) -> ID { return hash_string(s, current_id(ctx)) }
push_id :: proc "contextless" (ctx: ^Context, s: string) { abuf_push(&ctx.id_stack, get_id(ctx, s)) }
push_id_int :: proc "contextless" (ctx: ^Context, n: int) {
	abuf_push(&ctx.id_stack, ID(u32(current_id(ctx)) * 16777619 ~ u32(n) + 0x9E3779B9))
}
pop_id :: proc "contextless" (ctx: ^Context) { abuf_pop(&ctx.id_stack) }

// ---------------------------------------------------------------- Çizim yardımcıları
text_height :: proc "contextless" (ctx: ^Context) -> f32 { return 8 * ctx.style.font_scale }

// text_width: draw_text ile aynı hücre ilerlemesini kullanır (karakter, bayt değil) —
// aksi halde çok baytlı metinler yanlış hizalanır/ortalanmaz.
text_width :: proc "contextless" (ctx: ^Context, s: string) -> f32 {
	n := 0
	for _ in s { n += 1 }
	return f32(n) * 6 * ctx.style.font_scale
}

draw_rect :: proc "contextless" (ctx: ^Context, r: Rect, col: Color) {
	cx := f32((SOLID_CELL % ATLAS_COLS) * ATLAS_CELL + ATLAS_CELL / 2) / ATLAS_W
	cy := f32((SOLID_CELL / ATLAS_COLS) * ATLAS_CELL + ATLAS_CELL / 2) / ATLAS_H
	draw_quad_uv(&ctx.draw, r, {cx, cy}, {cx, cy}, col, 0)
}

solid_uv :: proc "contextless" () -> Vec2 {
	return {
		f32((SOLID_CELL % ATLAS_COLS) * ATLAS_CELL + ATLAS_CELL / 2) / ATLAS_W,
		f32((SOLID_CELL / ATLAS_COLS) * ATLAS_CELL + ATLAS_CELL / 2) / ATLAS_H,
	}
}

draw_line :: proc "contextless" (ctx: ^Context, a, b: Vec2, thickness: f32, col: Color) {
	d := b - a
	l := math.sqrt(d.x * d.x + d.y * d.y)
	if l < 1e-4 { return }
	n := Vec2{-d.y, d.x} * (thickness * 0.5 / l)
	draw_quad_points(&ctx.draw, {a - n, b - n, b + n, a + n}, solid_uv(), col, 0)
}

draw_rect_outline :: proc "contextless" (ctx: ^Context, r: Rect, col: Color, t: f32 = 1) {
	draw_rect(ctx, {r.min, {r.max.x, r.min.y + t}}, col)
	draw_rect(ctx, {{r.min.x, r.max.y - t}, r.max}, col)
	draw_rect(ctx, {{r.min.x, r.min.y + t}, {r.min.x + t, r.max.y - t}}, col)
	draw_rect(ctx, {{r.max.x - t, r.min.y + t}, {r.max.x, r.max.y - t}}, col)
}

// draw_text: yerleşik 5x7 ASCII font ile metin çizer.
//
// Dize RUNE (UTF-8 karakter) bazında ilerletilir. Bayt bazında ilerletildiğinde çok
// baytlı her karakter iki ayrı '?' olarak basılır ve hücre genişliği iki katına çıkar;
// model çıktısı ve Türkçe arayüz metinleri bu yüzden bozuk görünür ve hizalama kayar.
draw_text :: proc "contextless" (ctx: ^Context, pos: Vec2, s: string, col: Color) {
	sc := ctx.style.font_scale
	x := pos.x
	for ch in s {
		// Atlas yalnızca 32..126 ASCII gliflerini içerir; diğerleri için '?' basılır.
		c := u8(ch) if ch >= 32 && ch <= 126 else u8('?')
		idx := int(c) - 32
		ox := f32((idx % ATLAS_COLS) * ATLAS_CELL)
		oy := f32((idx / ATLAS_COLS) * ATLAS_CELL)
		if c != ' ' {
			draw_quad_uv(&ctx.draw, {{x, pos.y}, {x + 5 * sc, pos.y + 7 * sc}},
				{ox / ATLAS_W, oy / ATLAS_H}, {(ox + 5) / ATLAS_W, (oy + 7) / ATLAS_H}, col, 0)
		}
		x += 6 * sc
	}
}

draw_image :: proc "contextless" (ctx: ^Context, r: Rect, tex: Texture_ID, uv0, uv1: Vec2, tint := Color{1, 1, 1, 1}) {
	draw_quad_uv(&ctx.draw, r, uv0, uv1, tint, tex)
}

// ---------------------------------------------------------------- Yerleşim (auto-layout)
panel_cur :: proc "contextless" (ctx: ^Context) -> ^Panel { return &ctx.panels[ctx.panel_count - 1] }

// size.x <= 0: kalan genişliği doldur. size.y <= 0: kalan yüksekliği doldur.
layout_next :: proc "contextless" (ctx: ^Context, size: Vec2) -> Rect {
	p := panel_cur(ctx)
	if !p.continuing { p.line_start_y = p.cursor.y; p.line_h = 0 }
	w := size.x if size.x > 0 else max(p.content_max_x - p.cursor.x, 8)
	h := size.y if size.y > 0 else max(p.rect.max.y - p.cursor.y - ctx.style.padding, 8)
	r := Rect{p.cursor, p.cursor + {w, h}}
	p.line_h = max(p.line_h, h)
	p.last_rect = r
	p.cursor = {p.content_min.x, p.line_start_y + p.line_h + ctx.style.spacing}
	p.continuing = false
	return r
}

// Sonraki widget'ı önceki ile aynı satıra koyar.
same_line :: proc "contextless" (ctx: ^Context) {
	p := panel_cur(ctx)
	p.cursor = {p.last_rect.max.x + ctx.style.spacing, p.line_start_y}
	p.continuing = true
}

avail_width :: proc "contextless" (ctx: ^Context) -> f32 {
	p := panel_cur(ctx)
	return p.content_max_x - p.cursor.x
}

// ---------------------------------------------------------------- Etkileşim
// hovered: fare öğenin (kırpılmış) alanında; held: basılı tutuluyor; pressed: bu karede bırakıldı.
item_behavior :: proc "contextless" (ctx: ^Context, id: ID, r: Rect) -> (hovered, held, pressed: bool) {
	visible := rect_intersect(r, draw_clip_current(&ctx.draw))
	hovered = rect_contains(visible, ctx.input.mouse_pos) && (ctx.active == 0 || ctx.active == id)
	if hovered { ctx.hot = id }
	if hovered && mouse_pressed(ctx, 0) && ctx.active == 0 { ctx.active = id }
	if ctx.active == id {
		held = ctx.input.mouse_down[0]
		if mouse_released(ctx, 0) {
			pressed = hovered
			ctx.active = 0
		}
	}
	return
}

// ---------------------------------------------------------------- Pencere
begin_window :: proc "contextless" (ctx: ^Context, title: string, default_rect: Rect) -> bool {
	if ctx.panel_count >= MAX_PANELS { return false }
	id := get_id(ctx, title)
	abuf_push(&ctx.id_stack, id)

	def_pos  := default_rect.min
	def_size := rect_size(default_rect)
	st := storage_get(&ctx.storage, id, {def_pos.x, def_pos.y, def_size.x, def_size.y})
	pos, size := Vec2{st[0], st[1]}, Vec2{st[2], st[3]}

	s := &ctx.style
	title_h := text_height(ctx) + s.title_h_extra
	title_rect := Rect{pos, {pos.x + size.x, pos.y + title_h}}
	grip_rect  := Rect{{pos.x + size.x - 14, pos.y + size.y - 14}, pos + size}

	_, theld, _ := item_behavior(ctx, get_id(ctx, "##title"), title_rect)
	if theld { pos += ctx.input.mouse_delta }
	_, gheld, _ := item_behavior(ctx, get_id(ctx, "##grip"), grip_rect)
	if gheld {
		size += ctx.input.mouse_delta
		size = {max(size.x, 120), max(size.y, 80)}
	}
	pos = {clamp(pos.x, -size.x + 40, ctx.display.x - 40), clamp(pos.y, 0, ctx.display.y - title_h)}
	storage_set(&ctx.storage, id, {pos.x, pos.y, size.x, size.y})

	rect := Rect{pos, pos + size}
	if rect_contains(rect, ctx.input.mouse_pos) { ctx.want_capture_mouse = true }

	title_rect = Rect{pos, {pos.x + size.x, pos.y + title_h}}
	draw_rect(ctx, rect, s.window_bg)
	draw_rect(ctx, title_rect, s.title_bg)
	draw_rect_outline(ctx, rect, s.border)
	draw_text(ctx, {pos.x + s.padding, pos.y + s.title_h_extra * 0.5}, label_text(title), s.title_text)
	draw_rect(ctx, {{rect.max.x - 10, rect.max.y - 10}, {rect.max.x - 2, rect.max.y - 2}}, s.accent if gheld else s.widget_hot)

	content := Rect{{pos.x, pos.y + title_h}, rect.max}
	draw_push_clip(&ctx.draw, content)
	cmin := Vec2{pos.x + s.padding, pos.y + title_h + s.padding}
	ctx.panels[ctx.panel_count] = Panel{
		id = id, rect = rect, content_min = cmin, content_max_x = rect.max.x - s.padding, cursor = cmin,
	}
	ctx.panel_count += 1
	return true
}

end_window :: proc "contextless" (ctx: ^Context) {
	if ctx.panel_count == 0 { return }
	ctx.panel_count -= 1
	draw_pop_clip(&ctx.draw)
	pop_id(ctx)
}
