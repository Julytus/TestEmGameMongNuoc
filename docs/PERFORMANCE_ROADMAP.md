# Kế hoạch tối ưu & Roadmap

Mục tiêu: game HD-2D (nhân vật sprite 2D, thế giới 3D, skill/hiệu ứng 3D) chạy **60 FPS ổn định**,
và **mọi tính năng mới phải qua kiểm tra hiệu năng** trước khi coi là xong.

Nguyên tắc số 1: **đo trước, tối ưu sau**. Không tối ưu theo cảm giác; mỗi thay đổi có số liệu trước/sau.

Nguyên tắc số 2: **tính sẵn trước (bake-first)** — vì map sẽ rộng và VFX skill cần chỗ trống GPU:
- Thứ không đổi khi chơi (hình dạng cây, viền đất/cỏ, ánh sáng & bóng của vật tĩnh, noise nước) được **tính một lần
  lúc build** bằng `tools/` (Python hoặc tool script Godot) và lưu thành texture / `.res` / lightmap.
- Lúc chạy shader chỉ **đọc texture + chuyển động rẻ** (cuộn UV, gió ở vertex). Không có noise thủ tục mỗi pixel,
  không vòng lặp trong fragment, không dựng mesh bằng GDScript lúc load.
- **Ánh sáng cố định theo khu vực** (quyết định của người dùng 2026-11-25): mỗi khu vực một preset
  (day/sunset/night) → ánh sáng gián tiếp + bóng của vật tĩnh **bake bằng LightmapGI**; bóng thời gian thực chỉ
  còn cho vật động trong tầm ngắn. Preset vẫn đổi được bằng F2 / cutscene khi dev; nếu gameplay cần đổi preset
  trong cùng khu vực thì mỗi preset một bộ lightmap (chỉ khi thật cần).
- Luôn giữ **nguồn sinh** (script + tham số) trong git; asset bake là đầu ra, sinh lại được bằng một lệnh.

---

## 1. Hiện trạng (đo/đọc ngày 2026-11-25)

| Hạng mục | Hiện tại | Rủi ro khi game lớn lên |
|---|---|---|
| Phần cứng dev | RTX 3050 Ti Laptop (4 GB) + iGPU Radeon (Ryzen 7 5800H), màn 1920×1080 | — |
| GPU / khung — baseline 1080p fullscreen (`docs/perf_baseline.json`, meadow day, 4 điểm) | **RTX:** High 9,3–10,7 ms · Medium 7,5–8,3 · Low 4,7–4,9. **iGPU:** High 41–46 ms · Medium 30–32 · Low 14,5–14,8. Điểm nặng nhất `forest_edge` High RTX 10,75 ms (night 10,6) | High RTX đã **> 10 ms** (ngân sách §2) ở bìa rừng, chưa có VFX/kẻ địch; iGPU chỉ Low gần 60 FPS |
| Draw / primitive / VRAM (High) | 69–111 draw · **1,66 M primitive** (> ngân sách 1,5 M; Medium/Low 1,01 M) · 380 MB | Primitive gần như không đổi giữa các điểm → MultiMesh cỏ/rừng không cull |
| Stress 96×96 m (`bench_stress`, day) | RTX High 12,2–13,3 ms · 6,43 M primitive · iGPU High 50–52 ms · Low RTX 5,1–5,7 / iGPU 20–21; nạp 1,1–1,3 s (meadow 0,56–0,9 s) | Map ×4 diện tích → GPU tăng theo diện tích vì không chia ô (Mốc 1) |
| Cỏ / hoa | 3 MultiMesh phủ nguyên 48×48 m (TallGrass ~23k thẻ thử) | **Không chia ô** → không frustum-cull được; map lớn hơn là vẽ toàn bộ |
| Rừng | 4 MultiMesh (mỗi loài) phủ 64×64 m, mỗi cây hàng trăm thẻ lá alpha-scissor | Đổ bóng bằng chính thẻ lá → shadow pass nặng; không chia ô |
| Shader lá | `inverse(mat3(MODEL_MATRIX))` **mỗi đỉnh** | Lãng phí ALU với hàng trăm nghìn đỉnh |
| Nước | *(đã bake, plan water-bake-first)* fragment chỉ đọc ~13 texture, 0 noise / 0 vòng lặp; 720p High 0,21 ms (trước 0,36), 1080p High 0,51 ms (trước 0,94) | Phần cố định (raster/G-buffer/SSR của mặt nước) ≈ 0,16 ms ở 720p High — giảm tiếp phải bớt SSR/diện tích |
| Hậu kỳ | SSAO, SSR, volumetric fog, DOF, glow, MSAA 2x | Đắt theo độ phân giải; chưa có scale độ phân giải 3D |
| Đèn | Đèn lồng omni không bóng, group `lamps` | Ổn; cần quy tắc khi VFX thêm đèn |
| Công cụ đo | Bench tự động `tools/bench/run_bench.py` (ma trận 3 mức × 2 GPU, `--full` 24 cấu hình) + overlay F4 + level stress | Baseline giữa các phiên trôi (nhiệt/driver) → `[ĐỎ]` là tín hiệu, kết luận bằng A/B cùng phiên |
| Khác | Rò ObjectDB lúc thoát đã né: SceneManager nạp sẵn + ghim 8 file preload/#include (lỗi engine godot#120661) | Manifest phình theo preload của cả game (lint `check.py` in tổng KB); gỡ khi engine sửa |

