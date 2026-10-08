# stunn-ui

**Motor bağımsız, saf Odin immediate-mode GUI kütüphanesi.**

Yalnızca ham tiplerle (`^f32`, `^[3]f32`, `^bool`, `u32`) çalışır. Hiçbir motor veya framework'e bağlı değildir. OpenGL 4.6 backend'i ve 3B gizmo (Translate / Rotate / Scale) desteği dahildir.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Özellikler

| Kategori | Detay |
|----------|--------|
| **Çekirdek** | Immediate-mode, ID tabanlı kalıcı storage, auto-layout |
| **Widget'lar** | Label, Button, Checkbox, Selectable, DragFloat, DragFloat3, Slider, Separator, Viewport |
| **Pencere** | Sürüklenebilir, yeniden boyutlandırılabilir, clip + title bar |
| **Tema** | Dark (varsayılan) + Light |
| **Font** | Yerleşik 5×7 ASCII bitmap atlas (çalışma zamanında üretilir) |
| **Çizim** | Batching, scissor clip stack, texture ID köprüsü |
| **Gizmo** | 3B Translate / Rotate / Scale (`gizmo/` paketi, vmath ile) |
| **Backend** | OpenGL 4.6 Core + GLFW girdi köprüsü (`backend_gl/`) + yazılımsal CPU rasterizer (`backend_sw/`) |
| **Tahsisat** | Kare başına sıfır dinamik tahsisat (arena + sabit tamponlar; gizmo testleri ile doğrulanmış) |
| **Freestanding** | `src/` + `backend_sw/` bağlamsızdır (`contextless`); bare-metal çekirdeklerde çalışır (aşağıya bakın) |

---

## Bağımlılıklar

| Bağımlılık | Gerekli mi? | Not |
|------------|-------------|-----|
| [Odin](https://odin-lang.org/) (2024+) | Evet | `odin` PATH'te olmalı |
| **vmath** (kardeş dizin) | Gizmo + testler için | `../vmath` beklenir |
| GLFW + OpenGL | Standalone demo için | `libglfw3-dev` (Linux) / sistem GLFW |

> `gizmo/` paketi ayrıdır (`vmath` ister); çekirdek + yazılım backend için
> yalnızca `src/` + `backend_sw/` yeterlidir — harici bağımlılık yoktur
> (`core:math` dışında; `core:fmt`/`core:strings` kullanılmaz).

---

## Hızlı başlangıç

```bash
# Depoyu klonlayın (vmath ile yan yana önerilir)
git clone https://github.com/sswweett00/stunn-ui.git
cd stunn-ui

# Linux / macOS
./build.sh

# Windows
build.bat

# Demo çalıştır
./build/standalone_demo   # veya build\standalone_demo.exe
```

### Minimal entegrasyon (motor içi)

```odin
import stunn "path/to/stunn-ui/src"

// Ana bilgisayar tahsisatı (bir kez, init öncesi): arena/bump modeli.
my_heap: [8 * 1024 * 1024]u8
my_heap_cur: uint
my_alloc :: proc "contextless" (size, align: uint) -> rawptr {
    // ...hizala, dilimle, yetmezse nil dön
}

stunn.heap_alloc_fn = my_alloc

ctx: stunn.Context
stunn.init(&ctx)

// Her kare:
stunn.input_mouse_pos(&ctx, mouse)
stunn.input_mouse_button(&ctx, 0, left_down)
stunn.begin_frame(&ctx, display_size, dt)

if stunn.begin_window(&ctx, "Inspector", {{20, 20}, {320, 400}}) {
    stunn.drag_float3(&ctx, "Position", &my_pos, 0.05)
    if stunn.button(&ctx, "Reset") { my_pos = {} }
    stunn.end_window(&ctx)
}
stunn.end_frame(&ctx)

// Çizim komutlarını backend_gl, backend_sw veya kendi renderer'ınıza gönderin.
```

---

## API özeti

### Bağlam yaşam döngüsü
```odin
init(ctx, allocator)
destroy(ctx)
begin_frame(ctx, display: Vec2, dt: f32)
end_frame(ctx)
```

### Girdi
```odin
input_mouse_pos / input_mouse_button / input_scroll / input_modifiers
mouse_down / mouse_pressed / mouse_released
```

### Pencere & yerleşim
```odin
begin_window(ctx, title, default_rect) -> bool
end_window(ctx)
layout_next / same_line / avail_width
```

### Widget'lar
```odin
label / labelf / separator / button / selectable / checkbox
drag_float / drag_float3 / slider_float
viewport(ctx, tex: Texture_ID, size) -> Viewport_State
```

### Tema
```odin
set_theme(ctx, .Dark)   // veya .Light
style_for_theme(t) -> Style
```

### Gizmo (vmath gerekir)
```odin
gizmo(ctx, mode, viewport_state, view, proj, target) -> Gizmo_Result
gizmo_cancel(ctx)
```

---

## Dizin yapısı

```
stunn-ui/
├── src/                  # Çekirdek (motor bağımsız)
│   ├── types.odin
│   ├── context.odin
│   ├── draw.odin
│   ├── font.odin
│   ├── widgets.odin
│   ├── gizmo.odin
│   └── gizmo_test.odin
├── backend_gl/           # OpenGL 4.6 + GLFW köprüsü
│   └── renderer.odin
├── examples/
│   └── standalone_demo.odin
├── build.sh / build.bat
├── ols.json              # Odin Language Server
└── LICENSE (MIT)
```

---

## Mimari notlar

- **Immediate-mode**: Her karede widget'lar yeniden çağrılır; durum ID hash ile `Storage` içinde tutulur.
- **Draw_Command_Buffer**: Vertex/index/cmd biriktirir; GPU'ya yalnızca `render` anında gider.
- **ID stack**: `push_id` / `pop_id` ile hiyerarşik benzersiz kimlik üretir (ImGui tarzı `##` gizli kimlik desteklenir).
- **Sıfır tahsisat hedefi**: Storage sabit boyutlu hash tablosu; draw buffer kapasiteleri önceden ayrılır.

---

## Katkı

PR'lar ve issue'lar memnuniyetle karşılanır. Kod stili: `-vet -strict-style` ile temiz geçmelidir.

```bash
odin check src -no-entry-point -vet -strict-style -collection:vmath=../vmath
odin test src -vet -strict-style -collection:vmath=../vmath
```

---

## Lisans

MIT © 2026 kaanaydinli
