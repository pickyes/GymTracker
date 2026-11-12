import json, sys, numpy as np, cv2
from PIL import Image
import os
A_DIR=os.path.dirname(os.path.abspath(__file__))
S=5.6  # full-res px per canvas unit (1120/200)

def load(side):
    im=np.array(Image.open(f'{A_DIR}/Body{side.capitalize()}.png').convert('RGBA')).astype(int)
    R,G,B,A=im[...,0],im[...,1],im[...,2],im[...,3]
    alpha=A>128
    red=(alpha&(R>120)&(R-G>45)&(R-B>45)).astype(np.uint8)
    red=cv2.morphologyEx(red,cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
    n,lab,st,c=cv2.connectedComponentsWithStats(red,connectivity=4)
    return alpha,lab

def split_two(mask):
    o=cv2.morphologyEx(mask.astype(np.uint8),cv2.MORPH_OPEN,np.ones((7,7),np.uint8))
    n,l,st,c=cv2.connectedComponentsWithStats(o,connectivity=4)
    big=sorted([i for i in range(1,n) if st[i,4]>800],key=lambda i:c[i][1])[:2]
    # nearest-seed assignment so no original pixel is lost
    seeds=[(l==b) for b in big]
    dists=[cv2.distanceTransform((~s).astype(np.uint8),cv2.DIST_L2,5) for s in seeds]
    upper=mask&(dists[0]<=dists[1]); lower=mask&(dists[0]>dists[1])
    return upper,lower

FRONT={ # canvas-left = person's RIGHT on the front view
 'neck':[23,31,33,24,32,34],
 'trapRight':[38,43],'trapLeft':[40,44],
 'deltRight':[47,49],'deltLeft':[48,50],
 'pecRight':[52],'pecLeft':[51],
 'serratusRight':[57,71,67],'serratusLeft':[58,72,68],
 'bicepsRight':[59,62],'bicepsLeft':[60,61],
 'tricepsRight':[65],'tricepsLeft':[66],
 'abs':[69,70,74,76,90,91,101,102],
 'forearmRight':[81,87,89,92,94,99,105],'forearmLeft':[82,86,88,93,95,98,104],
 'handRight':[121,124,128,130,138,141,144],'handLeft':[123,125,129,131,139,145],
 'outerHipRight':[106],'outerHipLeft':[107],
 'hipFlexorRight':[111,114,117],'hipFlexorLeft':[112,113,118],
 'adductorRight':[120,134,155],'adductorLeft':[122,135,154],
 'quadRight':[109,126,133,165],'quadLeft':[110,127,132,166],
 'shinRight':[169,171,173,178],'shinLeft':[170,172,174,177],
 'calfRight':[175,179,181],'calfLeft':[176,180,182],
 'footRight':[191,193,195,207,211],'footLeft':[192,194,196,208,212],
}
BACK={ # canvas-left = person's LEFT on the back view
 'neck':[5,9,10,6],
 'trapLeft':[7],'trapRight':[8],
 'deltLeft':[15],'deltRight':[16],
 'rotatorCuffLeft':[17,19],'rotatorCuffRight':[18,20],
 'tricepsLeft':[22,24],'tricepsRight':[21,23],
 'forearmLeft':[27,32,34,35,37,45],'forearmRight':[28,31,33,36,38,44],
 'handLeft':[54,56,61],'handRight':[55,57,62],
 'latLeft':[25],'latRight':[26],
 'gluteLeft':[46,48],'gluteRight':[47,49],
 'outerHipLeft':[52],'outerHipRight':[53],
 'adductorLeft':[66,110],'adductorRight':[67,111],
 'hamstringLeft':[76,85,87,104,109],'hamstringRight':[77,86,88,105,108],
 'quadLeft':[89,106],'quadRight':[90,107],
 'calfLeft':[115,118,124,126,129],'calfRight':[116,119,125,127,128],
 'footLeft':[137],'footRight':[136],
}

def ellipse_mask(shape,cx,cy,rx,ry):
    m=np.zeros(shape,np.uint8); cv2.ellipse(m,(int(cx*S),int(cy*S)),(int(rx*S),int(ry*S)),0,0,360,1,-1); return m.astype(bool)

FILL_ZONES=[]
def build(side):
    FILL_ZONES.clear()
    alpha,lab=load(side)
    table=FRONT if side=='front' else BACK
    masks={k:np.isin(lab,v) for k,v in table.items()}
    if side=='front':
        for rid,pec,obl in ((53,'pecRight','obliqueRight'),(54,'pecLeft','obliqueLeft')):
            up,lo=split_two(lab==rid); masks[pec]|=up; masks[obl]=lo
    used=np.zeros_like(alpha)
    for m in masks.values(): used|=m
    unmapped=sorted({int(i) for i in np.unique(lab[(lab>0)&~used]) if (lab==i).sum()>400})
    # head: silhouette above the neck
    ys=np.where(masks['neck'])[0]; neck_top=ys.min()
    head=alpha.copy(); head[neck_top+8:]=False
    masks['head']=head&~used
    # neck: fill the silhouette between head and shoulders around the neck muscles
    ny0,ny1=neck_top, int(np.percentile(ys,95))
    band=np.zeros_like(alpha); band[ny0:ny1,560-75:560+75]=True
    masks['neck']|=(band&alpha&~used&~head)
    used=np.zeros_like(alpha)
    for m in masks.values(): used|=m
    free=alpha&~used
    # Joints as BANDS between the muscles around them, cut to the
    # silhouette: knee = thigh muscles' bottom -> calf/shin top; ankle =
    # calf/shin bottom -> foot; wrist = forearm bottom -> hand.
    L,Rn=('Right','Left') if side=='front' else ('Left','Right')
    H,W=alpha.shape
    yy,xx=np.mgrid[0:H,0:W]
    def ybot(names,q=96):
        ys=np.concatenate([np.where(masks[n])[0] for n in names if n in masks and masks[n].any()]); return np.percentile(ys,q)
    def ytop(names,q=4):
        ys=np.concatenate([np.where(masks[n])[0] for n in names if n in masks and masks[n].any()]); return np.percentile(ys,q)
    for sd,leftside in ((L,True),(Rn,False)):
        xc=(xx<100*S) if leftside else (xx>=100*S)
        thigh=[f'quad{sd}',f'hamstring{sd}',f'adductor{sd}']
        lower=[f'calf{sd}',f'shin{sd}']
        k0,k1=ybot(thigh,97),ytop(lower,3)
        masks[f'knee{sd}']=free&xc&(yy>=k0-12)&(yy<=k1+12)
        a0=ybot(lower,99)
        masks[f'ankle{sd}']=free&xc&(yy>=a0)&(yy<=367*S)
        armx=(xx<64*S) if leftside else (xx>136*S)
        w0=ybot([f'forearm{sd}'],98)
        masks[f'wrist{sd}']=free&armx&(yy>=w0)&(yy<=203*S)
        # rest of the calf: the open lower leg between knee and ankle
        FILL_ZONES.append(free&xc&(yy>k1+12)&(yy<a0)&~masks[f'knee{sd}']&~masks[f'ankle{sd}'])
    # neck: everything in the neck band joins the neck shape
    FILL_ZONES.append(band&alpha&~head)
    if side=='back':
        lat=masks['latLeft']|masks['latRight']
        lat_low=np.percentile(np.where(lat)[0],99)
        glute_top=ytop(['gluteLeft','gluteRight'],2)
        # mid back: the strip along the spine between traps and lats
        masks['midBack']=free&(np.abs(xx-100*S)<=np.where(yy<118*S,11*S,22*S))&(yy>=72*S)&(yy<lat_low-30)
        # keep only the strip along the spine (drop fragments by the shoulder blades)
        n_,l_,st_,_=cv2.connectedComponentsWithStats(masks['midBack'].astype(np.uint8),connectivity=8)
        if n_>1: masks['midBack']=l_==(1+int(np.argmax(st_[1:,cv2.CC_STAT_AREA])))
        # back obliques: the flanks between the lats and the glutes
        torso=(xx>56*S)&(xx<144*S)&(np.abs(xx-100*S)>14*S)
        fl=free&torso&(yy>=lat_low-80)&(yy<=glute_top+10)&~masks['midBack']
        masks['obliqueLeft']=fl&(xx<100*S); masks['obliqueRight']=fl&(xx>=100*S)
    # hands / feet: the whole silhouette past the wrist / ankle joint
    L,Rn=('Right','Left') if side=='front' else ('Left','Right')
    H,W=alpha.shape
    yy,xx=np.mgrid[0:H,0:W]
    for nm,cond in ((f'hand{L}',(yy>203*S)&(yy<250*S)&(xx<56*S)),(f'hand{Rn}',(yy>203*S)&(yy<250*S)&(xx>144*S)),
                    (f'foot{L}',(yy>367*S)&(xx<100*S)),(f'foot{Rn}',(yy>367*S)&(xx>=100*S))):
        masks[nm]=masks.get(nm,np.zeros_like(alpha))|(free&cond)
    # elbows: the joint area between upper arm and forearm
    for nm,cx in ((f'elbow{L}',47),(f'elbow{Rn}',153)):
        masks[nm]=free&ellipse_mask(alpha.shape,cx,140,9,9)
    if side=='back':
        # lower back: the lumbar area between the lats and the glutes
        pts=np.column_stack(np.where(masks['latLeft']|masks['latRight']))
        lat_low=pts[pts[:,0]>pts[:,0].max()-120]
        g=np.column_stack(np.where(masks['gluteLeft']|masks['gluteRight']))
        g_top=g[g[:,0]<g[:,0].min()+40]
        hull=cv2.convexHull(np.vstack([lat_low,g_top])[:,::-1].astype(np.int32))
        m=np.zeros(alpha.shape,np.uint8); cv2.fillConvexPoly(m,hull,1)
        newused=masks['midBack']|masks['obliqueLeft']|masks['obliqueRight']
        masks['lowerBack']=m.astype(bool)&alpha&~used&~newused
    return alpha,masks,unmapped

ELL=lambda n: cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(n,n))
JOINTS=('head','elbow','hand','foot')