---

## 2. Ngân sách hiệu năng (performance budget)

**Máy chuẩn:**
- **High:** RTX 3050 Ti Laptop, 1920×1080, 60 FPS.
- **Low:** iGPU Radeon của chính máy dev (chạy `--gpu-index 1`), 1920×1080, 60 FPS. Máy bạn có sẵn
  hai GPU nên test được cả hai mức mà không cần máy khác.

**Ngân sách GPU mỗi khung, mức High, 1080p, cảnh combat nặng nhất** (con số ban đầu, sẽ chỉnh lại
sau khi có số đo Mốc 0):

| Hạng mục | ms |
|---|---|
| Mặt đất + nước | 1,0 |
| Cỏ / hoa | 1,5 |
| Cây / rừng (gồm bóng) | 2,0 |
| Nhân vật & kẻ địch (sprite) | 0,5 |
| Hậu kỳ (SSAO, SSR, fog thể tích, DOF, glow) | 3,0 |
| VFX skill (bình thường / đỉnh) | 1,5 / 2,5 |
| UI | 0,3 |
| **Tổng** | **≤ 10 (đỉnh ≤ 12)** — chừa ~4 ms cho máy yếu hơn / giật driver |

**Giới hạn khác (cảnh nặng nhất):**
- Draw call ≤ 400 · primitive hiển thị ≤ 1,5 triệu.
- Đèn omni/spot nhìn thấy ≤ 16; đèn có bóng ≤ 2 (ngoài mặt trời).
- CPU frame (script + physics) ≤ 6 ms; kẻ địch AI đầy đủ cùng lúc ≤ 20.
- VFX: ≤ 32 hiệu ứng đồng thời, ≤ 5.000 hạt sống.
- VRAM ≤ 1,5 GB · chuyển level ≤ 3 s · **không giật khi dùng skill lần đầu**.

---

## 3. Roadmap

Các mốc xếp theo thứ tự phụ thuộc. Mốc tối ưu đi **trước** tính năng cần đến nó
(ví dụ khung VFX làm trước khi làm nhiều skill).

### Mốc 0 — Đo lường (làm đầu tiên)
Không có số đo thì mọi bước sau không kiểm chứng được.

