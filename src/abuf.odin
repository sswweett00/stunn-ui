package stunn

// =============================================================================
// Sabit-kapasiteli tamponlar (dinamik dizi yerine).
//
// Neden: `make/append/delete/clear/pop` yerleşik yordamları örtük `context`
// ister; freestanding (bare-metal) ana bilgisayarda bağlam yoktur ve
// `context` gölgelenemez. Bu yüzden tamponlar init'te TAM kapasiteyle,
// ana bilgisayarın verdiği tahsisat yordamıyla ayrılır; kare başında yalnızca
// sayaç sıfırlanır (yeniden tahsis yok, taşma sessizce yoksayılır).
//
// Ana bilgisayar, `stunn.init` ÖNCESİ `heap_alloc_fn`'i kurar:
//   stunn.heap_alloc_fn = my_bump_alloc   // "contextless" (boyut, hiza) -> ham işaretçi
// Kurulmazsa init başarısız döner (tamponlar nil; backend güvenli atlar).
// =============================================================================

// Ana bilgisayar tahsisatı: bağlamsız, sıfırlama garantisi YOKTUR
// (abuf_init belleği kendisi sıfırlar — sayaç 0'dan başlar).
Heap_Alloc :: proc "contextless" (size, align: uint) -> rawptr

heap_alloc_fn: Heap_Alloc = nil

ABuf :: struct($T: typeid) {
	data:  [^]T,
	count: int,
	cap:   int,
}

abuf_init :: proc "contextless" (b: ^ABuf($T), cap: int) -> bool {
	if cap <= 0 || b.data != nil || heap_alloc_fn == nil { return false }
	p := heap_alloc_fn(uint(cap * size_of(T)), 8)
	if p == nil { return false }
	b.data = cast([^]T)p
	b.count = 0
	b.cap = cap
	return true
}

abuf_push :: proc "contextless" (b: ^ABuf($T), v: T) -> bool {
	if b.data == nil || b.count >= b.cap { return false }
	b.data[b.count] = v
	b.count += 1
	return true
}

abuf_clear :: proc "contextless" (b: ^ABuf($T)) { b.count = 0 }

abuf_pop :: proc "contextless" (b: ^ABuf($T)) {
	if b.count > 0 { b.count -= 1 }
}

abuf_last :: proc "contextless" (b: ^ABuf($T)) -> T {
	zero: T
	if b.count <= 0 { return zero }
	return b.data[b.count - 1]
}