def clean_piece(m, open_k=13):
    """One painted piece -> smooth shape: open removes frayed tendon
    spikes and drip tails, close fills notches, blur + threshold turns
    pixel stair-steps into smooth edges."""
    m=m.astype(np.uint8)*255
    m=cv2.morphologyEx(m,cv2.MORPH_OPEN,ELL(open_k))
    m=cv2.morphologyEx(m,cv2.MORPH_CLOSE,ELL(7))
    m=cv2.GaussianBlur(m,(0,0),3)
    return (m>127).astype(np.uint8)

def pieces_of(mask):
    """Clean each painted piece ON ITS OWN, so pieces of one muscle (abs
    blocks, quad heads) never merge. Thin pieces that a full clean-up
    would erase get a gentler one."""
    n,lab,st,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),connectivity=8)
    out=[]
    for i in range(1,n):
        if st[i,cv2.CC_STAT_AREA]<300: continue
        raw=(lab==i)
        for k in (13,3):
            m=clean_piece(raw,k)
            if cv2.countNonZero(m)>=200: out.append(m); break
    if not out:  # whole area is thin: keep its raw outline
        out=[cv2.morphologyEx(mask.astype(np.uint8),cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))]
    return out

GROW=9   # px: muscles grow into narrow gaps -> fine hairlines (approved Nov 12)
LINE=3   # px: final separation line width (erode diameter)