- [ ] **Chế độ benchmark** `-- --bench=10 [--bench-out=path.json]`: người chơi đứng lần lượt ở các điểm đo cố định
      `BenchPoint` của level, đo N giây mỗi điểm (móc `EventBus.bench_point_entered` cho stress sau này), xuất JSON: GPU ms trung bình / p95 / p99
      (`RenderingServer.viewport_get_measured_render_time_gpu`), CPU ms, draw call, primitive,
      số node, bộ nhớ video (`Performance` monitors).
- [ ] **Overlay debug F4**: hiển thị các số trên khi đang chơi.
- [ ] **Scene stress** `bench_stress.tscn`: map lớn hơn + (sau này) 30 kẻ địch + spam skill.
- [ ] Script `tools/bench/run_bench.py`: chạy bench ở 3 mức × 2 GPU, so với `docs/perf_baseline.json`,
      báo đỏ nếu GPU p50 chậm hơn > 5 % VÀ > 0,3 ms; `--exe` cho bản export.
- [ ] Ghi **baseline 1080p** cho cả RTX và iGPU.
- [ ] Sửa rò rỉ ObjectDB lúc thoát.

**Xong khi:** một lệnh in ra bảng so sánh với baseline.

### Mốc 1 — Lõi render
Đổi cấu trúc `meadow_road.tscn` → sửa cả `bench_stress.tscn` + chạy `run_bench.py --stress --seconds 1` và `check.py --all`.

- [x] **Scale độ phân giải 3D** (`Settings.SCALE_3D`, UI vẫn độ phân giải gốc): High 1,0 · Medium 0,77 · Low 0,6,
      upscale **bilinear** — A/B cùng phiên 1080p (plan `261125-1514-render-core-m1`): FSR1 tạo quầng tối quanh
      viền sprite pixel và đắt hơn bilinear ~0,2 ms RTX / ~0,9 ms iGPU. Kết quả (meadow, GPU p50 trước → sau):
      Medium RTX 7,5–8,3 → 6,2–7,1 ms, iGPU 30–32 → 22–24 ms; Low RTX 4,7–4,9 → 4,6–4,8 ms (RTX Low không bị
      giới hạn bởi số pixel), iGPU 14,3–14,5 → 9,6–10,0 ms; High không đổi. Sprite ở 0,6 mềm hơn nhưng còn đọc rõ.
- [x] **Chia ô GrassField** (`chunk_size` = 16, con internal không lưu .tscn): cỏ/hoa `visibility_range_end` = 43 m
      (mép xa khung ≈ 31 m + nửa đường chéo ô); Low ×0,5 instance (`visible_instance_count`, không sinh lại) và
      co ngọn trong 25–30 m (global `foliage_fade_end`). `fade_mode = SELF` bị loại: +0,06–0,17 ms (720p) khi
      vài ô đang fade (instance đang fade vẽ ở pass alpha). Kết quả 1080p (GPU p50 trước → sau): meadow High RTX
      9,3–10,8 → 8,6–9,9 ms, primitive 1,66 M → 0,54–0,69 M, draw 69–111 → 176–259; stress High RTX 12,2–13,3 →
      8,6–9,1 ms, iGPU 50–52 → 39–41; Low iGPU stress 15,1–15,6 → 8,1–8,3. CPU render +0,1–0,5 ms (draw call).
- [x] **Bóng của cây**: rừng (GrassField Tree) đổ bóng bằng proxy low-poly (`TreeMeshBuilder.get_shadow_proxy`:
      ellipsoid mỗi cụm tán ×1,0, nón mỗi tầng thông, trụ thân; `SHADOWS_ONLY`), mesh lá thật `cast_shadow = OFF`;
      proxy ở mọi mức (ảnh gần như không khác thẻ lá). Sun `directional_shadow_max_distance` 40 → 30, Low ×0,75.
      A/B cùng phiên 1080p (thẻ lá → proxy): meadow High RTX 7,6–9,4 → 6,5–7,1 ms (`forest_edge` 9,37 → 7,15),
      iGPU 36,7–41,8 → 33,8–37,0; stress High RTX 8,3 → 6,6–6,8. Tổng Mốc 1 (meadow High RTX, trước P1 → sau P3):
      9,3–10,8 → 6,5–7,1 ms — **đạt mục tiêu ≤ 8 ms**.
      (Khi có lightmap ở Mốc 1B, proxy chỉ còn dùng để đổ bóng thời gian thực lên vật động; proxy không lắc theo gió.)
