#!/usr/bin/env python3
from pathlib import Path
from PIL import Image,ImageChops,ImageStat
import argparse,json
p=argparse.ArgumentParser(description="Compare fixed water captures; requires Pillow. Pixel differences are diagnostics, not a universal visual pass.")
p.add_argument("--windows",required=True,type=Path)
p.add_argument("--gles3",required=True,type=Path)
args=p.parse_args()

def metrics(a,b):
 d=ImageChops.difference(a,b)
 ps=list(d.getdata())
 return {'mean_abs_rgb':sum(ImageStat.Stat(d).mean)/3,'max_channel_error':max(max(p) for p in ps),'fraction_pixels_error_gt_8':sum(max(p)>8 for p in ps)/len(ps)}

report={}
for platform in ['windows','gles3']:
 root=getattr(args,platform)/'results'
 if not root.exists():continue
 ims={p.name[:2]:Image.open(p).convert('RGB') for p in root.glob('*-camera.png')}
 comparisons={}
 for a,b,name in [('00','05','grab_copy_vs_background'),('02','10','single_vs_four_draws'),('10','11','four_draws_vs_instanced'),('07','08','argb32_vs_half'),('08','09','half_vs_float')]:
  comparisons[name]=metrics(ims[a],ims[b])
 bg=list(ims['00'].getdata()); opaque=list(ims['01'].getdata()); alpha=list(ims['02'].getdata())
 errors=[]
 for b,o,a in zip(bg,opaque,alpha):
  if abs(o[0]-13)<=1 and abs(o[1]-166)<=1 and abs(o[2]-230)<=1:
   errors.append(max(abs(a[c]-(o[c]+b[c])/2) for c in range(3)))
 comparisons['alpha_half_equation']={'tested_pixels':len(errors),'max_channel_error':max(errors) if errors else None,'mean_max_channel_error':sum(errors)/len(errors) if errors else None,'fraction_error_gt_2':sum(e>2 for e in errors)/len(errors) if errors else None}
 report[platform]=comparisons
w=args.windows/'results';a=args.gles3/'results'
if a.exists():report['cross_platform']={p.name:metrics(Image.open(p).convert('RGB'),Image.open(w/p.name).convert('RGB')) for p in sorted(a.glob('*-camera.png'))}
(args.gles3/'image-comparison.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