def refine(alpha, masks):
    """Smooth shapes with FINE, EVEN separation lines. After smoothing,
    every muscle piece grows into the gap around it (nearest piece wins,
    at most GROW px), so painted borders of any width become a thin line;
    wide non-muscle areas (spine, fascia) stay as they are. A final light
    smooth + LINE px erode leaves the same hairline between all pieces."""
    pieces=[(n,p) for n,m in masks.items() if not n.startswith(JOINTS) for p in pieces_of(m)]
    union=np.zeros(alpha.shape,bool)
    for _,p in pieces: union|=p.astype(bool)
    joints=np.zeros(alpha.shape,bool)
    for n,m in masks.items():
        if n.startswith(JOINTS): joints|=m
    best_d=np.full(alpha.shape,1e9,np.float32); best_i=np.full(alpha.shape,-1,np.int32)
    for i,(_,p) in enumerate(pieces):
        d=cv2.distanceTransform((1-p).astype(np.uint8),cv2.DIST_L2,5)
        upd=d<best_d; best_d[upd]=d[upd]; best_i[upd]=i
    fill=np.zeros(alpha.shape,bool)
    for z in FILL_ZONES: fill|=z
    zone=alpha&~union&~joints&((best_d<=GROW)|(fill&(best_d<=90)))
    out={}
    for i,(n,p) in enumerate(pieces):
        g=(p.astype(bool)|(zone&(best_i==i))).astype(np.uint8)*255
        g=cv2.GaussianBlur(g,(0,0),2)
        g=cv2.erode((g>127).astype(np.uint8),ELL(LINE))
        out[n]=out.get(n,np.zeros(alpha.shape,np.uint8))|g
    for n,m in masks.items():
        if n.startswith(JOINTS):
            j=cv2.GaussianBlur(m.astype(np.uint8)*255,(0,0),2)
            out[n]=cv2.erode((j>127).astype(np.uint8),ELL(LINE))
    return out