- [x] **Shader lá**: bỏ `inverse()` mỗi đỉnh (scale đều → dùng transpose / scale²; mọi cây trong 2 level đều scale đều).
      Ảnh day/sunset `forest_edge` trùng hình khối, độ sáng trung bình bằng nhau (±0,1/255). Bench sau (1080p, p50, forest_edge):
      High RTX 7,12 ms, iGPU 36,7 ms — khớp mức sau Mốc 1; lần "trước" cùng phiên bị nhiễu (mất focus) nên **không đo được
      khác biệt** đáng kể, chỉ khẳng định không chậm hơn.
- [x] **Nước**: gom noise vào texture `water_noise.png` + `water_sparkle.png` (sinh bằng `tools/art/gen_water.py`),
      shader chỉ cuộn texture. Shore SDF thay bằng water field dùng chung đất + nước (`WaterField`, dựng lúc load ≈ 28 ms).
      0 lần `terrain_noise` và 0 vòng lặp trong fragment nước. Đo A/B cùng phiên (RTX 3050 Ti, p50): 720p High 0,360 → 0,211 ms
      (−41 %; người dùng chấp nhận thay cho mục tiêu −50 % vì phần cố định của mặt nước ≈ 0,157 ms), 1080p High 0,938 → 0,507 ms,
      720p Low 0,17 → 0,04 ms; iGPU Radeon 720p Low 1,13 → 0,64 ms. Low: đáy phẳng, không caustic (global `water_detail`).
      Chừa sẵn **điểm mở rộng cho gợn sóng tương tác** (một `ripple_texture` + vùng phủ, mặc định trống) để sau này
      người chơi đi trên nước tạo sóng mà không phải viết lại shader.
- [ ] *(sau, khi làm tính năng đi trên nước)* **Gợn sóng tương tác** — phần động duy nhất của nước, chỉ quanh
      người chơi: Low = vòng sóng flipbook pixel (pool VFX, không đụng shader nước); High = mô phỏng sóng
      trong SubViewport nhỏ (~128×128 px phủ ~16 m, đi theo người chơi) ghi vào `ripple_texture`.
      Ngân sách ≤ 0,3 ms GPU.
- [ ] *(phiên kế, sau plan `plans/261125-0320-water-bake-first`)* **Đi trên nước & biển** — người chơi đi trên mặt nước,
      ra tới giữa biển (gần như cả màn hình là nước → chi phí mỗi pixel nước quyết định FPS):
  - **Collision:** hiện nước là tường (`src/world/terrain/terrain_collision.gd:7-8`, `blocking_mask` có `FLAG_WATER`)
    → bỏ `FLAG_WATER` khỏi mask (việc gameplay của tính năng đi trên nước).
  - **Gợn sóng phải chạy cả giữa biển:** nhánh `ripple_texture`/`ripple_rect` tính theo tọa độ thế giới, đi theo người chơi,
    **không phụ thuộc** water field / khoảng cách tới bờ.
  - **Biển khơi không có field:** plan nước hiện coi ngoài vùng field = "không có nước" (discard). Chunk biển khơi phải hiểu
    ngược lại = "nước sâu" → giá trị ngoài field chỉnh được theo chunk (ràng buộc thiết kế cho Mốc 4).
  - **Chi tiết chỉ ở ven bờ:** field theo chunk, lưu 8-bit (RG8) clamp ~3 m (bọt/độ sâu chỉ cần ~2,4 m); chunk toàn biển
    khơi không cần field; mặt đất không vẽ ở vùng biển (tránh vẽ rồi discard).
  - [x] **Nước sâu bỏ qua đáy** *(đã làm trong plan water-bake-first)*: độ đục 0,92 → đáy gần như không thấy → một nhánh `if` bỏ đọc đáy + caustic.
  - **Phản chiếu:** SSR đắt theo số pixel phản chiếu; với biển dùng `sky_sheen` + ReflectionProbe bake, SSR chỉ cho hồ nhỏ ở
    High. Đo SSR trên cảnh biển kín màn trước khi quyết.
  - **Phản chiếu nhân vật:** nếu bỏ SSR → mất bóng phản chiếu khi đứng trên nước → sprite lật ngược mờ dưới chân (rẻ,
    chạy cả ở Low).
  - **Sóng biển** chỉ bằng texture cuộn: không dịch đỉnh, không tessellation.
  - **Công cụ xây map:** vẽ nước / "block nước" trong editor (hiện nước chỉ đến từ kênh B của layout PNG).
  - Mọi số tiết kiệm trên là ước tính `[ASSUMED]` — đo A/B khi làm.
