// stunn_ui - motor bağımsız, saf Odin immediate-mode GUI. Yalnızca ham tiplerle (^f32, ^[3]f32, ^bool, u32) çalışır.
package stunn

import "core:strings"

Vec2  :: [2]f32
Color :: [4]f32

ID         :: distinct u32
Texture_ID :: distinct u32 // 0 = yerleşik font atlası; diğerleri host (GL) doku kimlikleridir

Rect :: struct { min, max: Vec2 }

rect_size :: #force_inline proc "contextless" (r: Rect) -> Vec2 { return r.max - r.min }
rect_contains :: #force_inline proc "contextless" (r: Rect, p: Vec2) -> bool {
	return p.x >= r.min.x && p.y >= r.min.y && p.x < r.max.x && p.y < r.max.y
}
rect_intersect :: #force_inline proc "contextless" (a, b: Rect) -> Rect {
	return {{max(a.min.x, b.min.x), max(a.min.y, b.min.y)}, {min(a.max.x, b.max.x), min(a.max.y, b.max.y)}}
}
rect_shrink :: #force_inline proc "contextless" (r: Rect, d: f32) -> Rect {
	return {r.min + {d, d}, r.max - {d, d}}
}

// FNV-1a; seed = üst ID (ID stack). Sonuç asla 0 değildir (0 = "yok").
hash_string :: proc "contextless" (s: string, seed: ID) -> ID {
	h := u32(seed) if seed != 0 else 2166136261
	for i in 0 ..< len(s) {
		h = (h ~ u32(s[i])) * 16777619
	}
	return ID(h if h != 0 else 1)
}

// "Etiket##gizli_kimlik" biçiminde yalnızca görünen kısmı döner.
label_text :: proc(label: string) -> string {
	if i := strings.index(label, "##"); i >= 0 { return label[:i] }
	return label
}
