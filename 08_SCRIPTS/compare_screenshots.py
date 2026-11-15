from PIL import Image
import numpy as np

p_before = "05_LOGS/draw_census_occlusion_test/qte_t025s.png"
p_after  = "05_LOGS/gohma_mesh_verify/qte_t025s.png"

im_b = Image.open(p_before).convert('RGB')
im_a = Image.open(p_after).convert('RGB')

# Save side-by-side comparison image
w, h = im_b.size
comp = Image.new('RGB', (w * 2, h))
comp.paste(im_b, (0, 0))
comp.paste(im_a, (w, 0))
comp.save("05_LOGS/gohma_mesh_verify/comparison_t025s_before_after.png")
print("Saved comparison_t025s_before_after.png")

# Analyze brightness in center region (x: 400..880, y: 150..550)
b_arr = np.array(im_b.crop((400, 150, 880, 550)), dtype=np.float32)
a_arr = np.array(im_a.crop((400, 150, 880, 550)), dtype=np.float32)

print(f"Center region brightness: Before={np.mean(b_arr):.2f}, After={np.mean(a_arr):.2f}")
print(f"Center region non-black: Before={np.mean(b_arr > 30):.3f}, After={np.mean(a_arr > 30):.3f}")
