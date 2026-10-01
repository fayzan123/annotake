import AnnotakeCapture
import Testing

struct PixelStoreTests {
    @Test func pixelStoreEvicts() {
        var store = PixelStore<String>()
        for index in 1...4 {
            store.put("buffer \(index)", frameIndex: index)
        }
        store.evict(below: 3)
        #expect(store.count == 2)
        #expect(store.buffer(frameIndex: 3) == "buffer 3")
        #expect(store.buffer(frameIndex: 4) == "buffer 4")
        #expect(store.buffer(frameIndex: 2) == nil)
        #expect(store.buffer(frameIndex: 9) == nil)
    }
}