def polys(m, min_area=700):
    cs,_=cv2.findContours(m.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
    out=[]
    for c in cs:
        if cv2.contourArea(c)<min_area: continue   # drop slivers and fragments
        a=cv2.approxPolyDP(c,1.0,True)[:,0,:]
        out.append([(round(x/S,1),round(y/S,1)) for x,y in a])
    return out

result={}
for side in ('front','back'):
    alpha,masks,unmapped=build(side)
    print(side,'unmapped regions >400px:',unmapped)
    cov=np.zeros_like(alpha)
    for m in masks.values(): cov|=m
    print(side,f'silhouette covered: {100*(cov&alpha).sum()/alpha.sum():.1f}%  overlaps: {sum(m.sum() for m in masks.values())-cov.sum()} px')
    final=refine(alpha,masks)
    result[side]={k:polys(v,150 if k.startswith(JOINTS+('outerHip',)) else 700) for k,v in final.items() if v.any()}
    np.save(f'{sys.argv[1]}/cov_{side}.npy',cov)
json.dump(result,open(f'{sys.argv[1]}/regions.json','w'))

# EXACT outlines (used by the app since Nov 12): the painted muscle
# pixels themselves, full resolution, no smoothing or growth, so a tint
# cut to them stays inside the painted lines.
def polys_exact(m):
    cs,_=cv2.findContours(m.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
    out=[]
    for c in cs:
        if cv2.contourArea(c)<40: continue
        a=cv2.approxPolyDP(c,0.7,True)[:,0,:]
        out.append([(round(x/S,2),round(y/S,2)) for x,y in a])
    return out
exact={}
for side in ('front','back'):
    alpha,masks,_=build(side)
    _,lab=load(side)
    painted=lab>0
    NONMUSCLE=('head','elbow','hand','foot','knee','ankle','wrist','lowerBack','midBack')
    # muscles: painted muscle pixels only (no filled bands or flank slabs)
    clipped={k:(v if k.startswith(NONMUSCLE) else v&painted) for k,v in masks.items()}
    # neck: only its painted neck muscles (the band fill reaches under the chin)
    clipped['neck']=np.isin(lab,(FRONT if side=='front' else BACK)['neck'])
    exact[side]={k:polys_exact(v) for k,v in clipped.items() if v.any()}
    exact[side]={k:v for k,v in exact[side].items() if v}
json.dump(exact,open(f'{sys.argv[1]}/regions_exact.json','w'))
print({s:sum(len(p) for v in exact[s].values() for p in v) for s in exact},'exact points')
print({s:sum(len(p) for v in result[s].values() for p in v) for s in result},'points')