- [ ] **Viền đất/cỏ bake**: noise làm méo viền (`terrain_common.gdshaderinc`) tính sẵn vào layout/splat texture
      lúc build; shader mặt đất chỉ đọc texture.
- [ ] **Cây bake sẵn**: `TreeMeshBuilder` chạy lúc build (tool) → lưu mesh mỗi loài thành `.res`; lúc chạy chỉ nạp.
      Thêm LOD cho cây xa (ít thẻ lá hơn), xa nữa impostor (billboard chụp sẵn) — xét sau khi có số đo.
- [ ] **Overdraw**: xem chế độ debug Overdraw của Viewport cho cỏ, lá, nước; giảm thẻ chồng nhau.
- [ ] **Mức đồ họa mở rộng**: thêm vào `Settings` mật độ cỏ, tầm xa foliage, khoảng cách bóng,
      scale 3D, `vfx_quality` (dùng ở Mốc 4).

**Xong khi:** 1080p High ≤ 8 ms trên RTX ở meadow_road; Low giữ 60 FPS trên iGPU.

### Mốc 1B — Ánh sáng bake theo khu vực (sau "Cây bake sẵn")
Phụ thuộc: mesh tĩnh phải là resource có UV2 → cây/đá/địa hình phải bake sẵn trước (Mốc 1).

- [ ] **Probe trước** (chưa kiểm chứng, `[PRIOR]`): bake LightmapGI chạy được từ dòng lệnh hay chỉ trong editor;
      shadowmask của DirectionalLight trong Godot 4.7 (bóng thật gần camera, bóng bake ở xa); kích thước lightmap
      cho 48×48 m; UV2 cho mesh sinh bằng script.
- [ ] Mỗi level khai báo preset cố định; sun/lamp tĩnh `bake_mode = STATIC`, vật tĩnh `gi_mode = STATIC`.
- [ ] Cỏ/hoa (MultiMesh) và nhân vật là vật động → nhận sáng từ light probe của LightmapGI.
- [ ] **Bóng nhân vật/kẻ địch**: blob shadow (Decal/quad) — trùng mục Mốc 2.
- [ ] Mức Low: lightmap độ phân giải thấp hơn hoặc tắt bóng thời gian thực hoàn toàn (chỉ còn bóng bake).
- [ ] Lệnh bake sinh lại được (`tools/` + ghi trong README); lightmap là đầu ra, không chỉnh tay.

**Xong khi:** meadow_road day/sunset/night trông tương đương bản hiện tại (so screenshot) và shadow pass giảm rõ
(số đo bench); đổi preset bằng F2 không lỗi.

### Mốc 2 — Nhân vật 2D trên nền 3D (song song với tính năng kẻ địch)
- [ ] Sprite giữ **`alpha_cut` (opaque discard)**, không dùng alpha blend: vẽ được ở depth prepass,
      không lỗi sắp xếp, rẻ.
- [ ] Mỗi loại nhân vật dùng **chung** `SpriteFrames` và material; hiệu ứng riêng từng con
      (nháy trắng khi trúng đòn, viền, tint) bằng **`instance uniform`**, không duplicate material.
- [ ] **Bóng nhân vật**: billboard đổ bóng thật bị méo khi camera xoay → dùng blob shadow
      (Decal hoặc quad shader) cho kẻ địch/NPC; player có thể giữ bóng đẹp hơn.
- [ ] **LOD logic cho kẻ địch**: ngoài màn hình (`VisibleOnScreenNotifier3D`) hoặc ở xa → AI chạy
      10 Hz hoặc ngủ; tắt `_process` khi đứng yên.
- [ ] Hitbox/Hurtbox chỉ bật trong frame tấn công; collision mask tối thiểu.
- [ ] **Pool kẻ địch** cho spawn liên tục (không `instantiate()`/`queue_free()` giữa combat).
- [ ] Đám đông > 100 con (nếu có): MultiMesh + shader flipbook (chọn frame bằng `INSTANCE_CUSTOM`).

**Xong khi:** bench stress với 30 kẻ địch: CPU ≤ 6 ms, sprite ≤ 0,5 ms GPU.

### Mốc 3 — Khung skill & VFX 3D (làm trước khi làm nhiều skill)
VFX là nguồn tụt FPS số 1 của game action. Phải có khung + quy tắc ngay từ đầu.

- [ ] **`VfxPool`** (autoload): tạo sẵn N bản mỗi hiệu ứng lúc load level, `spawn(id, transform)`
      và tự trả về pool khi xong. Không instantiate giữa combat.
- [ ] **Warm-up shader**: lúc load level / màn hình loading, render mỗi hiệu ứng 1 lần ngoài camera để
      compile pipeline trước → **không giật lần đầu dùng skill**.
- [ ] **Cách dựng hiệu ứng** (ưu tiên từ trên xuống):
  1. **Mesh hiệu ứng** (vòng chém, vòng tròn, trụ, sóng) + shader unshaded cuộn texture / dissolve:
     ít quad lớn rẻ hơn hàng trăm hạt.
  2. **Flipbook pixel art** trên quad billboard (có thể làm bằng skill `pixelfx` → sprite sheet):
     hợp chất HD-2D nhất.
  3. `GPUParticles3D` cho bụi, tia lửa, mảnh vụn: thường ≤ 64 hạt, skill lớn ≤ 256.
- [ ] Material VFX: **unshaded**, additive hoặc alpha-scissor; texture nhỏ, filter Nearest.
      Tránh quad trong suốt to phủ màn hình (overdraw).
- [ ] **Đèn trong VFX**: OmniLight3D ngắn hạn, **không bóng**, tối đa 4 đèn VFX cùng lúc
      (`VfxPool` quản lý ngân sách), fade tắt.
- [ ] **Dấu trên mặt đất** (vùng AOE, vết cháy): `Decal` (rẻ trong Forward+).
- [ ] **Cảm giác đòn đánh gần như miễn phí**: hit-stop, rung camera, nháy màn hình qua `post_process.gdshader`.
- [ ] Hiệu ứng đọc screen texture (méo không khí, khúc xạ) chỉ bật ở High.
- [ ] `Settings.vfx_quality` → `amount_ratio` của particle, tắt đèn VFX / distortion ở Low.

**Xong khi:** bench stress spam skill: VFX ≤ 2,5 ms đỉnh, không khung nào > 20 ms.

### Mốc 4 — Thế giới mở rộng
- [ ] **Map chia chunk** (ví dụ 32×32 m): layout PNG theo chunk, nạp/xả chunk lân cận bằng
      `ResourceLoader.load_threaded_request`.
- [ ] **Sinh MultiMesh trên thread** (`WorkerThreadPool`), vì vòng lặp GDScript của GrassField chậm
      khi map lớn. Vẫn không lưu MultiMesh vào .tscn. Nếu vẫn chậm → bake dữ liệu instance mỗi chunk ra file
      `.res` riêng lúc build (không phải .tscn).
- [ ] **Mỗi chunk một bộ bake**: splat/layout texture, shore SDF, lightmap của chunk; sinh bằng một lệnh.
- [ ] **Đồi/vách**: mesh địa hình theo chunk (sinh từ heightmap) + `HeightMapShape3D` cho Jolt.
      Không dùng tessellation/displacement trong shader.
- [ ] **Prop lặp lại** (đá, hàng rào, cỏ cao) > ~20 cái trong tầm nhìn → MultiMesh;
      collision tách riêng (StaticBody gộp shape).
- [ ] Đèn: bật `distance_fade` cho đèn lồng; hang động/nhà trong dùng Environment rẻ hơn.
- [ ] Occlusion culling: **chưa cần** (camera nhìn chéo từ trên, ít bị che); xét lại khi có thị trấn/nội thất.

**Xong khi:** đi xuyên 3–4 chunk liên tục không khung nào > 20 ms; VRAM trong ngân sách.

### Mốc 5 — Loading, bộ nhớ, bản phát hành
- [ ] Màn hình loading + nạp level trên thread + warm-up VFX trong lúc loading.
- [ ] Texture lớn không phải pixel art (nếu có) → VRAM compressed; pixel art giữ Lossless.
- [ ] Pool âm thanh (`AudioManager`), giới hạn số SFX đồng thời.
- [ ] **Đo trên bản export release** (nhanh hơn chạy từ editor), chạy bench trên bản export trước mỗi bản phát hành.

---

## 4. Checklist bắt buộc cho MỌI tính năng mới

Một tính năng chỉ coi là **xong** khi:

1. **Đã chạy bench trước/sau** (`python tools/bench/run_bench.py`). GPU High không chậm thêm > 0,3 ms (hoặc có lý do ghi
   rõ trong commit). `[ĐỎ]` so baseline giữa các phiên chỉ là tín hiệu — kết luận "X làm chậm" phải dựa A/B cùng phiên.
2. **Có hành vi cho mức Low** (giảm/tắt bớt được).
3. **Vật lặp lại** → MultiMesh hoặc pool; không `instantiate`/`queue_free` liên tục giữa gameplay.
4. **Material dùng chung**; khác biệt từng instance dùng `instance uniform` / custom data.
5. **Hạn chế trong suốt**: ưu tiên alpha scissor; trong suốt thật chỉ cho VFX nhỏ.
6. **Đèn mặc định không bóng**, `omni_range` nhỏ nhất có thể.
7. **Không cấp phát mỗi khung** trong `_process` / `_physics_process` (mảng, Dictionary, string format);
   tắt process khi node rảnh.
8. **Physics**: collision mask tối thiểu, Area3D chỉ bật khi cần; scale đều (Jolt).
9. GDScript typed đầy đủ (typed chạy nhanh hơn untyped).
10. **Tính sẵn trước**: không noise thủ tục / vòng lặp trong fragment shader, không dựng mesh lúc load nếu bake
    được; vật tĩnh nhận sáng/bóng từ lightmap. Ngoại lệ phải ghi lý do.

## 5. Công cụ

- **Debugger → Visual Profiler / Profiler / Monitors** trong editor: xem từng pass GPU, hàm GDScript tốn CPU.
- **Viewport debug draw** (Overdraw, Wireframe, Unshaded): soi overdraw cỏ/lá/VFX.
- **RenderDoc**: soi từng draw call khi cần đào sâu.
- `--gpu-index 1`: ép chạy trên iGPU để test mức Low.
- `python tools/bench/run_bench.py [--full|--stress]`: bench tự động (Mốc 0), công cụ chính để chống regression.
- **F4** / `-- --perf-overlay` (bản debug): bảng GPU/CPU/draw/primitive/VRAM/node + tọa độ `--pos=x,z`.
- Level stress `bench_stress.tscn` (96×96 m) cho `run_bench.py --stress/--full`.
